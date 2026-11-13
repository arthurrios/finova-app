package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class InstallmentsTest {
    private val today = LocalDate.of(2026, 9, 26)
    private val card = CreditCard(id = 7, name = "Nubank", lastFourDigits = "4321", closingDay = 5, dueDay = 10)
    private fun d(m: Int, day: Int, y: Int = 2026) = LocalDate.of(y, m, day)

    private val parent = Transaction(
        id = 100, title = "TV - Installment Parent", category = TransactionCategory.Entertainment, type = TransactionType.Expense,
        amount = 0, date = d(8, 20), budgetMonth = YearMonth.of(2026, 8), hasInstallments = true, totalInstallments = 4,
    )
    private fun installment(n: Int, statementId: Long?, date: LocalDate, settled: Boolean = false, cancelledBy: Long? = null, cardId: Long? = 7) = Transaction(
        id = 100L + n, title = "TV", category = TransactionCategory.Entertainment, type = TransactionType.Expense,
        amount = 25_000, date = date, budgetMonth = YearMonth.from(date), parentTransactionId = 100,
        installmentNumber = n, totalInstallments = 4, creditCardId = cardId, statementId = statementId,
        settledByTransactionId = if (settled) 999 else null, cancelledByTransactionId = cancelledBy,
    )
    private val statements = listOf(
        CreditCardStatement(id = 1, creditCardId = 7, closingDate = d(9, 5), dueDate = d(9, 10)),
        CreditCardStatement(id = 2, creditCardId = 7, closingDate = d(10, 5), dueDate = d(10, 10)),
        CreditCardStatement(id = 3, creditCardId = 7, closingDate = d(11, 5), dueDate = d(11, 10)),
        CreditCardStatement(id = 4, creditCardId = 7, closingDate = d(12, 5), dueDate = d(12, 10)),
    )
    private val series = listOf(parent, installment(1, 1, d(9, 10)), installment(2, 2, d(10, 10)), installment(3, 3, d(11, 10)), installment(4, 4, d(12, 10)))

    @Test fun onlyInstallmentsOnOpenStatementsAreOutstandingNewestFirst() {
        val open = Installments.outstanding(series[2], series, statements, today)
        assertEquals(listOf(4, 3, 2), open.map { it.number })
        assertEquals(d(10, 10), open.last().dueDate)
    }

    @Test fun earlyPaidInstallmentsAreNotOfferedAgain() {
        val rows = series.map { if (it.id == 104L) it.copy(settledByTransactionId = 999) else it }
        assertEquals(listOf(3, 2), Installments.outstanding(rows[2], rows, statements, today).map { it.number })
    }

    @Test fun aPaidStatementClosesItsInstallments() {
        val paid = statements.map { if (it.id == 2L) it.copy(isPaid = true) else it }
        assertEquals(listOf(4, 3), Installments.outstanding(series[2], series, paid, today).map { it.number })
    }

    @Test fun withoutACardOrAStatementTheDateDecides() {
        val cash = series.map { it.copy(creditCardId = null, statementId = null) }
        assertEquals(listOf(4, 3, 2), Installments.outstanding(cash[1], cash, emptyList(), today).map { it.number })
        val missing = series.map { if (it.id == 103L) it.copy(statementId = 55) else it }
        assertTrue(3 in Installments.outstanding(missing[1], missing, statements, today).map { it.number })
    }

    @Test fun aCancelledPurchaseCannotBePaidEarly() {
        val rows = series.map { if (it.installmentNumber != null && it.installmentNumber!! >= 2) it.copy(cancelledByTransactionId = 500) else it }
        assertEquals(500L, Installments.cancellationRefundId(rows[1], rows))
        assertTrue(Installments.payable(rows[1], rows, statements, today).isEmpty())
    }

    @Test fun aSplitSeriesStillFindsItsSiblingsOnce() {
        // Installments 3 and 4 lost their parent link; a duplicate of 2 exists with a higher id.
        val rows = listOf(parent, series[1], series[2], series[3].copy(parentTransactionId = null), series[4].copy(parentTransactionId = null),
            series[2].copy(id = 300))
        assertEquals(listOf(101L, 102L, 103L, 104L), Installments.children(rows[1], rows).map { it.id })
    }

    @Test fun theCardIsFoundFromAnyRowOfTheSeries() {
        assertEquals(7L, Installments.cardId(parent, series))
    }

    @Test fun theNextOpenStatementSkipsOneClosingThatDayAndPaidOnes() {
        // On Oct 5 the October statement closes that very day: the money goes on November's.
        assertEquals(3L, Installments.nextOpenStatement(statements, card, d(10, 5), BusinessDayRule.Exact).id)
        val paid = statements.map { if (it.id == 3L) it.copy(isPaid = true) else it }
        assertEquals(4L, Installments.nextOpenStatement(paid, card, d(10, 5), BusinessDayRule.Exact).id)
    }

    @Test fun aCardUnusedForMonthsGetsAFreshOpenCycle() {
        // Only an old, closed statement exists: the next open cycle is the one after today, not
        // the one after that old statement.
        val old = listOf(CreditCardStatement(id = 1, creditCardId = 7, closingDate = d(3, 5), dueDate = d(3, 10)))
        val next = Installments.nextOpenStatement(old, card, today, BusinessDayRule.Exact)
        assertEquals(0L, next.id)
        assertEquals(d(10, 5), next.closingDate)
    }
}
