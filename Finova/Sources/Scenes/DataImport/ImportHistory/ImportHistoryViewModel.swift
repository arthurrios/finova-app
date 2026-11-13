//
//  ImportHistoryViewModel.swift
//  Finova
//
//  Past imports, and undoing one.
//

import Foundation

final class ImportHistoryViewModel {

    var onBatchesUpdated: (() -> Void)?
    var onError: ((String) -> Void)?
    var onParsed: ((LoadedFile, ImportPlan) -> Void)?
    var onParsing: ((Bool) -> Void)?

    private(set) var batches: [ImportBatch] = []

    private let batchRepo: ImportBatchRepository
    private let rollbackService: ImportRollbackService
    private let transactionRepo: TransactionRepository

    init(
        batchRepo: ImportBatchRepository = ImportBatchRepository(),
        rollbackService: ImportRollbackService = ImportRollbackService(),
        transactionRepo: TransactionRepository = TransactionRepository()
    ) {
        self.batchRepo = batchRepo
        self.rollbackService = rollbackService
        self.transactionRepo = transactionRepo
    }

    var isEmpty: Bool { batches.isEmpty }

    func refresh() {
        // Settles anything a crash left mid-write. Deliberately here rather than at launch: this is
        // the first moment the user has asked about imports, and `DataRepairService` establishes that
        // nothing rewriting financial rows runs automatically at startup.
        let needingRollback = batchRepo.reconcileInterrupted()
        for batch in needingRollback {
            _ = rollbackService.rollback(batchUuid: batch.uuid)
        }

        batches = batchRepo.history(limit: 100)
        onBatchesUpdated?()
    }

    func liveRowCount(for batch: ImportBatch) -> Int {
        batchRepo.liveTransactionCount(batchUuid: batch.uuid)
    }

    // MARK: - Reading a file

    /// Parses a picked file off the main thread and hands back the plan.
    func parse(file: LoadedFile) {
        onParsing?(true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let existing = self.transactionRepo.fetchAllTransactions()
            let alreadyImported = self.batchRepo.importedRowFingerprints()

            do {
                let plan = try CSVImportEngine.makePlan(CSVImportEngine.Input(
                    filename: file.displayName, data: file.data,
                    alreadyImported: alreadyImported, existing: existing))
                DispatchQueue.main.async {
                    self.onParsing?(false)
                    self.onParsed?(file, plan)
                }
            } catch {
                DispatchQueue.main.async {
                    self.onParsing?(false)
                    let message = (error as? ImportError)?.userMessage
                        ?? "import.error.cannotRead".localized
                    self.onError?(message)
                }
            }
        }
    }

    // MARK: - Rollback

    func rollback(_ batch: ImportBatch, policy: EditedRowPolicy = .keepEdited) {
        let outcome = rollbackService.rollback(batchUuid: batch.uuid, policy: policy)
        switch outcome {
        case .completed(let report):
            if report.editedKept > 0 {
                onError?(String(format: "import.history.undo.keptEdited".localized, report.editedKept))
            }
        case .deferred:
            onError?("import.history.undo.deferred".localized)
        case .alreadyRolledBack:
            break
        case .notFound:
            onError?("import.history.undo.notFound".localized)
        }
        refresh()
    }

    // MARK: - Presentation

    func summary(for batch: ImportBatch) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        switch batch.status {
        case .rolledBack:
            let when = batch.rolledBackAt.map(formatter.string(from:)) ?? ""
            return String(format: "import.history.status.rolledBack".localized, when)
        case .applied:
            return String(format: "import.history.status.applied".localized,
                          batch.rowsInserted, abs(batch.amountTotal).currencyString)
        case .rollbackDeferred:
            return "import.history.status.undoPending".localized
        case .applying, .rollingBack, .cancelling, .preparing:
            return "import.history.status.interrupted".localized
        case .cancelled:
            return "import.history.status.cancelled".localized
        case .failed:
            return "import.history.status.failed".localized
        }
    }

    func dateRange(for batch: ImportBatch) -> String? {
        guard let min = batch.dateMin, let max = batch.dateMax else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return "\(formatter.string(from: min)) – \(formatter.string(from: max))"
    }
}
