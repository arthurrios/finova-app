package com.arthurrios.finova.domain.history

import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.model.TransactionCategory
import java.time.YearMonth
import kotlin.math.roundToInt

/** What a budget history is read for: the whole month's budget, or one category's allocation. */
sealed interface BudgetHistoryFilter {
    data object WholeMonth : BudgetHistoryFilter
    data class Category(val category: TransactionCategory) : BudgetHistoryFilter
    /**
     * The part of the budget no category holds: the unallocated budget as the plan, and spending in
     * categories with no allocation that month as what was spent against it.
     */
    data object OutsideAllocations : BudgetHistoryFilter
}

/** One month of one filter: what was planned, and what was spent against it. Port of BudgetHistoryMonth. */
data class BudgetHistoryMonth(
    val month: YearMonth,
    /** Minor units. Zero means nothing was planned. */
    val planned: Long,
    /** Minor units. */
    val spent: Long,
    val isCurrent: Boolean,
) {
    /**
     * Where the month landed. [InProgress] is the open month while it is still under its plan: it
     * can still go over, so it never counts as a month "on plan". An open month already over is
     * [Over]. [NoPlan] is spending with nothing planned: neither a hit nor a miss.
     */
    enum class Status { Within, Over, InProgress, NoPlan, Empty }

    val hasPlan: Boolean get() = planned > 0

    /** Positive is what is left, negative is how far past the plan the month went. */
    val difference: Long get() = planned - spent

    /** `spent / planned`, unclamped so an overspend reads as more than 100%. Null with no plan. */
    val ratio: Double? get() = if (hasPlan) spent.toDouble() / planned else null

    /** Whole percent of the plan used. Rounded here so every surface prints the same figure. */
    val percentUsed: Int? get() = ratio?.let { (it * 100).roundToInt() }

    val status: Status
        get() = when {
            !hasPlan -> if (spent > 0) Status.NoPlan else Status.Empty
            spent > planned -> Status.Over
            isCurrent -> Status.InProgress
            else -> Status.Within
        }

    /** The spent part that fits inside the plan, and the part past it. Drawn as two stacked bars. */
    val spentWithinPlan: Long get() = if (hasPlan) minOf(spent, planned) else spent
    val spentOverPlan: Long get() = if (hasPlan) (spent - planned).coerceAtLeast(0) else 0
}

/** A run of months for one filter, oldest first, ending at the current month. Port of BudgetHistorySeries. */
data class BudgetHistorySeries(val filter: BudgetHistoryFilter, val months: List<BudgetHistoryMonth>) {

    /**
     * Closed months that had a plan. The open month is left out of every score: it can still change,
     * and counting it would make the score move day by day.
     */
    val scoredMonths: List<BudgetHistoryMonth> get() = months.filter { !it.isCurrent && it.hasPlan }

    val monthsOnPlan: Int get() = scoredMonths.count { it.status == BudgetHistoryMonth.Status.Within }

    /** Closed months on plan in a row, back from the latest closed month. A month with no plan ends it. */
    val streak: Int
        get() {
            var count = 0
            for (month in months.asReversed()) {
                if (month.isCurrent) continue
                if (month.status != BudgetHistoryMonth.Status.Within) break
                count++
            }
            return count
        }

    /** Lowest and highest share of the plan used across the scored months: a range, not an average. */
    val usageRange: Pair<Int, Int>?
        get() {
            val percents = scoredMonths.mapNotNull { it.percentUsed }
            val low = percents.minOrNull() ?: return null
            return low to percents.max()
        }

    /**
     * What closed months left over against their plan, netted: a month under its plan adds what it
     * did not spend, a month over it takes the overspend back off.
     */
    data class Savings(val saved: Long, val overspent: Long, val months: Int) {
        val net: Long get() = saved - overspent

        companion object {
            val None = Savings(0, 0, 0)
        }
    }

    /**
     * Savings over the closed months with a plan from [start] (inclusive) on, or over all of them.
     * The open month is never counted: what it has left is not saved yet.
     */
    fun savings(start: YearMonth? = null): Savings {
        val counted = scoredMonths.filter { start == null || it.month >= start }
        return Savings(
            saved = counted.sumOf { it.difference.coerceAtLeast(0) },
            overspent = counted.sumOf { (-it.difference).coerceAtLeast(0) },
            months = counted.size,
        )
    }

    /** Nothing planned and nothing spent in any month of the series. */
    val isEmpty: Boolean get() = months.all { it.status == BudgetHistoryMonth.Status.Empty }

    /** The last [count] months, keeping the current one. */
    fun suffix(count: Int) = copy(months = months.takeLast(count))

    /**
     * Drops leading months with nothing in them, so a ledger that started three months ago shows three
     * bars and not nine empty slots first. The current month always stays.
     */
    fun trimmingLeadingEmptyMonths(): BudgetHistorySeries {
        val first = months.indexOfFirst { it.status != BudgetHistoryMonth.Status.Empty || it.isCurrent }
        return copy(months = if (first < 0) emptyList() else months.drop(first))
    }

    fun month(month: YearMonth): BudgetHistoryMonth? = months.firstOrNull { it.month == month }
}

