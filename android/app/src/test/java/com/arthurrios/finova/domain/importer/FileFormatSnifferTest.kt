package com.arthurrios.finova.domain.importer

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.random.Random

/**
 * A spreadsheet fed to a CSV parser produces line noise, and every error after that describes a
 * symptom instead of the cause. These pin the cause being named. Port of
 * FinovaTests/Import/FileFormatSnifferTests.swift.
 */
class FileFormatSnifferTest {
    private lateinit var originalYear: () -> Int

    @Before fun pinYear() {
        originalYear = DateFieldParser.currentYear
        DateFieldParser.currentYear = { 2026 }
    }

    @After fun restoreYear() {
        DateFieldParser.currentYear = originalYear
    }

    private fun plan(data: ByteArray): ImportPlan =
        CsvImportEngine.makePlan(CsvImportEngine.Input(filename = "extrato.csv", data = data, alreadyImported = emptySet(), existing = emptyList()))

    private val ole2Magic = byteArrayOf(0xD0.toByte(), 0xCF.toByte(), 0x11, 0xE0.toByte(), 0xA1.toByte(), 0xB1.toByte(), 0x1A, 0xE1.toByte())

    // ---- Signatures ----

    @Test fun legacyExcelIsRecognised() {
        // OLE2 compound document header: what most Brazilian banks hand out as "Excel".
        val data = ole2Magic + ByteArray(512)
        assertEquals(DetectedFileFormat.Ole2Document, FileFormatSniffer.detect(data))
    }

    @Test fun modernSpreadsheetIsRecognised() {
        val data = "PK\u0003\u0004".toByteArray(Charsets.UTF_8) + ByteArray(64)
        assertEquals(DetectedFileFormat.ZipContainer, FileFormatSniffer.detect(data))
    }

    @Test fun pdfIsRecognised() {
        assertEquals(DetectedFileFormat.Pdf, FileFormatSniffer.detect("%PDF-1.7\n%âãÏÓ".toByteArray(Charsets.UTF_8)))
    }

    @Test fun aGenuineCSVIsText() {
        val csv = "Data;Descrição;Valor\n15/07/2026;MERCADO;-50,00\n"
        assertEquals(DetectedFileFormat.Text, FileFormatSniffer.detect(csv.toByteArray(Charsets.UTF_8)))
    }

    /** Accented pt-BR content is not binary: the high bytes are legitimate UTF-8. */
    @Test fun accentedCSVIsStillText() {
        val csv = "Data;Descrição;Valor\n15/07/2026;AÇOUGUE SÃO JOÃO;-50,00\n"
        assertEquals(DetectedFileFormat.Text, FileFormatSniffer.detect(csv.toByteArray(Charsets.UTF_8)))
    }

    @Test fun unsignedBinaryIsCaughtByControlDensity() {
        val data = ByteArray(2048) { Random.nextInt(0, 0x09).toByte() }
        assertEquals(DetectedFileFormat.OtherBinary, FileFormatSniffer.detect(data))
    }

    // ---- The message the user actually sees ----

    /** iOS checks the message string contains "xls"; Android carries the detected format itself. */
    @Test fun anExcelFileNamesItselfRatherThanFailingAsAParseError() {
        val data = ole2Magic + ByteArray(4096) { 0x20 }
        val error = assertThrows(ImportError::class.java) { plan(data) }
        assertTrue("expected WrongFileFormat, got $error", error is ImportError.WrongFileFormat)
        assertEquals(DetectedFileFormat.Ole2Document, (error as ImportError.WrongFileFormat).detected)
    }

    @Test fun aGenuineCSVStillImports() {
        val csv = """
            Data;Descrição;Valor;Saldo
            15/07/2026;MERCADO;-50,00;100,00
            16/07/2026;PADARIA;-12,50;87,50
            17/07/2026;SALARIO;500,00;587,50
        """.trimIndent()
        val result = plan(csv.toByteArray(Charsets.UTF_8))
        assertEquals(3, result.rows.size)
        assertTrue(result.failedRows.isEmpty())
    }
}
