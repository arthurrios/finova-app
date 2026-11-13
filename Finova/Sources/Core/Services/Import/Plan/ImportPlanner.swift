//
//  ImportPlanner.swift
//  Finova
//
//  Rows plus a schema plus the existing ledger, in; the reviewable diff, out.
//
//  The ledger arrives as an injected `[Transaction]` SNAPSHOT rather than a repository. That is the
//  most consequential structural decision in the engine: it means the entire hard part of this
//  feature — parsing, inference, categorization, dedupe, planning — is a pure function, testable with
//  no database, no `UIDUserDefaultsManager`, and no `DBHelper(path:)` fixture.
//

import Foundation

struct ImportPlanner {

    private let duplicates: DuplicateIndex
    private let alreadyImported: Set<String>
    private let categorizer: DeterministicCategorizer

    init(
        existing: [Transaction],
        alreadyImported: Set<String> = [],
        rules: MerchantRuleSet = .shared
    ) {
        self.duplicates = DuplicateIndex(existing: existing)
        self.alreadyImported = alreadyImported
        self.categorizer = DeterministicCategorizer(existing: existing, rules: rules)
    }

    func plan(
        rows: [CSVTokenizer.Row],
        schema: ResolvedSchema,
        confidence: InferenceConfidence,
        source: ImportSource
    ) -> ImportPlan {
        var planned: [ImportRow] = []
        /// Intra-file duplicates: the first row wins the slot, the rest are flagged — but all of them
        /// are still imported, because two identical rows in one statement are usually two real
        /// transactions.
        var seenInFile: [MatchKey: Int] = [:]

        let numberFormatUnproven = confidence.numberFormat.score < 0.9
        let signUnproven = confidence.signConvention.score < 0.6
        let dateUnproven = confidence.dateFormat.score < 0.6

        for row in rows {
            let fingerprint = Self.fingerprint(fileHash: source.sha256, line: row.line, cells: row.cells)
            var warnings: [RowWarning] = []

            guard let parsed = parse(row: row, schema: schema, warnings: &warnings) else {
                planned.append(ImportRow(
                    id: row.line, rawCells: row.cells, fingerprint: fingerprint, parsed: nil,
                    disposition: .failed(failureReason(row: row, schema: schema)),
                    categorySuggestion: nil, warnings: warnings))
                continue
            }

            if numberFormatUnproven { warnings.append(.ambiguousNumberFormat) }
            if parsed.title.installmentHint != nil { warnings.append(.installmentHintIgnored) }

            let type: TransactionType = parsed.signedCents > 0 ? .income : .expense
            let suggestion = categorizer.categorize(
                title: parsed.title, type: type, bankCategory: parsed.bankCategory)

            let disposition = classify(
                parsed: parsed, type: type, fingerprint: fingerprint, line: row.line,
                seenInFile: &seenInFile, signUnproven: signUnproven, dateUnproven: dateUnproven)

            planned.append(ImportRow(
                id: row.line, rawCells: row.cells, fingerprint: fingerprint, parsed: parsed,
                disposition: disposition, categorySuggestion: suggestion, warnings: warnings))
        }

        return ImportPlan(source: source, schema: schema, confidence: confidence, rows: planned)
    }

    // MARK: - Identity

    /// Stable across re-imports of the same file AND across re-inference of the same import.
    ///
    /// Computed over the RAW cells, so improving the title-cleaning rules later does not make every
    /// previously imported row look new.
    static func fingerprint(fileHash: String, line: Int, cells: [String]) -> String {
        DeterministicIdentity.v5("csvimport|\(fileHash)|\(line)|\(cells.joined(separator: "\u{1F}"))")
    }

    // MARK: - Parsing one row

    private func parse(
        row: CSVTokenizer.Row, schema: ResolvedSchema, warnings: inout [RowWarning]
    ) -> ParsedRow? {
        guard let dateIndex = schema.column(for: .date),
              let rawDate = row.cells[safe: dateIndex] else { return nil }

        // A fused column carries the date and the description in one field; consuming the leading
        // date leaves the description behind as the remainder.
        let date: Date
        var fusedRemainder: String?
        if schema.dateColumnCarriesDescription {
            guard let leading = DateFieldParser.parseLeadingDate(rawDate) else { return nil }
            date = leading.date
            fusedRemainder = leading.remainder
        } else {
            guard let parsed = DateFieldParser.parse(rawDate, spec: schema.dateFormat) else { return nil }
            date = parsed
        }

        guard let cents = signedCents(row: row, schema: schema, warnings: &warnings),
              cents != 0 else { return nil }

        // A dedicated description column still wins if the file has one; the remainder is the
        // fallback, which is the only source in the fused shape.
        let rawTitle = schema.column(for: .description)
            .flatMap { row.cells[safe: $0] }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? fusedRemainder
            ?? ""
        let cleaned = TitleCleaner.clean(rawTitle)
        if cleaned.title.isEmpty { warnings.append(.titleWasEmpty) }

        let bankCategory = schema.column(for: .category).flatMap { row.cells[safe: $0] }

        return ParsedRow(date: date, signedCents: cents, title: cleaned,
                         bankCategory: bankCategory?.isEmpty == false ? bankCategory : nil)
    }

