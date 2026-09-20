//
//  SpreadsheetReaderTests.swift
//  FinovaTests
//
//  Workbooks end to end: bytes → rows → the same plan a CSV would produce.
//

import XCTest

@testable import Finova

final class SpreadsheetReaderTests: XCTestCase {

    private func plan(_ data: Data, filename: String) throws -> ImportPlan {
        try CSVImportEngine.makePlan(CSVImportEngine.Input(
            filename: filename, data: data, alreadyImported: [], existing: []))
    }

    // MARK: - Recognition

    func testEachReaderClaimsOnlyItsOwnFormat() {
        XCTAssertTrue(XLSXReader.canRead(SpreadsheetFixtures.xlsx))
        XCTAssertFalse(XLSXReader.canRead(SpreadsheetFixtures.xls))

        XCTAssertTrue(XLSReader.canRead(SpreadsheetFixtures.xls))
        XCTAssertFalse(XLSReader.canRead(SpreadsheetFixtures.xlsx))

        let csv = Data("Data;Valor\n15/07/2026;-50,00".utf8)
        XCTAssertFalse(SpreadsheetImporter.canRead(csv))
    }

    // MARK: - ZIP

    func testZipReaderExtractsEntries() throws {
        let archive = try XCTUnwrap(ZipArchiveReader(data: SpreadsheetFixtures.xlsx))
        XCTAssertTrue(archive.contains("xl/sharedStrings.xml"))

        let shared = try XCTUnwrap(archive.extract("xl/sharedStrings.xml"))
        let text = try XCTUnwrap(String(data: shared, encoding: .utf8))
        XCTAssertTrue(text.contains("Lançamentos"), "inflated content must round-trip UTF-8")
        XCTAssertTrue(text.contains("MERCADO EXTRA"))
    }

    func testZipReaderRejectsNonArchives() {
        XCTAssertNil(ZipArchiveReader(data: Data("not a zip at all".utf8)))
        XCTAssertNil(ZipArchiveReader(data: SpreadsheetFixtures.xls))
    }

    // MARK: - XLSX

    func testXLSXReadsRowsWithSharedStringsAndDates() throws {
        let rows = try XLSXReader.read(SpreadsheetFixtures.xlsx)
        XCTAssertEqual(rows.count, 4, "header plus three data rows")

        XCTAssertEqual(rows[0].cells, ["Data", "Lançamentos", "Valor"],
                       "text cells are indices into the shared string table, not literals")

        // A date cell is a plain number; only its style says it is a date.
        XCTAssertEqual(rows[1].cells[0], "15/07/2026")
        XCTAssertEqual(rows[1].cells[1], "MERCADO EXTRA")
        XCTAssertEqual(rows[1].cells[2], "-50.5")
    }

    // MARK: - XLS

    func testXLSReadsRowsFromTheCompoundDocument() throws {
        let rows = try XLSReader.read(SpreadsheetFixtures.xls)
        XCTAssertEqual(rows.count, 4)

        XCTAssertEqual(rows[0].cells, ["Data", "Lançamentos", "Valor"])
        XCTAssertEqual(rows[1].cells[0], "15/07/2026")
        XCTAssertEqual(rows[1].cells[1], "MERCADO EXTRA")
        XCTAssertEqual(rows[1].cells[2], "-50.5")
    }

    func testOLE2ContainerFindsTheWorkbookStream() throws {
        let container = try XCTUnwrap(OLE2Container(data: SpreadsheetFixtures.xls))
        let workbook = try XCTUnwrap(container.stream(named: "Workbook"))
        XCTAssertGreaterThan(workbook.count, 4096)
        // Every BIFF stream opens with a BOF record.
        XCTAssertEqual(workbook.readUInt16(at: 0), 0x0809)
    }

    /// Serial 46218 must land on 15 July 2026 — the 1900-leap-year correction is off-by-one bait.
    func testExcelSerialDatesConvertCorrectly() {
        XCTAssertEqual(SpreadsheetCell.displayString(forExcelSerial: 46218, includesTime: false),
                       "15/07/2026")
        // Serial 59 and 61 straddle Excel's phantom 29 Feb 1900.
        XCTAssertEqual(SpreadsheetCell.displayString(forExcelSerial: 59, includesTime: false),
                       "28/02/1900")
        XCTAssertEqual(SpreadsheetCell.displayString(forExcelSerial: 61, includesTime: false),
                       "01/03/1900")
    }

    // MARK: - End to end, through the ordinary pipeline

    func testAnXLSXImportsThroughTheSamePipelineAsACSV() throws {
        let result = try plan(SpreadsheetFixtures.xlsx, filename: "extrato.xlsx")

        XCTAssertEqual(result.rows.count, 3, "the header is consumed by inference")
        XCTAssertTrue(result.failedRows.isEmpty)
        XCTAssertEqual(result.schema.dateFormat.pattern, "dd/MM/yyyy")
        XCTAssertEqual(result.rows.compactMap { $0.parsed?.title.title },
                       ["Mercado Extra", "Padaria", "Salario"])
    }

