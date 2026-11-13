package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class StatementPaymentsTest {
    private val statement = CreditCardStatement(
        id = 3, creditCardId = 7, closingDate = LocalDate.of(2026, 10, 5), dueDate = LocalDate.of(2026, 10, 10),
    )
    private val purchase = Transaction(
        id = 1, title = "Headphones", category = TransactionCategory.Utilities, type = TransactionType.Expense,
        amount = 10_000, date = LocalDate.of(2026, 10, 10), budgetMonth = YearMonth.of(2026, 10),
        creditCardId = 7, statementId = 3,
    )

    private fun paid(amount: Long, debitId: Long): List<Transaction> {
        val (debit, credit) = StatementPayments.pair(statement, amount, LocalDate.of(2026, 9, 25), "d", "c")
        return listOf(debit.copy(id = debitId), credit.copy(id = debitId + 1, statementPaymentId = debitId))
    }

    @Test fun theDebitIsCashOnThePaymentDate() {
        val (debit, _) = StatementPayments.pair(statement, 4_000, LocalDate.of(2026, 9, 25), "d", "c")
        assertNull(debit.creditCardId)
        assertTrue(debit.isStatementPayment)
        assertEquals(TransactionType.Expense, debit.type)
        assertEquals(LocalDate.of(2026, 9, 25), debit.date)
        assertEquals(YearMonth.of(2026, 9), debit.budgetMonth)
    }

    @Test fun theCreditSitsInsideTheStatementAsIncome() {
        val (_, credit) = StatementPayments.pair(statement, 4_000, LocalDate.of(2026, 9, 25), "d", "c")
        assertEquals(7L, credit.creditCardId)
        assertEquals(3L, credit.statementId)
        assertEquals(TransactionType.Income, credit.type)
        assertEquals(YearMonth.of(2026, 10), credit.budgetMonth)
        assertTrue(credit.isStatementOverridden)
    }

    @Test fun aPartialPaymentLowersWhatIsLeft() {
        val rows = listOf(purchase) + paid(4_000, 10)
        assertEquals(6_000L, StatementPayments.remaining(3, rows, listOf(statement)))
        assertEquals(4_000L, StatementPayments.totalPaid(3, rows))
    }

    @Test fun whatIsLeftNeverGoesNegative() {
        val refund = purchase.copy(id = 2, type = TransactionType.Income, amount = 15_000)
        assertEquals(0L, StatementPayments.remaining(3, listOf(purchase, refund), listOf(statement)))
    }

    @Test fun eachHalfFindsTheOther() {
        val pair = paid(4_000, 10)
        val rows = listOf(purchase) + pair
        assertEquals(listOf(11L), StatementPayments.partners(pair[0], rows))
        assertEquals(listOf(10L), StatementPayments.partners(pair[1], rows))
        assertTrue(StatementPayments.partners(purchase, rows).isEmpty())
    }

    @Test fun aFullPaymentLeavesNoStatementRowButTheDebitCharges() {
        val rows = listOf(purchase) + paid(10_000, 10)
        assertEquals(0L, StatementPayments.remaining(3, rows, listOf(statement)))
        assertTrue(StatementBook.statementRows(listOf(com.arthurrios.finova.domain.model.CreditCard(id = 7, name = "N", lastFourDigits = "1", closingDay = 5, dueDay = 10)), listOf(statement), rows).isEmpty())
    }
}
