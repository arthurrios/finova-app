//
//  ImportRollbackService.swift
//  Finova
//
//  Undoing one CSV import.
//
//  The guarantee this file exists to provide is that an undo is correct on LOCAL state alone:
//  offline, with sync disabled, on a device that has never completed a full pull. That holds because
//  the gates that could block it — `syncFullPullVerified_v2` and `mayPushDeleteForGroupRecord` — sit
//  on the PUSH inside `SyncEngine.pushLocalChanges`, never on the local write, and every read path in
//  `DBHelper` filters `is_deleted`. So the rows leave the user's ledger the moment this returns; the
//  cloud finds out whenever it next can.
//
//  Rollback is only closed-form because an import is INSERT-ONLY. If it could modify existing rows,
//  undoing it would mean merging a stored before-image against a `rev`-ordered conflict resolver that
//  was never designed to take a third input, and the failure mode of getting that wrong is silently
//  wrong money. "Re-categorize an existing match" belongs at review time, or as a separate edit the
//  ordinary undo already covers.
//

import Foundation

final class ImportRollbackService {

    private let db: DBHelper
    private let transactionRepo: TransactionRepository
    private let batchRepo: ImportBatchRepository
    private let isSyncInProgress: () -> Bool

    /// `isSyncInProgress` is injected so the deferral path is testable without a live sync.
    init(
        db: DBHelper = .shared,
        transactionRepo: TransactionRepository? = nil,
        batchRepo: ImportBatchRepository? = nil,
        isSyncInProgress: @escaping () -> Bool = { SyncEngine.shared.isSyncInProgress }
    ) {
        self.db = db
        self.transactionRepo = transactionRepo ?? TransactionRepository(db: db)
        self.batchRepo = batchRepo ?? ImportBatchRepository(db: db)
        self.isSyncInProgress = isSyncInProgress
    }

    /// Removes the rows a batch created.
    ///
    /// Rows are classified against the batch's `applied_at`, which every row in the batch carries
    /// verbatim in `updated_at`. That turns "has the user touched this since importing?" into an
    /// exact equality test rather than a tolerance comparison.
    ///
    /// `updated_at` is the right sentinel and `rev` is not. Every local edit bumps `updated_at`;
    /// `markAsSynced` deliberately does not, so merely pushing a row produces no false positive; and
    /// `executeCloudUpdate` does, so an edit arriving from another device correctly counts as
    /// touched. `rev` only ever moves inside the sync engine, and would miss the common case
    /// entirely.
    @discardableResult
    func rollback(
        batchUuid: String,
        policy: EditedRowPolicy = .keepEdited
    ) -> ImportRollbackOutcome {
        guard var batch = batchRepo.fetch(uuid: batchUuid) else { return .notFound }

        if batch.status == .rolledBack {
            return .alreadyRolledBack(ImportRollbackReport(hardDeleted: 0, softDeleted: 0,
                                                           alreadyGone: batch.rowsRemoved))
        }

        // A row that is mid-push still reads `ck_record_id IS NULL`, because `SyncEngine` only
        // assigns the record name in the per-record SUCCESS callback (`pendingCKIdAssignments`).
        // Classifying now would hard-delete a row that is about to exist in the cloud, leaving an
        // orphaned record that returns on the next full pull as an untracked transaction. So the
        // intent is persisted and executed once the cycle settles — deferred rather than refused,
        // because a large push runs for minutes and "try again later" would leave undo dead for the
        // whole window. `ImportOrphanSweep` is the backstop if this is ever wrong.
        if isSyncInProgress() {
            batch.status = .rollbackDeferred
            try? batchRepo.update(batch)
            logWarning("[Import] Rollback of \(batchUuid) deferred until the in-flight sync finishes")
            NotificationCenter.default.post(name: .importBatchesDidChange, object: nil)
            return .deferred
        }

        batch.status = .rollingBack
        try? batchRepo.update(batch)

        let report = removeRows(ofBatch: batchUuid, policy: policy)

        batch.rowsRemoved = report.totalRemoved
        batch.rolledBackAt = Date()
        batch.status = .rolledBack
        if report.editedKept > 0 {
            batch.notes = appendNote(
                to: batch.notes,
                "\(report.editedKept) row(s) kept because they were edited after importing.")
        }
        try? batchRepo.update(batch)

        logWarning("""
            [Import] Rolled back \(batchUuid): \(report.hardDeleted) hard-deleted, \
            \(report.softDeleted) tombstoned, \(report.editedKept) kept as edited, \
            \(report.alreadyGone) already gone
            """)
        NotificationCenter.default.post(name: .importBatchesDidChange, object: nil)
        return .completed(report)
    }

    /// Re-runs any rollback that was deferred while a sync was in flight, plus any that a crash left
    /// half-done. Safe to call on every sync cycle: it is a no-op when there is nothing to do, and
    /// the rollback itself is idempotent.
    @discardableResult
    func runDeferredRollbacks() -> Int {
        let pending = batchRepo.history(limit: 500).filter {
            $0.status == .rollbackDeferred || $0.status == .rollingBack || $0.status == .cancelling
        }
        guard !pending.isEmpty else { return 0 }

        var completed = 0
        for batch in pending {
            // `rollbackDeferred` is a persisted intent, so it must not be re-deferred forever if
            // this fires while another cycle is starting; the caller runs us after the cycle's
            // `group.notify`, where `isSyncInProgress` is already false.
            if case .completed = rollback(batchUuid: batch.uuid) { completed += 1 }
        }
        return completed
    }

    // MARK: - Classification

    private func removeRows(ofBatch batchUuid: String, policy: EditedRowPolicy) -> ImportRollbackReport {
        guard let batch = batchRepo.fetch(uuid: batchUuid), let appliedAt = batch.appliedAt else {
            return ImportRollbackReport()
        }
        let stamped = Int(appliedAt.timeIntervalSince1970)
        let states = db.fetchImportedRowStates(importBatchUuid: batchUuid)

        var report = ImportRollbackReport()
        var doomed: [Int] = []

        for state in states {
            if state.isDeleted {
                // Class C: a second rollback, or the user deleted it by hand. Nothing to do, and
                // this is one of the two reasons a double rollback is harmless.
                report.alreadyGone += 1
                continue
            }

            let untouched = state.updatedAt == stamped
            if untouched {
                // Classes A and B. Which one it is — hard delete or tombstone — is decided by
                // `TransactionRepository.deleteRow` from `ck_record_id`, exactly as it is for a row
                // the user deletes by hand. Counted here only so the report can say what happened.
                if state.hasCKRecord { report.softDeleted += 1 } else { report.hardDeleted += 1 }
                doomed.append(state.id)
            } else {
                // Class D. The user changed this row after importing it, and a later edit is newer
                // intent than the import that created it. Kept unless they say otherwise.
                switch policy {
                case .keepEdited:
                    report.editedKept += 1
                case .removeEdited:
                    report.editedRemoved += 1
                    doomed.append(state.id)
                }
            }
        }

        if !doomed.isEmpty {
            // Reuses the ordinary delete path rather than reimplementing the soft/hard rule: it also
            // releases early-payment and cancellation links, cancels scheduled notifications,
            // recalculates affected statements, and invalidates the cache and posts once for the
            // whole set. Imported rows touch none of that machinery, but going through the front
            // door means a future change to deletion semantics reaches rollback for free.
            try? transactionRepo.deleteBatch(ids: doomed)
        }

        return report
    }

    private func appendNote(to existing: String?, _ addition: String) -> String {
        guard let existing, !existing.isEmpty else { return addition }
        return existing + "\n" + addition
    }
}
