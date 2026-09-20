//
//  ResolvedSchema.swift
//  Finova
//
//  How to read one file: which column is what, and under which conventions.
//

import Foundation

enum ColumnRole: String, Codable, CaseIterable {
    case date
    case description
    /// One signed column carrying both directions.
    case amount
    /// Money out, in a file that splits the two.
    case debit
    /// Money in, in a file that splits the two.
    case credit
    /// A running balance. Never imported — but identifying it is what proves which column is the
    /// amount, and which way the signs run.
    case balance
    /// The bank's own category string, used as a categorization hint only.
    case category
    case docId
    /// A D/C marker column.
    case directionFlag
    case ignored
}

/// Which way the signs run in a single-amount column.
enum SignConvention: String, Codable {
    /// Negative means money out. Overwhelmingly the default for current accounts.
    case negativeIsExpense
    /// Positive means money out. The credit-card statement shape.
    case positiveIsExpense
    case separateDebitCredit
    case indicatorColumn
}

/// How strongly one aspect of the schema is believed, and on what basis.
struct SubConfidence: Equatable {
    let score: Double
    let evidence: String

    static func proof(_ why: String) -> SubConfidence { .init(score: 1.0, evidence: why) }
    static func strong(_ why: String) -> SubConfidence { .init(score: 0.8, evidence: why) }
    static func weak(_ why: String) -> SubConfidence { .init(score: 0.4, evidence: why) }
    static func none(_ why: String) -> SubConfidence { .init(score: 0.0, evidence: why) }
}

struct InferenceConfidence: Equatable {
    var header: SubConfidence
    var dateFormat: SubConfidence
    var numberFormat: SubConfidence
    var amountShape: SubConfidence
    var signConvention: SubConfidence
    var columnRoles: SubConfidence

    /// The WEAKEST link, deliberately — not the mean, and not the product.
    ///
    /// A file whose dates are certain and whose sign convention is a coin flip must not average out
    /// to something comfortable and sail through unchallenged. One unresolved aspect is enough to
    /// invert a month of the ledger, so one unresolved aspect sets the score.
    var overall: Double {
        [header, dateFormat, numberFormat, amountShape, signConvention, columnRoles]
            .map(\.score).min() ?? 0
    }

    enum Band { case high, medium, low }

    var band: Band {
        if overall >= 0.9 { return .high }
        if overall >= 0.6 { return .medium }
        return .low
    }

    /// The aspects dragging the score down, for highlighting on the mapping screen.
    var weakestAspects: [String] {
        let all: [(String, SubConfidence)] = [
            ("header", header), ("dateFormat", dateFormat), ("numberFormat", numberFormat),
            ("amountShape", amountShape), ("signConvention", signConvention),
            ("columnRoles", columnRoles),
        ]
        return all.filter { $0.1.score < 0.6 }.map(\.0)
    }
}

/// Everything needed to turn rows of strings into transactions.
struct ResolvedSchema: Equatable, Codable {
    var roles: [Int: ColumnRole]
    var hasHeaderRow: Bool
    /// Rows to drop before the header — preamble the bank prepends.
    var preambleRows: Int
    var dateFormat: DateFormatSpec
    var numberFormat: NumberFormatSpec
    var signConvention: SignConvention
    /// True when the date column ALSO carries the description in the same field, e.g. a single
    /// "Lançamentos" column holding `15/07/2026 14:30 COMPRA MERCADO`. The leading date is consumed
    /// and the remainder becomes the title.
    var dateColumnCarriesDescription: Bool = false
    /// Set when the file was matched to a bundled bank preset.
    var bankPresetId: String?

    func column(for role: ColumnRole) -> Int? {
        roles.first(where: { $0.value == role })?.key
    }

    var isUsable: Bool {
        guard column(for: .date) != nil else { return false }
        if column(for: .amount) != nil { return true }
        return column(for: .debit) != nil || column(for: .credit) != nil
    }

    /// JSON for the batch record's `column_mapping`, so history can explain how a file was read.
    func asJSON() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