    private func signedCents(
        row: CSVTokenizer.Row, schema: ResolvedSchema, warnings: inout [RowWarning]
    ) -> Int? {
        switch schema.signConvention {
        case .separateDebitCredit:
            let debit = schema.column(for: .debit).flatMap { row.cells[safe: $0] }
                .flatMap { try? AmountParser.parse($0, format: schema.numberFormat) }
            let credit = schema.column(for: .credit).flatMap { row.cells[safe: $0] }
                .flatMap { try? AmountParser.parse($0, format: schema.numberFormat) }

            if let debit, debit.cents != 0 {
                if debit.wasRounded { warnings.append(.amountRounded) }
                return -abs(debit.cents)
            }
            if let credit, credit.cents != 0 {
                if credit.wasRounded { warnings.append(.amountRounded) }
                return abs(credit.cents)
            }
            return nil

        case .indicatorColumn:
            guard let amountIndex = schema.column(for: .amount),
                  let raw = row.cells[safe: amountIndex],
                  let parsed = try? AmountParser.parse(raw, format: schema.numberFormat) else { return nil }
            if parsed.wasRounded { warnings.append(.amountRounded) }

            let flag = schema.column(for: .directionFlag)
                .flatMap { row.cells[safe: $0] }?
                .trimmingCharacters(in: .whitespaces).uppercased()
            let isDebit = flag == "D" || flag == "-" || flag == "DEBITO"
            return isDebit ? -abs(parsed.cents) : abs(parsed.cents)

        case .negativeIsExpense:
            guard let parsed = amountValue(row: row, schema: schema) else { return nil }
            if parsed.wasRounded { warnings.append(.amountRounded) }
            return parsed.cents

        case .positiveIsExpense:
            guard let parsed = amountValue(row: row, schema: schema) else { return nil }
            if parsed.wasRounded { warnings.append(.amountRounded) }
            return -parsed.cents
        }
    }

    private func amountValue(row: CSVTokenizer.Row, schema: ResolvedSchema) -> AmountParser.Parsed? {
        guard let index = schema.column(for: .amount), let raw = row.cells[safe: index] else { return nil }
        return try? AmountParser.parse(raw, format: schema.numberFormat)
    }

    private func failureReason(row: CSVTokenizer.Row, schema: ResolvedSchema) -> RowError {
        guard let dateIndex = schema.column(for: .date), let rawDate = row.cells[safe: dateIndex] else {
            return .missingField(.date)
        }
        if DateFieldParser.parse(rawDate, spec: schema.dateFormat) == nil {
            return .unparseableDate(rawDate)
        }
        if let index = schema.column(for: .amount), let raw = row.cells[safe: index] {
            do {
                let parsed = try AmountParser.parse(raw, format: schema.numberFormat)
                return parsed.cents == 0 ? .zeroAmount : .unparseableAmount(raw)
            } catch AmountParser.Failure.outOfRange {
                return .amountOutOfRange
            } catch {
                return .unparseableAmount(raw)
            }
        }
        return .missingField(.amount)
    }

    // MARK: - Classification

    private func classify(
        parsed: ParsedRow,
        type: TransactionType,
        fingerprint: String,
        line: Int,
        seenInFile: inout [MatchKey: Int],
        signUnproven: Bool,
        dateUnproven: Bool
    ) -> Disposition {
        // Tier 0: this exact row has been imported before.
        if alreadyImported.contains(fingerprint) { return .alreadyImported }

        // Unresolved file-level questions outrank duplicate detection: there is no point telling the
        // user a row looks like a duplicate when its sign might be inverted.
        if dateUnproven { return .needsDecision(.ambiguousDate) }
        if signUnproven { return .needsDecision(.ambiguousSign) }

        let day = DuplicateIndex.dayStart(of: parsed.date)
        let normalized = parsed.title.title.normalizedForSearch()
        let key = MatchKey(dayStart: day, signedCents: parsed.signedCents, normalizedTitle: normalized)

        // Tier 3: a twin earlier in this same file.
        if let firstLine = seenInFile[key] { return .duplicateInFile(firstRowId: firstLine) }
        seenInFile[key] = line

        // Tier 1: an exact match in the ledger.
        if let existingId = duplicates.exactMatch(
            dayStart: day, signedCents: parsed.signedCents, normalizedTitle: normalized) {
            return .duplicateExact(existingId: existingId)
        }

        // Tier 2: same amount, within a few days, similar title.
        if let fuzzy = duplicates.fuzzyMatch(
            dayStart: day, signedCents: parsed.signedCents, title: parsed.title.title) {
            return .duplicateLikely(existingId: fuzzy.id, similarity: fuzzy.similarity)
        }

        return .insert
    }
}
