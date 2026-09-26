package com.arthurrios.finova.data.repo

import androidx.room.withTransaction
import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.data.db.RecurringExclusionEntity
import com.arthurrios.finova.data.db.UserSettingsEntity
import com.arthurrios.finova.domain.model.Budget
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
class FinanceRepository(private val db: FinovaDatabase) {

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

    val budgets: Flow<List<Budget>> = db.budgets().observeAll().map { rows -> rows.map { it.toDomain() } }

    val balanceOffset: Flow<Long> = db.userSettings().observe().map { it?.balanceOffset ?: 0 }

    suspend fun add(transaction: Transaction): Long = db.transactions().insert(transaction.toEntity())

    suspend fun addAll(transactions: List<Transaction>): List<Long> = db.transactions().insertAll(transactions.map { it.toEntity() })

    /** A recurring series: the parent, linked to itself, and the months ahead. */
    suspend fun addRecurring(draft: TransactionDraft, today: LocalDate = LocalDate.now()): Long {
        val id = db.withTransaction {
            val id = db.transactions().insert(SeriesRules.recurringParent(draft).toEntity())
            db.transactions().setParent(id, id)
            id
        }
        materializeRecurring(today)
        return id
    }

    /** An installment purchase: the hidden parent and every installment, created together. */
    suspend fun addInstallments(draft: TransactionDraft, count: Int): Long = db.withTransaction {
        val (parent, children) = SeriesRules.installmentSeries(draft, count)
        val parentId = db.transactions().insert(parent.toEntity())
        db.transactions().insertAll(children.map { it.copy(parentTransactionId = parentId).toEntity() })
        parentId
    }

    /** Fills in recurring months missing from the horizon. iOS runs this after every dashboard load. */
    suspend fun materializeRecurring(today: LocalDate = LocalDate.now()): Int = db.withTransaction {
        val rows = db.transactions().getAll().map { it.toDomain() }
        val excluded = db.recurringExclusions().getAll().map { SeriesExclusion(it.parentId, it.seriesPeriod) }.toSet()
        val missing = SeriesRules.missingOccurrences(rows, excluded, today)
        if (missing.isNotEmpty()) db.transactions().insertAll(missing.map { it.toEntity() })
        missing.size
    }

    /** Saves an edited one-off. */
    suspend fun update(transaction: Transaction) = db.transactions().update(transaction.toEntity())

    /** Saves an edit to part of a recurring series (and a split, when it made one). */
    suspend fun applyEdit(edit: SeriesEdit, today: LocalDate = LocalDate.now()) {
        db.withTransaction {
            if (edit.stopRepeating.isNotEmpty()) db.transactions().setRecurring(edit.stopRepeating.toList(), false)
            edit.moveExclusions?.let { db.recurringExclusions().move(it.fromParent, it.toParent, it.fromSlot) }
            db.transactions().updateAll(edit.updates.map { it.toEntity() })
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
        val plan = SeriesRules.deletion(target, option, rows)
        if (plan.clearExclusionsFor.isNotEmpty()) db.recurringExclusions().deleteForParents(plan.clearExclusionsFor.toList())
        plan.addExclusions.forEach { db.recurringExclusions().add(RecurringExclusionEntity(it.parentId, it.slot)) }
        if (plan.stopRepeating.isNotEmpty()) db.transactions().setRecurring(plan.stopRepeating.toList(), false)
        if (plan.deleteIds.isNotEmpty()) db.transactions().deleteByIds(plan.deleteIds.toList())
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
