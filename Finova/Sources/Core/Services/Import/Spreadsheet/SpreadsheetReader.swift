//
//  SpreadsheetReader.swift
//  Finova
//
//  Workbooks in, the same rows of strings the CSV path produces out.
//
//  This is the whole point of the abstraction: `CSVTokenizer.Row` is already the engine's currency —
//  schema inference, categorization, dedupe, the review diff, apply and rollback all consume it and
//  none of them care where it came from. A spreadsheet reader therefore has exactly one job, produce
//  those rows, and everything downstream is reused unchanged rather than reimplemented per format.
//
//  Cells are handed over as the STRINGS a person would see in the spreadsheet, not as typed values.
//  That is deliberate: the CSV path already knows how to read `1.234,56` under an inferred locale and
//  how to resolve dd/MM against MM/dd, and having two different routes to a Date or an amount is how
//  the two drift apart. One parser, one set of edge cases, one set of tests.
//

import Foundation

protocol SpreadsheetReader {
    /// Whether this reader recognises the file, by content rather than by extension.
    static func canRead(_ data: Data) -> Bool
    /// The used range of the first sheet holding data, as rows of display strings.
    static func read(_ data: Data) throws -> [CSVTokenizer.Row]
}

enum SpreadsheetError: Error, Equatable {
    case notAWorkbook
    case noSheets
    /// The workbook parsed but every sheet was empty.
    case emptyWorkbook
    case corrupt(String)
    /// A format we can detect but deliberately do not implement — see `SpreadsheetImporter`.
    case unsupportedFormat(String)
}

enum SpreadsheetImporter {

    /// Readers in priority order. Each identifies itself from the bytes.
    private static let readers: [SpreadsheetReader.Type] = [
        XLSXReader.self,
        XLSReader.self,
    ]

    static func canRead(_ data: Data) -> Bool {
        readers.contains { $0.canRead(data) }
    }

    /// Converts a workbook into rows, or explains why it cannot.
    static func read(_ data: Data) throws -> [CSVTokenizer.Row] {
        guard let reader = readers.first(where: { $0.canRead(data) }) else {
            throw SpreadsheetError.notAWorkbook
        }
        return try reader.read(data)
    }
}

// MARK: - Shared cell helpers

enum SpreadsheetCell {

    /// Excel's epoch for date-formatted numbers.
    ///
    /// Serial 1 is 1900-01-01, but Excel also believes 1900 was a leap year — a bug preserved from
    /// Lotus 1-2-3 — so serials at or above 60 are one day ahead of reality. Subtracting a day above
    /// that threshold is the standard correction, and getting it wrong shifts every date in the file
    /// by one.
    static func date(fromExcelSerial serial: Double) -> Date? {
        guard serial > 0, serial < 2_958_466 else { return nil }  // year 9999 ceiling
        let corrected = serial >= 60 ? serial - 1 : serial

        var components = DateComponents()
        components.year = 1899
        components.month = 12
        components.day = 31
        components.hour = 12   // noon, for the same DST reason as `DateFieldParser`
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        guard let epoch = calendar.date(from: components) else { return nil }

        return calendar.date(byAdding: .day, value: Int(corrected.rounded(.down)), to: epoch)
    }

    /// Renders a date-formatted cell the way the CSV path expects to read it back.
    ///
    /// `dd/MM/yyyy` unambiguously, rather than the workbook's display format: the engine's date
    /// detection is then handed a shape it can prove rather than one it has to guess at.
    static func displayString(forExcelSerial serial: Double, includesTime: Bool) -> String? {
        guard let date = date(fromExcelSerial: serial) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "dd/MM/yyyy"

        guard includesTime else { return formatter.string(from: date) }

        let fractionalDay = serial - serial.rounded(.down)
        let totalMinutes = Int((fractionalDay * 24 * 60).rounded())
        return String(format: "%@ %02d:%02d",
                      formatter.string(from: date), totalMinutes / 60, totalMinutes % 60)
    }

    /// A number as the CSV path prefers to receive it: POSIX decimal point, no grouping.
    ///
    /// The importer's own number detection then reads it as en-US and gets it right, instead of
    /// meeting a locale-formatted string it has to disambiguate.
    static func displayString(forNumber value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%.10g", value)
    }
}
