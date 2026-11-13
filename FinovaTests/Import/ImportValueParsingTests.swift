//
//  ImportValueParsingTests.swift
//  FinovaTests
//
//  Money and calendar. The two places a quiet bug costs the user real accuracy.
//

import XCTest

@testable import Finova

final class ImportValueParsingTests: XCTestCase {

    // MARK: - Amounts

    private func cents(_ raw: String, _ format: NumberFormatSpec = .ptBR) throws -> Int {
        try AmountParser.parse(raw, format: format).cents
    }

    func testBrazilianAndAmericanGrouping() throws {
        XCTAssertEqual(try cents("1.234,56"), 123_456)
        XCTAssertEqual(try cents("1,234.56", .enUS), 123_456)
        XCTAssertEqual(try cents("1234,56"), 123_456)
        XCTAssertEqual(try cents("1234.56", .enUS), 123_456)
        XCTAssertEqual(try cents("1234", .enUS), 123_400)
    }

    func testNegativesInEveryDialectBanksUse() throws {
        XCTAssertEqual(try cents("-1.234,56"), -123_456)
        XCTAssertEqual(try cents("1.234,56-"), -123_456)   // trailing minus
        XCTAssertEqual(try cents("(1.234,56)"), -123_456)  // accounting parentheses
        XCTAssertEqual(try cents("1.234,56 D"), -123_456)  // débito marker
        XCTAssertEqual(try cents("1.234,56 C"), 123_456)   // crédito marker
        XCTAssertEqual(try cents("\u{2212}1.234,56"), -123_456)  // real minus sign
    }

    func testCurrencyNoiseIsStripped() throws {
        XCTAssertEqual(try cents("R$ 1.234,56"), 123_456)
        XCTAssertEqual(try cents("+1.234,56"), 123_456)
    }

    /// The one that bites: Brazilian exports use a non-breaking space as the thousands separator,
    /// and it is invisible in every editor you would inspect the file with.
    func testNonBreakingSpaceAsAThousandsSeparator() throws {
        XCTAssertEqual(try cents("R$\u{00A0}1\u{00A0}234,56"), 123_456)
    }

    func testThreeDecimalPlacesRoundAndAreFlagged() throws {
        let parsed = try AmountParser.parse("1.234,567", format: .ptBR)
        XCTAssertEqual(parsed.cents, 123_457)
        XCTAssertTrue(parsed.wasRounded, "money is never silently rounded")
    }

    func testTwoDecimalPlacesAreNotFlagged() throws {
        XCTAssertFalse(try AmountParser.parse("1.234,56", format: .ptBR).wasRounded)
    }

    func testScientificNotationFromExcelMangledExports() throws {
        XCTAssertEqual(try cents("1.2345E+3", .enUS), 123_450)
    }

    func testNonNumericInputFails() {
        XCTAssertThrowsError(try cents("Mercado Central"))
        XCTAssertThrowsError(try cents(""))
        XCTAssertThrowsError(try cents("   "))
    }

    func testAbsurdAmountsAreRejected() {
        XCTAssertThrowsError(try cents("999999999999,00")) { error in
            XCTAssertEqual(error as? AmountParser.Failure, .outOfRange)
        }
    }

    func testALetterAloneIsNotReadAsADebitMarker() {
        // A mis-mapped text column must fail, not be silently swallowed.
        XCTAssertThrowsError(try cents("D"))
        XCTAssertThrowsError(try cents("Mercado D"))
    }

    // MARK: - Number format detection

    func testBothSeparatorsPresentIsProof() {
        let ptBR = AmountParser.detectFormat(in: ["1.234,56", "12,00"])
        XCTAssertEqual(ptBR.spec, .ptBR)
        XCTAssertTrue(ptBR.isProven)

        let enUS = AmountParser.detectFormat(in: ["1,234.56", "12.00"])
        XCTAssertEqual(enUS.spec, .enUS)
        XCTAssertTrue(enUS.isProven)
    }

    func testTwoTrailingDigitsMeanDecimalWhenNoValueCarriesBoth() {
        let detected = AmountParser.detectFormat(in: ["12,50", "8,00", "134,20"])
        XCTAssertEqual(detected.spec.decimalSeparator, ",")
    }

    /// `1.234` with no tiebreaker anywhere is unresolvable in principle. The caller must warn.
    func testUnresolvableColumnIsReportedAsUnproven() {
        XCTAssertFalse(AmountParser.detectFormat(in: ["1.234", "5.678"]).isProven)
    }

    /// One convention per column, never per cell.
    func testAColumnResolvesUnderASingleConvention() throws {
        let values = ["1.234", "1.234,56", "999"]
        let format = AmountParser.detectFormat(in: values).spec
        XCTAssertEqual(try AmountParser.parse("1.234", format: format).cents, 123_400)
        XCTAssertEqual(try AmountParser.parse("1.234,56", format: format).cents, 123_456)
    }

    // MARK: - Dates

