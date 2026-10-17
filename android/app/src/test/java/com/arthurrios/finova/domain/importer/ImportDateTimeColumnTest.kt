package com.arthurrios.finova.domain.importer

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * A real Nubank/Itaú-shaped export that failed to import: a column carrying a date AND a time.
 * Port of FinovaTests/Import/ImportDateTimeColumnTests.swift.
 */
class ImportDateTimeColumnTest {
    private lateinit var originalYear: () -> Int

    @Before fun pinYear() {
        originalYear = DateFieldParser.currentYear
        DateFieldParser.currentYear = { 2026 }
    }

    @After fun restoreYear() {
        DateFieldParser.currentYear = originalYear
    }

    private fun plan(text: String): ImportPlan = CsvImportEngine.makePlan(
        CsvImportEngine.Input(filename = "extrato.csv", data = text.toByteArray(Charsets.UTF_8), alreadyImported = emptySet(), existing = emptyList()),
    )

    private fun titles(plan: ImportPlan) = plan.rows.mapNotNull { it.parsed?.title?.title }

    // ---- Does a date+time value parse at all? ----

    @Test fun dateTimeValueParsesUnderItsCandidate() {
        assertNotNull(DateFieldParser.parse("15/07/2026 14:30", DateFormatSpec("dd/MM/yyyy HH:mm")))
    }

    @Test fun dateTimeColumnScoresAsADateColumn() {
        val values = listOf("15/07/2026 14:30", "16/07/2026 09:05", "17/07/2026 21:44")
        assertTrue("a date+time column must be recognised as a date column", DateFieldParser.dateHitRate(values) >= 0.9)
    }

    @Test fun dateTimeColumnFormatIsDetected() {
        val values = listOf("15/07/2026 14:30", "16/07/2026 09:05", "17/07/2026 21:44")
        val detection = DateFieldParser.detectFormat(values)
        assertTrue("expected Proven for an unambiguous date+time column, got $detection", detection is DateFieldParser.Detection.Proven)
    }

    // ---- Whole-file shapes ----

    /** A separate date column that happens to carry a time. */
    @Test fun fileWithADateTimeColumn() {
        val result = plan(
            """
            Data;Lançamentos;Valor
            15/07/2026 14:30;MERCADO EXTRA;-50,00
            16/07/2026 09:05;PADARIA;-12,50
            17/07/2026 21:44;SALARIO;5.000,00
            """.trimIndent(),
        )
        assertEquals(3, result.rows.size)
        assertTrue(result.failedRows.isEmpty())
    }

    /** A seconds-precision variant. */
    @Test fun fileWithSecondsPrecision() {
        val result = plan(
            """
            Data;Lançamentos;Valor
            15/07/2026 14:30:11;MERCADO EXTRA;-50,00
            16/07/2026 09:05:02;PADARIA;-12,50
            17/07/2026 21:44:59;SALARIO;5.000,00
            """.trimIndent(),
        )
        assertEquals(3, result.rows.size)
        assertTrue(result.failedRows.isEmpty())
    }

    /** The bank names the DESCRIPTION column "Lançamentos" and the date is plain. */
    @Test fun lancamentosAsDescriptionColumn() {
        val result = plan(
            """
            Data;Lançamentos;Valor
            15/07/2026;MERCADO EXTRA;-50,00
            16/07/2026;PADARIA;-12,50
            17/07/2026;SALARIO;5.000,00
            """.trimIndent(),
        )
        assertEquals("\"Lançamentos\" should be recognised as the description", 1, result.schema.column(ColumnRole.Description))
        assertTrue(result.failedRows.isEmpty())
    }

    // ---- Fused date + description column ----

    /** Date, time and description all in one field, under a "Lançamentos" heading. */
    @Test fun fusedDateTimeAndDescriptionColumnIsUnderstood() {
        val result = plan(
            """
            Lançamentos;Valor
            15/07/2026 14:30 MERCADO EXTRA;-50,00
            16/07/2026 09:05 PADARIA;-12,50
            17/07/2026 21:44 SALARIO;5.000,00
            """.trimIndent(),
        )
        assertTrue(result.schema.dateColumnCarriesDescription)
        assertTrue(result.schema.isUsable)
        assertEquals(3, result.rows.size)
        assertTrue(result.failedRows.isEmpty())
        assertEquals("the remainder after the date becomes the title", listOf("Mercado Extra", "Padaria", "Salario"), titles(result))
    }

