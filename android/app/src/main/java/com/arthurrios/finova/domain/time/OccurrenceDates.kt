package com.arthurrios.finova.domain.time

import java.time.LocalDate
import java.time.YearMonth

/**
 * The day a series lands on in a given month. Port of OccurrenceDateCalculator.swift: the anchor
 * day is clamped to short months, and read again from the original date each time, so a 31st
 * becomes the 30th or 28th and returns to the 31st in long months.
 */
object OccurrenceDates {
    fun occurrence(anchorDay: Int, month: YearMonth): LocalDate =
        month.atDay(anchorDay.coerceAtMost(month.lengthOfMonth()))
}
