//
//  CSVTokenizer.swift
//  Finova
//
//  RFC 4180, plus the ways real banks break it.
//
//  Hand-rolled rather than delegated to `TabularData.DataFrame`, for three reasons that all bite on
//  exactly the files this feature exists to read:
//
//  1. `DataFrame` throws on a ragged row, and practically every bank export ends with a `Saldo` /
//     `Total` summary line carrying fewer fields than the header. One malformed line must cost the
//     user that line, not the other nine hundred.
//  2. Its errors carry no line number. The review screen has to be able to say "line 47: unterminated
//     quote", and "the file was bad" is not that.
//  3. Its type inference mangles `1.234,56`. Suppressing it with `types: [:]` reduces `DataFrame` to
//     a tokenizer — a worse one, with the two problems above.
//
//  Shipping both, with `DataFrame` as a fast path, would be worse than either: two tokenizers that
//  diverge precisely on the messy inputs that are the entire problem domain, and every bug
//  reproducing on only one of them.
//

import Foundation

enum CSVTokenizer {

    struct Row: Equatable {
        /// 1-based line in the source file. Survives into the diff so a failure can be pointed at.
        let line: Int
        let cells: [String]
    }

    /// A cap on rows, not on correctness: a file this size is a mistake, and reporting that is
    /// friendlier than spending a minute proving it.
    static let defaultMaxRows = 50_000

    /// Splits `text` into rows.
    ///
    /// Scans a flat `[Unicode.Scalar]` with an integer index rather than walking `String.Index`.
    /// `dropFirst` on a String is O(n), so index-walking a 5 MB file is quadratic and hangs.
    static func tokenize(
        _ text: String,
        dialect: CSVDialect,
        maxRows: Int = defaultMaxRows
    ) throws -> [Row] {
        let delimiter = dialect.delimiter.unicodeScalars.first!
        let quote = dialect.quote.unicodeScalars.first!
        let scalars = Array(text.unicodeScalars)

        var rows: [Row] = []
        var cells: [String] = []
        var field = String.UnicodeScalarView()
        var index = 0
        var line = 1
        var rowStartLine = 1
        var inQuotes = false
        /// Trailing whitespace held back rather than appended, so ` "value" ` unquotes cleanly but a
        /// genuine internal space in an unquoted field is preserved.
        var pendingSpaces = String.UnicodeScalarView()

        func endField() {
            // Held-back spaces are DISCARDED here, which is the whole point of holding them: they
            // were trailing padding. Interior spaces already made it into `field`, because the next
            // non-space character flushes them.
            pendingSpaces = String.UnicodeScalarView()
            cells.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRow() throws {
            endField()
            // A blank line is structure, not data. Banks pad with them freely.
            if !(cells.count == 1 && cells[0].isEmpty) {
                guard rows.count < maxRows else {
                    throw ImportError.tooManyRows(count: rows.count + 1, limit: maxRows)
                }
                rows.append(Row(line: rowStartLine, cells: cells))
            }
            cells = []
            rowStartLine = line
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if inQuotes {
                if scalar == quote {
                    // A doubled quote is one literal quote; a single one closes the field.
                    if index + 1 < scalars.count, scalars[index + 1] == quote {
                        field.append(quote)
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                // Newlines inside quotes are content, but still advance the line counter so a later
                // error points at the right place in the file.
                if scalar == "\n" { line += 1 }
                if scalar == "\r" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                    line += 1
                    field.append("\n")
                    index += 1
                    continue
                }
                field.append(scalar)
                index += 1
                continue
            }

            switch scalar {
            case quote where field.isEmpty:
                // Whitespace before an opening quote is not RFC-legal. Banks do it anyway, and the
                // held-back spaces are simply dropped.
                pendingSpaces = String.UnicodeScalarView()
                inQuotes = true
                index += 1

            case delimiter:
                endField()
                index += 1

            case "\r":
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                line += 1
                try endRow()
                rowStartLine = line
                index += 1

            case "\n":
                line += 1
                try endRow()
                rowStartLine = line
                index += 1

            // Held rather than appended: trailing padding disappears, interior spaces survive.
            // Split in two rather than `case " ", "\t" where …` because there the guard would bind
            // only to the tab — which is what we want, but not what the code appears to say.
            case " ":
                if !field.isEmpty { pendingSpaces.append(scalar) }
                index += 1

            case "\t" where delimiter != "\t":
                if !field.isEmpty { pendingSpaces.append(scalar) }
                index += 1

            default:
                field.append(contentsOf: pendingSpaces)
                pendingSpaces = String.UnicodeScalarView()
                field.append(scalar)
                index += 1
            }
        }

        if inQuotes {
            throw ImportError.unterminatedQuote(line: rowStartLine)
        }

        // A file with no trailing newline still has a final row.
        if !field.isEmpty || !pendingSpaces.isEmpty || !cells.isEmpty {
            try endRow()
        }

        return rows
    }

    /// The most common field count, and how many rows have it.
    ///
    /// Used both to score a candidate delimiter and to identify preamble and summary rows, which are
    /// exactly the rows that disagree with the mode.
    static func modalFieldCount(_ rows: [Row]) -> (count: Int, matchFraction: Double) {
        guard !rows.isEmpty else { return (0, 0) }
        var histogram: [Int: Int] = [:]
        for row in rows { histogram[row.cells.count, default: 0] += 1 }
        // Ties break toward the wider shape: a file where half the rows have 2 fields and half have
        // 5 is much more likely to be a 5-column file with preamble than the reverse.
        guard let best = histogram.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else {
            return (0, 0)
        }
        return (best.key, Double(best.value) / Double(rows.count))
    }
}
