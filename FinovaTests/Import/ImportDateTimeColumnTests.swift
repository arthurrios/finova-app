//
//  ImportDateTimeColumnTests.swift
//  FinovaTests
//
//  Diagnostics for a real Nubank/Itaú-shaped export that failed to import: a column carrying a date
//  AND a time together.
//

import XCTest

@testable import Finova

final class ImportDateTimeColumnTests: XCTestCase {

    private func plan(_ text: String) throws -> ImportPlan {
        try CSVImportEngine.makePlan(CSVImportEngine.Input(
            filename: "extrato.csv", data: Data(text.utf8),
            alreadyImported: [], existing: []))
    }

    // MARK: - Does a date+time value parse at all?

    func testDateTimeValueParsesUnderItsCandidate() {
        let spec = DateFormatSpec(pattern: "dd/MM/yyyy HH:mm")
        XCTAssertNotNil(DateFieldParser.parse("15/07/2026 14:30", spec: spec))
    }

    func testDateTimeColumnScoresAsADateColumn() {
        let values = ["15/07/2026 14:30", "16/07/2026 09:05", "17/07/2026 21:44"]
        XCTAssertGreaterThanOrEqual(
            DateFieldParser.dateHitRate(in: values), 0.9,
            "a date+time column must be recognised as a date column")
    }

    func testDateTimeColumnFormatIsDetected() {
        let values = ["15/07/2026 14:30", "16/07/2026 09:05", "17/07/2026 21:44"]
        let detection = DateFieldParser.detectFormat(in: values)
        guard case .proven = detection else {
            return XCTFail("expected .proven for an unambiguous date+time column, got \(detection)")
        }
    }

    // MARK: - Whole-file shapes

    /// A separate date column that happens to carry a time.
    func testFileWithADateTimeColumn() throws {
        let text = """
        Data;Lançamentos;Valor
        15/07/2026 14:30;MERCADO EXTRA;-50,00
        16/07/2026 09:05;PADARIA;-12,50
        17/07/2026 21:44;SALARIO;5.000,00
        """
        let result = try plan(text)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertTrue(result.failedRows.isEmpty)
    }

    /// A seconds-precision variant.
    func testFileWithSecondsPrecision() throws {
        let text = """
        Data;Lançamentos;Valor
        15/07/2026 14:30:11;MERCADO EXTRA;-50,00
        16/07/2026 09:05:02;PADARIA;-12,50
        17/07/2026 21:44:59;SALARIO;5.000,00
        """
        let result = try plan(text)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertTrue(result.failedRows.isEmpty)
    }

    /// The bank names the DESCRIPTION column "Lançamentos" and the date is plain.
    func testLancamentosAsDescriptionColumn() throws {
        let text = """
        Data;Lançamentos;Valor
        15/07/2026;MERCADO EXTRA;-50,00
        16/07/2026;PADARIA;-12,50
        17/07/2026;SALARIO;5.000,00
        """
        let result = try plan(text)
        XCTAssertEqual(result.schema.column(for: .description), 1,
                       "\"Lançamentos\" should be recognised as the description")
        XCTAssertTrue(result.failedRows.isEmpty)
    }

    // MARK: - Fused date + description column

    /// The shape several Brazilian banks emit under a "Lançamentos" heading: date, time and
    /// description all in one field.
    func testFusedDateTimeAndDescriptionColumnIsUnderstood() throws {
        let text = """
        Lançamentos;Valor
        15/07/2026 14:30 MERCADO EXTRA;-50,00
        16/07/2026 09:05 PADARIA;-12,50
        17/07/2026 21:44 SALARIO;5.000,00
        """
        let result = try plan(text)

        XCTAssertTrue(result.schema.dateColumnCarriesDescription)
        XCTAssertTrue(result.schema.isUsable)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertTrue(result.failedRows.isEmpty)

        let titles = result.rows.compactMap { $0.parsed?.title.title }
        XCTAssertEqual(titles, ["Mercado Extra", "Padaria", "Salario"],
                       "the remainder after the date becomes the title")
    }

