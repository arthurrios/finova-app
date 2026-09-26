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
     * The statement a purchase lands on closes this month if the purchase day is on or before the
     * closing day, else next month. Never shifted for weekends: the closing day is a billing
     * boundary, and moving it would reroute purchases between cycles.
     */
    fun closingDate(closingDay: Int, purchase: LocalDate): LocalDate {
        val month = YearMonth.from(purchase).let { if (purchase.dayOfMonth <= closingDay) it else it.plusMonths(1) }
        return closingDateIn(month, closingDay)
    }

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