    /** Same shape with no time component. */
    @Test fun fusedDateAndDescriptionWithoutATime() {
        val result = plan(
            """
            Lançamentos;Valor
            15/07/2026 MERCADO EXTRA;-50,00
            16/07/2026 PADARIA;-12,50
            17/07/2026 SALARIO;5.000,00
            """.trimIndent(),
        )
        assertTrue(result.schema.dateColumnCarriesDescription)
        assertEquals(listOf("Mercado Extra", "Padaria", "Salario"), titles(result))
    }

    /** Amounts and directions must survive the fused path unchanged. */
    @Test fun fusedColumnStillReadsAmountsAndDirections() {
        val result = plan(
            """
            Lançamentos;Valor
            15/07/2026 14:30 MERCADO EXTRA;-50,00
            16/07/2026 09:05 PADARIA;-12,50
            17/07/2026 21:44 SALARIO;5.000,00
            """.trimIndent(),
        )
        assertEquals(listOf(-5_000L, -1_250L, 500_000L), result.rows.mapNotNull { it.parsed?.signedCents })
    }

    /** A dedicated description column still wins over the remainder when the file has both. */
    @Test fun aDedicatedDescriptionColumnBeatsTheRemainder() {
        val result = plan(
            """
            Data;Descrição;Valor
            15/07/2026 14:30;MERCADO EXTRA;-50,00
            16/07/2026 09:05;PADARIA;-12,50
            17/07/2026 21:44;SALARIO;5.000,00
            """.trimIndent(),
        )
        assertFalse("a clean date column is not fused, even when it carries a time", result.schema.dateColumnCarriesDescription)
        assertEquals(listOf("Mercado Extra", "Padaria", "Salario"), titles(result))
    }

    // ---- Leading-date extraction in isolation ----

    @Test fun leadingDateExtractionTakesTheLongestValidPrefix() {
        val withTime = requireNotNull(DateFieldParser.parseLeadingDate("15/07/2026 14:30 COMPRA MERCADO"))
        assertEquals("the time must be consumed with the date, not stranded on the title", "COMPRA MERCADO", withTime.remainder)

        val withoutTime = requireNotNull(DateFieldParser.parseLeadingDate("15/07/2026 COMPRA MERCADO"))
        assertEquals("COMPRA MERCADO", withoutTime.remainder)
    }

    @Test fun leadingDateExtractionRejectsTextWithNoDate() {
        assertNull(DateFieldParser.parseLeadingDate("COMPRA MERCADO EXTRA"))
        assertNull(DateFieldParser.parseLeadingDate(""))
    }

    @Test fun leadingDateHitRateSeparatesFusedColumnsFromProse() {
        assertTrue(DateFieldParser.leadingDateHitRate(listOf("15/07/2026 14:30 MERCADO", "16/07/2026 09:05 PADARIA")) >= 0.9)
        assertEquals(0.0, DateFieldParser.leadingDateHitRate(listOf("MERCADO EXTRA", "PADARIA CENTRAL")), 0.0)
    }

    /**
     * A row whose date cannot be extracted fails on its own, without costing the rest of the file.
     * Sized like a real statement: a fused column needs 90% of its values to start with a date.
     */
    @Test fun aFusedColumnRowWithoutADateFailsAlone() {
        val lines = mutableListOf("Lançamentos;Valor", "SALDO ANTERIOR;-12,50")
        for (day in 10..20) lines += "$day/07/2026 09:05 MERCADO $day;-$day,00"
        val result = plan(lines.joinToString("\n"))

        assertTrue(result.schema.dateColumnCarriesDescription)
        assertEquals(12, result.rows.size)
        assertEquals("only the summary line fails", 1, result.failedRows.size)
        // Deliberately NOT asserting insertability: nothing proves the sign, so parsed rows park for a decision.
        assertEquals(11, result.rows.count { it.parsed != null })
    }
}
