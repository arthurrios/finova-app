//
//  CSVParsingTests.swift
//  FinovaTests
//
//  Bytes → rows. No database, no UI.
//

import XCTest

@testable import Finova

final class CSVParsingTests: XCTestCase {

    // MARK: - Tokenizer

    private func cells(_ text: String, _ delimiter: Character = ",") throws -> [[String]] {
        try CSVTokenizer.tokenize(text, dialect: CSVDialect(delimiter: delimiter)).map(\.cells)
    }

    func testQuotedFieldContainingTheDelimiter() throws {
        let rows = try cells("a,\"b,c\",d")
        XCTAssertEqual(rows, [["a", "b,c", "d"]])
    }

    func testQuotedFieldContainingANewline() throws {
        let rows = try cells("a,\"line one\nline two\",c\nx,y,z")
        XCTAssertEqual(rows, [["a", "line one\nline two", "c"], ["x", "y", "z"]])
    }

    func testDoubledQuotesBecomeOneLiteralQuote() throws {
        let rows = try cells("a,\"say \"\"hi\"\"\",c")
        XCTAssertEqual(rows, [["a", "say \"hi\"", "c"]])
    }

    func testEmptyQuotedFieldIsAnEmptyString() throws {
        XCTAssertEqual(try cells("a,\"\",c"), [["a", "", "c"]])
    }

    func testWhitespaceBeforeAnOpeningQuoteIsTolerated() throws {
        // Not RFC-legal. Banks do it anyway.
        XCTAssertEqual(try cells("a,  \"b\",c"), [["a", "b", "c"]])
    }

    func testTrailingSpacesAreTrimmedButInteriorOnesSurvive() throws {
        XCTAssertEqual(try cells("a,b  c  ,d"), [["a", "b  c", "d"]])
    }

    func testCRLFAndLoneCRBothEndRows() throws {
        XCTAssertEqual(try cells("a,b\r\nc,d"), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(try cells("a,b\rc,d"), [["a", "b"], ["c", "d"]])
    }

    func testAFinalRowWithoutATrailingNewlineIsKept() throws {
        XCTAssertEqual(try cells("a,b\nc,d"), [["a", "b"], ["c", "d"]])
    }

    func testBlankLinesAreStructureNotData() throws {
        XCTAssertEqual(try cells("a,b\n\n\nc,d"), [["a", "b"], ["c", "d"]])
    }

    /// Every Brazilian export ends with a `Saldo` summary line carrying fewer fields. It must cost
    /// that line and nothing else — which is the whole reason this is not `TabularData.DataFrame`.
    func testARaggedSummaryRowIsKeptRatherThanFailingTheFile() throws {
        let rows = try cells("data,desc,valor\n01/01/2026,Mercado,-50\nSaldo,1234")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[2], ["Saldo", "1234"])
    }

    func testARowWithExtraFieldsIsKept() throws {
        let rows = try cells("a,b\nc,d,e")
        XCTAssertEqual(rows[1], ["c", "d", "e"])
    }

    /// The diff has to be able to say WHICH row broke.
    func testUnterminatedQuoteReportsItsLineNumber() {
        let text = "a,b\nc,d\ne,\"unclosed"
        XCTAssertThrowsError(try cells(text)) { error in
            XCTAssertEqual(error as? ImportError, .unterminatedQuote(line: 3))
        }
    }

    func testRowLimitIsEnforced() {
        let text = (0..<50).map { "a\($0),b" }.joined(separator: "\n")
        XCTAssertThrowsError(try CSVTokenizer.tokenize(text, dialect: .comma, maxRows: 10)) { error in
            guard case ImportError.tooManyRows = error else { return XCTFail("expected .tooManyRows") }
        }
    }

    func testModalFieldCountIgnoresPreambleAndSummary() throws {
        let rows = try CSVTokenizer.tokenize(
            "Extrato\nConta 123\na,b,c\n1,2,3\n4,5,6\nSaldo,9",
            dialect: .comma)
        let (count, fraction) = CSVTokenizer.modalFieldCount(rows)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(fraction, 3.0 / 6.0, accuracy: 0.001)
    }

    // MARK: - Encoding

