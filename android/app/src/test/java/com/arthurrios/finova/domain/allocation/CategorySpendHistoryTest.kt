package com.arthurrios.finova.domain.allocation

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.YearMonth

class CategorySpendHistoryTest {
    private val now = YearMonth.of(2026, 9)
    private val market = TransactionCategory.Market
    private fun alloc(id: Long, month: YearMonth, amount: Long = 10_000) = AllocationRow(id = id, month = month, category = market, amount = amount)
    private fun spend(id: Long, month: YearMonth, amount: Long) = Transaction(
        id = id, title = "S", category = market, type = TransactionType.Expense, amount = amount,
        date = month.atDay(5), budgetMonth = month,
    )

    @Test fun fewerThanFourMonthsIsNotEnough() {
        val allocations = (1..3).map { alloc(it.toLong(), now.minusMonths(it.toLong())) }
        val h = CategorySpendHistory.of(listOf(market), now, allocations, emptyList(), now).getValue(market)
        assertEquals(CategorySpendHistory.Verdict.NotEnoughHistory, h.verdict)
    }

    @Test fun aNarrowRangeIsConsistentAndAMonthWithoutSpendingCountsAsZero() {
        val months = (1..4).map { now.minusMonths(it.toLong()) }
        val allocations = months.mapIndexed { i, m -> alloc(i + 1L, m) }
        val rows = listOf(spend(1, months[0], 3_000), spend(2, months[1], 2_000), spend(3, months[2], 1_000))
        val h = CategorySpendHistory.of(listOf(market), now, allocations, rows, now).getValue(market)
        assertEquals(CategorySpendHistory.Verdict.Consistent(0.0, 0.3, 4), h.verdict)
        assertEquals(0 to 30, h.percentRange)
    }

    @Test fun aWideRangeIsVariedAndOverspendIsNotClamped() {
        val months = (1..4).map { now.minusMonths(it.toLong()) }
        val allocations = months.mapIndexed { i, m -> alloc(i + 1L, m) }
        val rows = listOf(spend(1, months[0], 14_000), spend(2, months[1], 500), spend(3, months[2], 500), spend(4, months[3], 500))
        val h = CategorySpendHistory.of(listOf(market), now, allocations, rows, now).getValue(market)
        assertTrue(h.verdict is CategorySpendHistory.Verdict.Varied)
        assertEquals(5 to 140, h.percentRange)
    }

    @Test fun theViewedMonthAndLaterAreLeftOut() {
        // Viewing July: only months before July count, though August is closed.
        val allocations = listOf(alloc(1, YearMonth.of(2026, 8)), alloc(2, YearMonth.of(2026, 6)))
        val h = CategorySpendHistory.of(listOf(market), YearMonth.of(2026, 7), allocations, emptyList(), now).getValue(market)
        assertEquals(1, h.sampleCount)
    }

    @Test fun futureAllocationsNeverCount() {
        val allocations = listOf(alloc(1, now), alloc(2, now.plusMonths(1)))
        assertTrue(CategorySpendHistory.of(listOf(market), now.plusMonths(3), allocations, emptyList(), now).isEmpty())
    }
}
