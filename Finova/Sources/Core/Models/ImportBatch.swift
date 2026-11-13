//
//  ImportBatch.swift
//  Finova
//
//  One CSV import, as a reversible unit.
//
//  An import writes hundreds of rows from a file the app did not author, so it needs to be undoable
//  as a set rather than row by row. `ImportBatch` is that set: it records what was imported, from
//  which file, under which column mapping, and — through `ImportBatchRows` — exactly which
//  transactions it created.
//
//  This record is LOCAL ONLY and never reaches CloudKit. The transactions it creates sync normally,
//  so a second device sees them appear and (after a rollback) disappear as ordinary changes; what it
//  does not see is the import itself. That is deliberate. If the batch synced, rollback correctness
//  on the second device would depend on both the batch record and all of its rows having arrived,
//  and arrival order is not guaranteed — a partially hydrated batch would offer an undo button that
//  silently under-deletes. Import history is therefore per-device, and does not survive a reinstall
//  and rehydrate.
//

import Foundation

/// Where a batch is in its lifecycle.
///
/// `applying` and `rollingBack` are the load-bearing cases: both are persisted BEFORE any row is
/// written and cleared AFTER the last one, so a batch found in either state at next launch was
/// interrupted by a crash and can be reconciled by recounting the rows actually present.
enum ImportBatchStatus: String, Codable, CaseIterable {
    /// The row exists; nothing has been written to `Transactions` yet.
    case preparing
    /// Writes are in progress. A batch left here was interrupted.
    case applying
    case applied
    case cancelling
    case cancelled
    /// The user asked to undo while a push was in flight. See `ImportRollbackService` — a row
    /// mid-push still reads `ck_record_id IS NULL`, so classifying it now would hard-delete a row
    /// that is about to exist in the cloud. The intent is persisted and executed after the sync
    /// settles.
    case rollbackDeferred
    /// Undo is in progress. A batch left here was interrupted.
    case rollingBack
    case rolledBack
    case failed

    /// States that mean a write was interrupted rather than completed, and need reconciling.
    static let interrupted: Set<ImportBatchStatus> = [.applying, .rollingBack, .cancelling]

    /// Whether the user can still undo this batch.
    var isRollbackable: Bool {
        switch self {
        case .applied, .failed: return true
        case .preparing, .applying, .cancelling, .cancelled,
             .rollbackDeferred, .rollingBack, .rolledBack: return false
        }
    }
}

/// One CSV import.
struct ImportBatch: Equatable {
    var id: Int?
    let uuid: String
    let userId: String?
    let createdAt: Date

    var appliedAt: Date?
    var finishedAt: Date?
    var rolledBackAt: Date?

    let sourceFilename: String
    /// SHA-256 of the raw file bytes. Powers the "you already imported this file" check, which is
    /// the cheapest defence against the most common real mistake.
    let fileHash: String
    let fileByteCount: Int

    let bankPresetId: String?
    /// The resolved column mapping, as JSON. Display and diagnostic data — never a query predicate,
    /// which is why it is stored as text rather than normalized into columns.
    let columnMapping: String

    var rowsInFile: Int
    var rowsSelected: Int
    var rowsInserted: Int
    var rowsSkipped: Int
    var rowsFailed: Int
    /// How many rows a rollback actually removed. Distinct from `rowsInserted`, because rows the
    /// user edited after the import are kept by default.
    var rowsRemoved: Int

    /// Signed total in cents, denormalized so the history list needs no join.
    var amountTotal: Int
    var dateMin: Date?
    var dateMax: Date?

    var status: ImportBatchStatus
    var schemaVersion: Int
    var notes: String?

    init(
        id: Int? = nil,
        uuid: String = UUID().uuidString,
        userId: String?,
        createdAt: Date = Date(),
        appliedAt: Date? = nil,
        finishedAt: Date? = nil,
        rolledBackAt: Date? = nil,
        sourceFilename: String,
        fileHash: String,
        fileByteCount: Int = 0,
        bankPresetId: String? = nil,
        columnMapping: String = "{}",
        rowsInFile: Int = 0,
        rowsSelected: Int = 0,
        rowsInserted: Int = 0,
        rowsSkipped: Int = 0,
        rowsFailed: Int = 0,
        rowsRemoved: Int = 0,
        amountTotal: Int = 0,
        dateMin: Date? = nil,
        dateMax: Date? = nil,
        status: ImportBatchStatus = .preparing,
        schemaVersion: Int = 1,
        notes: String? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.userId = userId
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.finishedAt = finishedAt
        self.rolledBackAt = rolledBackAt
        self.sourceFilename = sourceFilename
        self.fileHash = fileHash
        self.fileByteCount = fileByteCount
        self.bankPresetId = bankPresetId
        self.columnMapping = columnMapping
        self.rowsInFile = rowsInFile
        self.rowsSelected = rowsSelected
        self.rowsInserted = rowsInserted
        self.rowsSkipped = rowsSkipped
        self.rowsFailed = rowsFailed
        self.rowsRemoved = rowsRemoved
        self.amountTotal = amountTotal
        self.dateMin = dateMin
        self.dateMax = dateMax
        self.status = status
        self.schemaVersion = schemaVersion
        self.notes = notes
    }
}

/// A transaction this batch created.
///
/// Kept in its own table rather than inferred from `Transactions.import_batch_uuid` because it must
/// survive a HARD delete of the transaction. After a rollback removes a never-pushed row there is
/// no other record that the row was ever ours — and without that, a copy CloudKit later hands back
/// would be indistinguishable from a transaction the user created by hand.
struct ImportBatchRow: Equatable {
    let batchUuid: String
    let transactionUuid: String
    /// 1-based line in the source file, for "row 47 failed" messages.
    let sourceLine: Int?
    /// Stable v5 identity over (file hash, line, raw cells). Recognises a row across re-imports of
    /// the same file even if title-cleaning rules have changed since.
    let rowFingerprint: String
}

/// What a rollback actually did.
struct ImportRollbackReport: Equatable {
    /// Rows that were never pushed, and were physically deleted.
    var hardDeleted: Int = 0
    /// Rows that had reached CloudKit, and were tombstoned for a delete push.
    var softDeleted: Int = 0
    /// Rows already gone before the rollback ran — a second rollback, or the user deleting by hand.
    var alreadyGone: Int = 0
    /// Rows the user edited after importing. Kept by default: a later edit is newer intent than the
    /// import that created the row.
    var editedKept: Int = 0
    /// Edited rows removed anyway, because the user asked.
    var editedRemoved: Int = 0

    var totalRemoved: Int { hardDeleted + softDeleted + editedRemoved }
}

/// What to do about rows the user edited after importing them.
enum EditedRowPolicy {
    case keepEdited
    case removeEdited
}

/// The result of asking for a rollback.
enum ImportRollbackOutcome: Equatable {
    case completed(ImportRollbackReport)
    /// A push was in flight, so the undo was recorded and will run once the sync settles.
    case deferred
    case alreadyRolledBack(ImportRollbackReport)
    case notFound
}
