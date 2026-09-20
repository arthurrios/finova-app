//
//  ImportApplyService.swift
//  Finova
//
//  Turns a reviewed import into rows, as one reversible batch.
//
//  The ordering in `apply` is the crash-safety mechanism and is not incidental: the batch record is
//  committed on its own BEFORE any transaction is written, and moved out of `applying` only after
//  the last one. A batch found in `applying` at next launch was therefore interrupted, and
//  `ImportBatchRepository.reconcileInterrupted()` can settle it by recounting. If the batch record
//  were written in the same transaction as the rows, a crash would roll it back too and the rows it
//  created would be unattributable — imported data that can never be undone.
//

import Foundation

/// One row that survived review and is going to be written.
struct ImportableRow {
    let model: TransactionModel
    /// Stable v5 identity over (file hash, line, raw cells).
    let fingerprint: String
    /// 1-based line in the source file.
    let sourceLine: Int?
}

struct ImportApplyRequest {
    let sourceFilename: String
    let fileHash: String
    let fileByteCount: Int
    let bankPresetId: String?
    /// The resolved column mapping, as JSON, for the history detail screen.
    let columnMapping: String
    let rowsInFile: Int
    let rowsSkipped: Int
    let rowsFailed: Int
    let rows: [ImportableRow]
}

enum ImportApplyError: Error {
    /// More rows than one batch is allowed to write. See `ImportApplyService.maxRowsPerBatch`.
    case tooManyRows(count: Int, limit: Int)
    case databaseUnavailable
}

final class ImportApplyService {

    /// The ceiling on one batch.
    ///
    /// Not a storage limit — SQLite would not notice. It is a sync limit: rows land as `pending`,
    /// `SyncEngine` pushes them 50 at a time, sequentially, with a 1.5 s pause between batches once
    /// there are more than five. A thousand rows is already ~20 batches; letting the number grow
    /// unbounded means an import that appears to finish instantly and then quietly occupies the sync
    /// engine for many minutes. Better to cap deliberately and let the user import a second file.
    static let maxRowsPerBatch = 1000

    /// Above this many rows, snapshot the database first.
    ///
    /// A bulk write from a user-supplied file is the largest single mutation the app performs on
    /// untrusted input, so the same courtesy `DataRepairService` extends before a repair applies
    /// here. Gated by size so that casual small imports don't churn the Backups directory.
    static let snapshotThreshold = 250

    private let db: DBHelper
    private let transactionRepo: TransactionRepository
    private let batchRepo: ImportBatchRepository
    private let currentUserId: () -> String?
    /// Injected rather than read from the singleton so the cancel path — which runs a rollback — is
    /// deterministic in tests and never reaches for a live `SyncEngine`.
    private let isSyncInProgress: () -> Bool

    init(
        db: DBHelper = .shared,
        transactionRepo: TransactionRepository? = nil,
        batchRepo: ImportBatchRepository? = nil,
        currentUserId: @escaping () -> String? = { UIDUserDefaultsManager.shared.currentUserUID },
        isSyncInProgress: @escaping () -> Bool = { SyncEngine.shared.isSyncInProgress }
    ) {
        self.db = db
        self.transactionRepo = transactionRepo ?? TransactionRepository(db: db)
        self.batchRepo = batchRepo ?? ImportBatchRepository(db: db, currentUserId: currentUserId)
        self.currentUserId = currentUserId
        self.isSyncInProgress = isSyncInProgress
    }