/** Every series the history screen can show, for the ledger. Pure. Port of BudgetHistory.swift. */
data class BudgetHistory(
    val months: List<YearMonth>,
    val current: YearMonth,
    val wholeMonth: BudgetHistorySeries,
    /** Every category with an allocation somewhere in the window, biggest plan first. */
    val categories: List<BudgetHistorySeries>,
    /** Unallocated budget against unplanned spending. Null when no category was ever planned. */
    val outside: BudgetHistorySeries? = null,
) {
    /** The month card's figures for one month: the budget row and the "used" figure. */
    data class MonthTotal(val budget: Long?, val used: Long)

    /** Closed months, oldest first: what the savings start can be set to. */
    val closedMonths: List<YearMonth> get() = months.filter { it != current }

    val filters: List<BudgetHistoryFilter> get() = listOf(BudgetHistoryFilter.WholeMonth) + categories.map { it.filter }

    fun series(filter: BudgetHistoryFilter): BudgetHistorySeries? = when (filter) {
        BudgetHistoryFilter.WholeMonth -> wholeMonth
        is BudgetHistoryFilter.Category -> categories.firstOrNull { it.filter == filter }
        BudgetHistoryFilter.OutsideAllocations -> outside
    }

    val isEmpty: Boolean get() = wholeMonth.isEmpty && categories.isEmpty()

    /**
     * What the whole month saved that no category accounts for: the whole month's net minus every
     * category's net. A remainder on purpose: budget never put into a category, spending in
     * categories with no allocation, and purchases the month card counts by date while allocations
     * count them by budget month. Null when the whole month has nothing to count.
     */
    fun outsideAllocations(start: YearMonth?): Long? {
        val whole = wholeMonth.savings(start)
        if (whole.months == 0) return null
        return whole.net - categories.sumOf { it.savings(start).net }
    }

    /**
     * The part of [outsideAllocations] the outside series does not explain: purchases the month card
     * counts by date and allocations by budget month, months with allocations but no budget, and
     * months that allocated more than the budget. Shown under the Saved card, so the outside series
     * plus this line equal the row in the category list.
     */
    fun outsideTiming(start: YearMonth?): Long? {
        val total = outsideAllocations(start) ?: return null
        val series = outside ?: return null
        return total - series.savings(start).net
    }

    companion object {
        /**
         * Twelve closed months plus the open one: the most the chart shows. A ledger with older plans
         * gets a longer window, so "saved since the start" counts every month that had a plan.
         */
        const val MINIMUM_WINDOW_MONTHS = 13

        /** Ten years. Only a bound against a corrupt month stretching the read without limit. */
        const val MAXIMUM_WINDOW_MONTHS = 120

        val Empty = BudgetHistory(
            months = emptyList(), current = YearMonth.of(2000, 1),
            wholeMonth = BudgetHistorySeries(BudgetHistoryFilter.WholeMonth, emptyList()), categories = emptyList(),
        )

        /**
         * @param months the window, oldest first. Anything outside it is ignored.
         * @param allocations the ledger's allocations, any months (deleted series months are skipped).
         *   Same-category rows in one month are summed.
         * @param spentByCategory category → month → spent, built with the allocation card's predicate,
         *   so a bar here matches the card for the same month.
         * @param monthTotals per month, the figures the dashboard's month card shows.
         */
        fun of(
            months: List<YearMonth>,
            current: YearMonth,
            allocations: List<AllocationRow>,
            spentByCategory: Map<TransactionCategory, Map<YearMonth, Long>>,
            monthTotals: Map<YearMonth, MonthTotal>,
        ): BudgetHistory {
            val window = months.toSet()
            val planned = mutableMapOf<TransactionCategory, MutableMap<YearMonth, Long>>()
            for (allocation in Allocations.live(allocations)) {
                if (allocation.month !in window || allocation.amount <= 0) continue
                val byMonth = planned.getOrPut(allocation.category) { mutableMapOf() }
                byMonth[allocation.month] = (byMonth[allocation.month] ?: 0) + allocation.amount
            }

            fun build(plannedIn: (YearMonth) -> Long, spentIn: (YearMonth) -> Long) = months.map { month ->
                BudgetHistoryMonth(month, plannedIn(month).coerceAtLeast(0), spentIn(month).coerceAtLeast(0), month == current)
            }

            val whole = BudgetHistorySeries(
                BudgetHistoryFilter.WholeMonth,
                build({ monthTotals[it]?.budget ?: 0L }, { monthTotals[it]?.used ?: 0L }),
            )

            // Biggest plan in the open month first (the order the card shows today), then the biggest
            // plan across the window for categories no longer planned. Key last, so the order never
            // depends on map order.
            val ordered = planned.keys.sortedWith(
                compareByDescending<TransactionCategory> { planned[it]?.get(current) ?: 0L }
                    .thenByDescending { planned[it]?.values?.sum() ?: 0L }
                    .thenBy { it.key },
            )
            val categories = ordered.map { category ->
                val plan = planned[category].orEmpty()
                val spent = spentByCategory[category].orEmpty()
                BudgetHistorySeries(BudgetHistoryFilter.Category(category), build({ plan[it] ?: 0L }, { spent[it] ?: 0L }))
            }
            // Per month: the budget left after allocations, against spending in every category with no
            // allocation that month (the budget card's "Unallocated" and its off-plan slices). An
            // over-allocated month has no outside plan; the timing line holds it.
            val allocatedByMonth = mutableMapOf<YearMonth, Long>()
            for (byMonth in planned.values) for ((month, amount) in byMonth) allocatedByMonth[month] = (allocatedByMonth[month] ?: 0) + amount
            val outside = if (categories.isEmpty()) null else BudgetHistorySeries(
                BudgetHistoryFilter.OutsideAllocations,
                build(
                    { month ->
                        val budget = monthTotals[month]?.budget ?: 0L
                        if (budget > 0) budget - (allocatedByMonth[month] ?: 0L) else 0L
                    },
                    { month ->
                        spentByCategory.entries.sumOf { (category, byMonth) ->
                            if ((planned[category]?.get(month) ?: 0L) > 0) 0L else byMonth[month] ?: 0L
                        }
                    },
                ),
            )
            return BudgetHistory(months, current, whole, categories, outside)
        }
    }
}
