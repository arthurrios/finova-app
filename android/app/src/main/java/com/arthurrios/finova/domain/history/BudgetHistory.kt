package com.arthurrios.finova.domain.history

import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
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
     * Savings over the closed months with a plan from [start] through [end] (both inclusive; null
     * leaves that side open). The open month is never counted: what it has left is not saved yet, so
     * an [end] at the open month counts up to the month before it.
     */
    fun savings(start: YearMonth? = null, end: YearMonth? = null): Savings {
        val counted = scoredMonths.filter { it.month.within(start, end) }
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

internal fun YearMonth.within(start: YearMonth?, end: YearMonth?) = (start == null || this >= start) && (end == null || this <= end)

/**
 * What made the Saved figure: the parts that moved it most, ranked, so the total reads as a few causes
 * rather than a list. For the whole month the parts are categories (and Outside allocations); for a
 * category or Outside allocations they are its months. The parts always sum to [total]. Port of
 * SavingsContributors.
 */
class SavingsContributors(items: List<Item>, val total: Long, val firstMonth: YearMonth?, val lastMonth: YearMonth?) {
    sealed interface Part {
        data class Category(val category: TransactionCategory) : Part
        data object OutsideAllocations : Part
        data class Month(val month: YearMonth) : Part
        /** A part of the Outside allocations figure that is not a month of its own series. */
        data class Difference(val reason: BudgetHistory.OutsideDifference.Reason) : Part
    }

    data class Item(val part: Part, val net: Long)

    /** Biggest saving first. */
    val savers: List<Item>
    /** Biggest overspend first. */
    val overspenders: List<Item>
    /** Everything not named, so savers + overspenders + others = total. */
    val others: Long
    val othersCount: Int
    /** The parts summed into [others], biggest effect first: what the Others line opens to. */
    val rest: List<Item>

    init {
        val nonZero = items.filter { it.net != 0L }
        savers = nonZero.filter { it.net > 0 }.sortedByDescending { it.net }.take(SHOWN_PER_SIDE)
        overspenders = nonZero.filter { it.net < 0 }.sortedBy { it.net }.take(SHOWN_PER_SIDE)
        val named = (savers + overspenders).map { it.part }.toSet()
        val remaining = nonZero.filter { it.part !in named }
        others = total - (savers + overspenders).sumOf { it.net }
        othersCount = remaining.size
        rest = remaining.sortedByDescending { kotlin.math.abs(it.net) }
    }

    companion object {
        /** How many savers and how many overspenders are named. The rest are summed into [others]. */
        const val SHOWN_PER_SIDE = 3
    }
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

    /**
     * The same history with the open month counted as if it closed today: what it has left, or is
     * over, so far. Read only for "Only" on the open month; every other figure leaves it out.
     *
     * The bars count the month's scheduled rows too, so the open month is summed again here from the
     * expenses dated up to [today].
     *
     * @param expenses the set [transactions] takes.
     */
    fun countingOpenMonthSoFar(expenses: List<Transaction>, today: LocalDate): BudgetHistory {
        val upToToday = expenses.filter { !it.date.isAfter(today) }
        fun closed(series: BudgetHistorySeries) = series.copy(
            months = series.months.map {
                it.copy(
                    spent = if (it.month == current) transactions(series.filter, current, upToToday).sumOf { row -> row.amount } else it.spent,
                    isCurrent = false,
                )
            },
        )
        // The month before the window is never in it, so as the open month it leaves every month closed.
        return copy(
            current = months.firstOrNull()?.minusMonths(1) ?: current,
            wholeMonth = closed(wholeMonth), categories = categories.map(::closed), outside = outside?.let(::closed),
        )
    }

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
    fun outsideAllocations(start: YearMonth?, end: YearMonth? = null): Long? {
        val whole = wholeMonth.savings(start, end)
        if (whole.months == 0) return null
        return whole.net - categories.sumOf { it.savings(start, end).net }
    }

    /**
     * The part of [outsideAllocations] the outside series does not explain: purchases the month card
     * counts by date and allocations by budget month, months with allocations but no budget, and
     * months that allocated more than the budget. Shown under the Saved card, so the outside series
     * plus this line equal the row in the category list.
     */
    fun outsideTiming(start: YearMonth?, end: YearMonth? = null): Long? {
        val total = outsideAllocations(start, end) ?: return null
        val series = outside ?: return null
        return total - series.savings(start, end).net
    }

    /** The ranked causes of the Saved figure for [filter], over the months the Saved card counts. */
    fun contributors(filter: BudgetHistoryFilter, start: YearMonth?, end: YearMonth?): SavingsContributors? {
        if (filter == BudgetHistoryFilter.OutsideAllocations) return outsideContributors(start, end)
        val series = series(filter) ?: return null
        val counted = series.scoredMonths.filter { it.month.within(start, end) }
        if (counted.isEmpty()) return null
        val total = series.savings(start, end).net
        val items = if (filter == BudgetHistoryFilter.WholeMonth && categories.isNotEmpty()) {
            // Categories plus the remainder no category holds, which is what makes them sum to the
            // whole month (see outsideAllocations).
            categories.mapNotNull { category ->
                val value = (category.filter as? BudgetHistoryFilter.Category)?.category ?: return@mapNotNull null
                SavingsContributors.Item(SavingsContributors.Part.Category(value), category.savings(start, end).net)
            } + listOfNotNull(outsideAllocations(start, end)?.let { SavingsContributors.Item(SavingsContributors.Part.OutsideAllocations, it) })
        } else {
            counted.map { SavingsContributors.Item(SavingsContributors.Part.Month(it.month), it.difference) }
        }
        return SavingsContributors(items, total, counted.first().month, counted.last().month)
    }

    /**
     * The Outside allocations figure as a Saved total: the same number as its row in the category
     * list and in the whole month's "Why" card, its own months plus the named differences.
     */
    fun outsideSavings(start: YearMonth?, end: YearMonth?): BudgetHistorySeries.Savings? {
        outsideAllocations(start, end) ?: return null
        val nets = outsideParts(start, end).map { it.net }
        return BudgetHistorySeries.Savings(
            saved = nets.filter { it > 0 }.sum(),
            overspent = -nets.filter { it < 0 }.sum(),
            months = wholeMonth.savings(start, end).months,
        )
    }

    /** Its months with an unallocated budget, then each named difference. */
    private fun outsideParts(start: YearMonth?, end: YearMonth?): List<SavingsContributors.Item> {
        val series = outside ?: return emptyList()
        val months = series.scoredMonths.filter { it.month.within(start, end) }
            .map { SavingsContributors.Item(SavingsContributors.Part.Month(it.month), it.difference) }
        val differences = outsideDifferences(start, end)
            .map { SavingsContributors.Item(SavingsContributors.Part.Difference(it.reason), it.amount) }
        return months + differences
    }

    private fun outsideContributors(start: YearMonth?, end: YearMonth?): SavingsContributors? {
        val total = outsideAllocations(start, end) ?: return null
        val items = outsideParts(start, end)
        if (items.isEmpty()) return null
        val counted = wholeMonth.scoredMonths.filter { it.month.within(start, end) }
        return SavingsContributors(items, total, counted.firstOrNull()?.month, counted.lastOrNull()?.month)
    }

    /** What [outsideTiming] is made of, so the screen can name it instead of one vague line. */
    data class OutsideDifference(val reason: Reason, val months: List<YearMonth>, val amount: Long) {
        enum class Reason {
            /** Months whose categories got more than the month's budget: by how much. */
            CategoriesAboveBudget,
            /** What those same months spent outside every category: with no budget left, all of it is over. */
            SpentOutsideWithNoRoom,
            /** Months with allocations but no month budget, which the whole month does not count. */
            NoMonthBudget,
            /** The rest: purchases the month card counts by date and allocations by budget month. */
            OtherMonth,
        }
    }

    /** [outsideTiming], split by why each month's remainder is not in the outside series. Non-zero parts only; they sum to it. */
    fun outsideDifferences(start: YearMonth?, end: YearMonth?): List<OutsideDifference> {
        val series = outside ?: return emptyList()
        val above = mutableListOf<YearMonth>(); var aboveAmount = 0L
        val noRoom = mutableListOf<YearMonth>(); var noRoomAmount = 0L
        val noBudget = mutableListOf<YearMonth>(); var noBudgetAmount = 0L
        var other = 0L
        for (month in closedMonths) {
            if (!month.within(start, end)) continue
            val whole = wholeMonth.month(month)
            val wholeNet = if (whole?.hasPlan == true) whole.difference else 0L
            val categoryMonths = categories.mapNotNull { it.month(month) }.filter { it.hasPlan }
            val categoriesNet = categoryMonths.sumOf { it.difference }
            val outsideMonth = series.month(month)
            val outsideNet = if (outsideMonth?.hasPlan == true) outsideMonth.difference else 0L
            val remainder = wholeNet - categoriesNet - outsideNet
            if (remainder == 0L) continue

            val budget = whole?.planned ?: 0L
            val allocated = categoryMonths.sumOf { it.planned }
            if (budget == 0L && allocated > 0) {
                noBudget += month
                noBudgetAmount += remainder
            } else if (allocated >= budget && budget > 0) {
                // remainder = (budget - allocated) - (spent outside categories) - (date-clock gap):
                // each part gets its own line, so every line has one true reason.
                val gap = budget - allocated
                if (gap != 0L) { above += month; aboveAmount += gap }
                val outsideSpent = outsideMonth?.spent ?: 0L
                if (outsideSpent != 0L) { noRoom += month; noRoomAmount -= outsideSpent }
                other += remainder - gap + outsideSpent
            } else {
                other += remainder
            }
        }
        return listOf(
            OutsideDifference(OutsideDifference.Reason.CategoriesAboveBudget, above, aboveAmount),
            OutsideDifference(OutsideDifference.Reason.SpentOutsideWithNoRoom, noRoom, noRoomAmount),
            OutsideDifference(OutsideDifference.Reason.NoMonthBudget, noBudget, noBudgetAmount),
            OutsideDifference(OutsideDifference.Reason.OtherMonth, emptyList(), other),
        ).filter { it.amount != 0L }
    }

    /**
     * The expenses one bar is made of, biggest first, each filter on the clock its bar uses:
     * - the whole month: every expense dated in the month except statement rows (the month card's "used");
     * - a category: its expenses with that budget month (the allocation card);
     * - outside allocations: expenses with that budget month in categories with no allocation then.
     *
     * @param expenses the ledger's expenses with early-paid installments already removed.
     */
    fun transactions(filter: BudgetHistoryFilter, month: YearMonth, expenses: List<Transaction>): List<Transaction> {
        val matching = when (filter) {
            BudgetHistoryFilter.WholeMonth -> expenses.filter { !it.isCreditCardStatement && YearMonth.from(it.date) == month }
            is BudgetHistoryFilter.Category -> expenses.filter { it.category == filter.category && it.budgetMonth == month }
            BudgetHistoryFilter.OutsideAllocations -> {
                val planned = categories.filter { it.month(month)?.hasPlan == true }
                    .mapNotNull { (it.filter as? BudgetHistoryFilter.Category)?.category }.toSet()
                expenses.filter { it.budgetMonth == month && it.category !in planned }
            }
        }
        return matching
            // The parent row of an installment purchase is a 0 summary of installments listed themselves.
            .filter { it.type == TransactionType.Expense && !(it.hasInstallments && it.parentTransactionId == null) }
            .sortedWith(compareByDescending<Transaction> { it.amount }.thenByDescending { it.date })
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
