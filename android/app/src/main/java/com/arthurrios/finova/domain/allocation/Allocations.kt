package com.arthurrios.finova.domain.allocation

import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.time.SeriesMonths
import java.time.YearMonth

/**
 * A stored allocation: part of a month's budget set aside for one category. Port of
 * BudgetAllocationModel. A series parent does not point at itself (unlike transactions); its
 * months point at it. A deleted month of a series stays as a tombstone so it is not recreated.
 */
data class AllocationRow(
    val id: Long = 0,
    val month: YearMonth,
    val category: TransactionCategory,
    val amount: Long,
    val isRecurring: Boolean = false,
    val parentId: Long? = null,
    val isDeleted: Boolean = false,
) {
    val seriesId: Long get() = parentId ?: id
}

enum class AllocationStatus { UnderBudget, NearLimit, OverBudget }

/** An allocation with what was spent against it (BudgetAllocation on iOS). */
data class BudgetAllocation(
    val id: Long,
    val month: YearMonth,
    val category: TransactionCategory,
    val allocated: Long,
    val isRecurring: Boolean,
    val parentId: Long?,
    val used: Long,
) {
    val remaining: Long get() = allocated - used
    val usagePercentage: Double get() = if (allocated <= 0) 0.0 else used.toDouble() / allocated * 100
    val status: AllocationStatus
        get() = when {
            usagePercentage > 100 -> AllocationStatus.OverBudget
            usagePercentage >= 80 -> AllocationStatus.NearLimit
            else -> AllocationStatus.UnderBudget
        }
    val isPartOfSeries: Boolean get() = isRecurring || parentId != null
}

/** The part of the budget no allocation covers (UnallocatedBudgetSummary). */
data class UnallocatedSummary(
    val month: YearMonth,
    val totalBudget: Long,
    val totalAllocated: Long,
    val usedInUnallocatedCategories: Long,
) {
    val unallocated: Long get() = totalBudget - totalAllocated
    val unallocatedRemaining: Long get() = unallocated - usedInUnallocatedCategories
    val isOverspent: Boolean get() = unallocatedRemaining < 0
}

data class UnallocatedSpending(val category: TransactionCategory, val spent: Long)

enum class AllocationEditScope { ThisOnly, ThisAndLater, Through, All }

/** Pure ports of BudgetAllocationService and BudgetAllocationRepository. */
object Allocations {

    /**
     * Spending per category in a month: expenses counted in that budget month, card purchases
     * included, installments paid early left out (calculateUsageByCategory).
     */
    fun usage(rows: List<Transaction>, month: YearMonth): Map<TransactionCategory, Long> =
        rows.filter { it.budgetMonth == month && it.type == TransactionType.Expense && !it.isSettledEarly && !it.isCreditCardStatement }
            .groupBy { it.category }
            .mapValues { (_, list) -> list.sumOf { it.amount } }

    fun withUsage(allocations: List<AllocationRow>, rows: List<Transaction>, month: YearMonth): List<BudgetAllocation> {
        val used = usage(rows, month)
        return live(allocations).filter { it.month == month }.map {
            BudgetAllocation(it.id, it.month, it.category, it.amount, it.isRecurring, it.parentId, used[it.category] ?: 0)
        }
    }

    fun unallocatedSummary(allocations: List<AllocationRow>, rows: List<Transaction>, budgets: List<Budget>, month: YearMonth): UnallocatedSummary {
        val inMonth = live(allocations).filter { it.month == month }
        val covered = inMonth.map { it.category }.toSet()
        return UnallocatedSummary(
            month = month,
            totalBudget = budgets.firstOrNull { it.month == month }?.amount ?: 0,
            totalAllocated = inMonth.sumOf { it.amount },
            usedInUnallocatedCategories = usage(rows, month).filterKeys { it !in covered }.values.sum(),
        )
    }

    /** Categories spent in with no allocation, biggest first. */
    fun unallocatedSpending(allocations: List<AllocationRow>, rows: List<Transaction>, month: YearMonth): List<UnallocatedSpending> {
        val covered = live(allocations).filter { it.month == month }.map { it.category }.toSet()
        return usage(rows, month).filter { (category, spent) -> category !in covered && spent > 0 }
            .map { (category, spent) -> UnallocatedSpending(category, spent) }
            .sortedByDescending { it.spent }
    }

