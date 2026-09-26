package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class StatementPeriodTest {
    private val card = CreditCard(id = 1, name = "N", lastFourDigits = "1", closingDay = 31, dueDay = 10)
    private fun stmt(id: Long, closing: LocalDate) = CreditCardStatement(id = id, creditCardId = 1, closingDate = closing, dueDate = closing.plusDays(10))

    @Test fun aMonthEndCardStartsTheDayAfterItsRealPreviousClosing() {
        val april = stmt(2, LocalDate.of(2026, 4, 30))
        // No March statement stored: the card closes on 31 March, so April's period starts 1 April.
        assertEquals(LocalDate.of(2026, 4, 1), StatementPeriod.start(april, listOf(april), card))
    }

    @Test fun theStoredPreviousStatementWins() {
        val march = stmt(1, LocalDate.of(2026, 3, 28))
        val april = stmt(2, LocalDate.of(2026, 4, 30))
        assertEquals(LocalDate.of(2026, 3, 29), StatementPeriod.start(april, listOf(march, april), card))
    }
}
