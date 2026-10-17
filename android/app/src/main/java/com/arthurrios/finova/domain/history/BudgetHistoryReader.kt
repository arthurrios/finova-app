package com.arthurrios.finova.domain.history

import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit

/**
 * Builds the ledger's past months for the budget history screen. Port of BudgetHistoryService.swift.
 *
 * Every figure comes from what the dashboard already shows for that month, so a bar never disagrees
 * with the card the user came from:
 * - the whole-month bar is the month card's budget and "used" figure, from [LedgerCalculator];
 * - a category bar is the allocation card's allocated and used amounts, with the row filter of
 *   [Allocations.usage]. Change one and change both.
 */
object BudgetHistoryReader {

    /**
     * @param ledgerRows stored rows plus the statement rows, as the dashboard reads them.
     * @param includeWholeMonth false skips the month totals (the full balance pass). The allocation
     *   details preview shows one category and has no use for them.
     */
    fun read(
        ledgerRows: List<Transaction>,
        budgets: List<Budget>,
        balanceOffset: Long,
        allocations: List<AllocationRow>,
        today: LocalDate,
        includeWholeMonth: Boolean = true,
    ): BudgetHistory {
        val current = YearMonth.from(today)
        val live = Allocations.live(allocations)

        // Back to the first month that had a plan, so savings "since the start" are complete. Future
        // months are ignored: repeating allocations are created years ahead.
        val firstPlanned = (live.filter { it.amount > 0 }.map { it.month } + budgets.filter { it.amount > 0 }.map { it.month })
            .filter { it <= current }
            .minOrNull()
        val span = firstPlanned?.let { ChronoUnit.MONTHS.between(it, current).toInt() + 1 } ?: 0
        val count = span.coerceAtLeast(BudgetHistory.MINIMUM_WINDOW_MONTHS).coerceAtMost(BudgetHistory.MAXIMUM_WINDOW_MONTHS)
        val months = (count - 1 downTo 0).map { current.minusMonths(it.toLong()) }
        val window = months.toSet()

        // Allocation spending counts stored rows only, never the synthetic statement rows.
        val spent = mutableMapOf<TransactionCategory, MutableMap<YearMonth, Long>>()
        for (row in ledgerRows) {
            if (row.type != TransactionType.Expense || row.budgetMonth !in window || row.isSettledEarly || row.isCreditCardStatement) continue
            val byMonth = spent.getOrPut(row.category) { mutableMapOf() }
            byMonth[row.budgetMonth] = (byMonth[row.budgetMonth] ?: 0) + row.amount
        }

        val totals = if (!includeWholeMonth) emptyMap() else
            LedgerCalculator.monthlySummaries(ledgerRows, budgets, balanceOffset, months, today)
                .associate { it.month to BudgetHistory.MonthTotal(it.budgetLimit, it.usedValue) }

        return BudgetHistory.of(months, current, live.filter { it.month in window }, spent, totals)
    }
}
