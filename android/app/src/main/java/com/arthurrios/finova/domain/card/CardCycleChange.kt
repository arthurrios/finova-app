package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import java.time.LocalDate
import java.time.YearMonth

/**
 * What changes when a card's closing or due day changes. Port of
 * CreditCardService.recalculateStatementDatesForCard and the three passes it runs.
 *
 * Only cycles that have not closed yet move. A statement the user was already billed for is a
 * record of what they were charged, so its dates and rows stay exactly as they are.
 */
object CardCycleChange {

    /**
     * [created] statements carry negative temporary ids, which rows in [rows] may point at; the
     * repository swaps them for the ids it gets on insert. [deleted] statements lost their rows to
     * the statement they were merged into.
     */
    data class Plan(
        val updated: List<CreditCardStatement>,
        val created: List<CreditCardStatement>,
        val deleted: Set<Long>,
        val rows: List<Transaction>,
    )

    fun plan(
        card: CreditCard,
        statements: List<CreditCardStatement>,
        rows: List<Transaction>,
        today: LocalDate,
        rule: BusinessDayRule,
        /** The unattended repair leaves dates the user set by hand; a card edit moves them too, as on iOS. */
        respectingDateOverrides: Boolean = false,
    ): Plan {
        val stmts = statements.filter { it.creditCardId == card.id }.associateBy { it.id }.toMutableMap()
        val original = stmts.toMap()
        val changedRows = linkedMapOf<Long, Transaction>()
        fun current(row: Transaction) = changedRows[row.id] ?: row
        val deleted = mutableSetOf<Long>()
        var nextTempId = -1L
        fun isOpen(s: CreditCardStatement) = s.closingDate > today && !s.isPaid

        // 1. Open statements take the new days, in the month they already close in.
        for (s in stmts.values.toList()) {
            if (!isOpen(s) || (respectingDateOverrides && s.isDatesOverridden)) continue
            val closing = CardCycle.closingDateIn(YearMonth.from(s.closingDate), card.closingDay)
            stmts[s.id] = s.copy(closingDate = closing, dueDate = CardCycle.dueDate(closing, card.dueDay, rule))
        }

        // 2. Two open statements in one month (one on the old day, one on the new) become one, or
        //    an installment stays on a "ghost" invoice with the old due date. The keeper is the one
        //    on the current closing day, else the one with most rows, else the oldest.
        for ((month, group) in stmts.values.groupBy { YearMonth.from(it.closingDate) }) {
            if (group.size < 2 || !group.all(::isOpen)) continue
            val closingDay = CardCycle.closingDateIn(month, card.closingDay).dayOfMonth
            val rowCount = { s: CreditCardStatement -> rows.count { current(it).statementId == s.id && !it.isCreditCardStatement } }
            val sorted = group.sortedWith(
                compareByDescending<CreditCardStatement> { it.closingDate.dayOfMonth == closingDay }
                    .thenByDescending(rowCount)
                    .thenBy { it.id }
            )
            val keeper = sorted.first()
            for (drop in sorted.drop(1)) {
                rows.filter { current(it).statementId == drop.id && !it.isCreditCardStatement }
                    .forEach { changedRows[it.id] = current(it).copy(statementId = keeper.id) }
                stmts.remove(drop.id)
                deleted += drop.id
            }
            if (!keeper.isDatesOverridden) {
                val closing = CardCycle.closingDateIn(month, card.closingDay)
                stmts[keeper.id] = keeper.copy(closingDate = closing, dueDate = CardCycle.dueDate(closing, card.dueDay, rule))
            }
        }

        // 3. An installment's date is its statement's due date: installments on open statements
        //    follow the new due date and count in its month.
        for (row in rows) {
            val r = current(row)
            if (r.creditCardId != card.id || r.installmentNumber == null || r.isCreditCardStatement) continue
            val s = r.statementId?.let { stmts[it] } ?: continue
            if (!isOpen(s) || r.date == s.dueDate) continue
            changedRows[r.id] = r.copy(date = s.dueDate, budgetMonth = YearMonth.from(s.dueDate))
        }

        // 4. Other card purchases in cycles still ahead go on the statement their date now routes
        //    to. Left alone: installments that already have a statement (chained at creation, not
        //    routed by date), rows the user moved by hand, and anything in a closed cycle.
        val closedIds = original.values.filter { it.closingDate <= today }.map { it.id }.toSet()
        for (row in rows) {
            val r = current(row)
            if (r.creditCardId != card.id || r.isCreditCardStatement || r.isStatementOverridden) continue
            if (r.installmentNumber != null && r.statementId != null) continue
            if (r.statementId != null && r.statementId in closedIds) continue
            if (CardCycle.closingDate(card.closingDay, r.unadjusted) <= today) continue
            var target = StatementBook.route(stmts.values.toList(), card, r.unadjusted, rule)
            if (target.id == 0L) {
                target = target.copy(id = nextTempId--)
                stmts[target.id] = target
            }
            if (r.statementId != target.id) changedRows[r.id] = r.copy(statementId = target.id)
        }

        return Plan(
            updated = stmts.values.filter { it.id > 0 && original[it.id] != it },
            created = stmts.values.filter { it.id < 0 },
            deleted = deleted,
            rows = changedRows.values.toList(),
        )
    }
}
