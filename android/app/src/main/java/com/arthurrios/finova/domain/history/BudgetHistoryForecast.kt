package com.arthurrios.finova.domain.history

import com.arthurrios.finova.domain.allocation.AllocationBalanceProjection
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.UnallocatedSpending
import com.arthurrios.finova.domain.allocation.UnallocatedSummary
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.YearMonth
import kotlin.math.roundToLong

/**
 * One month ahead, read from what the dashboard's budget card is given for that month. Port of
 * BudgetHistoryForecast.swift.
 *
 * Kept apart from [BudgetHistoryMonth] on purpose. Every score, streak and savings total walks
 * [BudgetHistorySeries.months], so a projected month that is never in that list cannot reach them.
 */
data class BudgetForecastMonth(
    val month: YearMonth,
    /** Zero means no budget was set. */
    val budget: Long,
    val allocations: List<Allocation>,
    /** Rows dated in the month, in categories with no allocation then. */
    val outsideByCategory: Map<TransactionCategory, Long>,
    /** The card's "used in unallocated categories". */
    val outside: Long,
    /**
     * Statements falling due in the month. They move the balance but not the budget: their purchases
     * count in the month they were made, so each card purchase counts once.
     */
    val statementsDue: Long,
    /** The card's own projection. Null when the month has no balance, as on the card. */
    val projection: AllocationBalanceProjection?,
) {
    /** One allocated category. Same-category rows in a month are summed, as [BudgetHistory] does. */
    data class Allocation(
        val category: TransactionCategory,
        val planned: Long,
        /** Rows already dated in the month: the card's "used". */
        val scheduled: Long,
    ) {
        /** The projection assumes the whole plan gets spent, and more when the rows already pass it. */
        val expected: Long get() = maxOf(planned, scheduled)
    }

    val inside: Long get() = allocations.sumOf { it.expected }
    val allocated: Long get() = allocations.sumOf { it.planned }

    /** Nothing to project: no budget, no allocation and no row. */
    val isEmpty: Boolean get() = budget == 0L && allocations.isEmpty() && outside == 0L

    companion object {
        /** Takes the values the dashboard's card is handed, so the two can only differ if one side changes. */
        fun of(
            month: YearMonth,
            allocations: List<BudgetAllocation>,
            summary: UnallocatedSummary,
            unallocatedSpending: List<UnallocatedSpending>,
            closingBalance: Long?,
            deferredCardSpending: Long,
            statementsDue: Long,
        ): BudgetForecastMonth {
            val planned = linkedMapOf<TransactionCategory, Long>()
            val scheduled = mutableMapOf<TransactionCategory, Long>()
            allocations.forEach {
                planned[it.category] = (planned[it.category] ?: 0) + it.allocated
                scheduled[it.category] = it.used
            }
            return BudgetForecastMonth(
                month = month,
                budget = summary.totalBudget.coerceAtLeast(0),
                allocations = planned
                    .map { (category, amount) -> Allocation(category, amount, scheduled[category] ?: 0) }
                    .sortedWith(compareByDescending<Allocation> { it.planned }.thenBy { it.category.key }),
                outsideByCategory = unallocatedSpending.groupingBy { it.category }.fold(0L) { total, row -> total + row.spent },
                outside = summary.usedInUnallocatedCategories.coerceAtLeast(0),
                statementsDue = statementsDue,
                projection = closingBalance?.let {
                    AllocationBalanceProjection.forMonth(it, allocations, summary, deferredCardSpending, AllocationBalanceProjection.Tense.Projected)
                },
            )
        }
    }
}

/**
 * One projected month through one filter: the same plan the past months of that filter are read
 * against, and what is expected to land on it.
 */
