package com.arthurrios.finova.data.repo

import androidx.room.withTransaction
import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.data.db.RecurringExclusionEntity
import com.arthurrios.finova.data.db.StatementEntity
import com.arthurrios.finova.data.db.UserSettingsEntity
import com.arthurrios.finova.domain.card.CardCycleChange
import com.arthurrios.finova.domain.card.StatementBook
import com.arthurrios.finova.domain.card.StatementPayments
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.domain.series.SeriesEdit
import com.arthurrios.finova.domain.series.SeriesExclusion
import com.arthurrios.finova.domain.series.SeriesRules
import com.arthurrios.finova.domain.series.TransactionDraft
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.time.LocalDate

/**
 * The signed-in user's money data. Port of the parts of TransactionRepository, BudgetRepository,
 * RecurringTransactionManager and the balance offset in UIDUserDefaultsManager that the
 * dashboard and the add sheet use.
 */
class FinanceRepository(
    private val db: FinovaDatabase,
    /** The account's weekend rule, which new statements' due dates follow. */
    private val defaultRule: () -> BusinessDayRule = { BusinessDayRule.Exact },
) {

    private val exclusions: Flow<Set<SeriesExclusion>> =
        db.recurringExclusions().observeAll().map { rows -> rows.map { SeriesExclusion(it.parentId, it.seriesPeriod) }.toSet() }

    /**
     * Every stored row, series parents included (iOS `fetchAllTransactions`), minus a recurring
     * parent whose own month the user deleted: that row stays in the database so the series keeps
     * generating, but it no longer shows or counts.
     */
    val transactions: Flow<List<Transaction>> =
        combine(db.transactions().observeAll(), exclusions) { rows, excluded ->
            rows.map { it.toDomain() }.filterNot { SeriesExclusion(it.id, it.slot) in excluded }
        }

    val statements: Flow<List<CreditCardStatement>> =
        db.statements().observeAll().map { rows -> rows.map { it.toModel() } }

    /** Every card, deleted ones too: their statements still charge the balance. */
    private val allCards: Flow<List<CreditCard>> = db.creditCards().observeAll().map { rows -> rows.map { it.toModel() } }

    /**
     * What the ledger and the dashboard list read: the stored rows plus one synthetic row per card
     * statement, dated on its due date (iOS adds them in TransactionLedgerService).
     */
    val ledgerRows: Flow<List<Transaction>> = combine(transactions, statements, allCards) { rows, stmts, cards ->
        rows + StatementBook.statementRows(cards, stmts, rows)
    }

    val budgets: Flow<List<Budget>> = db.budgets().observeAll().map { rows -> rows.map { it.toDomain() } }

    val balanceOffset: Flow<Long> = db.userSettings().observe().map { it?.balanceOffset ?: 0 }

    suspend fun add(transaction: Transaction): Long = db.withTransaction {
        db.transactions().insert(transaction.toEntity()).also { settleCardRows() }
    }

    suspend fun addAll(transactions: List<Transaction>): List<Long> = db.transactions().insertAll(transactions.map { it.toEntity() })

    /** A recurring series: the parent, linked to itself, and the months ahead. */
    suspend fun addRecurring(draft: TransactionDraft, today: LocalDate = LocalDate.now()): Long {
        val id = db.withTransaction {
            val id = db.transactions().insert(SeriesRules.recurringParent(draft).toEntity())
            db.transactions().setParent(id, id)
            settleCardRows()
            id
        }
        materializeRecurring(today)
        return id
    }

    /** An installment purchase: the hidden parent and every installment, created together. */
    suspend fun addInstallments(draft: TransactionDraft, count: Int): Long = db.withTransaction {
        val (parent, children) = SeriesRules.installmentSeries(draft, count)
        val parentId = db.transactions().insert(parent.toEntity())
        val card = draft.creditCardId?.let { db.creditCards().getById(it)?.toModel() }
        val placed = if (card == null) children else chainOnStatements(card, children)
        db.transactions().insertAll(placed.map { it.copy(parentTransactionId = parentId).toEntity() })
        settleCardRows()
        parentId
    }

    /**
     * Puts installments on consecutive statements, as iOS does: the first routed by its picked
     * date, each next one on the cycle after. An installment is charged when its invoice is due,
     * so it takes the due date and counts in that month; its slot stays on the picked month.
     */
    private suspend fun chainOnStatements(card: CreditCard, children: List<Transaction>): List<Transaction> {
        val known = db.statements().forCard(card.id).map { it.toModel() }.toMutableList()
        var previous: CreditCardStatement? = null
        return children.sortedBy { it.installmentNumber }.map { child ->
            val wanted = previous?.let { StatementBook.next(known, card, it, defaultRule()) }
                ?: StatementBook.route(known, card, child.unadjusted, defaultRule())
            val statement = stored(wanted, known)
            previous = statement
            child.copy(
                date = statement.dueDate,
                budgetMonth = java.time.YearMonth.from(statement.dueDate),
                statementId = statement.id,
            )
        }
    }

    /** Inserts [statement] if it is new, and remembers it for the next lookup. */
    private suspend fun stored(statement: CreditCardStatement, known: MutableList<CreditCardStatement>): CreditCardStatement {
        if (statement.id != 0L) return statement
        val id = db.statements().insert(statement.toEntity())
        return statement.copy(id = id).also { known += it }
    }

    /**
     * Gives every card row without a statement its statement (routed by the picked date, as iOS
     * `assignToStatement` and `repairOrphanedCreditCardTransactions` do), then brings every
     * statement's cached total up to date and removes statements nothing points at any more.
     * Runs inside the caller's database transaction after every change that touches card rows.
     */
    private suspend fun settleCardRows() {
        val dao = db.transactions()
        val orphans = dao.getAll().filter { it.creditCardId != null && it.statementId == null }
        if (orphans.isNotEmpty()) {
            val cards = db.creditCards().getAll().associateBy { it.id }
            val known = db.statements().getAll().map { it.toModel() }.toMutableList()
            val routed = orphans.mapNotNull { row ->
                val card = cards[row.creditCardId]?.toModel() ?: return@mapNotNull null
                val statement = stored(StatementBook.route(known, card, row.unadjustedDate ?: row.date, defaultRule()), known)
                row.copy(statementId = statement.id)
            }
            dao.updateAll(routed)
        }
        val rows = dao.getAll().map { it.toDomain() }
        for (statement in db.statements().getAll()) {
            if (StatementBook.members(statement.id, rows).isEmpty()) {
                db.statements().delete(statement.id)
            } else {
                val total = StatementBook.total(statement.id, rows)
                if (total != statement.totalAmount) {
                    db.statements().update(statement.copy(totalAmount = total, updatedAt = System.currentTimeMillis()))
                }
            }
        }
    }

    /** Fills in recurring months missing from the horizon. iOS runs this after every dashboard load. */
    suspend fun materializeRecurring(today: LocalDate = LocalDate.now()): Int = db.withTransaction {
        val rows = db.transactions().getAll().map { it.toDomain() }
        val excluded = db.recurringExclusions().getAll().map { SeriesExclusion(it.parentId, it.seriesPeriod) }.toSet()
        val missing = SeriesRules.missingOccurrences(rows, excluded, today)
        if (missing.isNotEmpty()) {
            db.transactions().insertAll(missing.map { it.toEntity() })
            settleCardRows()
        }
        missing.size
    }

    /** Saves an edited one-off. */
    suspend fun update(transaction: Transaction) = db.withTransaction {
        db.transactions().update(transaction.toEntity())
        settleCardRows()
    }

    /** Saves an edit to part of a recurring series (and a split, when it made one). */
    suspend fun applyEdit(edit: SeriesEdit, today: LocalDate = LocalDate.now()) {
        db.withTransaction {
            if (edit.stopRepeating.isNotEmpty()) db.transactions().setRecurring(edit.stopRepeating.toList(), false)
            edit.moveExclusions?.let { db.recurringExclusions().move(it.fromParent, it.toParent, it.fromSlot) }
            db.transactions().updateAll(edit.updates.map { it.toEntity() })
            settleCardRows()
        }
        // A new head (after a split) or a new day may leave months to fill in.
        materializeRecurring(today)
    }

    /**
     * Rebuilds an installment series from the edited values, like iOS
     * `updateAllInstallmentTransactions`: the old rows go and the series is created again.
     */
    suspend fun replaceInstallments(seriesId: Long, draft: TransactionDraft, count: Int): Long = db.withTransaction {
        val rows = db.transactions().getAll().map { it.toDomain() }
        val old = rows.filter { it.id == seriesId || it.parentTransactionId == seriesId }.map { it.id }
        db.transactions().deleteByIds(old)
        addInstallments(draft, count)
    }

    /** Deletes a row, or part of its series, as [option] says. */
    suspend fun delete(transactionId: Long, option: SeriesDeleteOption) = db.withTransaction {
        val rows = db.transactions().getAll().map { it.toDomain() }
        val target = rows.firstOrNull { it.id == transactionId } ?: return@withTransaction
        val series = SeriesRules.deletion(target, option, rows)
        // Half of a statement payment never stays behind alone: an orphan debit charges for a
        // payment the invoice no longer shows, an orphan credit discounts an invoice nobody paid.
        val partners = series.deleteIds.flatMap { id -> rows.firstOrNull { it.id == id }?.let { StatementPayments.partners(it, rows) }.orEmpty() }
        val plan = series.copy(deleteIds = series.deleteIds + partners)
        val touchedStatements = rows.filter { it.id in plan.deleteIds }.mapNotNull { it.statementId }.toSet()
        if (plan.clearExclusionsFor.isNotEmpty()) db.recurringExclusions().deleteForParents(plan.clearExclusionsFor.toList())
        plan.addExclusions.forEach { db.recurringExclusions().add(RecurringExclusionEntity(it.parentId, it.slot)) }
        if (plan.stopRepeating.isNotEmpty()) db.transactions().setRecurring(plan.stopRepeating.toList(), false)
        if (plan.deleteIds.isNotEmpty()) db.transactions().deleteByIds(plan.deleteIds.toList())
        settleCardRows()
        // A statement that owes money again stops reading "paid".
        if (touchedStatements.isNotEmpty()) {
            val left = db.transactions().getAll().map { it.toDomain() }
            for (id in touchedStatements) {
                val statement = db.statements().getById(id) ?: continue
                if (statement.isPaid && StatementPayments.remaining(id, left) > 0) {
                    db.statements().update(statement.copy(isPaid = false, paidDate = null, paidAmount = null, updatedAt = System.currentTimeMillis()))
                }
            }
        }
    }

    /**
     * After a card's closing or due day changed: moves its open statements to the new days and
     * re-routes what they hold ([CardCycleChange]). Closed and paid statements stay as they were.
     */
    suspend fun applyCardCycleChange(cardId: Long, today: LocalDate = LocalDate.now()) = db.withTransaction {
        val card = db.creditCards().getById(cardId)?.toModel() ?: return@withTransaction
        val plan = CardCycleChange.plan(
            card = card,
            statements = db.statements().forCard(cardId).map { it.toModel() },
            rows = db.transactions().getAll().map { it.toDomain() },
            today = today,
            rule = defaultRule(),
        )
        val realIds = plan.created.associate { it.id to db.statements().insert(it.copy(id = 0).toEntity()) }
        plan.updated.forEach { db.statements().update(it.toEntity()) }
        db.transactions().updateAll(plan.rows.map { row -> row.copy(statementId = row.statementId?.let { realIds[it] ?: it }).toEntity() })
        plan.deleted.forEach { db.statements().delete(it) }
        settleCardRows()
    }

    /**
     * Books a payment of [amount] against the statement on [date]: the debit and the credit, in one
     * database transaction. Once nothing is left to pay, the statement reads as paid from the
     * payment's date (a future date reads as scheduled until then). Returns the debit's id.
     */
    suspend fun payStatement(statementId: Long, amount: Long, date: LocalDate, debitTitle: String, creditTitle: String): Long =
        db.withTransaction {
            val statement = db.statements().getById(statementId)?.toModel() ?: error("No statement $statementId")
            val rows = db.transactions().getAll().map { it.toDomain() }
            require(amount in 1..StatementPayments.remaining(statementId, rows)) { "The amount is more than the statement owes" }
            val (debit, credit) = StatementPayments.pair(statement, amount, date, debitTitle, creditTitle)
            val debitId = db.transactions().insert(debit.toEntity())
            db.transactions().insert(credit.copy(statementPaymentId = debitId).toEntity())
            settleCardRows()
            val after = db.transactions().getAll().map { it.toDomain() }
            if (StatementPayments.remaining(statementId, after) == 0L) {
                db.statements().getById(statementId)?.let {
                    db.statements().update(
                        it.copy(isPaid = true, paidDate = date, paidAmount = StatementPayments.totalPaid(statementId, after), updatedAt = System.currentTimeMillis())
                    )
                }
            }
            debitId
        }

    /**
     * "Mark as Paid": the statement reads as paid from [date] on. Nothing moves in the balance;
     * the statement row already charges it on the due date (iOS `markAsPaid`).
     */
    suspend fun markStatementPaid(statementId: Long, amount: Long, date: LocalDate) {
        val statement = db.statements().getById(statementId) ?: return
        db.statements().update(
            statement.copy(isPaid = true, paidDate = date, paidAmount = amount, updatedAt = System.currentTimeMillis())
        )
    }

    suspend fun setBudget(budget: Budget) = db.budgets().upsert(budget.toEntity())

    suspend fun deleteBudget(month: java.time.YearMonth) = db.budgets().delete(month)

    suspend fun setBalanceOffset(value: Long) = db.userSettings().save(UserSettingsEntity(balanceOffset = value))

    suspend fun isEmpty(): Boolean = db.transactions().count() == 0

    companion object {
        /**
         * What the lists show: iOS `fetchTransactions` hides a recurring parent that is not
         * self-linked and the zero-amount installment parent.
         */
        fun isListed(t: Transaction): Boolean =
            !(t.isRecurring && t.parentTransactionId == null) && !(t.hasInstallments && t.parentTransactionId == null)
    }
}
