package com.arthurrios.finova.domain.time

import com.arthurrios.finova.domain.model.BusinessDayRule
import java.time.DayOfWeek
import java.time.LocalDate

/** Moves weekend dates to a weekday. Holidays are ignored, as on iOS 1.5.2. */
object BusinessDayAdjuster {
    private const val MAX_SHIFT_DAYS = 10

    fun isBusinessDay(date: LocalDate): Boolean =
        date.dayOfWeek != DayOfWeek.SATURDAY && date.dayOfWeek != DayOfWeek.SUNDAY

    fun adjust(date: LocalDate, rule: BusinessDayRule): LocalDate {
        if (rule == BusinessDayRule.Exact || isBusinessDay(date)) return date
        val step = if (rule == BusinessDayRule.NextBusinessDay) 1L else -1L
        var candidate = date
        repeat(MAX_SHIFT_DAYS) {
            candidate = candidate.plusDays(step)
            if (isBusinessDay(candidate)) return candidate
        }
        return date
    }
}
