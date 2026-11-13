package com.arthurrios.finova.domain.time

import com.arthurrios.finova.domain.model.BusinessDayRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth

/** Ports of the date rules pinned by BusinessDayAdjustmentTests and MonthAnchorArithmeticTests on iOS. */
class TimeRulesTest {

    @Test
    fun exactRuleNeverMovesADate() {
        val saturday = LocalDate.of(2026, 9, 26)
        assertEquals(saturday, BusinessDayAdjuster.adjust(saturday, BusinessDayRule.Exact))
    }

    @Test
    fun previousFromASundaySkipsSaturdayAndLandsOnFriday() {
        val sunday = LocalDate.of(2026, 9, 27)
        assertEquals(LocalDate.of(2026, 9, 25), BusinessDayAdjuster.adjust(sunday, BusinessDayRule.PreviousBusinessDay))
    }

    @Test
    fun nextFromASaturdaySkipsSundayAndLandsOnMonday() {
        val saturday = LocalDate.of(2026, 9, 26)
        assertEquals(LocalDate.of(2026, 9, 28), BusinessDayAdjuster.adjust(saturday, BusinessDayRule.NextBusinessDay))
    }

    @Test
    fun adjustmentIsIdempotentForEveryDayOfAYear() {
        var day = LocalDate.of(2026, 1, 1)
        while (day.year == 2026) {
            for (rule in BusinessDayRule.entries) {
                val once = BusinessDayAdjuster.adjust(day, rule)
                assertEquals(once, BusinessDayAdjuster.adjust(once, rule))
                if (rule != BusinessDayRule.Exact) {
                    assertTrue(once.dayOfWeek != DayOfWeek.SATURDAY && once.dayOfWeek != DayOfWeek.SUNDAY)
                }
            }
            day = day.plusDays(1)
        }
    }

    @Test
    fun occurrenceClampsToShortMonthsAndReturnsToTheAnchorDay() {
        assertEquals(LocalDate.of(2026, 2, 28), OccurrenceDates.occurrence(31, YearMonth.of(2026, 2)))
        assertEquals(LocalDate.of(2028, 2, 29), OccurrenceDates.occurrence(31, YearMonth.of(2028, 2)))
        assertEquals(LocalDate.of(2026, 4, 30), OccurrenceDates.occurrence(31, YearMonth.of(2026, 4)))
        assertEquals(LocalDate.of(2026, 5, 31), OccurrenceDates.occurrence(31, YearMonth.of(2026, 5)))
    }

    @Test
    fun carouselRunsAYearBackAndTwoAheadWithTodayAtTwelve() {
        val months = SeriesMonths.carouselMonths(YearMonth.of(2026, 9))
        assertEquals(37, months.size)
        assertEquals(YearMonth.of(2025, 9), months.first())
        assertEquals(YearMonth.of(2028, 9), months.last())
        assertEquals(YearMonth.of(2026, 9), months[SeriesMonths.todayIndex()])
    }

    @Test
    fun steppingCrossesTheYearBoundaryBothWays() {
        val months = SeriesMonths.carouselMonths(YearMonth.of(2026, 1))
        assertEquals(YearMonth.of(2025, 12), months[SeriesMonths.todayIndex() - 1])
        assertEquals(YearMonth.of(2026, 2), months[SeriesMonths.todayIndex() + 1])
    }

    @Test
    fun seriesMonthsStopAtTheHorizonOrTheEnd() {
        val today = YearMonth.of(2026, 9)
        val open = SeriesMonths.seriesMonths(YearMonth.of(2026, 1), null, today)
        assertEquals(YearMonth.of(2026, 1), open.first())
        assertEquals(today.plusMonths(36), open.last())
        val bounded = SeriesMonths.seriesMonths(YearMonth.of(2026, 1), YearMonth.of(2026, 3), today)
        assertEquals(listOf(YearMonth.of(2026, 1), YearMonth.of(2026, 2), YearMonth.of(2026, 3)), bounded)
        // A series starting in the future still gets a full horizon after its start.
        val future = SeriesMonths.seriesMonths(YearMonth.of(2027, 1), null, today)
        assertEquals(YearMonth.of(2030, 1), future.last())
    }
}