    func testUTF8WithBOMDecodesAndTheBOMIsStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("data;descrição\n".data(using: .utf8)!)
        let result = try XCTUnwrap(EncodingSniffer.decode(data))
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertTrue(result.text.hasPrefix("data"), "a BOM glued to the first header cell hides it")
        XCTAssertTrue(result.text.contains("descrição"))
    }

    func testPlainUTF8Accents() throws {
        let result = try XCTUnwrap(EncodingSniffer.decode("São Paulo, Ação, Nº 5".data(using: .utf8)!))
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.text, "São Paulo, Ação, Nº 5")
        XCTAssertFalse(result.wasLossy)
    }

    func testWindows1252IsDecodedWhenItGenuinelyIsWindows1252() throws {
        let data = try XCTUnwrap("São Paulo".data(using: .windowsCP1252))
        let result = try XCTUnwrap(EncodingSniffer.decode(data))
        XCTAssertEqual(result.text, "São Paulo")
    }

    /// The bug this ordering exists to prevent. Latin-1 NEVER fails, so trying it before measuring
    /// UTF-8 shape turns one damaged byte into a permanently mojibaked ledger.
    func testAUTF8FileWithOneCorruptByteStaysUTF8() throws {
        var data = "São Paulo, Mercado Central, Padaria".data(using: .utf8)!
        data.append(0xFF)  // never valid in UTF-8
        data.append(contentsOf: Array(", Farmácia".utf8))

        let result = try XCTUnwrap(EncodingSniffer.decode(data))
        XCTAssertEqual(result.encoding, .utf8, "one bad byte must not flip the whole file to Latin-1")
        XCTAssertTrue(result.wasLossy)
        XCTAssertTrue(result.text.contains("São Paulo"))
        XCTAssertTrue(result.text.contains("Farmácia"))
        XCTAssertFalse(result.text.contains("SÃ£o"))
    }

    func testUTF8ValidityScoresAsciiAsFullyValid() {
        XCTAssertEqual(EncodingSniffer.utf8Validity(of: Data("plain ascii".utf8)), 1.0)
    }

    func testUTF8ValidityScoresLatin1AccentsLow() throws {
        let data = try XCTUnwrap("café à la carte".data(using: .isoLatin1))
        XCTAssertLessThan(EncodingSniffer.utf8Validity(of: data), 0.5)
    }

    func testMojibakeSignatureIsRecognised() {
        XCTAssertTrue(EncodingSniffer.looksLikeMisreadUTF8("SÃ£o Paulo"))
        XCTAssertFalse(EncodingSniffer.looksLikeMisreadUTF8("São Paulo"))
    }

    func testUTF16LittleEndianWithBOM() throws {
        let data = try XCTUnwrap("data;valor".data(using: .utf16LittleEndian))
        var withBOM = Data([0xFF, 0xFE])
        withBOM.append(data)
        let result = try XCTUnwrap(EncodingSniffer.decode(withBOM))
        XCTAssertEqual(result.text, "data;valor")
    }

    // MARK: - Delimiter

    func testSemicolonWinsForAPtBRFileWhoseAmountsUseCommas() {
        let text = """
        Data;Descrição;Valor
        01/07/2026;Mercado Extra, Centro;-1.234,56
        02/07/2026;Padaria;-12,50
        03/07/2026;Salário;5.000,00
        """
        XCTAssertEqual(DelimiterSniffer.sniff(text).dialect.delimiter, ";")
    }

    func testCommaWinsForAnEnglishFile() {
        let text = """
        Date,Description,Amount
        2026-07-01,Grocery Store,-1234.56
        2026-07-02,Bakery,-12.50
        2026-07-03,Salary,5000.00
        """
        XCTAssertEqual(DelimiterSniffer.sniff(text).dialect.delimiter, ",")
    }

    func testTabDelimited() {
        let text = "Date\tDescription\tAmount\n2026-07-01\tShop\t-10.00\n2026-07-02\tCafe\t-4.00"
        XCTAssertEqual(DelimiterSniffer.sniff(text).dialect.delimiter, "\t")
    }

    func testExcelSepDirectiveWinsOutright() {
        let detection = DelimiterSniffer.sniff("sep=;\nDate;Desc\n01/01/2026;x")
        XCTAssertEqual(detection.dialect.delimiter, ";")
        XCTAssertEqual(detection.skipLeadingLines, 1)
    }

    /// The case naive `split(separator:)` gets wrong: commas inside quoted descriptions outnumber
    /// the real delimiters.
    func testDelimiterSniffingIgnoresSeparatorsInsideQuotes() {
        let text = """
        Data;Descrição;Valor
        01/07/2026;"Mercado, Padaria, Açougue";-10,00
        02/07/2026;"Loja A, Loja B, Loja C";-20,00
        03/07/2026;"Bar, Restaurante, Café";-30,00
        """
        XCTAssertEqual(DelimiterSniffer.sniff(text).dialect.delimiter, ";")
    }
}
