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
     * statement). What a closed month's figures still read; an open month reads
     * [balanceCommitments], which also holds debt run up in earlier months.
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

    /**
     * What is on a card at the end of [month] and has not reached that month's balance: every stored
     * card row counted by then whose statement is due later, or that has no live statement, which
     * never reaches the balance at all. Signed like [com.arthurrios.finova.domain.card.StatementBook.total],
     * so refunds and payment credits net out as they do on the statement.
     *
     * A purchase counts from its budget month. A credit counts from its own date: a payment's debit
     * moves the balance on that date, while the credit's budget month is the statement's closing
     * month. Reading that month instead counted a payment made before closing twice, and dropped the
     * debt for a scheduled payment still to come.
     */
    fun outstandingCard(rows: List<Transaction>, statements: List<CreditCardStatement>, month: YearMonth): Long =
        outstandingCard(cardRows(rows, statements), month)

    private class CardRow(val countsFrom: YearMonth, val settles: YearMonth?, val owed: Long)

    private fun cardRows(rows: List<Transaction>, statements: List<CreditCardStatement>): List<CardRow> {
        val dueMonth = statements.associate { it.id to YearMonth.from(it.dueDate) }
        return rows.filter { it.creditCardId != null && !it.isCreditCardStatement && !it.isSettledEarly }.map { row ->
            CardRow(
                countsFrom = if (row.type == TransactionType.Income) YearMonth.from(row.date) else row.budgetMonth,
                settles = row.statementId?.let { dueMonth[it] },
                owed = -row.signedAmount,
            )
        }
    }

    private fun outstandingCard(cardRows: List<CardRow>, month: YearMonth): Long =
        cardRows.filter { it.countsFrom <= month && (it.settles == null || it.settles > month) }.sumOf { it.owed }

    /** Statement amounts per month they fall due. [ledgerRows] are the rows the balance is built from. */
    fun statementsDue(ledgerRows: List<Transaction>): Map<YearMonth, Long> =
        ledgerRows.filter { it.isCreditCardStatement && it.type == TransactionType.Expense }
            .groupBy { YearMonth.from(it.date) }
            .mapValues { (_, rows) -> rows.sumOf { it.amount } }

    /**
     * The two terms an open month's projection takes off its closing balance, for every month from
     * [current] through [through]. One pass for the whole range, so the card and the budget history
     * read one table and cannot disagree. No entry for a closed month: those keep their own figures.
     *
     * @param rows stored rows, never the statement rows.
     * @param statementsDue from [statementsDue], over the same rows the closing balance used.
     */
    fun balanceCommitments(
        allocations: List<AllocationRow>,
        rows: List<Transaction>,
        statements: List<CreditCardStatement>,
        statementsDue: Map<YearMonth, Long>,
        current: YearMonth,
        through: YearMonth,
    ): Map<YearMonth, BalanceCommitment> {
        val cardRows = cardRows(rows, statements)
        val commitments = linkedMapOf<YearMonth, BalanceCommitment>()
        var reserved = 0L
        var month = current
        while (month <= through) {
            reserved += AllocationBalanceProjection.reservedPlan(withUsage(allocations, rows, month), statementsDue[month] ?: 0)
            commitments[month] = BalanceCommitment(outstandingCard(cardRows, month), reserved)
            month = month.plusMonths(1)
        }
        return commitments
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

/** What an open month's projection takes off its closing balance. See [Allocations.balanceCommitments]. */
data class BalanceCommitment(
    /** Money on a card that this month's balance has not absorbed. See [Allocations.outstandingCard]. */
    val outstandingCard: Long,
    /** The plan left unspent from the current month through this one. */
    val reservedPlan: Long,
)

/**
 * The projected end-of-month balance and the saved-versus-overspent comparison on the
 * allocations card. Pure port of AllocationBalanceProjection.swift.
 *
 * For an open month: `projected = base - outstanding card - plan(current..month)`. The closing
 * balance is cumulative, so it holds every salary up to the month. It has to carry every plan up to
 * the month too, or each month ahead would keep what the months before it planned to spend.
 *
 * @property unspentAllocations this month's own unspent plan. [reservedPlan] is what the balance loses.
 * @property reservedPlan the unspent plan of the current month through this one.
 * @property deferredCardSpending the outstanding card debt; negative when credits exceed it.
 */
data class AllocationBalanceProjection(
    val base: Long,
    val unspentAllocations: Long,
    val unallocatedHeadroom: Long,
    val overspent: Long,
    val usedWithinAllocations: Long,
    val reservedPlan: Long,
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
        /**
         * What one month adds to the plan still to leave the balance: each allocation's unspent part.
         * Statement rows never count as usage, so a Credit Card allocation is drawn down by the bills
         * due in the month here, or the bill would come off twice: once as the statement in the
         * balance and again as an untouched plan.
         */
        fun reservedPlan(allocations: List<BudgetAllocation>, statementsDue: Long): Long =
            allocations.sumOf {
                val bill = if (it.category == TransactionCategory.CreditCard) statementsDue else 0
                (it.remaining - bill).coerceAtLeast(0)
            }

        /**
         * The figures a month's card reads, in the one order they are handed over: the dashboard and
         * the budget history's months ahead both come through here, so they cannot disagree.
         */
        fun forMonth(
            base: Long,
            allocations: List<BudgetAllocation>,
            unallocated: UnallocatedSummary,
            deferredCardSpending: Long,
            tense: Tense,
            reservedPlan: Long? = null,
        ): AllocationBalanceProjection = of(
            base = base,
            allocations = allocations,
            unallocatedSpending = unallocated.usedInUnallocatedCategories,
            unallocatedHeadroom = unallocated.unallocated,
            deferredCardSpending = deferredCardSpending,
            tense = tense,
            reservedPlan = reservedPlan,
        )

        /**
         * @param deferredCardSpending not clamped: a card's credit nets against its debt, and a net
         *   credit does reach the balance, through the next statement it lowers.
         * @param reservedPlan null reads this month's own unspent plan: a closed month, which has no
         *   months of plan behind it.
         */
        fun of(
            base: Long,
            allocations: List<BudgetAllocation>,
            unallocatedSpending: Long = 0,
            unallocatedHeadroom: Long = 0,
            deferredCardSpending: Long = 0,
            tense: Tense,
            reservedPlan: Long? = null,
        ): AllocationBalanceProjection {
            val unspent = allocations.sumOf { it.remaining.coerceAtLeast(0) }
            val reserved = reservedPlan ?: unspent
            return AllocationBalanceProjection(
                base = base,
                unspentAllocations = unspent,
                unallocatedHeadroom = unallocatedHeadroom.coerceAtLeast(0),
                overspent = allocations.sumOf { (-it.remaining).coerceAtLeast(0) } + unallocatedSpending.coerceAtLeast(0),
                usedWithinAllocations = allocations.sumOf { minOf(it.used, it.allocated).coerceAtLeast(0) },
                reservedPlan = reserved,
                deferredCardSpending = deferredCardSpending,
                projected = base - deferredCardSpending - reserved,
                tense = tense,
            )
        }
    }
}
