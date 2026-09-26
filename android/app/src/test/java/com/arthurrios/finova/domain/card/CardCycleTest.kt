package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.StatementStatus
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class CardCycleTest {
    private fun d(y: Int, m: Int, day: Int) = LocalDate.of(y, m, day)

    @Test fun aPurchaseOnOrBeforeTheClosingDayClosesThisMonth() {
        assertEquals(d(2026, 9, 10), CardCycle.closingDate(10, d(2026, 9, 3)))
        assertEquals(d(2026, 9, 10), CardCycle.closingDate(10, d(2026, 9, 10)))
    }

    @Test fun aPurchaseAfterTheClosingDayClosesNextMonth() {
        assertEquals(d(2026, 10, 10), CardCycle.closingDate(10, d(2026, 9, 11)))
        assertEquals(d(2027, 1, 10), CardCycle.closingDate(10, d(2026, 12, 20)))
    }

    @Test fun theClosingDayIsCappedToShortMonths() {
        // Closing day 28 is the highest iOS allows, so only February 2027 (28 days) is at the cap.
        assertEquals(d(2027, 2, 28), CardCycle.closingDate(28, d(2027, 2, 28)))
        assertEquals(d(2027, 3, 28), CardCycle.closingDate(28, d(2027, 3, 1)))
        assertEquals(d(2027, 2, 28), CardCycle.closingDateIn(java.time.YearMonth.of(2027, 2), 28))
    }

    @Test fun aDueDayAfterTheClosingDayIsDueTheSameMonth() {
        assertEquals(d(2026, 9, 17), CardCycle.dueDate(d(2026, 9, 10), 17, BusinessDayRule.Exact))
    }

    @Test fun aDueDayOnOrBeforeTheClosingDayIsDueNextMonth() {
        assertEquals(d(2026, 10, 5), CardCycle.dueDate(d(2026, 9, 25), 5, BusinessDayRule.Exact))
        assertEquals(d(2026, 10, 10), CardCycle.dueDate(d(2026, 9, 10), 10, BusinessDayRule.Exact))
        assertEquals(d(2027, 1, 3), CardCycle.dueDate(d(2026, 12, 20), 3, BusinessDayRule.Exact))
    }

    @Test fun theDueDateFollowsTheWeekendRule() {
        // 2026-10-17 is a Saturday.
        assertEquals(d(2026, 10, 19), CardCycle.dueDate(d(2026, 10, 10), 17, BusinessDayRule.NextBusinessDay))
        assertEquals(d(2026, 10, 16), CardCycle.dueDate(d(2026, 10, 10), 17, BusinessDayRule.PreviousBusinessDay))
        assertEquals(d(2026, 10, 17), CardCycle.dueDate(d(2026, 10, 10), 17, BusinessDayRule.Exact))
    }

    @Test fun statementStatusFollowsTheDates() {
        val s = CreditCardStatement(creditCardId = 1, closingDate = d(2026, 9, 10), dueDate = d(2026, 9, 17))
        assertEquals(StatementStatus.Open, s.status(d(2026, 9, 10)))
        assertEquals(StatementStatus.Closed, s.status(d(2026, 9, 11)))
        assertEquals(StatementStatus.Closed, s.status(d(2026, 9, 17)))
        assertEquals(StatementStatus.Overdue, s.status(d(2026, 9, 18)))
        val paid = s.copy(isPaid = true, paidDate = d(2026, 9, 15))
        assertEquals(StatementStatus.Scheduled, paid.status(d(2026, 9, 14)))
        assertEquals(StatementStatus.Paid, paid.status(d(2026, 9, 15)))
    }
}
