package com.arthurrios.finova.domain.budget

import com.arthurrios.finova.domain.model.Budget
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.YearMonth

/** Same cases as iOS `BudgetMultiMonthTests`, so both platforms agree. */
class BudgetRangeTest {

    private val jan = YearMonth.of(2031, 1)
    private fun month(offset: Long) = jan.plusMonths(offset)

    /**
     * A stand-in for Room's `withTransaction`: it keeps a copy of the table and puts it back when
     * the block throws, which is what SQLite's ROLLBACK does.
     */
    private class FakeTable(initial: Map<YearMonth, Long> = emptyMap(), val failOn: YearMonth? = null) {
        val rows = initial.toMutableMap()
        var transactions = 0
        val transaction: suspend (suspend () -> Unit) -> Unit = { block ->
            transactions++
            val before = rows.toMap()
            try {
                block()
            } catch (e: Throwable) {
                rows.clear()
                rows.putAll(before)
                throw e
            }
        }
        val upsert: suspend (Budget) -> Unit = { budget ->
            if (budget.month == failOn) throw IllegalStateException("forced failure")
            rows[budget.month] = budget.amount
        }
    }

    private fun save(table: FakeTable, end: YearMonth, amount: Long, replace: Boolean) = runBlocking {
        val months = BudgetRange.monthsToWrite(table.rows.keys, jan, end, replace)
        BudgetRange.write(months, amount, table.transaction, table.upsert)
    }

    // Month range

    @Test
    fun monthsCoverEveryMonthAcrossAYearEnd() {
        assertEquals((10L..14L).map(::month), BudgetRange.months(month(10), month(14)))
    }

    @Test
    fun monthsIsEmptyWhenEndIsBeforeStart() {
        assertEquals(emptyList<YearMonth>(), BudgetRange.months(month(3), month(1)))
    }

    // Range write

    @Test
    fun oneSaveWritesTheAmountToEveryMonthInTheRange() {
        val table = FakeTable()
        save(table, month(5), 300_000, replace = true)
        assertEquals((0L..5L).associate { month(it) to 300_000L }, table.rows)
        assertEquals("all months in one transaction", 1, table.transactions)
    }

    // Conflicts

    @Test
    fun existingMonthsAreListedInCalendarOrder() {
        val existing = listOf(month(4), month(1), month(9))
        assertEquals(listOf(month(1), month(4)), BudgetRange.existingIn(existing, jan, month(5)))
    }

    @Test
    fun replaceOverwritesTheMonthsThatAlreadyHaveABudget() {
        val table = FakeTable(mapOf(month(1) to 50_000L, month(2) to 60_000L))
        save(table, month(3), 300_000, replace = true)
        assertEquals((0L..3L).associate { month(it) to 300_000L }, table.rows)
    }

    @Test
    fun keepExistingFillsOnlyTheEmptyMonths() {
        val table = FakeTable(mapOf(month(1) to 50_000L, month(2) to 60_000L))
        save(table, month(3), 300_000, replace = false)
        assertEquals(
            mapOf(month(0) to 300_000L, month(1) to 50_000L, month(2) to 60_000L, month(3) to 300_000L),
            table.rows,
        )
    }

    @Test
    fun keepExistingWithEveryMonthTakenWritesNothing() {
        val table = FakeTable(mapOf(month(0) to 1L, month(1) to 2L))
        save(table, month(1), 300_000, replace = false)
        assertEquals(mapOf(month(0) to 1L, month(1) to 2L), table.rows)
        assertEquals(0, table.transactions)
    }

    // All or nothing

    @Test
    fun aFailureMidwayWritesNoMonthAtAll() {
        val table = FakeTable(mapOf(month(1) to 50_000L), failOn = month(3))
        try {
            save(table, month(5), 300_000, replace = true)
            fail("the forced failure must surface")
        } catch (e: IllegalStateException) {
            // expected
        }
        assertEquals(
            "the rollback must undo the months written before the failure, and the replace too",
            mapOf(month(1) to 50_000L), table.rows,
        )
    }

    // Single month is unchanged

    @Test
    fun aRangeOfOneMonthIsJustThatMonth() {
        assertEquals(listOf(jan), BudgetRange.months(jan, jan))
        assertTrue(BudgetRange.existingIn(listOf(month(1)), jan, jan).isEmpty())
    }
}
