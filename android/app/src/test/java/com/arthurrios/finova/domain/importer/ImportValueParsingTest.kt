package com.arthurrios.finova.domain.importer

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/**
 * Money and calendar: the two places a quiet bug costs the user real accuracy. Port of
 * FinovaTests/Import/ImportValueParsingTests.swift.
 */
class ImportValueParsingTest {
    private lateinit var originalYear: () -> Int

    @Before fun pinYear() {
        originalYear = DateFieldParser.currentYear
        DateFieldParser.currentYear = { 2026 }
    }

    @After fun restoreYear() {
        DateFieldParser.currentYear = originalYear
    }

    // ---- Amounts ----

    private fun cents(raw: String, format: NumberFormatSpec = NumberFormatSpec.PtBR): Long =
        AmountParser.parse(raw, format).cents

    @Test fun brazilianAndAmericanGrouping() {
        assertEquals(123_456L, cents("1.234,56"))
        assertEquals(123_456L, cents("1,234.56", NumberFormatSpec.EnUS))
        assertEquals(123_456L, cents("1234,56"))
        assertEquals(123_456L, cents("1234.56", NumberFormatSpec.EnUS))
        assertEquals(123_400L, cents("1234", NumberFormatSpec.EnUS))
    }

    @Test fun negativesInEveryDialectBanksUse() {
        assertEquals(-123_456L, cents("-1.234,56"))
        assertEquals(-123_456L, cents("1.234,56-")) // trailing minus
        assertEquals(-123_456L, cents("(1.234,56)")) // accounting parentheses
        assertEquals(-123_456L, cents("1.234,56 D")) // débito marker
        assertEquals(123_456L, cents("1.234,56 C")) // crédito marker
        assertEquals(-123_456L, cents("−1.234,56")) // real minus sign
    }

    @Test fun currencyNoiseIsStripped() {
        assertEquals(123_456L, cents("R$ 1.234,56"))
        assertEquals(123_456L, cents("+1.234,56"))
    }

    /** Brazilian exports use a non-breaking space as the thousands separator, invisible in every editor. */
    @Test fun nonBreakingSpaceAsAThousandsSeparator() {
        assertEquals(123_456L, cents("R$ 1 234,56"))
    }

    @Test fun threeDecimalPlacesRoundAndAreFlagged() {
        val parsed = AmountParser.parse("1.234,567", NumberFormatSpec.PtBR)
        assertEquals(123_457L, parsed.cents)
        assertTrue("money is never silently rounded", parsed.wasRounded)
    }

    @Test fun twoDecimalPlacesAreNotFlagged() {
        assertFalse(AmountParser.parse("1.234,56", NumberFormatSpec.PtBR).wasRounded)
    }

    @Test fun scientificNotationFromExcelMangledExports() {
        assertEquals(123_450L, cents("1.2345E+3", NumberFormatSpec.EnUS))
    }

    @Test fun nonNumericInputFails() {
        assertThrows(AmountParser.Failure::class.java) { cents("Mercado Central") }
        assertThrows(AmountParser.Failure::class.java) { cents("") }
        assertThrows(AmountParser.Failure::class.java) { cents("   ") }
    }

    @Test fun absurdAmountsAreRejected() {
        val error = assertThrows(AmountParser.Failure::class.java) { cents("999999999999,00") }
        assertEquals(AmountParser.Failure.OutOfRange, error)
    }

    @Test fun aLetterAloneIsNotReadAsADebitMarker() {
        // A mis-mapped text column must fail, not be silently swallowed.
        assertThrows(AmountParser.Failure::class.java) { cents("D") }
        assertThrows(AmountParser.Failure::class.java) { cents("Mercado D") }
    }

    // ---- Number format detection ----

    @Test fun bothSeparatorsPresentIsProof() {
        val (ptSpec, ptProven) = AmountParser.detectFormat(listOf("1.234,56", "12,00"))
        assertEquals(NumberFormatSpec.PtBR, ptSpec)
        assertTrue(ptProven)

        val (enSpec, enProven) = AmountParser.detectFormat(listOf("1,234.56", "12.00"))
        assertEquals(NumberFormatSpec.EnUS, enSpec)
        assertTrue(enProven)
    }

    @Test fun twoTrailingDigitsMeanDecimalWhenNoValueCarriesBoth() {
        val (spec, _) = AmountParser.detectFormat(listOf("12,50", "8,00", "134,20"))
        assertEquals(',', spec.decimalSeparator)
    }

    /** `1.234` with no tiebreaker anywhere is unresolvable in principle. The caller must warn. */
    @Test fun unresolvableColumnIsReportedAsUnproven() {
        assertFalse(AmountParser.detectFormat(listOf("1.234", "5.678")).second)
    }

    /** One convention per column, never per cell. */
    @Test fun aColumnResolvesUnderASingleConvention() {
        val format = AmountParser.detectFormat(listOf("1.234", "1.234,56", "999")).first
        assertEquals(123_400L, AmountParser.parse("1.234", format).cents)
        assertEquals(123_456L, AmountParser.parse("1.234,56", format).cents)
    }

