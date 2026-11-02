package com.arthurrios.finova.domain.history

import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.CreditCardStatement
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

    /**
     * The next months through what the dashboard's card reads them from, so a month shows the same
     * figures in both places. Nothing is summed here that the card does not sum, and a statement only
     * reaches the closing balance: the rows behind [BudgetForecastMonth] are the stored ones.
     *
     * @param ledgerRows stored rows plus the statement rows, as the dashboard reads them.
     */
    fun forecast(
        ledgerRows: List<Transaction>,
        budgets: List<Budget>,
        balanceOffset: Long,
        allocations: List<AllocationRow>,
        statements: List<CreditCardStatement>,
        today: LocalDate,
    ): BudgetForecast {
        val current = YearMonth.from(today)
        val months = (1..BudgetForecast.MONTHS_AHEAD).map { current.plusMonths(it.toLong()) }
        val stored = ledgerRows.filterNot { it.isCreditCardStatement }
        val statementsDue = ledgerRows
            .filter { it.isCreditCardStatement && it.type == TransactionType.Expense }
            .groupBy { YearMonth.from(it.date) }
            .mapValues { (_, rows) -> rows.sumOf { it.amount } }

        return BudgetForecast(
            LedgerCalculator.monthlySummaries(ledgerRows, budgets, balanceOffset, months, today).map { summary ->
                BudgetForecastMonth.of(
                    month = summary.month,
                    allocations = Allocations.withUsage(allocations, stored, summary.month),
                    summary = Allocations.unallocatedSummary(allocations, stored, budgets, summary.month),
                    unallocatedSpending = Allocations.unallocatedSpending(allocations, stored, summary.month),
                    closingBalance = summary.finalBalance,
                    deferredCardSpending = Allocations.deferredCardSpending(stored, statements, summary.month),
                    statementsDue = statementsDue[summary.month] ?: 0,
                )
            }
        )
    }
}
