package com.arthurrios.finova.domain.ledger

import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class LedgerCalculatorTest {

    private val today = LocalDate.of(2026, 9, 15)
    private val aug = YearMonth.of(2026, 8)
    private val sep = YearMonth.of(2026, 9)
    private val oct = YearMonth.of(2026, 10)

    private fun tx(
        amount: Long,
        date: LocalDate,
        type: TransactionType = TransactionType.Expense,
        budgetMonth: YearMonth = YearMonth.from(date),
        card: Long? = null,
        settled: Boolean = false,
        statement: Boolean = false,
        installmentParent: Boolean = false,
    ) = Transaction(
        title = "t",
        category = TransactionCategory.Market,
        type = type,
        amount = amount,
        date = date,
        budgetMonth = budgetMonth,
        creditCardId = card,
        settledByTransactionId = if (settled) 99 else null,
        isCreditCardStatement = statement,
        hasInstallments = installmentParent,
    )

    private fun summaries(rows: List<Transaction>, offset: Long = 0, budgets: List<Budget> = emptyList()) =
        LedgerCalculator.monthlySummaries(rows, budgets, offset, listOf(aug, sep, oct), today)

    @Test
    fun finalBalancesChainAcrossMonthsFromTheOffset() {
        val rows = listOf(
            tx(500_00, LocalDate.of(2026, 8, 5), TransactionType.Income),
            tx(200_00, LocalDate.of(2026, 8, 10)),
            tx(100_00, LocalDate.of(2026, 9, 3)),
            tx(50_00, LocalDate.of(2026, 10, 20)),
        )
        val (a, s, o) = summaries(rows, offset = 1_000_00)
        assertEquals(1_000_00, a.previousBalance)
        assertEquals(1_300_00, a.finalBalance)
        assertEquals(1_300_00, s.previousBalance)
        assertEquals(1_200_00, s.finalBalance)
        assertEquals(1_150_00, o.finalBalance)
    }

    @Test
    fun currentBalanceCountsOnlyUpToTodayInTheCurrentMonth() {
        val rows = listOf(
            tx(100_00, LocalDate.of(2026, 9, 15)),
            tx(40_00, LocalDate.of(2026, 9, 16)),
            tx(30_00, LocalDate.of(2026, 8, 31)),
        )
        val (a, s, o) = summaries(rows, offset = 1_000_00)
        assertEquals("past month shows its final", a.finalBalance, a.currentBalance)
        assertEquals(1_000_00 - 30_00 - 100_00, s.currentBalance)
        assertEquals(1_000_00 - 30_00 - 140_00, s.finalBalance)
        assertEquals("future month shows the previous final", s.finalBalance, o.currentBalance)
    }

    @Test
    fun rowsBucketByDateNotByBudgetMonth() {
        // A weekend shift pushed this bill into October while it still counts against September.
        val shifted = tx(100_00, LocalDate.of(2026, 10, 1), budgetMonth = sep)
        val (_, s, o) = summaries(listOf(shifted))
        assertEquals(0, s.expense)
        assertEquals(100_00, o.expense)
        assertEquals(100_00, o.usedValue)
    }

    @Test
    fun installmentParentOfZeroChangesNothing() {
        val (_, s, _) = summaries(listOf(tx(0, LocalDate.of(2026, 9, 1), installmentParent = true)))
        assertEquals(0, s.expense)
        assertEquals(0, s.finalBalance)
    }

    @Test
    fun cardPurchasesCountAsUsedButOnlyTheStatementMovesTheBalance() {
        val purchase = tx(80_00, LocalDate.of(2026, 9, 5), card = 1)
        val statement = tx(80_00, LocalDate.of(2026, 10, 10), card = 1, statement = true)
        val (_, s, o) = summaries(listOf(purchase, statement))
        assertEquals(80_00, s.usedValue)
        assertEquals(0, s.expense)
        assertEquals(0, o.usedValue)
        assertEquals(80_00, o.expense)
        assertEquals(-80_00, o.finalBalance)
    }

    @Test
    fun earlyPaidInstallmentsAreLeftOut() {
        val (_, s, _) = summaries(listOf(tx(60_00, LocalDate.of(2026, 9, 2), settled = true)))
        assertEquals(0, s.expense)
        assertEquals(0, s.usedValue)
    }

    @Test
    fun transactionsBeforeTheFirstMonthStillCount() {
        val old = tx(250_00, LocalDate.of(2024, 1, 10), TransactionType.Income)
        val (a, _, _) = summaries(listOf(old), offset = 100_00)
        assertEquals(350_00, a.previousBalance)
    }

    @Test
    fun budgetLimitComesFromTheMonthsBudget() {
        val (a, s, _) = summaries(emptyList(), budgets = listOf(Budget(sep, 3_000_00)))
        assertNull(a.budgetLimit)
        assertEquals(3_000_00L, s.budgetLimit)
    }

    @Test
    fun balanceOnADayCountsTheWholeHistoryUpToThatDay() {
        val rows = listOf(
            tx(100_00, LocalDate.of(2025, 1, 1), TransactionType.Income),
            tx(30_00, LocalDate.of(2026, 9, 10)),
            tx(20_00, LocalDate.of(2026, 9, 11)),
        )
        assertEquals(70_00 + 10_00, LedgerCalculator.balanceOn(rows, 10_00, LocalDate.of(2026, 9, 10)))
        assertEquals(50_00 + 10_00, LedgerCalculator.balanceOn(rows, 10_00, LocalDate.of(2026, 9, 11)))
    }
}
