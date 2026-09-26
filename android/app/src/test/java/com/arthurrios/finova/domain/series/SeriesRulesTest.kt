package com.arthurrios.finova.domain.series

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionMode
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/**
 * Ports of the rules pinned by TransactionLogicTests, RecurringDeletionTests and
 * BusinessDayAdjustmentTests on iOS, plus the two deliberate fixes.
 */
class SeriesRulesTest {

    private val today = LocalDate.of(2026, 9, 15)
    private fun draft(amount: Long = 100_00, date: LocalDate = LocalDate.of(2026, 1, 31), rule: BusinessDayRule = BusinessDayRule.Exact) =
        TransactionDraft("Rent", TransactionCategory.HomeMaintenance, TransactionType.Expense, amount, date, rule)

    /** A saved recurring parent (self-linked) with id 1. */
    private fun savedParent(d: TransactionDraft = draft()) = SeriesRules.recurringParent(d).copy(id = 1, parentTransactionId = 1)

    private fun materialized(parent: Transaction): List<Transaction> =
        SeriesRules.missingOccurrences(listOf(parent), emptySet(), today)
            .mapIndexed { i, t -> t.copy(id = 100L + i) }

    // ---- Creation ----

    @Test
    fun recurringParentIsFiledUnderThePickedMonthAndShiftedOffTheWeekend() {
        val saturday = LocalDate.of(2026, 1, 31)
        val parent = SeriesRules.recurringParent(draft(date = saturday, rule = BusinessDayRule.NextBusinessDay))
        assertTrue(parent.isRecurring)
        assertEquals(LocalDate.of(2026, 2, 2), parent.date)
        assertEquals(YearMonth.of(2026, 1), parent.budgetMonth)
        assertEquals(YearMonth.of(2026, 1), parent.slot)
        assertEquals(saturday, parent.unadjusted)
    }

    @Test
    fun selfLinkedParentReadsAsRecurring() {
        assertEquals(TransactionMode.Recurring, savedParent().mode)
    }

    @Test
    fun installmentRemainderGoesOnTheFirstInstallment() {
        val (parent, children) = SeriesRules.installmentSeries(draft(amount = 1_000_01), 3)
        assertEquals(0, parent.amount)
        assertTrue(parent.hasInstallments)
        assertTrue(parent.title.endsWith(SeriesRules.INSTALLMENT_PARENT_SUFFIX))
        assertEquals(listOf(333_35L, 333_33L, 333_33L), children.map { it.amount })
        assertEquals(1_000_01, children.sumOf { it.amount })
        assertEquals(listOf(1, 2, 3), children.map { it.installmentNumber })
        assertTrue(children.all { it.totalInstallments == 3 && it.originalAmount == 1_000_01L })
    }

    @Test
    fun installmentsClampToShortMonthsAndKeepTheirOwnSlot() {
        val (_, children) = SeriesRules.installmentSeries(draft(date = LocalDate.of(2026, 1, 31)), 3)
        assertEquals(
            listOf(LocalDate.of(2026, 1, 31), LocalDate.of(2026, 2, 28), LocalDate.of(2026, 3, 31)),
            children.map { it.unadjusted },
        )
        assertEquals(listOf(YearMonth.of(2026, 1), YearMonth.of(2026, 2), YearMonth.of(2026, 3)), children.map { it.slot })
    }

    @Test(expected = IllegalArgumentException::class)
    fun oneInstallmentIsRejected() {
        SeriesRules.installmentSeries(draft(), 1)
    }

    @Test
    fun installmentChildrenReadAsInstallmentsOnceLinked() {
        val (_, children) = SeriesRules.installmentSeries(draft(), 2)
        assertEquals(TransactionMode.Installments, children.first().copy(parentTransactionId = 9).mode)
    }

    // ---- Materialization ----

    @Test
    fun seriesGeneratesForwardToTheHorizonOnePerMonth() {
        val parent = savedParent()
        val children = materialized(parent)
        assertEquals(YearMonth.of(2026, 2), children.first().slot)
        assertEquals(YearMonth.of(2029, 9), children.last().slot) // today + 36 months
        assertEquals(children.size, children.map { it.slot }.toSet().size)
        assertTrue(children.all { it.parentTransactionId == 1L && !it.isRecurring })
    }

    @Test
    fun occurrencesReturnToTheAnchorDayAfterShortMonths() {
        val children = materialized(savedParent())
        assertEquals(LocalDate.of(2026, 2, 28), children[0].unadjusted)
        assertEquals(LocalDate.of(2026, 3, 31), children[1].unadjusted)
    }

    @Test
    fun weekendOccurrencesMoveButKeepTheirSlot() {
        val parent = savedParent(draft(date = LocalDate.of(2026, 1, 31), rule = BusinessDayRule.NextBusinessDay))
        val oct = materialized(parent).first { it.slot == YearMonth.of(2026, 10) }
        assertEquals(LocalDate.of(2026, 10, 31), oct.unadjusted) // a Saturday
        assertEquals(LocalDate.of(2026, 11, 2), oct.date)
        assertEquals(YearMonth.of(2026, 10), oct.budgetMonth)
    }

