package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.time.BusinessDayAdjuster
import java.time.LocalDate
import java.time.YearMonth

/**
 * When a card bills a purchase. Port of CreditCardService.calculateClosingDate and
 * calculateDueDate on iOS.
 */
object CardCycle {
    /**
     * The statement a purchase lands on closes this month if the purchase is before the closing
     * day, else next month: a statement is issued on its closing day, so a purchase made that day
     * is on the next one. Never shifted for weekends: the closing day is a billing boundary, and
     * moving it would reroute purchases between cycles.
     */
    fun closingDate(closingDay: Int, purchase: LocalDate): LocalDate {
        val thisMonth = closingDateIn(YearMonth.from(purchase), closingDay)
        return if (purchase < thisMonth) thisMonth else closingDateIn(YearMonth.from(purchase).plusMonths(1), closingDay)
    }

    /**
     * A date that routes to the statement closing in [month]. The last day of the month before is
     * past the previous closing on every card; the 1st is not, on a card closing on the 1st.
     */
    fun routingDate(month: YearMonth): LocalDate = month.minusMonths(1).atEndOfMonth()

    /** The closing date of the cycle that closes in [month]. */
    fun closingDateIn(month: YearMonth, closingDay: Int): LocalDate =
        month.atDay(closingDay.coerceAtMost(month.lengthOfMonth()))

    /**
     * Due the same month when the due day comes after the closing day, else the next month. A due
     * date is a payment date, so it follows the account's default weekend rule (one statement
     * holds purchases with different rules, so a purchase's own rule cannot apply).
     */
    fun dueDate(closingDate: LocalDate, dueDay: Int, rule: BusinessDayRule): LocalDate {
        val month = YearMonth.from(closingDate).let { if (dueDay > closingDate.dayOfMonth) it else it.plusMonths(1) }
        return BusinessDayAdjuster.adjust(month.atDay(dueDay.coerceAtMost(month.lengthOfMonth())), rule)
    }
}
