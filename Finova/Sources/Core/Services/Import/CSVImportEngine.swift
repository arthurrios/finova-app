//
//  CSVImportEngine.swift
//  Finova
//
//  The whole read path, as one synchronous function.
//
//  Deliberately synchronous and free of side effects: bytes in, `ImportPlan` out. No database, no
//  UI, no queue of its own. The CALLER decides what thread to run it on, which is what keeps every
//  interesting decision in this feature testable with a string literal and an array.
//

import CryptoKit
import Foundation

enum CSVImportEngine {

    /// Bigger than any real bank export by two orders of magnitude. Past this, something else is
    /// going on and saying so beats spending a minute proving it.
    static let maxFileBytes = 10 * 1_048_576

    struct Input {
        let filename: String
        let data: Data
        /// Fingerprints already imported by this user, for the "already imported" tier.
        let alreadyImported: Set<String>
        /// The current ledger. Injected, not fetched — see `ImportPlanner`.
        let existing: [Transaction]
    }

    /// Reads a file and produces the reviewable plan, or the reason it could not.
    static func makePlan(_ input: Input) throws -> ImportPlan {
        guard !input.data.isEmpty else { throw ImportError.emptyFile }
        guard input.data.count <= maxFileBytes else {
            throw ImportError.fileTooLarge(bytes: input.data.count, limit: maxFileBytes)
        }

        // A workbook is unpacked into the same rows of strings the CSV path produces, so everything
        // downstream — inference, dedupe, the review diff, apply, rollback — is reused untouched.
        let rows: [CSVTokenizer.Row]
        let dialect: CSVDialect
        let decoded: EncodingSniffer.Result
        let cameFromWorkbook = SpreadsheetImporter.canRead(input.data)

        if cameFromWorkbook {
            do {
                rows = try SpreadsheetImporter.read(input.data)
            } catch let error as SpreadsheetError {
                throw Self.importError(for: error, format: FileFormatSniffer.detect(input.data))
            }
            guard !rows.isEmpty else { throw ImportError.emptyFile }
            // Nominal values: a workbook has no encoding or delimiter of its own, and the diagnostics
            // and `ImportSource` both want something truthful to report.
            dialect = CSVDialect(delimiter: "\t")
            decoded = EncodingSniffer.Result(text: "", encoding: .utf8, wasLossy: false)
        } else {
            // Checked before decoding: a PDF run through a text decoder yields line noise, and every
            // error after that point describes a symptom rather than the cause.
            let format = FileFormatSniffer.detect(input.data)
            if let name = format.displayName {
                throw ImportError.wrongFileFormat(detected: name)
            }

            guard let text = EncodingSniffer.decode(input.data) else { throw ImportError.notTextual }
            guard text.text.contains(where: { !$0.isWhitespace }) else { throw ImportError.emptyFile }
            decoded = text

            let detection = DelimiterSniffer.sniff(text.text)
            let body = detection.skipLeadingLines > 0
                ? text.text.split(separator: "\n", omittingEmptySubsequences: false)
                    .dropFirst(detection.skipLeadingLines).joined(separator: "\n")
                : text.text

            var workingDialect = detection.dialect
            var tokenized = try CSVTokenizer.tokenize(body, dialect: workingDialect)
            guard !tokenized.isEmpty else { throw ImportError.emptyFile }

            // The sniffer scores delimiters and picks a winner, but a wrong pick collapses the file
            // into one column and everything downstream fails. Cheap insurance: if the winner
            // produced no table, try the others outright before giving up on the file.
            if CSVTokenizer.modalFieldCount(tokenized).count < 2 {
                for candidate in CSVDialect.candidateDelimiters where candidate != workingDialect.delimiter {
                    let retryDialect = CSVDialect(delimiter: candidate)
                    guard let retryRows = try? CSVTokenizer.tokenize(body, dialect: retryDialect),
                          CSVTokenizer.modalFieldCount(retryRows).count >= 2 else { continue }
                    workingDialect = retryDialect
                    tokenized = retryRows
                    break
                }
            }
            dialect = workingDialect
            rows = tokenized
        }

        // `infer` only returns nil when the file has no tabular shape at all — fewer than two columns,
        // or no data rows. A file that IS a table but whose columns we could not identify comes back
        // with an unusable schema and zero confidence, and is deliberately NOT an error: it is a file
        // the user maps by hand. Throwing here dead-ended those imports in an alert with nothing to
        // act on.
        guard let inferred = SchemaInferencer.infer(rows: rows) else {
            throw ImportError.notTabular(
                details: diagnostics(decoded: decoded, dialect: dialect, rows: rows))
        }

        var schema = inferred.schema
        if cameFromWorkbook {
            // The workbook readers render numbers themselves, with a POSIX decimal point and no
            // grouping — so the format is KNOWN and must not be re-inferred. It cannot be inferred
            // reliably either: a value like `-50.5` has a one-digit fraction, matches neither the
            // two-digit decimal nor the three-digit grouping pattern, and the fallback to the device
            // locale then reads that dot as a THOUSANDS separator under pt-BR. Fifty and a half
            // becomes five hundred and five.
            schema.numberFormat = .enUS
        }

        let source = ImportSource(
            filename: input.filename,
            byteCount: input.data.count,
            sha256: sha256(of: input.data),
            encoding: decoded.text.isEmpty ? "workbook" : String(describing: decoded.encoding),
            dialect: dialect,
            wasLossy: decoded.wasLossy)

        let planner = ImportPlanner(
            existing: input.existing, alreadyImported: input.alreadyImported)

        return planner.plan(
            rows: inferred.dataRows, schema: schema,
            confidence: inferred.confidence, source: source)
    }

