//
//  ImportReviewViewModel.swift
//  Finova
//
//  The diff the user signs off on, and the apply that follows it.
//

import Foundation

/// One visual grouping in the review list.
struct ImportReviewSection {
    enum Kind {
        case willBeAdded
        case needsDecision
        case duplicates
        case couldNotBeRead
    }

    let kind: Kind
    let rows: [ImportRow]

    var title: String {
        switch kind {
        case .willBeAdded: return "import.review.section.willAdd".localized
        case .needsDecision: return "import.review.section.needsDecision".localized
        case .duplicates: return "import.review.section.duplicates".localized
        case .couldNotBeRead: return "import.review.section.failed".localized
        }
    }

    var footer: String? {
        switch kind {
        case .needsDecision: return "import.review.section.needsDecision.footer".localized
        case .duplicates: return "import.review.section.duplicates.footer".localized
        case .couldNotBeRead: return "import.review.section.failed.footer".localized
        case .willBeAdded: return nil
        }
    }
}

final class ImportReviewViewModel {

    // MARK: - Bindings

    var onPlanUpdated: (() -> Void)?
    var onApplyProgress: ((Int, Int) -> Void)?
    var onApplyFinished: ((ImportBatch) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - State

    private(set) var plan: ImportPlan
    private(set) var overrides = ImportOverrides()
    private(set) var isApplying = false

    let file: LoadedFile
    /// A previous import of this exact file, if there is one. The cheapest guard against the most
    /// common mistake.
    let priorImport: ImportBatch?

    private let applyService: ImportApplyService
    private let transactionRepo: TransactionRepository
    private let categorizer: TransactionCategorizing
    private var modelTask: Task<Void, Never>?

    init(
        file: LoadedFile,
        plan: ImportPlan,
        applyService: ImportApplyService = ImportApplyService(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        batchRepo: ImportBatchRepository = ImportBatchRepository(),
        categorizer: TransactionCategorizing = TransactionCategorizerFactory.make()
    ) {
        self.file = file
        self.plan = plan
        self.applyService = applyService
        self.transactionRepo = transactionRepo
        self.categorizer = categorizer
        self.priorImport = batchRepo.priorImports(ofFileHash: file.sha256).first
    }

    deinit { modelTask?.cancel() }

    // MARK: - Presentation

    var sections: [ImportReviewSection] {
        var result: [ImportReviewSection] = []
        let included = plan.rows.filter { isIncluded($0) }
        if !included.isEmpty { result.append(.init(kind: .willBeAdded, rows: included)) }

        let undecided = plan.undecidedRows.filter { !isIncluded($0) }
        if !undecided.isEmpty { result.append(.init(kind: .needsDecision, rows: undecided)) }

        let duplicates = plan.duplicateRows.filter { !isIncluded($0) }
        if !duplicates.isEmpty { result.append(.init(kind: .duplicates, rows: duplicates)) }

        if !plan.failedRows.isEmpty {
            result.append(.init(kind: .couldNotBeRead, rows: plan.failedRows))
        }
        return result
    }

    var summary: String {
        let resolved = plan.resolve(with: overrides)
        return String(
            format: "import.review.summary".localized,
            resolved.rows.count, resolved.skippedCount, resolved.failedCount)
    }

    /// Signed total of everything that will actually be written.
    var netTotal: Int {
        plan.resolve(with: overrides).rows.reduce(0) { sum, row in
            let amount = row.model.data.amount
            return sum + (row.model.data.type == TransactionType.income.key ? amount : -amount)
        }
    }

    var canApply: Bool { !isApplying && !plan.resolve(with: overrides).rows.isEmpty }

    var warningMessage: String? {
        if plan.source.wasLossy { return "import.review.warning.damagedFile".localized }
        if let priorImport {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return String(format: "import.review.warning.alreadyImported".localized,
                          formatter.string(from: priorImport.createdAt), priorImport.rowsInserted)
        }
        return nil
    }

    func isIncluded(_ row: ImportRow) -> Bool {
        if let explicit = overrides.override(for: row.fingerprint)?.isIncluded { return explicit }
        switch row.disposition {
        case .duplicateLikely: return overrides.includeLikelyDuplicates
        case .duplicateExact: return overrides.includeExactDuplicates
        case .needsDecision: return overrides.override(for: row.fingerprint)?.typeKey != nil
        default: return row.disposition.isIncludedByDefault
        }
    }

    func category(for row: ImportRow) -> TransactionCategory {
        if let key = overrides.override(for: row.fingerprint)?.categoryKey,
           let category = TransactionCategory.allCases.first(where: { $0.key == key }) {
            return category
        }
        return row.categorySuggestion?.category ?? .miscellaneous
    }

    func title(for row: ImportRow) -> String {
        overrides.override(for: row.fingerprint)?.title
            ?? row.parsed?.title.title
            ?? row.rawCells.first
            ?? ""
    }

    // MARK: - Editing

    func toggleInclusion(of row: ImportRow) {
        let current = isIncluded(row)
        overrides.update(row.fingerprint) { $0.isIncluded = !current }
        onPlanUpdated?()
    }

    func setCategory(_ category: TransactionCategory, for row: ImportRow) {
        overrides.update(row.fingerprint) { $0.categoryKey = category.key }
        onPlanUpdated?()
    }

    func setTitle(_ title: String, for row: ImportRow) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        overrides.update(row.fingerprint) { $0.title = trimmed.isEmpty ? nil : trimmed }
        onPlanUpdated?()
    }

    /// Resolves an ambiguous-sign row by stating its direction.
    func setType(_ type: TransactionType, for row: ImportRow) {
        overrides.update(row.fingerprint) {
            $0.typeKey = type.key
            $0.isIncluded = true
        }
        onPlanUpdated?()
    }

    /// Applies one direction to every row still waiting on the sign question.
    func resolveAllSigns(asWritten: Bool) {
        for row in plan.undecidedRows {
            guard let parsed = row.parsed else { continue }
            let asRead: TransactionType = parsed.signedCents > 0 ? .income : .expense
            let chosen: TransactionType = asWritten
                ? asRead
                : (asRead == .income ? .expense : .income)
            overrides.update(row.fingerprint) {
                $0.typeKey = chosen.key
                $0.isIncluded = true
            }
        }
        onPlanUpdated?()
    }

    func setIncludeDuplicates(exact: Bool? = nil, likely: Bool? = nil) {
        if let exact { overrides.includeExactDuplicates = exact }
        if let likely { overrides.includeLikelyDuplicates = likely }
        onPlanUpdated?()
    }

    // MARK: - On-device refinement

    /// Asks the on-device model to improve the categories the deterministic engine admitted it was
    /// guessing at.
    ///
    /// Started only AFTER the diff is on screen, and it patches in one atomic update. Nothing waits
    /// on it, and tapping Apply cancels it — apply reads the plan, never the model.
    func refineCategoriesInBackground(existing: [Transaction]) {
        guard categorizer.isAvailable else { return }
        let requests = ModelCategoryRefinement.requests(from: plan)
        guard requests.count >= 3 else { return }

        let examples = ModelCategoryRefinement.examples(from: existing)
        modelTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.categorizer.categorize(requests, examples: examples)
            guard case .categorized(let categories) = outcome, !categories.isEmpty else { return }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.plan = ModelCategoryRefinement.apply(
                    categories, to: self.plan, overrides: self.overrides)
                self.onPlanUpdated?()
            }
        }
    }

    // MARK: - Apply

    func apply() {
        guard canApply else { return }
        modelTask?.cancel()
        isApplying = true
        onPlanUpdated?()

        let resolved = plan.resolve(with: overrides)
        let request = ImportApplyRequest(
            sourceFilename: file.displayName,
            fileHash: file.sha256,
            fileByteCount: file.byteCount,
            bankPresetId: plan.schema.bankPresetId,
            columnMapping: plan.schema.asJSON(),
            rowsInFile: plan.rows.count,
            rowsSkipped: resolved.skippedCount,
            rowsFailed: resolved.failedCount,
            rows: resolved.rows)

        // Off the main thread: a thousand rows is ten committed chunks and a CloudKit wake-up.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let batch = try self.applyService.apply(request) { done, total in
                    DispatchQueue.main.async { self.onApplyProgress?(done, total) }
                }
                DispatchQueue.main.async {
                    self.isApplying = false
                    self.onApplyFinished?(batch)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isApplying = false
                    let message = (error as? ImportError)?.userMessage
                        ?? (error as? ImportApplyError).map(Self.message(for:))
                        ?? "import.error.applyFailed".localized
                    self.onError?(message)
                    self.onPlanUpdated?()
                }
            }
        }
    }

    private static func message(for error: ImportApplyError) -> String {
        switch error {
        case .tooManyRows(let count, let limit):
            return String(format: "import.error.batchTooLarge".localized, count, limit)
        case .databaseUnavailable:
            return "import.error.applyFailed".localized
        }
    }
}
