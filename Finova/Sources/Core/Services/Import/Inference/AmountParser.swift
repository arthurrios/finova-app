//
//  AmountParser.swift
//  Finova
//
//  Text to cents. `Decimal` throughout, never `Double` — binary floating point cannot represent
//  1234.56, and a cent lost per row across a year of statements is a ledger that does not reconcile.
//

import Foundation

/// Which separator means what, decided PER COLUMN and never per cell. Two rows in one column must
/// not be read under different conventions: that is how `1.234` becomes 1234 on one line and 1.23 on
/// the next.
struct NumberFormatSpec: Hashable, Codable {
    let decimalSeparator: Character
    let groupingSeparator: Character?

    static let ptBR = NumberFormatSpec(decimalSeparator: ",", groupingSeparator: ".")
    static let enUS = NumberFormatSpec(decimalSeparator: ".", groupingSeparator: ",")

    init(decimalSeparator: Character, groupingSeparator: Character?) {
        self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator
    }

    private enum CodingKeys: String, CodingKey { case decimalSeparator, groupingSeparator }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decimalSeparator = (try c.decode(String.self, forKey: .decimalSeparator)).first ?? ","
        groupingSeparator = (try c.decodeIfPresent(String.self, forKey: .groupingSeparator))?.first
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(String(decimalSeparator), forKey: .decimalSeparator)
        try c.encodeIfPresent(groupingSeparator.map(String.init), forKey: .groupingSeparator)
    }
}

enum AmountParser {

    struct Parsed: Equatable {
        /// Signed. Direction is reapplied at normalization time, where `TransactionType` carries it.
        let cents: Int
        /// The input carried more than two decimal places. Surfaced as a row warning — money is never
        /// silently rounded.
        let wasRounded: Bool
    }

    enum Failure: Error, Equatable {
        case empty
        case unparseable(String)
        case outOfRange
    }

    /// Roughly a hundred million currency units. Anything past it is a parse gone wrong — a document
    /// number read as an amount, most often — not a transaction.
    static let maxCents = 100_000_000_00

    /// Characters banks put in amount fields that carry no numeric meaning.
    ///
    /// U+00A0 is the one that bites: Brazilian exports routinely use a non-breaking space as the
    /// thousands separator, and it is invisible in every editor you would inspect the file with.
    private static let noise: Set<Character> = [
        "R", "$", "€", "£", " ",
        "\u{00A0}",  // no-break space
        "\u{202F}",  // narrow no-break space
        "\u{2007}",  // figure space
        "\u{2212}",  // minus sign (not hyphen-minus)
    ]

    static func parse(_ raw: String, format: NumberFormatSpec) throws -> Parsed {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.empty }

        var isNegative = false

        // Accounting parentheses: (1.234,56) is a credit.
        if text.hasPrefix("("), text.hasSuffix(")") {
            isNegative = true
            text = String(text.dropFirst().dropLast())
        }

