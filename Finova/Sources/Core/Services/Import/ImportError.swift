//
//  ImportError.swift
//  Finova
//

import Foundation

/// A failure that stops the whole file. Per-row failures are `RowError` and live on the plan, so a
/// bad line never costs the user the other nine hundred.
enum ImportError: Error, Equatable {
    case cannotReadFile
    case fileTooLarge(bytes: Int, limit: Int)
    case tooManyRows(count: Int, limit: Int)
    case emptyFile
    /// The bytes did not decode as text under any candidate encoding — most often a PDF or XLSX
    /// picked by mistake, since banks mislabel their exports and the picker has to accept
    /// `public.data` to see the real CSVs at all.
    case notTextual
    case unterminatedQuote(line: Int)
    /// No column looked like a date, or none looked like an amount. Without both there is nothing to
    /// import.
    case noUsableColumns
    /// The file is not a CSV at all — a spreadsheet, PDF or other binary picked by mistake.
    ///
    /// Detected from magic bytes BEFORE decoding, so the message can name the real format instead of
    /// describing the line noise it would otherwise produce.
    case wrongFileFormat(detected: String)
    /// The file decoded as text but never resolved into columns under ANY delimiter.
    ///
    /// Carries what the engine actually observed, because "no date and amount columns" is a lie in
    /// this case and leaves the user with nothing to act on: the real problem is upstream — a
    /// delimiter we do not recognise, a fixed-width report, or a spreadsheet saved under a .csv name.
    case notTabular(details: String)
    /// Dates in the file parse both as dd/MM and as MM/dd depending on the row, so the file
    /// contradicts itself and no single reading is right.
    case inconsistentDateFormat
    case cancelled
}

extension ImportError {
    /// Localized, user-facing. Deliberately concrete about numbers — "too large" without the figure
    /// leaves the user with nothing to act on.
    var userMessage: String {
        switch self {
        case .cannotReadFile:
            return "import.error.cannotRead".localized
        case .fileTooLarge(let bytes, let limit):
            return String(format: "import.error.tooLarge".localized,
                          bytes / 1_048_576, limit / 1_048_576)
        case .tooManyRows(let count, let limit):
            return String(format: "import.error.tooManyRows".localized, count, limit)
        case .emptyFile:
            return "import.error.empty".localized
        case .notTextual:
            return "import.error.notTextual".localized
        case .unterminatedQuote(let line):
            return String(format: "import.error.unterminatedQuote".localized, line)
        case .noUsableColumns:
            return "import.error.noUsableColumns".localized
        case .wrongFileFormat(let detected):
            return String(format: "import.error.wrongFormat".localized, detected)
        case .notTabular(let details):
            return String(format: "import.error.notTabular".localized, details)
        case .inconsistentDateFormat:
            return "import.error.inconsistentDates".localized
        case .cancelled:
            return "import.error.cancelled".localized
        }
    }
}
