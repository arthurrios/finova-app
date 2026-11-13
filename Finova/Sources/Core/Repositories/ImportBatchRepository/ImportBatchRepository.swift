//
//  ImportBatchRepository.swift
//  Finova
//
//  Local-only storage for CSV import history. See `ImportBatch` for why none of this syncs.
//

import Foundation

final class ImportBatchRepository: ImportBatchRepositoryProtocol {

    private let db: DBHelper
    private let currentUserId: () -> String?

    /// `currentUserId` is injected rather than read inline so tests can drive a batch's ownership
    /// without going through the global `UIDUserDefaultsManager`.
    init(
        db: DBHelper = .shared,
        currentUserId: @escaping () -> String? = { UIDUserDefaultsManager.shared.currentUserUID }
    ) {
        self.db = db
        self.currentUserId = currentUserId
    }

    // MARK: - CRUD

    @discardableResult
    func create(_ batch: ImportBatch) throws -> ImportBatch {
        var stored = batch
        let id = try db.insertImportBatch(batch)
        stored.id = id
        return stored
    }

    func update(_ batch: ImportBatch) throws {
        try db.updateImportBatch(batch)
    }

    func fetch(uuid: String) -> ImportBatch? {
        db.fetchImportBatch(uuid: uuid)
    }

    func history(limit: Int = 100) -> [ImportBatch] {
        db.fetchImportBatches(userId: currentUserId(), limit: limit)
    }

    func priorImports(ofFileHash hash: String) -> [ImportBatch] {
        db.fetchImportBatches(fileHash: hash, userId: currentUserId())
    }

    func recordRows(_ rows: [ImportBatchRow]) throws {
        try db.recordImportBatchRows(rows)
    }

    func importedRowFingerprints() -> Set<String> {
        db.importedRowFingerprints(userId: currentUserId())
    }

    func liveTransactionCount(batchUuid: String) -> Int {
        db.liveTransactionCount(importBatchUuid: batchUuid)
    }

    // MARK: - Crash recovery

    /// Settles batches that a crash left mid-write, and returns the ones that still need a rollback
    /// re-run.
    ///
    /// `applying` is resolved here and needs no cloud, no heuristics and no user input: recount the
    /// rows actually present and call the batch applied. Those rows are real user data — a partial
    /// import is a smaller import, not a corrupt one — and the batch stays fully rollback-able.
    ///
    /// `rollingBack` and `cancelling` are returned rather than handled, because re-running a
    /// rollback means reaching into `ImportRollbackService`, and having the repository call the
    /// service that calls the repository is a cycle worth not having. The caller re-runs them; the
    /// rollback is idempotent, so doing so twice is harmless.
    ///
    /// Deliberately NOT called from `DBHelper.initializeDatabase()`. That runs before auth on every
    /// launch, and `DataRepairService` establishes the rule that nothing which rewrites financial
    /// rows runs automatically at startup. Call it when the history screen appears, and before
    /// starting a new import.
    @discardableResult
    func reconcileInterrupted() -> [ImportBatch] {
        let interrupted = db.fetchInterruptedImportBatches(userId: currentUserId())
        guard !interrupted.isEmpty else { return [] }

        var needsRollback: [ImportBatch] = []

        for var batch in interrupted {
            switch batch.status {
            case .applying:
                let live = db.liveTransactionCount(importBatchUuid: batch.uuid)
                batch.rowsInserted = live
                batch.status = .applied
                batch.finishedAt = Date()
                batch.notes = appendNote(
                    to: batch.notes,
                    "Interrupted during apply; recovered \(live) row(s)."
                )
                try? update(batch)
                logWarning("[Import] Recovered interrupted batch \(batch.uuid): \(live) row(s) applied")

            case .rollingBack, .cancelling:
                needsRollback.append(batch)

            default:
                break
            }
        }

        return needsRollback
    }

    private func appendNote(to existing: String?, _ addition: String) -> String {
        guard let existing, !existing.isEmpty else { return addition }
        return existing + "\n" + addition
    }
}
