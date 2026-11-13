package com.arthurrios.finova.domain.importer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.Charset

/** Bytes to rows. No database, no UI. Port of FinovaTests/Import/CSVParsingTests.swift. */
class CsvParsingTest {

    // ---- Tokenizer ----

    private fun cells(text: String, delimiter: Char = ','): List<List<String>> =
        CsvTokenizer.tokenize(text, CsvDialect(delimiter)).map { it.cells }

    @Test fun quotedFieldContainingTheDelimiter() {
        assertEquals(listOf(listOf("a", "b,c", "d")), cells("a,\"b,c\",d"))
    }

    @Test fun quotedFieldContainingANewline() {
        assertEquals(
            listOf(listOf("a", "line one\nline two", "c"), listOf("x", "y", "z")),
            cells("a,\"line one\nline two\",c\nx,y,z"),
        )
    }

    @Test fun doubledQuotesBecomeOneLiteralQuote() {
        assertEquals(listOf(listOf("a", "say \"hi\"", "c")), cells("a,\"say \"\"hi\"\"\",c"))
    }

    @Test fun emptyQuotedFieldIsAnEmptyString() {
        assertEquals(listOf(listOf("a", "", "c")), cells("a,\"\",c"))
    }

    @Test fun whitespaceBeforeAnOpeningQuoteIsTolerated() {
        // Not RFC-legal. Banks do it anyway.
        assertEquals(listOf(listOf("a", "b", "c")), cells("a,  \"b\",c"))
    }

    @Test fun trailingSpacesAreTrimmedButInteriorOnesSurvive() {
        assertEquals(listOf(listOf("a", "b  c", "d")), cells("a,b  c  ,d"))
    }

    @Test fun crlfAndLoneCRBothEndRows() {
        assertEquals(listOf(listOf("a", "b"), listOf("c", "d")), cells("a,b\r\nc,d"))
        assertEquals(listOf(listOf("a", "b"), listOf("c", "d")), cells("a,b\rc,d"))
    }

    @Test fun aFinalRowWithoutATrailingNewlineIsKept() {
        assertEquals(listOf(listOf("a", "b"), listOf("c", "d")), cells("a,b\nc,d"))
    }

    @Test fun blankLinesAreStructureNotData() {
        assertEquals(listOf(listOf("a", "b"), listOf("c", "d")), cells("a,b\n\n\nc,d"))
    }

    /** Every Brazilian export ends with a `Saldo` summary line carrying fewer fields. It costs that line only. */
    @Test fun aRaggedSummaryRowIsKeptRatherThanFailingTheFile() {
        val rows = cells("data,desc,valor\n01/01/2026,Mercado,-50\nSaldo,1234")
        assertEquals(3, rows.size)
        assertEquals(listOf("Saldo", "1234"), rows[2])
    }

    @Test fun aRowWithExtraFieldsIsKept() {
        val rows = cells("a,b\nc,d,e")
        assertEquals(listOf("c", "d", "e"), rows[1])
    }

    /** The diff has to be able to say WHICH row broke. */
    @Test fun unterminatedQuoteReportsItsLineNumber() {
        val error = assertThrows(ImportError::class.java) { cells("a,b\nc,d\ne,\"unclosed") }
        assertEquals(ImportError.UnterminatedQuote(3), error)
    }

    @Test fun rowLimitIsEnforced() {
        val text = (0 until 50).joinToString("\n") { "a$it,b" }
        assertThrows(ImportError.TooManyRows::class.java) {
            CsvTokenizer.tokenize(text, CsvDialect(','), maxRows = 10)
        }
    }

    @Test fun modalFieldCountIgnoresPreambleAndSummary() {
        val rows = CsvTokenizer.tokenize("Extrato\nConta 123\na,b,c\n1,2,3\n4,5,6\nSaldo,9", CsvDialect(','))
        val (count, fraction) = CsvTokenizer.modalFieldCount(rows)
        assertEquals(3, count)
        assertEquals(3.0 / 6.0, fraction, 0.001)
    }

    // ---- Encoding ----

    @Test fun utf8WithBOMDecodesAndTheBOMIsStripped() {
        val data = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "data;descrição\n".toByteArray(Charsets.UTF_8)
        val result = unwrap(EncodingSniffer.decode(data))
        assertEquals("UTF-8", result.encoding)
        assertTrue("a BOM glued to the first header cell hides it", result.text.startsWith("data"))
        assertTrue(result.text.contains("descrição"))
    }

