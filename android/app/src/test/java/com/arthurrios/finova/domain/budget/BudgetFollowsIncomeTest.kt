package com.arthurrios.finova.domain.budget

import com.arthurrios.finova.domain.budget.BudgetFollowsIncome.Settings
import com.arthurrios.finova.domain.fx.ForeignAmount
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.YearMonth

/** Port of BudgetFollowsIncomeTests.swift (the pure rules). */
class BudgetFollowsIncomeTest {
    private val nov = YearMonth.of(2026, 11)
    private val oct = nov.minusMonths(1)
    private val dec = nov.plusMonths(1)
    private val on = Settings(isEnabled = true, percent = 80, startMonth = nov)

    private fun income(amount: Long, month: YearMonth = nov) = Transaction(
        title = "Salary", category = TransactionCategory.Salary, type = TransactionType.Income,
        amount = amount, date = month.atDay(5), budgetMonth = month,
    )

    @Test fun budgetIsIncomeTimesPercentRoundedHalfUp() {
        assertEquals(800_000L, BudgetFollowsIncome.budget(1_000_000, 80))
        assertEquals(1L, BudgetFollowsIncome.budget(1, 50)) // 0.5 → 1
        assertEquals(0L, BudgetFollowsIncome.budget(1, 49)) // 0.49 → 0
        assertEquals(0L, BudgetFollowsIncome.budget(0, 80))
    }

    @Test fun onlyPlainCashIncomeCounts() {
        val rows = listOf(
            income(1_000),
            income(50).copy(creditCardId = 1), // card refund
            income(70).copy(statementPaymentId = 9), // credit side of a statement payment
            income(80).copy(isCancellationRefund = true),
            income(90).copy(isEarlyPayment = true),
            income(5).copy(type = TransactionType.Expense),
        )
        assertEquals(mapOf(nov to 1_000L), BudgetFollowsIncome.incomeByMonth(rows))
    }

    @Test fun followingMonthsTakeTheirIncomeTimesThePercent() {
        val targets = BudgetFollowsIncome.targets(listOf(income(1_000_000), income(500_000, dec)), on, emptyMap(), nov)
        assertEquals(mapOf(nov to 800_000L, dec to 400_000L), targets)
    }

    @Test fun onlyMonthsThatChangeAreWritten() {
        assertEquals(emptyMap<YearMonth, Long>(), BudgetFollowsIncome.targets(listOf(income(1_000_000)), on, mapOf(nov to 800_000L), nov))
    }

    @Test fun changingThePercentRecomputes() {
        val targets = BudgetFollowsIncome.targets(listOf(income(1_000_000)), on.copy(percent = 50), mapOf(nov to 800_000L), nov)
        assertEquals(mapOf(nov to 500_000L), targets)
    }

    @Test fun foreignIncomeCountsWithItsAppCurrencyAmount() {
        val salary = income(2_882_550).copy(foreign = ForeignAmount("USD", 500_000))
        assertEquals(mapOf(nov to 2_306_040L), BudgetFollowsIncome.targets(listOf(salary), on, emptyMap(), nov))
    }

    @Test fun anOptedOutMonthKeepsItsFixedBudget() {
        val s = on.copy(optedOutMonths = setOf(nov))
        assertEquals(emptyMap<YearMonth, Long>(), BudgetFollowsIncome.targets(listOf(income(1_000_000)), s, mapOf(nov to 123L), nov))
        assertFalse(BudgetFollowsIncome.follows(nov, s, mapOf(nov to 1_000_000L), nov))
    }

    @Test fun turnedOffNothingIsWrittenAndNothingFollows() {
        val off = on.copy(isEnabled = false)
        assertEquals(emptyMap<YearMonth, Long>(), BudgetFollowsIncome.targets(listOf(income(1_000_000)), off, emptyMap(), nov))
        assertFalse(BudgetFollowsIncome.follows(nov, off, mapOf(nov to 1L), nov))
    }

    @Test fun currentAndFutureMonthsWithNoIncomeGetZero() {
        val targets = BudgetFollowsIncome.targets(emptyList(), on, mapOf(nov to 5_000L), nov)
        assertEquals(mapOf(nov to 0L), targets)
        assertTrue(BudgetFollowsIncome.follows(nov, on, emptyMap(), nov))
    }

    @Test fun aMonthAfterTheLastIncomeKeepsItsTypedBudgetAndDoesNotFollow() {
        val dec = nov.plusMonths(1)
        val jan = nov.plusMonths(2)
        val rows = listOf(income(1_000_000), income(1_000_000, dec))
        val targets = BudgetFollowsIncome.targets(rows, on, mapOf(jan to 600_000L), nov)
        assertFalse(jan in targets)
        val byMonth = BudgetFollowsIncome.incomeByMonth(rows)
        assertTrue(BudgetFollowsIncome.follows(dec, on, byMonth, nov))
        assertFalse(BudgetFollowsIncome.follows(jan, on, byMonth, nov))
    }

    @Test fun aPastMonthWithNoIncomeKeepsItsBudgetOrStaysEmpty() {
        val s = on.copy(startMonth = oct)
        val targets = BudgetFollowsIncome.targets(emptyList(), s, mapOf(oct to 5_000L), nov)
        assertFalse(oct in targets)
        assertFalse(BudgetFollowsIncome.follows(oct, s, emptyMap(), nov))
        assertTrue(BudgetFollowsIncome.follows(oct, s, mapOf(oct to 1L), nov))
    }

    @Test fun fromThisMonthOnLeavesPastMonthsAlone() {
        val rows = listOf(income(1_000_000, oct), income(1_000_000))
        val s = BudgetFollowsIncome.enabled(Settings(), 80, includePastMonths = false, rows = rows, currentMonth = nov)
        assertEquals(nov, s.startMonth)
        assertEquals(setOf(nov), BudgetFollowsIncome.targets(rows, s, emptyMap(), nov).keys)
    }

    @Test fun includePastMonthsStartsAtTheFirstMonthWithIncome() {
        val rows = listOf(income(1_000_000, oct.minusMonths(2)), income(1_000_000))
        val s = BudgetFollowsIncome.enabled(
            Settings(optedOutMonths = setOf(oct.minusMonths(5), oct)), 80, includePastMonths = true, rows = rows, currentMonth = nov,
        )
        assertEquals(oct.minusMonths(2), s.startMonth)
        // An opt-out before the new start is forgotten; one inside it stays.
        assertEquals(setOf(oct), s.optedOutMonths)
    }
}