    // ---- Dates ----

    private fun parse(raw: String, pattern: String): LocalDate? = DateFieldParser.parse(raw, DateFormatSpec(pattern))

    @Test fun commonFormats() {
        val dmy = parse("31/01/2026", "dd/MM/yyyy")
        assertEquals(31, dmy?.dayOfMonth)
        assertEquals(1, dmy?.monthValue)

        assertEquals(31, parse("2026-01-31", "yyyy-MM-dd")?.dayOfMonth)
        assertEquals(31, parse("31.01.2026", "dd.MM.yyyy")?.dayOfMonth)
    }

    /**
     * iOS checks the parsed instant sits at local noon. Android parses to a [LocalDate], which has no
     * time of day to anchor, so this reduces to "the calendar day is the one written".
     */
    @Test fun datesAreAnchoredAtLocalNoon() {
        assertEquals(LocalDate.of(2026, 6, 15), parse("15/06/2026", "dd/MM/yyyy"))
    }

    /**
     * `America/Sao_Paulo` skipped midnight on 2018-11-04. On iOS this needs TZ=America/Sao_Paulo; a
     * [LocalDate] is zone-free, so here it is a plain date check that holds in every zone.
     */
    @Test fun aDSTStartDayStillLandsOnItsOwnCalendarDay() {
        assertEquals(LocalDate.of(2018, 11, 4), parse("04/11/2018", "dd/MM/yyyy"))
    }

    @Test fun leapDays() {
        assertNotNull(parse("29/02/2024", "dd/MM/yyyy"))
        // Non-lenient: 29 Feb 2025 does not exist and must fail rather than roll to 1 March.
        assertNull(parse("29/02/2025", "dd/MM/yyyy"))
    }

    @Test fun implausibleYearsAreRejected() {
        assertNull(parse("01/01/1900", "dd/MM/yyyy"))
        assertNull(parse("01/01/2099", "dd/MM/yyyy"))
    }

    // ---- Date format detection ----

    @Test fun aDayAbove12ProvesDayFirst() {
        assertEquals(
            DateFieldParser.Detection.Proven(DateFormatSpec("dd/MM/yyyy")),
            DateFieldParser.detectFormat(listOf("31/01/2026", "02/02/2026")),
        )
    }

    @Test fun aSecondComponentAbove12ProvesMonthFirst() {
        assertEquals(
            DateFieldParser.Detection.Proven(DateFormatSpec("MM/dd/yyyy")),
            DateFieldParser.detectFormat(listOf("01/31/2026", "02/02/2026")),
        )
    }

    @Test fun aFileThatContradictsItselfIsRejected() {
        assertEquals(DateFieldParser.Detection.Inconsistent, DateFieldParser.detectFormat(listOf("31/01/2026", "01/31/2026")))
    }

    /** Every component <= 12 with too few rows to infer order. Guessing silently shifts every month. */
    @Test fun allComponentsUnder12WithFewRowsIsAmbiguous() {
        val detection = DateFieldParser.detectFormat(listOf("01/02/2026", "03/04/2026"))
        assertTrue("expected Ambiguous, got $detection", detection is DateFieldParser.Detection.Ambiguous)
    }

    @Test fun monotonicityBreaksTheTieWhenThereAreEnoughRows() {
        // Under dd/MM these are consecutive days in January; under MM/dd they scatter across months.
        val values = listOf(
            "01/01/2026", "02/01/2026", "03/01/2026", "04/01/2026",
            "05/01/2026", "06/01/2026", "07/01/2026", "08/01/2026",
        )
        val detection = DateFieldParser.detectFormat(values)
        if (detection !is DateFieldParser.Detection.Likely) return fail("expected Likely with enough rows to infer order, got $detection")
        assertEquals("dd/MM/yyyy", detection.spec.pattern)
    }

    @Test fun isoDatesAreProvenOutright() {
        assertEquals(
            DateFieldParser.Detection.Proven(DateFormatSpec("yyyy-MM-dd")),
            DateFieldParser.detectFormat(listOf("2026-01-05", "2026-02-11")),
        )
    }

    @Test fun dateHitRateDistinguishesDateColumnsFromOthers() {
        assertEquals(1.0, DateFieldParser.dateHitRate(listOf("01/01/2026", "02/01/2026")), 0.0)
        assertEquals(0.0, DateFieldParser.dateHitRate(listOf("Mercado", "Padaria")), 0.0)
    }

    // ---- Budget month ----

    /**
     * A 31 January transaction belongs to January's budget, not February's. iOS checks `monthAnchor`;
     * Android's budget month is a [YearMonth] taken from the date (as [ImportPlan.resolve] does).
     */
    @Test fun monthAnchorFollowsTheTransactionsOwnMonth() {
        val date = requireNotNull(parse("31/01/2026", "dd/MM/yyyy"))
        assertEquals(YearMonth.of(2026, 1), YearMonth.from(date))
    }
}
