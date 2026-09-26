package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import java.time.LocalDate
import java.time.YearMonth

/** The purchases a statement covers: from the day after the previous cycle closed to its closing. */
object StatementPeriod {
    /**
     * The day after the card's previous closing. That is the previous statement's closing when one
     * exists, else the card's closing day a month earlier. Subtracting a month from the closing date
     * was wrong at month ends: a card closing on the 31st closes on 30 April, and 30 March is not
     * the previous closing (31 March is).
     */
    fun start(statement: CreditCardStatement, statements: List<CreditCardStatement>, card: CreditCard?): LocalDate {
        val previous = statements
            .filter { it.creditCardId == statement.creditCardId && it.closingDate < statement.closingDate }
            .maxOfOrNull { it.closingDate }
        val previousClosing = previous
            ?: card?.let { CardCycle.closingDateIn(YearMonth.from(statement.closingDate).minusMonths(1), it.closingDay) }
            ?: statement.closingDate.minusMonths(1)
        return previousClosing.plusDays(1)
    }
}
