package com.arthurrios.finova.domain.budget

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import java.time.YearMonth

/**
 * "Budget follows income": when on, a month's budget is that month's income × a percent. Port of
 * the pure rules in BudgetFollowsIncomeService.swift.
 *
 * Rules (Arthur, 2026-11-26):
 * - One switch and one percent (default 100).
 * - It applies from the month it was turned on; past months only if the user picked that.
 * - A single month can opt out: it then keeps a fixed budget, typed as before.
 * - A current or future month with no income gets a budget of 0; a PAST month with no income
 *   keeps its old budget.
 * - Turning it off leaves the rows as they are (they become fixed budgets).
 *
 * The budgets it sets are ordinary budget rows, so every reader sees them with no change.
 */
object BudgetFollowsIncome {

    data class Settings(
        val isEnabled: Boolean = false,
        /** Whole percent of income, e.g. 80 for 80%. */
        val percent: Int = 100,
        /** First month it applies to. Null means this month. */
        val startMonth: YearMonth? = null,
        /** Months that keep a fixed budget while the switch is on. */
        val optedOutMonths: Set<YearMonth> = emptySet(),
    )

    val PERCENT_RANGE = 1..200
    val PERCENT_PRESETS = listOf(50, 60, 70, 80, 90, 100)

    /** `income × percent`, rounded half up to whole minor units. */
    fun budget(income: Long, percent: Int): Long =
        if (income <= 0 || percent <= 0) 0 else (income * percent + 50) / 100

    /**
     * Money that came in during a month. Card rows are left out (a card refund is not money
     * received), and so are rows that only balance another row: both sides of a statement payment,
     * cancellation refunds and early payments. Early-paid installments are already settled. A
     * foreign-currency income counts with its app-currency amount.
     */
    fun isCountedIncome(tx: Transaction): Boolean =
        tx.type == TransactionType.Income && tx.creditCardId == null && !tx.isCreditCardStatement &&
            tx.statementPaymentId == null && !tx.isStatementPayment && !tx.isCancellationRefund &&
            !tx.isEarlyPayment && !tx.isSettledEarly

    /** Counted income per budget month. */
    fun incomeByMonth(rows: List<Transaction>): Map<YearMonth, Long> =
        rows.filter(::isCountedIncome).groupBy { it.budgetMonth }.mapValues { (_, list) -> list.sumOf { it.amount } }

    /**
     * The budget each following month must have, only where the stored value differs. Covers every
     * month from the start through the later of this month and the last month with income.
     */
    fun targets(
        rows: List<Transaction>,
        settings: Settings,
        existing: Map<YearMonth, Long>,
        currentMonth: YearMonth,
    ): Map<YearMonth, Long> {
        if (!settings.isEnabled) return emptyMap()
        val byMonth = incomeByMonth(rows)
        val last = maxOf(currentMonth, byMonth.keys.maxOrNull() ?: currentMonth)
        val start = settings.startMonth ?: currentMonth
        val out = linkedMapOf<YearMonth, Long>()
        for (month in BudgetRange.months(start, last)) {
            if (month in settings.optedOutMonths) continue
            val income = byMonth[month] ?: 0
            if (month < currentMonth && income <= 0) continue
            val target = budget(income, settings.percent)
            if (existing[month] != target) out[month] = target
        }
        return out
    }

    /**
     * Whether [month]'s budget is set from income right now. It matches the months [targets]
     * writes: a past month with no income keeps its old budget, and so does a month after both this
     * month and the last month with income. Neither counts as following.
     */
    fun follows(month: YearMonth, settings: Settings, incomeByMonth: Map<YearMonth, Long>, currentMonth: YearMonth): Boolean {
        val start = settings.startMonth ?: currentMonth
        if (!settings.isEnabled || month < start || month in settings.optedOutMonths) return false
        if (month < currentMonth) return (incomeByMonth[month] ?: 0) > 0
        val lastMonth = maxOf(currentMonth, incomeByMonth.keys.maxOrNull() ?: currentMonth)
        return month <= lastMonth
    }

    /** Turning it on: from this month, or from the first month with income when past months count. */
    fun enabled(settings: Settings, percent: Int, includePastMonths: Boolean, rows: List<Transaction>, currentMonth: YearMonth): Settings {
        val first = incomeByMonth(rows).keys.minOrNull()
        val start = if (includePastMonths) minOf(currentMonth, first ?: currentMonth) else currentMonth
        return settings.copy(
            isEnabled = true,
            percent = percent,
            startMonth = start,
            // Months typed by hand before keep their opt-out only from here on.
            optedOutMonths = settings.optedOutMonths.filter { it >= start }.toSet(),
        )
    }
}