    func testAnXLSImportsThroughTheSamePipelineAsACSV() throws {
        let result = try plan(SpreadsheetFixtures.xls, filename: "extrato.xls")

        XCTAssertEqual(result.rows.count, 3)
        XCTAssertTrue(result.failedRows.isEmpty)
        XCTAssertEqual(result.rows.compactMap { $0.parsed?.title.title },
                       ["Mercado Extra", "Padaria", "Salario"])
        XCTAssertEqual(result.rows.compactMap { $0.parsed?.signedCents }, [-5_050, -1_250, 500_000])
    }

    /// The whole point of the abstraction: a workbook reaches the review diff, so undo, dedupe and
    /// sync all apply to it exactly as they do to a CSV.
    func testAWorkbookProducesAReviewablePlan() throws {
        let result = try plan(SpreadsheetFixtures.xls, filename: "extrato.xls")
        let resolved = result.resolve(with: ImportOverrides())
        XCTAssertEqual(resolved.rows.count + resolved.skippedCount + resolved.failedCount,
                       result.rows.count)
    }

    // MARK: - Refusals

    func testAnEncryptedWorkbookIsRefusedRatherThanGuessedAt() {
        // A FILEPASS record anywhere in the stream means the contents are encrypted.
        var stream = Data()
        stream.append(contentsOf: [0x09, 0x08, 0x10, 0x00])
        stream.append(Data(repeating: 0, count: 16))
        stream.append(contentsOf: [0x2F, 0x00, 0x04, 0x00])   // FILEPASS
        stream.append(Data(repeating: 0, count: 4))

        XCTAssertThrowsError(try BIFFWorkbook.rows(from: stream)) { error in
            XCTAssertEqual(error as? SpreadsheetError, .unsupportedFormat("encrypted"))
        }
    }

    func testAPDFIsNamedRatherThanParsed() {
        let pdf = Data("%PDF-1.7\nstream nonsense".utf8)
        XCTAssertThrowsError(try plan(pdf, filename: "extrato.pdf")) { error in
            guard case ImportError.wrongFileFormat(let detected) = error else {
                return XCTFail("expected .wrongFileFormat, got \(error)")
            }
            XCTAssertTrue(detected.uppercased().contains("PDF"))
        }
    }

    // MARK: - The SST continuation bug

    /// The failure that made a real 1819-row statement decode as replacement characters.
    ///
    /// BIFF8 splits the shared-string table across CONTINUE records, and a string caught by a
    /// boundary resumes in the next segment BEHIND a fresh option byte declaring the encoding of the
    /// remainder. Splicing the segments together first swallows that byte as though it were text, and
    /// every string after the first boundary comes out as garbage.
    func testAStringSplitAcrossAContinueBoundaryIsReassembled() {
        var first = Data()
        first.append(contentsOf: [3, 0, 0, 0])      // total count
        first.append(contentsOf: [3, 0, 0, 0])      // unique count

        // "MERCADO", 8-bit, entirely inside this segment.
        first.append(contentsOf: [7, 0])
        first.append(0x00)
        first.append(contentsOf: Array("MERCADO".utf8))

        // "PADARIA CENTRAL" declared as 15 characters, but the segment ends after five of them.
        first.append(contentsOf: [15, 0])
        first.append(0x00)
        first.append(contentsOf: Array("PADAR".utf8))

        var second = Data()
        second.append(0x00)                          // continuation option byte: still 8-bit
        second.append(contentsOf: Array("IA CENTRAL".utf8))

        // A 16-bit string following it, to prove the cursor stays aligned afterwards.
        second.append(contentsOf: [6, 0])
        second.append(0x01)                          // wide
        second.append(contentsOf: Array("AÇÚCAR".data(using: .utf16LittleEndian)!))

        let strings = BIFFWorkbook.parseSST(segments: [first, second])
        XCTAssertEqual(strings, ["MERCADO", "PADARIA CENTRAL", "AÇÚCAR"])
    }

    /// The same boundary, but the continuation flips the remainder to 16-bit.
    func testAContinuationMayChangeTheEncodingMidString() {
        var first = Data()
        first.append(contentsOf: [1, 0, 0, 0])
        first.append(contentsOf: [1, 0, 0, 0])
        first.append(contentsOf: [6, 0])
        first.append(0x00)                           // starts 8-bit
        first.append(contentsOf: Array("PAD".utf8))  // three of six characters

        var second = Data()
        second.append(0x01)                          // remainder is 16-bit
        second.append(contentsOf: Array("ARIA".prefix(3).data(using: .utf16LittleEndian)!))

        XCTAssertEqual(BIFFWorkbook.parseSST(segments: [first, second]), ["PADARI"])
    }

    /// A table entirely inside one segment must still read correctly.
    func testASingleSegmentTableStillParses() {
        var only = Data()
        only.append(contentsOf: [2, 0, 0, 0])
        only.append(contentsOf: [2, 0, 0, 0])
        only.append(contentsOf: [5, 0]); only.append(0x00)
        only.append(contentsOf: Array("SALDO".utf8))
        only.append(contentsOf: [6, 0]); only.append(0x01)
        only.append(contentsOf: Array("AÇÚCAR".data(using: .utf16LittleEndian)!))

        XCTAssertEqual(BIFFWorkbook.parseSST(segments: [only]), ["SALDO", "AÇÚCAR"])
    }
}
