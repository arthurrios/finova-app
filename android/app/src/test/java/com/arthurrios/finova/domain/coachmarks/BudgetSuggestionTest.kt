package com.arthurrios.finova.domain.coachmarks

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.YearMonth
import org.junit.Assert.assertEquals
import org.junit.Test

class BudgetSuggestionTest {
    private val month = YearMonth.of(2026, 11)
    private val other = YearMonth.of(2026, 12)

    private fun row(amount: Long, type: TransactionType, month: YearMonth, card: Long? = null, settledBy: Long? = null) = Transaction(
        title = "Row", category = TransactionCategory.Salary, type = type, amount = amount, date = month.atDay(5),
        budgetMonth = month, creditCardId = card, settledByTransactionId = settledBy,
    )

    @Test fun sumsEveryIncomeOfTheMonth() {
        val rows = listOf(row(800_000, TransactionType.Income, month), row(50_000, TransactionType.Income, month))
        assertEquals(850_000, BudgetSuggestion.monthlyIncome(rows, month))
    }

    @Test fun leavesOutExpensesOtherMonthsCardRefundsAndEarlyPaidRows() {
        val rows = listOf(
            row(100_000, TransactionType.Income, month),
            row(30_000, TransactionType.Expense, month),
            row(900_000, TransactionType.Income, other),
            row(20_000, TransactionType.Income, month, card = 7),
            row(10_000, TransactionType.Income, month, settledBy = 9),
        )
        assertEquals(100_000, BudgetSuggestion.monthlyIncome(rows, month))
    }

    @Test fun noIncomeSuggestsNothing() {
        assertEquals(0, BudgetSuggestion.monthlyIncome(emptyList(), month))
    }
}
