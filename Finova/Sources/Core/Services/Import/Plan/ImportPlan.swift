//
//  ImportPlan.swift
//  Finova
//
//  The complete proposed change set, computed without touching the database.
//

import Foundation

struct ImportSource: Equatable {
    let filename: String
    let byteCount: Int
    let sha256: String
    let encoding: String
    let dialect: CSVDialect
    /// The file needed repair to decode. Worth telling the user before rows land.
    let wasLossy: Bool
}

enum RowWarning: String, Equatable {
    /// The value carried more than two decimal places and was rounded. Money is never silently
    /// rounded — this surfaces it.
    case amountRounded
    /// The column's decimal separator could not be proven, only guessed.
    case ambiguousNumberFormat
    case dateFarFromOthers
    /// The description carried an `n/m` installment marker. Recorded and shown; not acted on.
    case installmentHintIgnored
    case titleWasEmpty
}

enum RowError: Equatable {
    case unparseableDate(String)
    case unparseableAmount(String)
    case zeroAmount
    case missingField(ColumnRole)
    case amountOutOfRange
    case shortRow(expected: Int, got: Int)
}

/// What needs deciding before a row can be imported.
enum RowDecision: Equatable {
    /// Nothing in the file proves which sign means money out.
    case ambiguousSign
    /// Both the debit and the credit column carry a value.
    case debitAndCreditBothSet
    /// Day and month are interchangeable for this file.
    case ambiguousDate
}

enum Disposition: Equatable {
    case insert
    case duplicateExact(existingId: Int)
    case duplicateLikely(existingId: Int, similarity: Double)
    /// Two identical rows within the same file. Both are kept — two coffees on the same day at the
    /// same price is an ordinary Tuesday, and collapsing them silently loses one.
    case duplicateInFile(firstRowId: Int)
    case alreadyImported
    case needsDecision(RowDecision)
    case failed(RowError)