data class BudgetForecastFigures(
    val month: YearMonth,
    val filter: BudgetHistoryFilter,
    /** Zero means nothing was planned: no budget for the month, or no allocation for the category. */
    val planned: Long,
    /** For the whole month, the plan assumed spent in full. For a category, its rows already dated. */
    val inside: Long,
    /** Rows already dated in the month in categories with no allocation then. */
    val outside: Long,
) {
    enum class Status {
        Fits,
        Short,

        /** Costs are expected, but nothing was planned. Never a plan of zero. */
        NoPlan,

        /** Nothing planned and nothing expected. */
        Empty,
    }

    val hasPlan: Boolean get() = planned > 0
    val expected: Long get() = inside + outside

    /** Positive is what is left, negative is the shortfall. */
    val difference: Long get() = planned - expected

    val percentExpected: Int?
        get() = if (hasPlan) (expected.toDouble() / planned * 100).roundToLong().toInt() else null

    val status: Status
        get() = when {
            !hasPlan -> if (expected > 0) Status.NoPlan else Status.Empty
            expected > planned -> Status.Short
            else -> Status.Fits
        }

    /**
     * The three pieces the chart stacks, adding up to [expected]. The part past the plan is its own
     * piece, so it never hides inside the two below it.
     */
    val insideWithinPlan: Long get() = if (hasPlan) minOf(inside, planned) else inside
    val outsideWithinPlan: Long get() = if (hasPlan) minOf(outside, planned - insideWithinPlan) else outside
    val overPlan: Long get() = if (hasPlan) (expected - planned).coerceAtLeast(0) else 0
}

/** The months ahead of the open one, nearest first. Pure: no repository, no clock. */
data class BudgetForecast(val months: List<BudgetForecastMonth>) {

    val isEmpty: Boolean get() = months.all { it.isEmpty }

    fun month(month: YearMonth): BudgetForecastMonth? = months.firstOrNull { it.month == month }

    /** Categories with an allocation in a month ahead, biggest plan first. */
    val plannedCategories: List<TransactionCategory>
        get() {
            val totals = mutableMapOf<TransactionCategory, Long>()
            months.flatMap { it.allocations }.forEach { totals[it.category] = (totals[it.category] ?: 0) + it.planned }
            return totals.entries
                .sortedWith(compareByDescending<Map.Entry<TransactionCategory, Long>> { it.value }.thenBy { it.key.key })
                .map { it.key }
        }

    /** Every month read through [filter]. */
    fun figures(filter: BudgetHistoryFilter): List<BudgetForecastFigures> = months.map { figures(it, filter) }

    private fun figures(month: BudgetForecastMonth, filter: BudgetHistoryFilter): BudgetForecastFigures = when (filter) {
        BudgetHistoryFilter.WholeMonth ->
            BudgetForecastFigures(month.month, filter, month.budget, month.inside, month.outside)
        is BudgetHistoryFilter.Category -> {
            // One category has no full plan to assume: its allocation is the plan, and the rows already
            // dated are what can be said about it. With no allocation those rows are outside costs.
            val allocation = month.allocations.firstOrNull { it.category == filter.category }
            if (allocation != null) BudgetForecastFigures(month.month, filter, allocation.planned, allocation.scheduled, 0)
            else BudgetForecastFigures(month.month, filter, 0, 0, month.outsideByCategory[filter.category] ?: 0)
        }
        // The rule BudgetHistory uses for the past: no budget, or a budget the categories took whole,
        // leaves no outside plan.
        BudgetHistoryFilter.OutsideAllocations -> BudgetForecastFigures(
            month.month, filter,
            planned = if (month.budget > 0) (month.budget - month.allocated).coerceAtLeast(0) else 0,
            inside = 0, outside = month.outside,
        )
    }

    /**
     * The rows behind one month's figures, biggest first. On the budget month for every filter,
     * because these figures have no date-clock total to match. Statement rows are never among them.
     *
     * @param expenses the set [BudgetHistory.transactions] takes.
     */
    fun transactions(filter: BudgetHistoryFilter, month: YearMonth, expenses: List<Transaction>): List<Transaction> {
        val inMonth = expenses.filter { it.budgetMonth == month }
        val matching = when (filter) {
            BudgetHistoryFilter.WholeMonth -> inMonth
            is BudgetHistoryFilter.Category -> inMonth.filter { it.category == filter.category }
            BudgetHistoryFilter.OutsideAllocations -> {
                val planned = month(month)?.allocations.orEmpty().map { it.category }.toSet()
                inMonth.filter { it.category !in planned }
            }
        }
        return matching
            .filter { it.type == TransactionType.Expense && !it.isCreditCardStatement && !(it.hasInstallments && it.parentTransactionId == null) }
            .sortedWith(compareByDescending<Transaction> { it.amount }.thenByDescending { it.date })
    }

    companion object {
        /** How far ahead the history screen reads. */
        const val MONTHS_AHEAD = 6

        val Empty = BudgetForecast(emptyList())
    }
}