        // A trailing D/C indicator (débito / crédito), with or without a separating space. Only
        // stripped when a digit precedes it, so a stray letter in a mis-mapped text column still
        // fails the parse rather than being quietly swallowed.
        if let indicator = trailingDebitCreditIndicator(of: text) {
            isNegative = (indicator == "D")
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // A minus can lead or trail depending on the bank. U+2212 is normalized into the noise set.
        if text.hasPrefix("-") || text.hasPrefix("\u{2212}") {
            isNegative = true
            text = String(text.dropFirst())
        } else if text.hasSuffix("-") || text.hasSuffix("\u{2212}") {
            isNegative = true
            text = String(text.dropLast())
        }
        if text.hasPrefix("+") { text = String(text.dropFirst()) }

        text.removeAll { noise.contains($0) }
        guard !text.isEmpty else { throw Failure.empty }

        // Apply the column's convention: drop grouping, normalize the decimal mark to a POSIX dot.
        if let grouping = format.groupingSeparator {
            text.removeAll { $0 == grouping }
        }
        if format.decimalSeparator != "." {
            text = text.replacingOccurrences(of: String(format.decimalSeparator), with: ".")
        }

        // Anything left that isn't a digit, a dot, or scientific notation means this was never a
        // number — a description column mis-mapped as the amount, typically.
        guard text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "e" || $0 == "E" || $0 == "+" || $0 == "-" }),
              text.contains(where: \.isNumber) else {
            throw Failure.unparseable(raw)
        }

        // `Decimal(string:locale:)` with a nil locale is POSIX, and also handles `1.2345E+3`, which
        // Excel-mangled exports genuinely emit.
        guard let value = Decimal(string: text, locale: nil) else {
            throw Failure.unparseable(raw)
        }

        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let wasRounded = rounded != scaled

        let number = NSDecimalNumber(decimal: rounded)
        guard number.doubleValue.magnitude <= Double(maxCents) else { throw Failure.outOfRange }

        let cents = number.intValue
        return Parsed(cents: isNegative ? -abs(cents) : cents, wasRounded: wasRounded)
    }

    // MARK: - Column-level convention detection

    /// Decides the separator convention for a whole column.
    ///
    /// Proof first: a value carrying BOTH separators settles it outright, because only one ordering
    /// is possible. Failing that, count separators followed by exactly two digits (decimal-shaped)
    /// against exactly three (grouping-shaped) — money has two decimal places, and that asymmetry is
    /// the only signal available.
    static func detectFormat(in values: [String]) -> (spec: NumberFormatSpec, isProven: Bool) {
        let samples = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !samples.isEmpty else { return (.ptBR, false) }

        for value in samples {
            if matches(value, #"^[^\d]*-?\d{1,3}(\.\d{3})+,\d{1,2}[^\d]*$"#) {
                return (.ptBR, true)
            }
            if matches(value, #"^[^\d]*-?\d{1,3}(,\d{3})+\.\d{1,2}[^\d]*$"#) {
                return (.enUS, true)
            }
        }

        var commaDecimal = 0, commaGrouping = 0
        var dotDecimal = 0, dotGrouping = 0
        for value in samples {
            commaDecimal += countMatches(value, #",\d{2}(?!\d)"#)
            commaGrouping += countMatches(value, #",\d{3}(?!\d)"#)
            dotDecimal += countMatches(value, #"\.\d{2}(?!\d)"#)
            dotGrouping += countMatches(value, #"\.\d{3}(?!\d)"#)
        }

        // A separator used as a decimal point somewhere and as grouping nowhere is decisive enough.
        if commaDecimal > 0 && commaDecimal >= dotDecimal {
            return (NumberFormatSpec(decimalSeparator: ",", groupingSeparator: "."), commaGrouping == 0 || dotGrouping > 0)
        }
        if dotDecimal > 0 {
            return (NumberFormatSpec(decimalSeparator: ".", groupingSeparator: ","), dotGrouping == 0 || commaGrouping > 0)
        }

        // Only grouping-shaped separators anywhere, e.g. every value is `1.234`. Genuinely
        // unresolvable from the column alone; fall back to the device locale and let the caller warn.
        let localeUsesComma = (Locale.current.decimalSeparator ?? ",") == ","
        return (localeUsesComma ? .ptBR : .enUS, false)
    }

    /// `"D"` or `"C"` when the value ends in a debit/credit marker, else nil.
    private static func trailingDebitCreditIndicator(of text: String) -> Character? {
        guard let last = text.last.map({ Character($0.uppercased()) }),
              last == "D" || last == "C" else { return nil }
        let beforeMarker = text.dropLast().trimmingCharacters(in: .whitespaces)
        guard let preceding = beforeMarker.last, preceding.isNumber else { return nil }
        return last
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        countMatches(text, pattern) > 0
    }

    private static func countMatches(_ text: String, _ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