    /// Whether this row goes in unless the user says otherwise.
    var isIncludedByDefault: Bool {
        switch self {
        case .insert, .duplicateInFile:
            return true
        // Included by default, with a warning badge. The asymmetry against `.duplicateExact` is
        // deliberate: a false skip silently loses a real transaction, which is strictly worse than a
        // visible duplicate the user removes in two taps.
        case .duplicateLikely:
            return true
        case .duplicateExact, .alreadyImported, .needsDecision, .failed:
            return false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct ParsedRow: Equatable {
    /// Anchored at local noon. See `DateFieldParser`.
    let date: Date
    let signedCents: Int
    let title: CleanedTitle
    let bankCategory: String?
}

struct ImportRow: Identifiable, Equatable {
    /// The source line number, which is stable across re-inference and is what the UI shows.
    let id: Int
    let rawCells: [String]
    /// v5 over (file hash, line, raw cells). Invariant under re-inference, because it is computed
    /// from the bytes rather than from any interpretation of them — which is what lets user
    /// overrides survive a change of date format.
    let fingerprint: String
    let parsed: ParsedRow?
    let disposition: Disposition
    let categorySuggestion: CategorySuggestion?
    let warnings: [RowWarning]
}

struct ImportPlan {
    let source: ImportSource
    let schema: ResolvedSchema
    let confidence: InferenceConfidence
    /// EVERY row in file order, including the ones that failed. A row that vanishes from the review
    /// is a row the user cannot reason about.
    let rows: [ImportRow]

    var insertableRows: [ImportRow] { rows.filter { $0.disposition.isIncludedByDefault } }
    var failedRows: [ImportRow] { rows.filter { $0.disposition.isFailure } }
    var duplicateRows: [ImportRow] {
        rows.filter {
            switch $0.disposition {
            case .duplicateExact, .duplicateLikely, .alreadyImported: return true
            default: return false
            }
        }
    }
    var undecidedRows: [ImportRow] {
        rows.filter { if case .needsDecision = $0.disposition { return true } else { return false } }
    }
}

/// One row's worth of user intent, layered over whatever the planner decided.
struct RowOverride: Codable, Equatable {
    var isIncluded: Bool?
    var categoryKey: String?
    var title: String?
    var typeKey: String?
    var date: Date?

    var isEmpty: Bool {
        isIncluded == nil && categoryKey == nil && title == nil && typeKey == nil && date == nil
    }
}

/// All of the user's edits on the review screen.
///
/// Keyed by FINGERPRINT, never by array index — that is what makes back-navigation lossless. Going
/// back to change the date format recomputes the whole plan: indices shift, dispositions change, and
/// rows can appear or vanish. The fingerprint is over the raw bytes of the row, so it survives all of
/// it.
struct ImportOverrides: Codable, Equatable {
    private(set) var byFingerprint: [String: RowOverride] = [:]
    var includeExactDuplicates = false
    var includeLikelyDuplicates = true

    mutating func set(_ override: RowOverride, for fingerprint: String) {
        if override.isEmpty {
            byFingerprint.removeValue(forKey: fingerprint)
        } else {
            byFingerprint[fingerprint] = override
        }
    }

    mutating func update(_ fingerprint: String, _ mutate: (inout RowOverride) -> Void) {
        var existing = byFingerprint[fingerprint] ?? RowOverride()
        mutate(&existing)
        set(existing, for: fingerprint)
    }

    func override(for fingerprint: String) -> RowOverride? { byFingerprint[fingerprint] }

    // Note: overrides for fingerprints absent from the current plan are RETAINED, never pruned, so
    // bouncing between the mapping and review screens is lossless.
}

/// Everything apply needs, and nothing it doesn't.
struct ResolvedImport {
    let rows: [ImportableRow]
    let skippedCount: Int
    let failedCount: Int
}

extension ImportPlan {

    /// Applies the user's overrides and produces the final row set.
    ///
    /// PURE: no database, no file system, no global state. That is what makes the whole engine
    /// testable without a `DBHelper` fixture, and it is why the ledger arrives as an injected
    /// snapshot rather than a repository.
    func resolve(with overrides: ImportOverrides) -> ResolvedImport {
        var importable: [ImportableRow] = []
        var skipped = 0
        var failed = 0

        for row in rows {
            guard let parsed = row.parsed else {
                failed += 1
                continue
            }

            let override = overrides.override(for: row.fingerprint)
            if let included = includeDecision(row: row, override: override, overrides: overrides) {
                guard included else { skipped += 1; continue }
            } else {
                skipped += 1
                continue
            }

            let type = resolveType(parsed: parsed, override: override)
            let category = resolveCategory(row: row, override: override)
            let title = override?.title ?? parsed.title.title
            let date = override?.date ?? parsed.date

            importable.append(ImportableRow(
                model: RowNormalizer.model(
                    title: title, category: category, type: type,
                    date: date, cents: parsed.signedCents),
                fingerprint: row.fingerprint,
                sourceLine: row.id))
        }

        return ResolvedImport(rows: importable, skippedCount: skipped, failedCount: failed)
    }

    /// nil means "cannot be imported at all", as distinct from "excluded".
    private func includeDecision(
        row: ImportRow, override: RowOverride?, overrides: ImportOverrides
    ) -> Bool? {
        // An explicit per-row choice always wins, including forcing a known duplicate in.
        if let explicit = override?.isIncluded { return explicit }

        switch row.disposition {
        case .insert, .duplicateInFile:
            return true
        case .duplicateLikely:
            return overrides.includeLikelyDuplicates
        case .duplicateExact:
            return overrides.includeExactDuplicates
        case .alreadyImported:
            return false
        case .needsDecision:
            // Resolvable by overriding the type; otherwise it stays out.
            return override?.typeKey != nil
        case .failed:
            return nil
        }
    }

    private func resolveType(parsed: ParsedRow, override: RowOverride?) -> TransactionType {
        if let key = override?.typeKey,
           let type = TransactionType.allCases.first(where: { $0.key == key }) {
            return type
        }
        return parsed.signedCents > 0 ? .income : .expense
    }

    private func resolveCategory(row: ImportRow, override: RowOverride?) -> TransactionCategory {
        if let key = override?.categoryKey,
           let category = TransactionCategory.allCases.first(where: { $0.key == key }) {
            return category
        }
        return row.categorySuggestion?.category ?? .miscellaneous
    }
}