    /// Re-plans the same file under a schema the user corrected on the mapping screen.
    ///
    /// A full recompute rather than a patch: changing the date format can change which rows parse at
    /// all, which are duplicates, and which fail. Overrides survive because they are keyed by a
    /// fingerprint over the raw bytes, not by position.
    static func replan(_ input: Input, schema: ResolvedSchema) throws -> ImportPlan {
        let plan = try makePlan(input)
        guard let decoded = EncodingSniffer.decode(input.data) else { throw ImportError.notTextual }

        let detection = DelimiterSniffer.sniff(decoded.text)
        let rows = try CSVTokenizer.tokenize(decoded.text, dialect: detection.dialect)
        let (modalCount, _) = CSVTokenizer.modalFieldCount(rows)
        var shaped = rows.filter { $0.cells.count == modalCount }
        if schema.hasHeaderRow, !shaped.isEmpty { shaped.removeFirst() }

        // The user resolved whatever the inferencer was unsure about, so those aspects are now
        // settled by definition — otherwise every row would stay parked in `.needsDecision`.
        var confidence = plan.confidence
        confidence.dateFormat = .proof("confirmed by the user")
        confidence.signConvention = .proof("confirmed by the user")
        confidence.numberFormat = .proof("confirmed by the user")
        confidence.columnRoles = .proof("confirmed by the user")

        let planner = ImportPlanner(
            existing: input.existing, alreadyImported: input.alreadyImported)
        return planner.plan(
            rows: shaped, schema: schema, confidence: confidence, source: plan.source)
    }

    /// Maps a workbook failure onto the user-facing error, keeping the cause visible.
    private static func importError(
        for error: SpreadsheetError, format: DetectedFileFormat
    ) -> ImportError {
        switch error {
        case .unsupportedFormat(let reason) where reason == "encrypted":
            return .wrongFileFormat(detected: "import.format.encrypted".localized)
        case .notAWorkbook, .noSheets, .unsupportedFormat:
            return .wrongFileFormat(detected: format.displayName ?? "import.format.binary".localized)
        case .emptyWorkbook:
            return .emptyFile
        case .corrupt(let detail):
            // The user's answer is the same either way — "this is an .xls we could not read, export
            // a CSV instead" — so name the format rather than surface an internal parse detail.
            logWarning("[Import] Workbook could not be read: \(detail)")
            if let name = format.displayName { return .wrongFileFormat(detected: name) }
            return .notTabular(details: detail)
        }
    }

    /// What the engine observed, for a file it could not resolve into a table.
    ///
    /// Deliberately concrete and user-visible. "No date and amount columns" sends someone hunting for
    /// a problem in their columns when the actual answer is usually "this is a spreadsheet, not a
    /// CSV" or "the separator is something we do not try" — and neither is guessable from a generic
    /// message. Truncated hard so a binary file pasted into an alert stays readable.
    private static func diagnostics(
        decoded: EncodingSniffer.Result, dialect: CSVDialect, rows: [CSVTokenizer.Row]
    ) -> String {
        let firstLine = decoded.text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .prefix(80) ?? ""
        // Control characters in the preview are the tell-tale of a binary file renamed to .csv.
        let readable = String(firstLine).map { $0.isLetter || $0.isNumber || $0.isPunctuation
            || $0.isWhitespace || $0.isSymbol ? $0 : "·" }

        return """
            \(describe(decoded.encoding)) · \("\(dialect.displayName)") · \
            \(CSVTokenizer.modalFieldCount(rows).count) col · \(rows.count) rows
            “\(String(readable))”
            """
    }

    private static func describe(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .windowsCP1252: return "Windows-1252"
        case .isoLatin1: return "ISO-8859-1"
        case .utf16LittleEndian, .utf16BigEndian, .utf16: return "UTF-16"
        default: return "\(encoding.rawValue)"
        }
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
