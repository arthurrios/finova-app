package com.arthurrios.finova.domain.notifications

import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class NotificationPlannerTest {
    private val today = LocalDate.of(2026, 9, 26)
    private fun tx(id: Long, date: LocalDate, amount: Long = 1_000, type: TransactionType = TransactionType.Expense, build: (Transaction) -> Transaction = { it }) =
        build(Transaction(id = id, title = "T$id", category = TransactionCategory.Market, type = type, amount = amount, date = date, budgetMonth = YearMonth.from(date)))
    private fun plan(rows: List<Transaction>, statements: List<CreditCardStatement> = emptyList(), cards: List<CreditCard> = emptyList(),
                     offset: Long = 1_000_000, prefs: NotificationPreferences = NotificationPreferences()) =
        NotificationPlanner.plan(today, rows, statements, cards, offset, prefs)

    @Test fun todaysTransactionsAreRemindedAndOtherDaysAreNot() {
        val planned = plan(listOf(tx(1, today), tx(2, today.plusDays(1)), tx(3, today, type = TransactionType.Income)))
        assertEquals(listOf("transaction_1_$today", "transaction_3_$today"), planned.filterIsInstance<PlannedNotification.TransactionDue>().map { it.id })
    }

    @Test fun switchesTurnRemindersOff() {
        assertTrue(plan(listOf(tx(1, today)), prefs = NotificationPreferences(allDisabled = true)).isEmpty())
        assertTrue(plan(listOf(tx(1, today)), prefs = NotificationPreferences(transactions = false)).isEmpty())
    }

    @Test fun installmentsGetOneMonthReminderOnTheirFirstDay() {
        val rows = listOf(
            tx(10, today, 5_000) { it.copy(hasInstallments = true, parentTransactionId = 9, installmentNumber = 2, totalInstallments = 4) },
            tx(11, today.plusDays(2), 3_000) { it.copy(hasInstallments = true, parentTransactionId = 8, installmentNumber = 1, totalInstallments = 2) },
        )
        val month = plan(rows).filterIsInstance<PlannedNotification.SeriesMonth>().single()
        assertEquals(SeriesKind.Installments, month.kind)
        assertEquals(2, month.count)
        assertEquals(8_000L, month.total)
        // Two days later, not again.
        assertTrue(NotificationPlanner.plan(today.plusDays(2), rows, emptyList(), emptyList(), 0, NotificationPreferences())
            .none { it is PlannedNotification.SeriesMonth })
    }

    @Test fun anUnpaidStatementRemindsOnClosingAndDueDays() {
        val card = CreditCard(id = 7, name = "Nubank", lastFourDigits = "1", closingDay = 26, dueDay = 3)
        val statement = CreditCardStatement(id = 3, creditCardId = 7, closingDate = today, dueDate = today.plusDays(7))
        val purchase = tx(1, today.minusDays(5), 20_000) { it.copy(creditCardId = 7, statementId = 3) }
        val closed = plan(listOf(purchase), listOf(statement), listOf(card)).filterIsInstance<PlannedNotification.StatementClosed>().single()
        assertEquals(20_000L, closed.amount)
        assertEquals("Nubank", closed.cardName)
        val due = NotificationPlanner.plan(today.plusDays(7), listOf(purchase), listOf(statement), listOf(card), 0, NotificationPreferences())
        assertEquals(1, due.filterIsInstance<PlannedNotification.StatementDue>().size)
        // Deleted card: silent.
        assertTrue(plan(listOf(purchase), listOf(statement), listOf(card.copy(isDeleted = true))).none { it is PlannedNotification.StatementClosed })
        // Paid: silent.
        assertTrue(plan(listOf(purchase), listOf(statement.copy(isPaid = true)), listOf(card)).none { it is PlannedNotification.StatementClosed })
    }

    @Test fun theMorningBeforeTheBalanceGoesNegativeWarns() {
        val rent = tx(1, today.plusDays(1), 2_000_000)
        val warning = plan(listOf(rent), offset = 1_000_000).filterIsInstance<PlannedNotification.NegativeBalanceTomorrow>().single()
        assertEquals(today.plusDays(1), warning.day)
        // Negative in three days: not yet.
        assertTrue(plan(listOf(tx(1, today.plusDays(3), 2_000_000)), offset = 1_000_000).none { it is PlannedNotification.NegativeBalanceTomorrow })
    }
}
