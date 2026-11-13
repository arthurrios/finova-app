package com.arthurrios.finova.domain.time

import java.time.YearMonth

/** Month ranges shared by the dashboard and series generation. Port of SeriesMonths.swift. */
object SeriesMonths {
    /** How far ahead recurring series are generated. */
    const val HORIZON_MONTHS = 36L

    /** The dashboard carousel: a year back, two years ahead. Today is at index 12. */
    val carouselOffsets: IntRange = -12..24

    fun carouselMonths(today: YearMonth): List<YearMonth> = carouselOffsets.map { today.plusMonths(it.toLong()) }

    fun todayIndex(): Int = -carouselOffsets.first

    /**
     * Every month from [start] through [end], capped at [HORIZON_MONTHS] past the later of today
     * and [start]. Inclusive at both ends.
     */
    fun seriesMonths(start: YearMonth, end: YearMonth? = null, today: YearMonth): List<YearMonth> {
        val horizon = maxOf(today, start).plusMonths(HORIZON_MONTHS)
        val last = if (end != null && end < horizon) end else horizon
        if (last < start) return emptyList()
        return generateSequence(start) { it.plusMonths(1) }.takeWhile { it <= last }.toList()
    }
}