    /// Writes the batch and returns its final record.
    ///
    /// `progress` is called once per committed chunk — roughly ten times for a thousand rows, which
    /// is the right granularity for a progress bar and the wrong granularity for a spinner. It is
    /// called on whatever queue `apply` was called on; marshalling to main is the caller's job.
    @discardableResult
    func apply(
        _ request: ImportApplyRequest,
        isCancelled: () -> Bool = { false },
        progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) throws -> ImportBatch {
        guard request.rows.count <= Self.maxRowsPerBatch else {
            throw ImportApplyError.tooManyRows(count: request.rows.count, limit: Self.maxRowsPerBatch)
        }

        // Step 1: the batch record, committed alone, before anything else exists.
        var batch = ImportBatch(
            userId: currentUserId(),
            sourceFilename: request.sourceFilename,
            fileHash: request.fileHash,
            fileByteCount: request.fileByteCount,
            bankPresetId: request.bankPresetId,
            columnMapping: request.columnMapping,
            rowsInFile: request.rowsInFile,
            rowsSelected: request.rows.count,
            rowsSkipped: request.rowsSkipped,
            rowsFailed: request.rowsFailed,
            amountTotal: Self.signedTotal(of: request.rows),
            dateMin: Self.earliestDate(in: request.rows),
            dateMax: Self.latestDate(in: request.rows),
            status: .preparing
        )
        batch = try batchRepo.create(batch)

        if request.rows.count >= Self.snapshotThreshold {
            db.snapshotDatabase(tag: "pre-import")
        }

        // Step 2: mark it in flight. This is the marker a crash leaves behind.
        let appliedAt = Date()
        batch.appliedAt = appliedAt
        batch.status = .applying
        try batchRepo.update(batch)

        // Step 3: the rows.
        let outcome: TransactionRepository.ImportInsertOutcome
        do {
            outcome = try transactionRepo.insertImportedBatch(
                request.rows.map(\.model),
                batchUuid: batch.uuid,
                appliedAt: appliedAt,
                isCancelled: isCancelled,
                progress: progress
            )
        } catch {
            batch.status = .failed
            batch.finishedAt = Date()
            batch.notes = "Apply failed: \(error)"
            try? batchRepo.update(batch)
            throw error
        }

        // Durable membership, recorded only once the rows have committed. This outlives a hard
        // delete of the transactions, which is what makes a resurrected row recognisable later.
        let membership = zip(outcome.inserted, request.rows).map { inserted, row in
            ImportBatchRow(
                batchUuid: batch.uuid,
                transactionUuid: inserted.uuid,
                sourceLine: row.sourceLine,
                rowFingerprint: row.fingerprint
            )
        }
        try? batchRepo.recordRows(membership)

        // Step 4: settle.
        batch.rowsInserted = outcome.inserted.count
        batch.finishedAt = Date()
        batch.status = outcome.cancelled ? .cancelling : .applied
        try batchRepo.update(batch)

        // A cancel is just an immediate undo — one code path, one set of edge cases, one test
        // surface. Everything already committed goes back out the way any rollback would.
        if outcome.cancelled {
            _ = ImportRollbackService(
                db: db, transactionRepo: transactionRepo, batchRepo: batchRepo,
                isSyncInProgress: isSyncInProgress
            ).rollback(batchUuid: batch.uuid, policy: .removeEdited)
            batch = batchRepo.fetch(uuid: batch.uuid) ?? batch
            batch.status = .cancelled
            try? batchRepo.update(batch)
        }

        NotificationCenter.default.post(name: .importBatchesDidChange, object: nil)
        return batch
    }

    // MARK: - Summary helpers

    /// Signed total in cents. The stored `amount` is always a positive magnitude and direction lives
    /// in `type`, so the sign has to be reapplied here — the same thing every reader in
    /// `TransactionLedgerService` does.
    private static func signedTotal(of rows: [ImportableRow]) -> Int {
        rows.reduce(0) { sum, row in
            let amount = row.model.data.amount
            return sum + (row.model.data.type == TransactionType.income.key ? amount : -amount)
        }
    }

    private static func earliestDate(in rows: [ImportableRow]) -> Date? {
        rows.map(\.model.data.dateTimestamp).min().map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private static func latestDate(in rows: [ImportableRow]) -> Date? {
        rows.map(\.model.data.dateTimestamp).max().map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