    private func day(_ date: Date) -> (y: Int, m: Int, d: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    func testCommonFormats() throws {
        let dmy = try XCTUnwrap(DateFieldParser.parse("31/01/2026", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        XCTAssertEqual(day(dmy).d, 31)
        XCTAssertEqual(day(dmy).m, 1)

        let iso = try XCTUnwrap(DateFieldParser.parse("2026-01-31", spec: DateFormatSpec(pattern: "yyyy-MM-dd")))
        XCTAssertEqual(day(iso).d, 31)

        let dotted = try XCTUnwrap(DateFieldParser.parse("31.01.2026", spec: DateFormatSpec(pattern: "dd.MM.yyyy")))
        XCTAssertEqual(day(dotted).d, 31)
    }

    func testDatesAreAnchoredAtLocalNoon() throws {
        let date = try XCTUnwrap(DateFieldParser.parse("15/06/2026", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        XCTAssertEqual(calendar.component(.hour, from: date), 12)
    }

    /// `America/Sao_Paulo` SKIPPED midnight on 2018-11-04 (DST start). A row on that date cannot be
    /// represented at 00:00 and would be shifted into an adjacent day; noon cannot.
    func testADSTStartDayStillLandsOnItsOwnCalendarDay() throws {
        let saoPaulo = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        let original = TimeZone.current
        // The parser reads TimeZone.current at call time via its formatter, so this only proves the
        // noon anchoring when the process zone matches. Skip rather than assert falsely elsewhere.
        try XCTSkipUnless(original.identifier == saoPaulo.identifier
            || ProcessInfo.processInfo.environment["TZ"] == "America/Sao_Paulo",
            "run with TZ=America/Sao_Paulo to exercise the DST-skip case")

        let date = try XCTUnwrap(DateFieldParser.parse("04/11/2018", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        XCTAssertEqual(day(date).d, 4)
        XCTAssertEqual(day(date).m, 11)
    }

    func testLeapDays() {
        XCTAssertNotNil(DateFieldParser.parse("29/02/2024", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        // Non-lenient parsing: 29 Feb 2025 does not exist and must fail rather than roll to 1 March.
        XCTAssertNil(DateFieldParser.parse("29/02/2025", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
    }

    func testImplausibleYearsAreRejected() {
        XCTAssertNil(DateFieldParser.parse("01/01/1900", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        XCTAssertNil(DateFieldParser.parse("01/01/2099", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
    }

    // MARK: - Date format detection

    func testADayAbove12ProvesDayFirst() {
        let detection = DateFieldParser.detectFormat(in: ["31/01/2026", "02/02/2026"])
        XCTAssertEqual(detection, .proven(DateFormatSpec(pattern: "dd/MM/yyyy")))
    }

    func testASecondComponentAbove12ProvesMonthFirst() {
        let detection = DateFieldParser.detectFormat(in: ["01/31/2026", "02/02/2026"])
        XCTAssertEqual(detection, .proven(DateFormatSpec(pattern: "MM/dd/yyyy")))
    }

    func testAFileThatContradictsItselfIsRejected() {
        XCTAssertEqual(DateFieldParser.detectFormat(in: ["31/01/2026", "01/31/2026"]), .inconsistent)
    }

    /// Every component ≤ 12 with too few rows to infer order. Guessing here silently shifts every
    /// row's month, so it must ask.
    func testAllComponentsUnder12WithFewRowsIsAmbiguous() {
        let detection = DateFieldParser.detectFormat(in: ["01/02/2026", "03/04/2026"])
        guard case .ambiguous = detection else {
            return XCTFail("expected .ambiguous, got \(detection)")
        }
    }

    func testMonotonicityBreaksTheTieWhenThereAreEnoughRows() {
        // Under dd/MM these are consecutive days in January; under MM/dd they scatter across months.
        let values = ["01/01/2026", "02/01/2026", "03/01/2026", "04/01/2026",
                      "05/01/2026", "06/01/2026", "07/01/2026", "08/01/2026"]
        guard case .likely(let spec, _) = DateFieldParser.detectFormat(in: values) else {
            return XCTFail("expected .likely with enough rows to infer order")
        }
        XCTAssertEqual(spec.pattern, "dd/MM/yyyy")
    }

    func testISODatesAreProvenOutright() {
        let detection = DateFieldParser.detectFormat(in: ["2026-01-05", "2026-02-11"])
        XCTAssertEqual(detection, .proven(DateFormatSpec(pattern: "yyyy-MM-dd")))
    }

    func testDateHitRateDistinguishesDateColumnsFromOthers() {
        XCTAssertEqual(DateFieldParser.dateHitRate(in: ["01/01/2026", "02/01/2026"]), 1.0)
        XCTAssertEqual(DateFieldParser.dateHitRate(in: ["Mercado", "Padaria"]), 0.0)
    }

    // MARK: - Budget month

    /// A 31 January transaction belongs to January's budget, not February's.
    func testMonthAnchorFollowsTheTransactionsOwnMonth() throws {
        let date = try XCTUnwrap(DateFieldParser.parse("31/01/2026", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let anchor = Date(timeIntervalSince1970: TimeInterval(date.monthAnchor))
        XCTAssertEqual(calendar.component(.month, from: anchor), 1)
        XCTAssertEqual(calendar.component(.day, from: anchor), 1)
        XCTAssertEqual(calendar.component(.year, from: anchor), 2026)
    }
}