    /// Same shape with no time component.
    func testFusedDateAndDescriptionWithoutATime() throws {
        let text = """
        Lançamentos;Valor
        15/07/2026 MERCADO EXTRA;-50,00
        16/07/2026 PADARIA;-12,50
        17/07/2026 SALARIO;5.000,00
        """
        let result = try plan(text)
        XCTAssertTrue(result.schema.dateColumnCarriesDescription)
        XCTAssertEqual(result.rows.compactMap { $0.parsed?.title.title },
                       ["Mercado Extra", "Padaria", "Salario"])
    }

    /// Amounts and directions must survive the fused path unchanged.
    func testFusedColumnStillReadsAmountsAndDirections() throws {
        let text = """
        Lançamentos;Valor
        15/07/2026 14:30 MERCADO EXTRA;-50,00
        16/07/2026 09:05 PADARIA;-12,50
        17/07/2026 21:44 SALARIO;5.000,00
        """
        let result = try plan(text)
        XCTAssertEqual(result.rows.compactMap { $0.parsed?.signedCents }, [-5_000, -1_250, 500_000])
    }

    /// A dedicated description column still wins over the remainder when the file has both.
    func testADedicatedDescriptionColumnBeatsTheRemainder() throws {
        let text = """
        Data;Descrição;Valor
        15/07/2026 14:30;MERCADO EXTRA;-50,00
        16/07/2026 09:05;PADARIA;-12,50
        17/07/2026 21:44;SALARIO;5.000,00
        """
        let result = try plan(text)
        XCTAssertFalse(result.schema.dateColumnCarriesDescription,
                       "a clean date column is not fused, even when it carries a time")
        XCTAssertEqual(result.rows.compactMap { $0.parsed?.title.title },
                       ["Mercado Extra", "Padaria", "Salario"])
    }

    // MARK: - Leading-date extraction in isolation

    func testLeadingDateExtractionTakesTheLongestValidPrefix() throws {
        let withTime = try XCTUnwrap(DateFieldParser.parseLeadingDate("15/07/2026 14:30 COMPRA MERCADO"))
        XCTAssertEqual(withTime.remainder, "COMPRA MERCADO",
                       "the time must be consumed with the date, not stranded on the title")

        let withoutTime = try XCTUnwrap(DateFieldParser.parseLeadingDate("15/07/2026 COMPRA MERCADO"))
        XCTAssertEqual(withoutTime.remainder, "COMPRA MERCADO")
    }

    func testLeadingDateExtractionRejectsTextWithNoDate() {
        XCTAssertNil(DateFieldParser.parseLeadingDate("COMPRA MERCADO EXTRA"))
        XCTAssertNil(DateFieldParser.parseLeadingDate(""))
    }

    func testLeadingDateHitRateSeparatesFusedColumnsFromProse() {
        XCTAssertGreaterThanOrEqual(
            DateFieldParser.leadingDateHitRate(in: [
                "15/07/2026 14:30 MERCADO", "16/07/2026 09:05 PADARIA",
            ]), 0.9)
        XCTAssertEqual(
            DateFieldParser.leadingDateHitRate(in: ["MERCADO EXTRA", "PADARIA CENTRAL"]), 0)
    }

    /// A row whose date cannot be extracted fails on its own, without costing the rest of the file.
    ///
    /// Sized like a real statement deliberately: identifying a fused column needs 90% of its values to
    /// start with a date, and in a three-row fixture a single summary line is 33% of the file — no
    /// threshold should accept that as "mostly dates". A `SALDO ANTERIOR` line among a month of real
    /// ones is the actual case.
    func testAFusedColumnRowWithoutADateFailsAlone() throws {
        var lines = ["Lançamentos;Valor", "SALDO ANTERIOR;-12,50"]
        for day in 10...20 {
            lines.append("\(day)/07/2026 09:05 MERCADO \(day);-\(day),00")
        }
        let result = try plan(lines.joined(separator: "\n"))

        XCTAssertTrue(result.schema.dateColumnCarriesDescription)
        XCTAssertEqual(result.rows.count, 12)
        XCTAssertEqual(result.failedRows.count, 1, "only the summary line fails")
        // Deliberately NOT asserting insertability: with just a fused column and an amount there is
        // no balance, no D/C flag and no split columns, so nothing proves which sign means money out
        // and every parsed row correctly parks for a decision. What matters here is that eleven rows
        // PARSED — the summary line costs itself and nothing else.
        XCTAssertEqual(result.rows.filter { $0.parsed != nil }.count, 11)
    }
}