    /**
     * Card spending counted in [month] whose statement is due in a later month (or has no
     * statement): it is in the allocations' "used" already but has not left the balance yet, so
     * the projection takes it off (deferredCardSpending).
     */
    fun deferredCardSpending(rows: List<Transaction>, statements: List<CreditCardStatement>, month: YearMonth): Long {
        val dueMonth = statements.associate { it.id to YearMonth.from(it.dueDate) }
        return rows.filter {
            it.budgetMonth == month && it.type == TransactionType.Expense && it.creditCardId != null &&
                !it.isCreditCardStatement && !it.isSettledEarly
        }.sumOf { row ->
            val due = row.statementId?.let { dueMonth[it] }
            if (due == null || due > month) row.amount else 0
        }
    }

    /** Categories that can get a new allocation in [month]. */
    fun availableCategories(allocations: List<AllocationRow>, month: YearMonth): List<TransactionCategory> {
        val taken = live(allocations).filter { it.month == month }.map { it.category }.toSet()
        return TransactionCategory.entries.filter { it !in taken }
    }

    fun live(allocations: List<AllocationRow>) = allocations.filterNot { it.isDeleted }

    // ---- Series ------------------------------------------------------------------------------

    /**
     * The months a series still needs, from its parent's month through the horizon (or [endMonth]).
     * Skips months it already has, months the user deleted, and months another allocation of the
     * same category holds. Each new month copies the latest amount at or before it
     * (materializeSeries). A parent that stopped repeating is filled in but never extended.
     */
    fun missingSeriesMonths(allocations: List<AllocationRow>, parentId: Long, endMonth: YearMonth?, thisMonth: YearMonth): List<AllocationRow> {
        val live = live(allocations)
        val parent = live.firstOrNull { it.id == parentId } ?: return emptyList()
        val series = live.filter { it.id == parentId || it.parentId == parentId }.sortedBy { it.month }
        val end = endMonth ?: if (parent.isRecurring) null else series.maxOf { it.month }
        val tombstoned = allocations.filter { it.isDeleted && it.seriesId == parentId }.map { it.month }.toSet()
        val own = series.map { it.month }.toMutableSet()
        val foreign = live.filter { it.category == parent.category && it.month !in own }.map { it.month }.toSet()
        return SeriesMonths.seriesMonths(parent.month, end, thisMonth)
            .filter { it > parent.month && it !in own && it !in tombstoned && it !in foreign }
            .map { month ->
                val template = series.lastOrNull { it.month <= month } ?: parent
                AllocationRow(month = month, category = parent.category, amount = template.amount, isRecurring = true, parentId = parentId)
            }
    }

    /** Parents whose series may need months: repeating, or owning at least one month. */
    fun seriesParents(allocations: List<AllocationRow>): List<AllocationRow> {
        val live = live(allocations)
        return live.filter { candidate -> candidate.parentId == null && (candidate.isRecurring || live.any { it.parentId == candidate.id }) }
    }

    /** The ids an edit reaches. Deleted months are never edited. */
    fun editTargets(allocations: List<AllocationRow>, id: Long, scope: AllocationEditScope, through: YearMonth? = null): Set<Long> {
        val live = live(allocations)
        val target = live.firstOrNull { it.id == id } ?: return emptySet()
        val keys = seriesKeys(target, live)
        return when (scope) {
            AllocationEditScope.ThisOnly -> setOf(id)
            // The series root follows too, so months created later copy the new amount.
            AllocationEditScope.ThisAndLater -> live.filter { it.id == id || it.id in keys || (isMember(it, keys) && it.month >= target.month) }.map { it.id }.toSet()
            // "This through a month": this month to [through], inclusive.
            AllocationEditScope.Through -> live.filter {
                it.id == id || (isMember(it, keys) && it.month >= target.month && (through == null || it.month <= through))
            }.map { it.id }.toSet()
            AllocationEditScope.All -> live.filter { it.id == id || isMember(it, keys) }.map { it.id }.toSet()
        }
    }

    /** The series' months from this one on, for the "through which month?" choice. */
    fun laterSeriesMonths(allocations: List<AllocationRow>, id: Long): List<YearMonth> {
        val live = live(allocations)
        val target = live.firstOrNull { it.id == id } ?: return emptyList()
        val keys = seriesKeys(target, live)
        return live.filter { isMember(it, keys) && it.month >= target.month }.map { it.month }.distinct().sorted()
    }

    fun isPartOfSeries(allocations: List<AllocationRow>, id: Long): Boolean {
        val live = live(allocations)
        val target = live.firstOrNull { it.id == id } ?: return false
        return target.isRecurring || target.parentId != null || live.any { it.parentId == id }
    }

    /**
     * Same-category allocations a new repeating one would meet: after [month], up to [endMonth]
     * when it has one. (iOS checks every later month, even past the end month.)
     */
    fun conflicts(allocations: List<AllocationRow>, category: TransactionCategory, month: YearMonth, endMonth: YearMonth?): List<AllocationRow> =
        live(allocations).filter { it.category == category && it.month > month && (endMonth == null || it.month <= endMonth) }
            .sortedBy { it.month }

