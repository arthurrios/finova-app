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

class CardCycleChangeTest {
    private val today = LocalDate.of(2026, 9, 25)
    private val rule = BusinessDayRule.Exact
    private fun d(m: Int, day: Int, y: Int = 2026) = LocalDate.of(y, m, day)

    /** The card after the edit: it used to close on the 5th and be due on the 10th. */
    private val card = CreditCard(id = 7, name = "Nubank", lastFourDigits = "4321", closingDay = 15, dueDay = 22)

    private fun stmt(id: Long, closing: LocalDate, due: LocalDate, paid: Boolean = false) =
        CreditCardStatement(id = id, creditCardId = 7, closingDate = closing, dueDate = due, isPaid = paid)

    private fun row(id: Long, statementId: Long?, date: LocalDate, installment: Int? = null) = Transaction(
        id = id, title = "R$id", category = TransactionCategory.Market, type = TransactionType.Expense, amount = 1_000,
        date = date, budgetMonth = YearMonth.from(date), creditCardId = 7, statementId = statementId,
        installmentNumber = installment, totalInstallments = installment?.let { 3 },
        parentTransactionId = installment?.let { 50L },
    )

    @Test fun openStatementsTakeTheNewDaysAndClosedOnesStay() {
        val closed = stmt(1, d(9, 5), d(9, 10))
        val open = stmt(2, d(10, 5), d(10, 10))
        val plan = CardCycleChange.plan(card, listOf(closed, open), emptyList(), today, rule)
        assertEquals(listOf(open.copy(closingDate = d(10, 15), dueDate = d(10, 22))), plan.updated)
        assertTrue(plan.created.isEmpty())
    }

    @Test fun installmentsOnOpenStatementsMoveToTheNewDueDate() {
        val open = stmt(2, d(10, 5), d(10, 10))
        val installment = row(20, 2, d(10, 10), installment = 2)
        val plan = CardCycleChange.plan(card, listOf(open), listOf(installment), today, rule)
        val moved = plan.rows.single()
        assertEquals(d(10, 22), moved.date)
        assertEquals(YearMonth.of(2026, 10), moved.budgetMonth)
        assertEquals(2L, moved.statementId)
    }

    @Test fun aGhostStatementIsMergedIntoTheOneOnTheNewDay() {
        val ghost = stmt(2, d(10, 5), d(10, 10))
        val current = stmt(3, d(10, 15), d(10, 22))
        val installment = row(20, 2, d(10, 10), installment = 2)
        val plan = CardCycleChange.plan(card, listOf(ghost, current), listOf(installment), today, rule)
        // Both now close on the 15th, so the one holding the installment is kept (as on iOS).
        assertEquals(setOf(3L), plan.deleted)
        val kept = plan.updated.single()
        assertEquals(2L, kept.id)
        assertEquals(d(10, 15), kept.closingDate)
        assertEquals(d(10, 22), kept.dueDate)
        assertEquals(d(10, 22), plan.rows.single().date)
    }

    @Test fun aPurchaseInACycleAheadIsReroutedByItsDate() {
        // Bought on Oct 8: with closing on the 5th it was on November's statement; closing on the
        // 15th puts it on October's.
        val october = stmt(2, d(10, 5), d(10, 10))
        val november = stmt(3, d(11, 5), d(11, 10))
        val purchase = row(30, 3, d(10, 8))
        val plan = CardCycleChange.plan(card, listOf(october, november), listOf(purchase), today, rule)
        assertEquals(2L, plan.rows.single { it.id == 30L }.statementId)
    }

    @Test fun aPurchaseRoutedToAMissingCycleGetsANewStatement() {
        val purchase = row(30, null, d(12, 20))
        val plan = CardCycleChange.plan(card, emptyList(), listOf(purchase), today, rule)
        val created = plan.created.single()
        assertEquals(d(1, 15, 2027), created.closingDate)
        assertEquals(created.id, plan.rows.single().statementId)
        assertTrue(created.id < 0)
    }

    @Test fun historyAndHandMovedRowsStayPut() {
        val closed = stmt(1, d(9, 5), d(9, 10))
        val inClosedCycle = row(40, 1, d(9, 1))
        val moved = row(41, 1, d(10, 8)).copy(isStatementOverridden = true)
        val chained = row(42, 1, d(10, 8), installment = 1)
        val plan = CardCycleChange.plan(card, listOf(closed), listOf(inClosedCycle, moved, chained), today, rule)
        assertTrue(plan.rows.isEmpty())
        assertTrue(plan.updated.isEmpty())
    }

    @Test fun paidStatementsAreNotMerged() {
        val paid = stmt(2, d(10, 5), d(10, 10), paid = true)
        val current = stmt(3, d(10, 15), d(10, 22))
        val plan = CardCycleChange.plan(card, listOf(paid, current), emptyList(), today, rule)
        assertTrue(plan.deleted.isEmpty())
    }
}