    @Test
    fun runningItAgainAddsNothing() {
        val parent = savedParent()
        val all = listOf(parent) + materialized(parent)
        assertTrue(SeriesRules.missingOccurrences(all, emptySet(), today).isEmpty())
    }

    @Test
    fun anExcludedMonthIsNotRecreated() {
        val parent = savedParent()
        val exclusions = setOf(SeriesExclusion(1, YearMonth.of(2026, 5)))
        val slots = SeriesRules.missingOccurrences(listOf(parent), exclusions, today).map { it.slot }
        assertFalse(YearMonth.of(2026, 5) in slots)
        assertTrue(YearMonth.of(2026, 6) in slots)
    }

    @Test
    fun aStoppedSeriesGeneratesNothing() {
        assertTrue(SeriesRules.missingOccurrences(listOf(savedParent().copy(isRecurring = false)), emptySet(), today).isEmpty())
    }

    // ---- Deletion: recurring ----

    @Test
    fun deletingOnlyThisOccurrenceLeavesTheRestAlone() {
        val parent = savedParent()
        val children = materialized(parent)
        val may = children.first { it.slot == YearMonth.of(2026, 5) }
        val plan = SeriesRules.deletion(may, SeriesDeleteOption.ThisOnly, listOf(parent) + children)
        assertEquals(setOf(may.id), plan.deleteIds)
        assertEquals(setOf(SeriesExclusion(1, YearMonth.of(2026, 5))), plan.addExclusions)
    }

    @Test
    fun deletingOnlyTheParentsOccurrenceKeepsTheSeriesAlive() {
        val parent = savedParent()
        val plan = SeriesRules.deletion(parent, SeriesDeleteOption.ThisOnly, listOf(parent) + materialized(parent))
        assertTrue(plan.deleteIds.isEmpty())
        assertEquals(setOf(SeriesExclusion(1, parent.slot)), plan.addExclusions)
    }

    @Test
    fun deletingThisAndRemainingKeepsEarlierInstancesAndStopsTheSeries() {
        val parent = savedParent()
        val children = materialized(parent)
        val may = children.first { it.slot == YearMonth.of(2026, 5) }
        val plan = SeriesRules.deletion(may, SeriesDeleteOption.ThisAndLater, listOf(parent) + children)
        val kept = (listOf(parent) + children).filterNot { it.id in plan.deleteIds }
        assertTrue(kept.all { it.slot < YearMonth.of(2026, 5) })
        assertEquals(4, kept.size) // Jan (parent) .. Apr
        assertEquals(setOf(1L), plan.stopRepeating)
    }

    @Test
    fun deletingThisAndRemainingFromTheParentRemovesEverything() {
        val parent = savedParent()
        val all = listOf(parent) + materialized(parent)
        val plan = SeriesRules.deletion(parent, SeriesDeleteOption.ThisAndLater, all)
        assertEquals(all.map { it.id }.toSet(), plan.deleteIds)
    }

    @Test
    fun deletingAllOccurrencesLeavesNothingBehind() {
        val parent = savedParent()
        val all = listOf(parent) + materialized(parent)
        val plan = SeriesRules.deletion(all[5], SeriesDeleteOption.All, all)
        assertEquals(all.map { it.id }.toSet(), plan.deleteIds)
        assertEquals(setOf(1L), plan.clearExclusionsFor)
    }

    // ---- Deletion: installments ----

    private fun savedInstallments(count: Int = 4): List<Transaction> {
        val (parent, children) = SeriesRules.installmentSeries(draft(amount = 400_00), count)
        return listOf(parent.copy(id = 50)) + children.mapIndexed { i, c -> c.copy(id = 51L + i, parentTransactionId = 50) }
    }

    @Test
    fun deletingOneInstallmentKeepsTheOthersAndTheParent() {
        val rows = savedInstallments()
        val plan = SeriesRules.deletion(rows[2], SeriesDeleteOption.ThisOnly, rows)
        assertEquals(setOf(rows[2].id), plan.deleteIds)
    }

    @Test
    fun deletingThisAndRemainingInstallmentsKeepsEarlierOnes() {
        val rows = savedInstallments()
        val plan = SeriesRules.deletion(rows[3], SeriesDeleteOption.ThisAndLater, rows) // installment 3
        assertEquals(setOf(rows[3].id, rows[4].id), plan.deleteIds)
    }

    @Test
    fun deletingAllInstallmentsAlsoRemovesTheHiddenParent() {
        val rows = savedInstallments()
        val plan = SeriesRules.deletion(rows[1], SeriesDeleteOption.All, rows)
        assertEquals(rows.map { it.id }.toSet(), plan.deleteIds)
    }

    @Test
    fun theLastInstallmentLeavingTakesTheParentWithIt() {
        val rows = savedInstallments(count = 2).let { listOf(it[0], it[1]) } // one child left
        val plan = SeriesRules.deletion(rows[1], SeriesDeleteOption.ThisOnly, rows)
        assertEquals(setOf(rows[0].id, rows[1].id), plan.deleteIds)
    }
}
