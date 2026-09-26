package com.arthurrios.finova.domain.allocation

import com.arthurrios.finova.domain.allocation.AllocationBalanceProjection.Tense
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.YearMonth

/** Ports of FinovaTests/AllocationBalanceProjectionTests.swift. */
class AllocationBalanceProjectionTest {
    private fun a(category: TransactionCategory, allocated: Long, used: Long) =
        BudgetAllocation(0, YearMonth.of(2026, 9), category, allocated, false, null, used)

    private fun p(
        base: Long, allocations: List<BudgetAllocation>, off: Long = 0, headroom: Long = 0, deferred: Long = 0, tense: Tense = Tense.Projected,
    ) = AllocationBalanceProjection.of(base, allocations, off, headroom, deferred, tense)

    private fun assertShares(projection: AllocationBalanceProjection) {
        val (x, y, z) = projection.barShares
        val sum = x + y + z
        if (sum != 0f) assertEquals(1f, sum, 0.0001f)
        assertTrue(x >= 0 && y >= 0 && z >= 0)
    }

    @Test fun projectedIsBalanceMinusUnspentAllocations() {
        val p = p(428_000, listOf(a(Meals, 90_000, 52_000), a(Savings, 48_000, 0)))
        assertEquals(86_000L, p.unspentAllocations)
        assertEquals(342_000L, p.projected)
    }

    @Test fun noAllocationsLeavesBalanceUntouchedAndPlotsNothing() {
        val p = p(428_000, emptyList())
        assertEquals(0L, p.overspent); assertEquals(0L, p.netSaved); assertEquals(428_000L, p.projected)
        assertFalse(p.isOverCommitted); assertShares(p)
    }

    @Test fun overspentAllocationClampsAndDoesNotCreditTheProjection() {
        assertEquals(100_000L, p(100_000, listOf(a(Meals, 50_000, 70_000))).projected)
    }

    @Test fun overspentCategoryDoesNotOffsetAnotherCategorysHeadroom() {
        val p = p(100_000, listOf(a(Meals, 50_000, 70_000), a(Transportation, 30_000, 0)))
        assertEquals(30_000L, p.unspentAllocations); assertEquals(70_000L, p.projected)
    }

    @Test fun negativeBaseIsCarriedThrough() {
        val p = p(-20_000, listOf(a(Meals, 10_000, 0)))
        assertEquals(-30_000L, p.projected); assertTrue(p.isOverCommitted)
    }

    @Test fun cardPurchaseDoesNotRaiseTheProjection() {
        val before = p(100_000, listOf(a(Market, 50_000, 10_000)))
        val after = p(100_000, listOf(a(Market, 50_000, 25_000)), deferred = 15_000)
        assertEquals(60_000L, before.projected); assertEquals(before.projected, after.projected)
    }

    @Test fun deferredCardSpendingComesOffTheProjectionOnly() {
        val allocations = listOf(a(Meals, 90_000, 52_000))
        val without = p(400_000, allocations, off = 8_000, headroom = 20_000)
        val with = p(400_000, allocations, off = 8_000, headroom = 20_000, deferred = 30_000)
        assertEquals(without.projected - 30_000, with.projected)
        assertEquals(without.totalSaved, with.totalSaved); assertEquals(without.netSaved, with.netSaved)
        assertEquals(without.usedWithinAllocations, with.usedWithinAllocations)
    }

    @Test fun negativeDeferredCardSpendingIsIgnored() {
        val p = p(100_000, emptyList(), deferred = -25_000)
        assertEquals(0L, p.deferredCardSpending); assertEquals(100_000L, p.projected)
    }

    @Test fun cardDebtCanOverCommitAMonthTheAllocationsAloneWouldNot() {
        val allocations = listOf(a(Meals, 30_000, 0))
        assertFalse(p(40_000, allocations).isOverCommitted)
        val with = p(40_000, allocations, deferred = 25_000)
        assertTrue(with.isOverCommitted); assertEquals(-15_000L, with.projected); assertEquals(15_000L, with.shortfall)
        assertShares(with)
    }

    @Test fun closedMonthIsNeverFlaggedOverCommitted() {
        val actual = p(50_000, listOf(a(Utilities, 90_000, 0)), tense = Tense.Actual)
        assertTrue(actual.projected < 0); assertFalse(actual.isOverCommitted)
    }

    @Test fun fundedSavingsAllocationsAreNotCountedAsSaved() {
        val p = p(400_000, listOf(a(Investments, 40_000, 40_000), a(Meals, 90_000, 90_000)))
        assertEquals(0L, p.unspentAllocations); assertEquals(130_000L, p.usedWithinAllocations); assertEquals(0L, p.totalSaved)
    }

    @Test fun overAllocationDoesNotReadAsNegativeSaving() {
        val p = p(400_000, listOf(a(Meals, 90_000, 0)), headroom = -20_000)
        assertEquals(0L, p.unallocatedHeadroom); assertEquals(90_000L, p.totalSaved)
    }

    @Test fun savedIsWhatCameInUnderPlanAndOverspentIsEveryOverrun() {
        val p = p(400_000, listOf(a(Meals, 90_000, 52_000), a(Utilities, 60_000, 63_060), a(Donations, 44_000, 36_500)))
        assertEquals(45_500L, p.unspentAllocations); assertEquals(3_060L, p.overspent); assertEquals(42_440L, p.netSaved)
        assertShares(p)
    }

    @Test fun offPlanSpendingCountsAsOverspent() {
        val allocations = listOf(a(Meals, 90_000, 52_000))
        val without = p(400_000, allocations)
        val with = p(400_000, allocations, off = 18_000)
        assertEquals(18_000L, with.overspent); assertEquals(without.projected, with.projected)
        assertEquals(without.netSaved - 18_000, with.netSaved)
    }

    @Test fun netGoesNegativeWhenOverspendingDominates() {
        val p = p(400_000, listOf(a(Meals, 50_000, 52_000)), off = 40_000)
        assertEquals(42_000L, p.overspent); assertEquals(-42_000L, p.netSaved)
    }

    @Test fun barComparesProjectedAgainstSavedAndOverspent() {
        val p = p(400_000, listOf(a(Meals, 100_000, 40_000)), headroom = 20_000)
        val (x, y, z) = p.barShares
        assertEquals(340_000f / 420_000f, x, 0.0001f); assertEquals(80_000f / 420_000f, y, 0.0001f); assertEquals(0f, z)
    }

    @Test fun overCommittedBarDropsTheProjectedSegment() {
        val p = p(50_000, listOf(a(Meals, 200_000, 0)))
        assertEquals(0f, p.barShares.first); assertEquals(1f, p.barShares.second, 0.0001f)
    }

    @Test fun barIsEmptyWhenThereIsNothingToCompare() {
        assertEquals(Triple(0f, 0f, 0f), p(0, emptyList()).barShares)
    }

    @Test fun closedMonthLeadsWithWhatThePlanSavedAndOpenMonthWithTheProjection() {
        val allocations = listOf(a(Meals, 90_000, 52_000))
        assertEquals(p(400_000, allocations, tense = Tense.Actual).netSaved, p(400_000, allocations, tense = Tense.Actual).headline)
        assertEquals(p(400_000, allocations).projected, p(400_000, allocations).headline)
    }
}
