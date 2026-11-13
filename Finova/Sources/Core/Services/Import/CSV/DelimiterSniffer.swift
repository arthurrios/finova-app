//
//  DelimiterSniffer.swift
//  Finova
//

import Foundation

enum DelimiterSniffer {

    struct Detection {
        let dialect: CSVDialect
        /// Rows the caller should skip — an Excel `sep=` directive is structure, not data.
        let skipLeadingLines: Int
        let confidence: Double
    }

    /// Picks the delimiter by tokenizing the whole file with each candidate and scoring the result.
    ///
    /// Scoring on TOKENIZED output rather than a naive `split(separator:)` is what makes this
    /// correct: a delimiter appearing inside a quoted description would otherwise inflate the field
    /// count for the wrong candidate. A file whose descriptions contain commas is exactly the file
    /// that gets this wrong, and in Brazil that is most of them.
    static func sniff(_ text: String) -> Detection {
        // Excel writes `sep=;` as a first line. That is a declaration, and it wins outright.
        if let declared = declaredSeparator(in: text) {
            return Detection(dialect: CSVDialect(delimiter: declared),
                             skipLeadingLines: 1, confidence: 1.0)
        }

        var best: (dialect: CSVDialect, score: Double, columns: Int)?

        for candidate in CSVDialect.candidateDelimiters {
            let dialect = CSVDialect(delimiter: candidate)
            // Sample rather than tokenize the whole file four times; the shape is established well
            // before row 200.
            guard let rows = try? CSVTokenizer.tokenize(
                sample(of: text), dialect: dialect, maxRows: 500), !rows.isEmpty else { continue }

            let (columns, matchFraction) = CSVTokenizer.modalFieldCount(rows)
            // A single column means the delimiter never appeared: not evidence, just absence.
            guard columns >= 2 else { continue }

            // Consistency matters more than width, but width breaks ties — hence log2 rather than a
            // linear factor, so 8 columns beats 4 without dwarfing a cleaner 4-column reading.
            let score = matchFraction * log2(Double(columns))
            if best == nil || score > best!.score {
                best = (dialect, score, columns)
            }
        }

        guard let best else {
            // No delimiter produced structure. Semicolon is the likeliest for this app's users, and
            // the mapping screen will ask anyway.
            return Detection(dialect: .semicolon, skipLeadingLines: 0, confidence: 0)
        }

        // The pt-BR tie-break, and it decides most Brazilian files. `;` and `,` score identically on
        // field count whenever a description contains a comma; the decimal separator in the numbers
        // resolves it, because a comma cannot be both.
        var chosen = best.dialect
        if chosen.delimiter == "," || chosen.delimiter == ";" {
            if commaDecimalCount(in: text) > dotDecimalCount(in: text) {
                chosen = .semicolon
            }
        }

        return Detection(dialect: chosen, skipLeadingLines: 0, confidence: min(1.0, best.score / 3.0))
    }

    // MARK: - Signals

    private static func declaredSeparator(in text: String) -> Character? {
        guard let firstLine = text.split(separator: "\n", maxSplits: 1,
                                         omittingEmptySubsequences: false).first else { return nil }
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // "sep=" plus exactly one delimiter character.
        guard trimmed.lowercased().hasPrefix("sep="), trimmed.count == 5 else { return nil }
        return trimmed.last
    }

    /// Occurrences of a comma used as a decimal point: `1234,56`.
    static func commaDecimalCount(in text: String) -> Int {
        matchCount(in: text, pattern: #"\d,\d{2}(?!\d)"#)
    }

    /// Occurrences of a dot used as a decimal point: `1234.56`.
    static func dotDecimalCount(in text: String) -> Int {
        matchCount(in: text, pattern: #"\d\.\d{2}(?!\d)"#)
    }

    private static func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let scoped = sample(of: text)
        return regex.numberOfMatches(in: scoped, range: NSRange(scoped.startIndex..., in: scoped))
    }

    /// The first ~200 lines. Enough to establish shape, bounded so a 10 MB file doesn't get scanned
    /// four times over.
    private static func sample(of text: String) -> String {
        var lines: [Substring] = []
        var count = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(line)
            count += 1
            if count >= 200 { break }
        }
        return lines.joined(separator: "\n")
    }
}
