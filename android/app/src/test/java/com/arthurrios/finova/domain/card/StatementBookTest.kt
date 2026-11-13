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

class StatementBookTest {
    private val card = CreditCard(id = 7, name = "Nubank", lastFourDigits = "4321", closingDay = 10, dueDay = 17)
    private val rule = BusinessDayRule.Exact
    private fun d(y: Int, m: Int, day: Int) = LocalDate.of(y, m, day)
    private fun stmt(id: Long, closing: LocalDate, cardId: Long = card.id) =
        CreditCardStatement(id = id, creditCardId = cardId, closingDate = closing, dueDate = closing.plusDays(7))
    private fun purchase(id: Long, amount: Long, statementId: Long?, type: TransactionType = TransactionType.Expense, settled: Boolean = false) =
        Transaction(
            id = id, title = "P$id", category = TransactionCategory.Market, type = type, amount = amount,
            date = d(2026, 9, 5), budgetMonth = YearMonth.of(2026, 9), creditCardId = card.id, statementId = statementId,
            settledByTransactionId = if (settled) 99 else null,
        )

    @Test fun anExactClosingDateMatchIsReused() {
        val existing = stmt(3, d(2026, 9, 10))
        assertEquals(existing, StatementBook.route(listOf(existing), card, d(2026, 9, 4), rule))
    }

    @Test fun aStatementInTheSameMonthIsReusedAfterTheClosingDayChanged() {
        // Old closing day 5; the card now closes on the 10th. The September invoice is still one.
        val older = stmt(4, d(2026, 9, 5))
        val oldest = stmt(2, d(2026, 9, 6))
        assertEquals(oldest, StatementBook.route(listOf(older, oldest), card, d(2026, 9, 8), rule))
    }

    @Test fun otherCardsStatementsAreIgnored() {
        val foreign = stmt(3, d(2026, 9, 10), cardId = 8)
        val routed = StatementBook.route(listOf(foreign), card, d(2026, 9, 4), rule)
        assertEquals(0L, routed.id)
        assertEquals(d(2026, 9, 10), routed.closingDate)
        assertEquals(d(2026, 9, 17), routed.dueDate)
    }

    @Test fun aPurchaseAfterTheClosingDayGoesOnNextMonthsNewStatement() {
        val routed = StatementBook.route(emptyList(), card, d(2026, 9, 11), rule)
        assertEquals(0L, routed.id)
        assertEquals(d(2026, 10, 10), routed.closingDate)
        assertEquals(d(2026, 10, 17), routed.dueDate)
    }

    @Test fun nextIsTheFollowingCycleEvenAcrossYears() {
        val december = stmt(5, d(2026, 12, 10))
        val next = StatementBook.next(listOf(december), card, december, rule)
        assertEquals(d(2027, 1, 10), next.closingDate)
        val existingJanuary = stmt(6, d(2027, 1, 10))
        assertEquals(existingJanuary, StatementBook.next(listOf(december, existingJanuary), card, december, rule))
    }

    @Test fun theTotalSubtractsCreditsAndSkipsEarlyPaidInstallments() {
        val rows = listOf(
            purchase(1, 10_000, 3),
            purchase(2, 2_500, 3, type = TransactionType.Income),
            purchase(3, 4_000, 3, settled = true),
            purchase(4, 9_999, 4),
        )
        assertEquals(7_500L, StatementBook.total(3, rows))
    }

    @Test fun statementRowsChargeOnTheDueDate() {
        val s = stmt(3, d(2026, 9, 10))
        val rows = listOf(purchase(1, 10_000, 3), purchase(2, 5_000, 3))
        val row = StatementBook.statementRows(listOf(card), listOf(s), rows).single()
        assertEquals(15_000L, row.amount)
        assertEquals(s.dueDate, row.date)
        assertEquals(YearMonth.of(2026, 9), row.budgetMonth)
        assertEquals(2, row.totalInstallments)
        assertEquals(-(3L * 1000 + card.id), row.id)
        assertTrue(row.isCreditCardStatement)
        assertEquals(TransactionType.Expense, row.type)
    }

    @Test fun emptyOrCreditStatementsMakeNoRow() {
        val empty = stmt(3, d(2026, 9, 10))
        val credit = stmt(4, d(2026, 10, 10))
        val rows = listOf(purchase(1, 5_000, 4, type = TransactionType.Income))
        assertTrue(StatementBook.statementRows(listOf(card), listOf(empty, credit), rows).isEmpty())
    }

    @Test fun aDeletedCardsStatementStillCharges() {
        val deleted = card.copy(isDeleted = true)
        val s = stmt(3, d(2026, 9, 10))
        val rows = listOf(purchase(1, 10_000, 3))
        assertEquals(1, StatementBook.statementRows(listOf(deleted), listOf(s), rows).size)
    }

    @Test fun aCreditLargerThanItsStatementCarriesToTheNextOnes() {
        // A cancelled 3 x 100 purchase: the 300 credit lands on the first statement.
        val oct = stmt(3, d(2026, 10, 10))
        val nov = stmt(4, d(2026, 11, 10))
        val dec = stmt(5, d(2026, 12, 10))
        val rows = listOf(
            purchase(1, 10_000, 3), purchase(2, 10_000, 4), purchase(3, 10_000, 5),
            purchase(4, 30_000, 3, type = TransactionType.Income),
        )
        val charges = StatementBook.charges(listOf(dec, oct, nov), rows)
        assertEquals(0L, charges.getValue(3).charged)
        assertEquals(-20_000L, charges.getValue(3).carriedOut)
        assertEquals(-20_000L, charges.getValue(4).carriedIn)
        assertEquals(0L, charges.getValue(4).charged)
        assertEquals(-10_000L, charges.getValue(5).carriedIn)
        assertEquals(0L, charges.getValue(5).charged)
        // So nothing charges the balance: the credit and the three installments cancel out.
        assertTrue(StatementBook.statementRows(listOf(card), listOf(oct, nov, dec), rows).isEmpty())
    }

    @Test fun carriedCreditOnlyLowersTheSameCard() {
        val mine = stmt(3, d(2026, 10, 10))
        val other = stmt(4, d(2026, 11, 10), cardId = 8)
        val rows = listOf(
            purchase(1, 5_000, 3, type = TransactionType.Income),
            purchase(2, 10_000, 4).copy(creditCardId = 8),
        )
        assertEquals(10_000L, StatementBook.charges(listOf(mine, other), rows).getValue(4).charged)
    }
}