    data class DeletePlan(val remove: Set<Long>, val tombstone: Set<Long>, val stopRepeating: Long?)

    /**
     * Deleting: a month of a series is tombstoned so it is not recreated; a one-off is removed.
     * "This and later" tombstones this month and every later one and stops the series repeating
     * (deleteRecurringAllocationAndFuture); "all" tombstones every month.
     */
    fun deletePlan(allocations: List<AllocationRow>, id: Long, scope: AllocationEditScope): DeletePlan {
        val live = live(allocations)
        val target = live.firstOrNull { it.id == id } ?: return DeletePlan(emptySet(), emptySet(), null)
        val keys = seriesKeys(target, live)
        val inSeries = target.isRecurring || target.parentId != null || live.any { it.parentId == target.id }
        return when (scope) {
            AllocationEditScope.ThisOnly ->
                if (target.isRecurring || target.parentId != null) DeletePlan(emptySet(), setOf(id), null)
                else DeletePlan(setOf(id), emptySet(), null)
            AllocationEditScope.ThisAndLater -> DeletePlan(
                emptySet(),
                live.filter { it.id == id || (isMember(it, keys) && it.month >= target.month) }.map { it.id }.toSet(),
                stopRepeating = if (inSeries) resolvedRoot(target, live) else null,
            )
            AllocationEditScope.All, AllocationEditScope.Through ->
                DeletePlan(emptySet(), live.filter { it.id == id || isMember(it, keys) }.map { it.id }.toSet(), null)
        }
    }

    private fun resolvedRoot(row: AllocationRow, live: List<AllocationRow>): Long {
        val pointer = row.parentId ?: return row.id
        return if (live.any { it.id == pointer }) pointer else row.id
    }

    private fun seriesKeys(row: AllocationRow, live: List<AllocationRow>): Set<Long> {
        val root = resolvedRoot(row, live)
        return setOfNotNull(root, row.parentId)
    }

    private fun isMember(row: AllocationRow, keys: Set<Long>) = row.id in keys || (row.parentId != null && row.parentId in keys)
}

/**
 * The projected end-of-month balance and the saved-versus-overspent comparison on the
 * allocations card. Pure port of AllocationBalanceProjection.swift.
 */
data class AllocationBalanceProjection(
    val base: Long,
    val unspentAllocations: Long,
    val unallocatedHeadroom: Long,
    val overspent: Long,
    val usedWithinAllocations: Long,
    val deferredCardSpending: Long,
    val projected: Long,
    val tense: Tense,
) {
    enum class Tense { Projected, Actual }

    val totalSaved: Long get() = unspentAllocations + unallocatedHeadroom
    val netSaved: Long get() = totalSaved - overspent
    val isOverCommitted: Boolean get() = tense == Tense.Projected && projected < 0
    /** An open month leads with the projection; a closed one with what the plan saved. */
    val headline: Long get() = if (tense == Tense.Projected) projected else netSaved
    val shortfall: Long get() = if (isOverCommitted) -projected else 0

    /** (projected, saved, overspent) shares of the bar; all zero when there is nothing to compare. */
    val barShares: Triple<Float, Float, Float>
        get() {
            val survives = projected.coerceAtLeast(0)
            val total = survives + totalSaved + overspent
            if (total <= 0) return Triple(0f, 0f, 0f)
            return Triple(survives.toFloat() / total, totalSaved.toFloat() / total, overspent.toFloat() / total)
        }

    companion object {
        fun of(
            base: Long,
            allocations: List<BudgetAllocation>,
            unallocatedSpending: Long = 0,
            unallocatedHeadroom: Long = 0,
            deferredCardSpending: Long = 0,
            tense: Tense,
        ): AllocationBalanceProjection {
            val unspent = allocations.sumOf { it.remaining.coerceAtLeast(0) }
            val deferred = deferredCardSpending.coerceAtLeast(0)
            return AllocationBalanceProjection(
                base = base,
                unspentAllocations = unspent,
                unallocatedHeadroom = unallocatedHeadroom.coerceAtLeast(0),
                overspent = allocations.sumOf { (-it.remaining).coerceAtLeast(0) } + unallocatedSpending.coerceAtLeast(0),
                usedWithinAllocations = allocations.sumOf { minOf(it.used, it.allocated).coerceAtLeast(0) },
                deferredCardSpending = deferred,
                projected = base - deferred - unspent,
                tense = tense,
            )
        }
    }
}