    @Test fun plainUTF8Accents() {
        val result = unwrap(EncodingSniffer.decode("São Paulo, Ação, Nº 5".toByteArray(Charsets.UTF_8)))
        assertEquals("UTF-8", result.encoding)
        assertEquals("São Paulo, Ação, Nº 5", result.text)
        assertFalse(result.wasLossy)
    }

    @Test fun windows1252IsDecodedWhenItGenuinelyIsWindows1252() {
        val data = "São Paulo".toByteArray(Charset.forName("windows-1252"))
        val result = unwrap(EncodingSniffer.decode(data))
        assertEquals("São Paulo", result.text)
    }

    /**
     * The bug this ordering exists to prevent. Latin-1 NEVER fails, so trying it before measuring
     * UTF-8 shape turns one damaged byte into a permanently mojibaked ledger.
     */
    @Test fun aUTF8FileWithOneCorruptByteStaysUTF8() {
        val data = "São Paulo, Mercado Central, Padaria".toByteArray(Charsets.UTF_8) +
            byteArrayOf(0xFF.toByte()) + // never valid in UTF-8
            ", Farmácia".toByteArray(Charsets.UTF_8)

        val result = unwrap(EncodingSniffer.decode(data))
        assertEquals("one bad byte must not flip the whole file to Latin-1", "UTF-8", result.encoding)
        assertTrue(result.wasLossy)
        assertTrue(result.text.contains("São Paulo"))
        assertTrue(result.text.contains("Farmácia"))
        assertFalse(result.text.contains("SÃ£o"))
    }

    @Test fun utf8ValidityScoresAsciiAsFullyValid() {
        assertEquals(1.0, EncodingSniffer.utf8Validity("plain ascii".toByteArray(Charsets.UTF_8)), 0.0)
    }

    @Test fun utf8ValidityScoresLatin1AccentsLow() {
        val data = "café à la carte".toByteArray(Charsets.ISO_8859_1)
        assertTrue(EncodingSniffer.utf8Validity(data) < 0.5)
    }

    @Test fun mojibakeSignatureIsRecognised() {
        assertTrue(EncodingSniffer.looksLikeMisreadUtf8("SÃ£o Paulo"))
        assertFalse(EncodingSniffer.looksLikeMisreadUtf8("São Paulo"))
    }

    @Test fun utf16LittleEndianWithBOM() {
        val data = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "data;valor".toByteArray(Charsets.UTF_16LE)
        val result = unwrap(EncodingSniffer.decode(data))
        assertEquals("data;valor", result.text)
    }

    // ---- Delimiter ----

    @Test fun semicolonWinsForAPtBRFileWhoseAmountsUseCommas() {
        val text = """
            Data;Descrição;Valor
            01/07/2026;Mercado Extra, Centro;-1.234,56
            02/07/2026;Padaria;-12,50
            03/07/2026;Salário;5.000,00
        """.trimIndent()
        assertEquals(';', DelimiterSniffer.sniff(text).dialect.delimiter)
    }

    @Test fun commaWinsForAnEnglishFile() {
        val text = """
            Date,Description,Amount
            2026-07-01,Grocery Store,-1234.56
            2026-07-02,Bakery,-12.50
            2026-07-03,Salary,5000.00
        """.trimIndent()
        assertEquals(',', DelimiterSniffer.sniff(text).dialect.delimiter)
    }

    @Test fun tabDelimited() {
        val text = "Date\tDescription\tAmount\n2026-07-01\tShop\t-10.00\n2026-07-02\tCafe\t-4.00"
        assertEquals('\t', DelimiterSniffer.sniff(text).dialect.delimiter)
    }

    @Test fun excelSepDirectiveWinsOutright() {
        val detection = DelimiterSniffer.sniff("sep=;\nDate;Desc\n01/01/2026;x")
        assertEquals(';', detection.dialect.delimiter)
        assertEquals(1, detection.skipLeadingLines)
    }

    /** The case a naive split gets wrong: commas inside quoted descriptions outnumber the real delimiters. */
    @Test fun delimiterSniffingIgnoresSeparatorsInsideQuotes() {
        val text = """
            Data;Descrição;Valor
            01/07/2026;"Mercado, Padaria, Açougue";-10,00
            02/07/2026;"Loja A, Loja B, Loja C";-20,00
            03/07/2026;"Bar, Restaurante, Café";-30,00
        """.trimIndent()
        assertEquals(';', DelimiterSniffer.sniff(text).dialect.delimiter)
    }

    private fun <T : Any> unwrap(value: T?): T = requireNotNull(value) { "expected a value" }
}
