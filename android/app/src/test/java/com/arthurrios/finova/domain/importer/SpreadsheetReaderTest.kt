package com.arthurrios.finova.domain.importer

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream

/**
 * Workbooks end to end: bytes to rows to the same plan a CSV would produce. Port of
 * FinovaTests/Import/SpreadsheetReaderTests.swift.
 */
class SpreadsheetReaderTest {
    private lateinit var originalYear: () -> Int

    @Before fun pinYear() {
        originalYear = DateFieldParser.currentYear
        DateFieldParser.currentYear = { 2026 }
    }

    @After fun restoreYear() {
        DateFieldParser.currentYear = originalYear
    }

    private fun plan(data: ByteArray, filename: String): ImportPlan =
        CsvImportEngine.makePlan(CsvImportEngine.Input(filename = filename, data = data, alreadyImported = emptySet(), existing = emptyList()))

    // ---- Recognition ----

    @Test fun eachReaderClaimsOnlyItsOwnFormat() {
        assertTrue(XlsxReader.canRead(SpreadsheetFixtures.xlsx))
        assertFalse(XlsxReader.canRead(SpreadsheetFixtures.xls))

        assertTrue(XlsReader.canRead(SpreadsheetFixtures.xls))
        assertFalse(XlsReader.canRead(SpreadsheetFixtures.xlsx))

        assertFalse(SpreadsheetImporter.canRead("Data;Valor\n15/07/2026;-50,00".toByteArray(Charsets.UTF_8)))
    }

    // ---- ZIP ----
    // iOS has its own `ZipArchiveReader`; Android reads the archive with java.util.zip inside
    // XlsxReader, so these check the same facts through the reader.

    /** Inflated content must round-trip UTF-8 ("Lançamentos" lives in sharedStrings.xml). */
    @Test fun zipReaderExtractsEntries() {
        val cells = XlsxReader.read(SpreadsheetFixtures.xlsx).flatMap { it.cells }
        assertTrue("inflated content must round-trip UTF-8", "Lançamentos" in cells)
        assertTrue("MERCADO EXTRA" in cells)
    }

    @Test fun zipReaderRejectsNonArchives() {
        assertFalse(XlsxReader.canRead("not a zip at all".toByteArray(Charsets.UTF_8)))
        assertFalse(XlsxReader.canRead(SpreadsheetFixtures.xls))
    }

    // ---- XLSX ----

    @Test fun xlsxReadsRowsWithSharedStringsAndDates() {
        val rows = XlsxReader.read(SpreadsheetFixtures.xlsx)
        assertEquals("header plus three data rows", 4, rows.size)

        assertEquals("text cells are indices into the shared string table, not literals", listOf("Data", "Lançamentos", "Valor"), rows[0].cells)

        // A date cell is a plain number; only its style says it is a date.
        assertEquals("15/07/2026", rows[1].cells[0])
        assertEquals("MERCADO EXTRA", rows[1].cells[1])
        assertEquals("-50.5", rows[1].cells[2])
    }

    // ---- XLS ----

    @Test fun xlsReadsRowsFromTheCompoundDocument() {
        val rows = XlsReader.read(SpreadsheetFixtures.xls)
        assertEquals(4, rows.size)

        assertEquals(listOf("Data", "Lançamentos", "Valor"), rows[0].cells)
        assertEquals("15/07/2026", rows[1].cells[0])
        assertEquals("MERCADO EXTRA", rows[1].cells[1])
        assertEquals("-50.5", rows[1].cells[2])
    }

    @Test fun ole2ContainerFindsTheWorkbookStream() {
        val container = requireNotNull(Ole2Container.open(SpreadsheetFixtures.xls))
        val workbook = requireNotNull(container.stream("Workbook"))
        assertTrue(workbook.size > 4096)
        // Every BIFF stream opens with a BOF record.
        assertEquals(0x0809, workbook.u16(0))
    }

    /** Serial 46218 must land on 15 July 2026: the 1900-leap-year correction is off-by-one bait. */
    @Test fun excelSerialDatesConvertCorrectly() {
        assertEquals("15/07/2026", SpreadsheetCell.displayDate(46218.0, includesTime = false))
        // Serial 59 and 61 straddle Excel's phantom 29 Feb 1900.
        assertEquals("28/02/1900", SpreadsheetCell.displayDate(59.0, includesTime = false))
        assertEquals("01/03/1900", SpreadsheetCell.displayDate(61.0, includesTime = false))
    }

    // ---- End to end, through the ordinary pipeline ----

    @Test fun anXLSXImportsThroughTheSamePipelineAsACSV() {
        val result = plan(SpreadsheetFixtures.xlsx, "extrato.xlsx")

        assertEquals("the header is consumed by inference", 3, result.rows.size)
        assertTrue(result.failedRows.isEmpty())
        assertEquals("dd/MM/yyyy", result.schema.dateFormat.pattern)
        assertEquals(listOf("Mercado Extra", "Padaria", "Salario"), result.rows.mapNotNull { it.parsed?.title?.title })
    }

    @Test fun anXLSImportsThroughTheSamePipelineAsACSV() {
        val result = plan(SpreadsheetFixtures.xls, "extrato.xls")

        assertEquals(3, result.rows.size)
        assertTrue(result.failedRows.isEmpty())
        assertEquals(listOf("Mercado Extra", "Padaria", "Salario"), result.rows.mapNotNull { it.parsed?.title?.title })
        assertEquals(listOf(-5_050L, -1_250L, 500_000L), result.rows.mapNotNull { it.parsed?.signedCents })
    }

