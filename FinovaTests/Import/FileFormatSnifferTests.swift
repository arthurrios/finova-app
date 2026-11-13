//
//  FileFormatSnifferTests.swift
//  FinovaTests
//
//  A spreadsheet fed to a CSV parser produces line noise, and every error after that describes a
//  symptom instead of the cause. These pin the cause being named.
//

import XCTest

@testable import Finova

final class FileFormatSnifferTests: XCTestCase {

    private func plan(_ data: Data) throws -> ImportPlan {
        try CSVImportEngine.makePlan(CSVImportEngine.Input(
            filename: "extrato.csv", data: data, alreadyImported: [], existing: []))
    }

    // MARK: - Signatures

    func testLegacyExcelIsRecognised() {
        // OLE2 compound document header — what most Brazilian banks hand out as "Excel".
        var data = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        data.append(Data(repeating: 0x00, count: 512))
        XCTAssertEqual(FileFormatSniffer.detect(data), .ole2Document)
    }

    func testModernSpreadsheetIsRecognised() {
        var data = Data(Array("PK\u{03}\u{04}".utf8))
        data.append(Data(repeating: 0x00, count: 64))
        XCTAssertEqual(FileFormatSniffer.detect(data), .zipContainer)
    }

    func testPDFIsRecognised() {
        XCTAssertEqual(FileFormatSniffer.detect(Data("%PDF-1.7\n%âãÏÓ".utf8)), .pdf)
    }

    func testAGenuineCSVIsText() {
        let csv = "Data;Descrição;Valor\n15/07/2026;MERCADO;-50,00\n"
        XCTAssertEqual(FileFormatSniffer.detect(Data(csv.utf8)), .text)
    }

    /// Accented pt-BR content is not binary — the high bytes are legitimate UTF-8.
    func testAccentedCSVIsStillText() {
        let csv = "Data;Descrição;Valor\n15/07/2026;AÇOUGUE SÃO JOÃO;-50,00\n"
        XCTAssertEqual(FileFormatSniffer.detect(Data(csv.utf8)), .text)
    }

    func testUnsignedBinaryIsCaughtByControlDensity() {
        let data = Data((0..<2048).map { _ in UInt8.random(in: 0...0x08) })
        XCTAssertEqual(FileFormatSniffer.detect(data), .otherBinary)
    }

    // MARK: - The message the user actually sees

    func testAnExcelFileNamesItselfRatherThanFailingAsAParseError() {
        var data = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        data.append(Data(repeating: 0x20, count: 4096))

        XCTAssertThrowsError(try plan(data)) { error in
            guard case ImportError.wrongFileFormat(let detected) = error else {
                return XCTFail("expected .wrongFileFormat, got \(error)")
            }
            XCTAssertTrue(detected.lowercased().contains("xls"),
                          "the message must name the real format, got \(detected)")
        }
    }

    func testAGenuineCSVStillImports() throws {
        let csv = """
        Data;Descrição;Valor;Saldo
        15/07/2026;MERCADO;-50,00;100,00
        16/07/2026;PADARIA;-12,50;87,50
        17/07/2026;SALARIO;500,00;587,50
        """
        let result = try plan(Data(csv.utf8))
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertTrue(result.failedRows.isEmpty)
    }
}
