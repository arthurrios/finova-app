package com.arthurrios.finova.domain.allocation

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.YearMonth
import kotlin.math.roundToInt

/**
 * How much of one category's allocation was actually spent, across closed months. Port of
 * CategorySpendHistory.swift: it reports a range, not an average, because an average hides months
 * that disagree. It feeds no money figure; the projection still assumes the whole plan is spent.
 *
 * @param ratiosByMonth used / allocated per closed month. Keyed by month so one month counts once.
 */
class CategorySpendHistory(ratiosByMonth: Map<YearMonth, Double>) {
    val sampleCount: Int = ratiosByMonth.size
    /** Unclamped: 1.4 means "you usually go past this budget". */
    val lowestRatio: Double = ratiosByMonth.values.minOrNull() ?: 0.0
    val highestRatio: Double = ratiosByMonth.values.maxOrNull() ?: 0.0
    val spread: Double get() = highestRatio - lowestRatio

    sealed interface Verdict {
        data object NotEnoughHistory : Verdict
        data class Consistent(val low: Double, val high: Double, val months: Int) : Verdict
        data class Varied(val low: Double, val high: Double, val months: Int) : Verdict
    }

    val verdict: Verdict
        get() = when {
            sampleCount < MINIMUM_SAMPLES -> Verdict.NotEnoughHistory
            spread <= MAXIMUM_SPREAD -> Verdict.Consistent(lowestRatio, highestRatio, sampleCount)
            else -> Verdict.Varied(lowestRatio, highestRatio, sampleCount)
        }

    /** The range as whole percents. Both ends can round together, and then a caller shows one. */
    val percentRange: Pair<Int, Int> get() = (lowestRatio * 100).roundToInt() to (highestRatio * 100).roundToInt()

    companion object {
        /** The carousel reaches twelve months back, so that is the whole past worth sampling. */
        const val SAMPLE_WINDOW = 12
        const val MINIMUM_SAMPLES = 4
        const val MAXIMUM_SPREAD = 0.40
        val None = CategorySpendHistory(emptyMap())

        /**
         * One history per category, from closed months before [month] only. Port of
         * BudgetAllocationService.spendHistories. A month counts when the category had a non-zero
         * allocation; a month with no spending is a real 0% sample. Usage uses the same rows as
         * [Allocations.usage], so the ratio matches what the card shows.
         */
        fun of(
            categories: List<TransactionCategory>,
            month: YearMonth,
            allocations: List<AllocationRow>,
            rows: List<Transaction>,
            thisMonth: YearMonth,
        ): Map<TransactionCategory, CategorySpendHistory> {
            if (categories.isEmpty()) return emptyMap()
            val window = (1..SAMPLE_WINDOW).map { thisMonth.minusMonths(it.toLong()) }.filter { it < month }.toSet()
            if (window.isEmpty()) return emptyMap()
            val wanted = categories.toSet()
            // Summed, in case an old ledger holds two rows for one category and month.
            val allocated = Allocations.live(allocations)
                .filter { it.category in wanted && it.month in window && it.amount > 0 }
                .groupBy { it.category }
                .mapValues { (_, list) -> list.groupBy { it.month }.mapValues { (_, m) -> m.sumOf { it.amount } } }
            if (allocated.isEmpty()) return emptyMap()
            val used = rows
                .filter {
                    it.category in allocated && it.type == TransactionType.Expense && it.budgetMonth in window &&
                        !it.isSettledEarly && !it.isCreditCardStatement
                }
                .groupBy { it.category }
                .mapValues { (_, list) -> list.groupBy { it.budgetMonth }.mapValues { (_, m) -> m.sumOf { it.amount } } }
            return allocated.mapValues { (category, byMonth) ->
                val spent = used[category].orEmpty()
                CategorySpendHistory(byMonth.mapValues { (m, amount) -> (spent[m] ?: 0L).toDouble() / amount })
            }
        }
    }
}