    /** A workbook reaches the review diff, so undo, dedupe and sync apply to it as to a CSV. */
    @Test fun aWorkbookProducesAReviewablePlan() {
        val result = plan(SpreadsheetFixtures.xls, "extrato.xls")
        val resolved = result.resolve(ImportOverrides())
        assertEquals(result.rows.size, resolved.rows.size + resolved.skippedCount + resolved.failedCount)
    }

    // ---- Refusals ----

    @Test fun anEncryptedWorkbookIsRefusedRatherThanGuessedAt() {
        // A FILEPASS record anywhere in the stream means the contents are encrypted.
        val stream = bytes(0x09, 0x08, 0x10, 0x00) + ByteArray(16) + bytes(0x2F, 0x00, 0x04, 0x00) + ByteArray(4)
        val error = assertThrows(SpreadsheetError::class.java) { Biff.rows(stream) }
        assertEquals(SpreadsheetError.Encrypted, error)
    }

    /** iOS checks the message contains "PDF"; Android carries the detected format itself. */
    @Test fun aPDFIsNamedRatherThanParsed() {
        val error = assertThrows(ImportError::class.java) { plan("%PDF-1.7\nstream nonsense".toByteArray(Charsets.UTF_8), "extrato.pdf") }
        assertTrue("expected WrongFileFormat, got $error", error is ImportError.WrongFileFormat)
        assertEquals(DetectedFileFormat.Pdf, (error as ImportError.WrongFileFormat).detected)
    }

    // ---- The SST continuation bug ----
    // iOS calls `BIFFWorkbook.parseSST(segments:)` directly. Android's SST reader is private to
    // Biff, so each case is wrapped in a minimal BIFF stream (BOF, SST, CONTINUE, one LABELSST cell
    // per string, EOF) and read back through Biff.rows.

    /**
     * The failure that made a real 1819-row statement decode as replacement characters: a string
     * caught by a CONTINUE boundary resumes BEHIND a fresh option byte.
     */
    @Test fun aStringSplitAcrossAContinueBoundaryIsReassembled() {
        val first = ByteArrayOutputStream().apply {
            write(bytes(3, 0, 0, 0)) // total count
            write(bytes(3, 0, 0, 0)) // unique count
            // "MERCADO", 8-bit, entirely inside this segment.
            write(bytes(7, 0)); write(0x00); write("MERCADO".toByteArray(Charsets.US_ASCII))
            // "PADARIA CENTRAL" declared as 15 characters, but the segment ends after five of them.
            write(bytes(15, 0)); write(0x00); write("PADAR".toByteArray(Charsets.US_ASCII))
        }.toByteArray()

        val second = ByteArrayOutputStream().apply {
            write(0x00) // continuation option byte: still 8-bit
            write("IA CENTRAL".toByteArray(Charsets.US_ASCII))
            // A 16-bit string following it, to prove the cursor stays aligned afterwards.
            write(bytes(6, 0)); write(0x01); write("AÇÚCAR".toByteArray(Charsets.UTF_16LE))
        }.toByteArray()

        assertEquals(listOf("MERCADO", "PADARIA CENTRAL", "AÇÚCAR"), sstStrings(listOf(first, second)))
    }

    /** The same boundary, but the continuation flips the remainder to 16-bit. */
    @Test fun aContinuationMayChangeTheEncodingMidString() {
        val first = ByteArrayOutputStream().apply {
            write(bytes(1, 0, 0, 0)); write(bytes(1, 0, 0, 0))
            write(bytes(6, 0)); write(0x00) // starts 8-bit
            write("PAD".toByteArray(Charsets.US_ASCII)) // three of six characters
        }.toByteArray()

        val second = ByteArrayOutputStream().apply {
            write(0x01) // remainder is 16-bit
            write("ARI".toByteArray(Charsets.UTF_16LE))
        }.toByteArray()

        assertEquals(listOf("PADARI"), sstStrings(listOf(first, second)))
    }

    /** A table entirely inside one segment must still read correctly. */
    @Test fun aSingleSegmentTableStillParses() {
        val only = ByteArrayOutputStream().apply {
            write(bytes(2, 0, 0, 0)); write(bytes(2, 0, 0, 0))
            write(bytes(5, 0)); write(0x00); write("SALDO".toByteArray(Charsets.US_ASCII))
            write(bytes(6, 0)); write(0x01); write("AÇÚCAR".toByteArray(Charsets.UTF_16LE))
        }.toByteArray()

        assertEquals(listOf("SALDO", "AÇÚCAR"), sstStrings(listOf(only)))
    }

    // ---- Helpers ----

    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

    private fun ByteArrayOutputStream.record(type: Int, body: ByteArray) {
        write(bytes(type and 0xFF, type shr 8, body.size and 0xFF, body.size shr 8))
        write(body)
    }

    /** The shared strings a BIFF stream with these SST segments yields, one LABELSST cell per string (row i, column 0). */
    private fun sstStrings(segments: List<ByteArray>): List<String> {
        val unique = segments.first().u32(4).toInt()
        val stream = ByteArrayOutputStream().apply {
            record(0x0809, ByteArray(16)) // BOF
            record(0x00FC, segments.first()) // SST
            for (segment in segments.drop(1)) record(0x003C, segment) // CONTINUE
            for (index in 0 until unique) {
                // LABELSST: row, column, xf, then the SST index.
                record(0x00FD, bytes(index, 0, 0, 0, 0, 0, index, 0, 0, 0))
            }
            record(0x000A, ByteArray(0)) // EOF
        }.toByteArray()
        return Biff.rows(stream).map { it.cells.firstOrNull().orEmpty() }
    }
}
