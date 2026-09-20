//
//  ImportRollbackTests.swift
//  FinovaTests
//
//  Undo. The property under test throughout is that it is correct on LOCAL state alone — offline,
//  unhydrated, sync disabled.
//

import XCTest

@testable import Finova

final class ImportRollbackTests: XCTestCase {

    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private var txRepo: TransactionRepository!
    private var batchRepo: ImportBatchRepository!
    private var applyService: ImportApplyService!
    /// `syncFullPullVerified_v2` is global UserDefaults state that the whole sync layer reads.
    /// One test flips it, so its prior value is captured and put back — clearing it instead
    /// would leave the flag absent for every suite that runs afterwards.
    private var originalHydrationFlag: Any?

    override func setUp() {
        super.setUp()
        // The repository cache is static and keyed only on the user uid, not on the
        // DBHelper instance — so whatever ran before in this process can still be sitting
        // in it. Clearing on the way IN as well as out makes these suites independent of
        // execution order.
        TransactionRepository.invalidateCache()
        originalHydrationFlag = UserDefaults.standard.object(forKey: "syncFullPullVerified_v2")
        userUID = "test_rollback_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaRollback-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        txRepo = TransactionRepository(db: db)
        batchRepo = ImportBatchRepository(db: db, currentUserId: { [userUID] in userUID })
        applyService = ImportApplyService(
            db: db, transactionRepo: txRepo, batchRepo: batchRepo,
            currentUserId: { [userUID] in userUID }, isSyncInProgress: { false })
    }

    override func tearDown() {
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        if let originalHydrationFlag {
            UserDefaults.standard.set(originalHydrationFlag, forKey: "syncFullPullVerified_v2")
        } else {
            UserDefaults.standard.removeObject(forKey: "syncFullPullVerified_v2")
        }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func rollbackService(syncInProgress: Bool = false) -> ImportRollbackService {
        ImportRollbackService(
            db: db, transactionRepo: txRepo, batchRepo: batchRepo,
            isSyncInProgress: { syncInProgress })
    }

    @discardableResult
    private func applyBatch(_ count: Int, filename: String = "extrato.csv") throws -> ImportBatch {
        let rows = (0..<count).map { i in
            ImportableRow(
                model: CloudKitSyncTestHelpers.makeTransactionModel(title: "Row \(i)", amount: 1000 + i),
                fingerprint: "fp-\(filename)-\(i)",
                sourceLine: i + 2)
        }
        return try applyService.apply(ImportApplyRequest(
            sourceFilename: filename, fileHash: "sha-\(filename)", fileByteCount: 100,
            bankPresetId: nil, columnMapping: "{}", rowsInFile: count,
            rowsSkipped: 0, rowsFailed: 0, rows: rows))
    }

    private func liveCount(_ batchUuid: String) -> Int {
        db.liveTransactionCount(importBatchUuid: batchUuid)
    }

    /// Gives the first `count` rows of the batch a CloudKit record name, as a successful push would.
    private func markAsPushed(_ batchUuid: String, count: Int) {
        let ids = db.fetchImportedRowStates(importBatchUuid: batchUuid).prefix(count).map(\.id)
        for id in ids {
            txRepo.setCKRecordId(for: id, ckRecordName: "transaction-\(UUID().uuidString)")
        }
    }

    /// Edits a row the way a user would, and forces `updated_at` to a LATER second.
    ///
    /// Both timestamps are whole seconds, and a test applies and edits within the same one — so
    /// without this the edited row still compares equal to the batch's `applied_at` and reads as
    /// untouched. Real usage cannot hit this (a person has to open the row first), but the test must
    /// not depend on wall-clock luck.
    private func editByHand(_ id: Int) {
        try? txRepo.updateSingleTransactionOnly(
            id: id, title: "Edited by hand", category: .meals, type: .expense,
            amount: 9999, date: Date())
        db.executeSyncUpdate(
            "UPDATE Transactions SET updated_at = updated_at + 60 WHERE id = ?;",
            intBindings: [id])
    }

    // MARK: - Classification

    func testNeverPushedRowsAreHardDeleted() throws {
        let batch = try applyBatch(20)
        let outcome = rollbackService().rollback(batchUuid: batch.uuid)

        guard case .completed(let report) = outcome else { return XCTFail("expected .completed") }
        XCTAssertEqual(report.hardDeleted, 20)
        XCTAssertEqual(report.softDeleted, 0)

        // Physically gone, not tombstoned — nothing to push a delete for, so a tombstone would be
        // inert and would linger forever.
        XCTAssertEqual(
            db.fetchSingleInt("SELECT COUNT(*) FROM Transactions WHERE import_batch_uuid = ?;",
                              textBinding: batch.uuid), 0)
    }

    func testPushedRowsAreTombstonedForADeletePush() throws {
        let batch = try applyBatch(20)
        markAsPushed(batch.uuid, count: 20)

        let outcome = rollbackService().rollback(batchUuid: batch.uuid)
        guard case .completed(let report) = outcome else { return XCTFail("expected .completed") }
        XCTAssertEqual(report.softDeleted, 20)
        XCTAssertEqual(report.hardDeleted, 0)

        XCTAssertEqual(liveCount(batch.uuid), 0, "gone from every read path")
        XCTAssertEqual(db.fetchSingleInt("""
            SELECT COUNT(*) FROM Transactions
             WHERE import_batch_uuid = ? AND is_deleted = 1 AND sync_status = 'pendingDelete'
               AND ck_record_id IS NOT NULL;
            """, textBinding: batch.uuid), 20, "the record name must survive so the delete can be pushed")
        XCTAssertEqual(txRepo.fetchPendingDeletes().count, 20)
    }

    func testMixedBatchTakesBothPathsAtOnce() throws {
        let batch = try applyBatch(10)
        markAsPushed(batch.uuid, count: 4)

        guard case .completed(let report) = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(report.softDeleted, 4)
        XCTAssertEqual(report.hardDeleted, 6)
        XCTAssertEqual(report.totalRemoved, 10)
        XCTAssertEqual(liveCount(batch.uuid), 0)
    }

    // MARK: - The cloud-agnostic guarantee

    /// The direct test of the requirement. `syncFullPullVerified_v2` gates the DELETE PUSH inside
    /// `SyncEngine.pushLocalChanges`, never the local write — so an undo on an unhydrated device must
    /// still empty the ledger immediately.
    func testRollbackTakesFullLocalEffectWhenSyncIsUnhydrated() throws {
        UserDefaults.standard.set(false, forKey: "syncFullPullVerified_v2")

        let batch = try applyBatch(15)
        markAsPushed(batch.uuid, count: 15)
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 15)

        guard case .completed = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }

        XCTAssertEqual(liveCount(batch.uuid), 0)
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 0)
        XCTAssertTrue(txRepo.fetchTransactions().isEmpty)
    }

    // MARK: - Idempotence

    func testDoubleRollbackChangesNothing() throws {
        let batch = try applyBatch(12)
        markAsPushed(batch.uuid, count: 6)

        guard case .completed(let first) = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(first.totalRemoved, 12)

        let second = rollbackService().rollback(batchUuid: batch.uuid)
        guard case .alreadyRolledBack = second else {
            return XCTFail("expected .alreadyRolledBack, got \(second)")
        }

        let stored = try XCTUnwrap(batchRepo.fetch(uuid: batch.uuid))
        XCTAssertEqual(stored.rowsRemoved, 12, "the second pass must not double-count")
        XCTAssertEqual(liveCount(batch.uuid), 0)
    }

    /// The second, independent reason a repeat is safe: even with the status guard bypassed, rows
    /// already soft-deleted fall into the "already gone" class and rows hard-deleted are simply not
    /// there.
    func testRollbackIsIdempotentEvenWithoutTheStatusGuard() throws {
        let batch = try applyBatch(8)
        markAsPushed(batch.uuid, count: 8)
        guard case .completed = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }

        // Force the guard open and run it again.
        var reopened = try XCTUnwrap(batchRepo.fetch(uuid: batch.uuid))
        reopened.status = .applied
        try batchRepo.update(reopened)

        guard case .completed(let report) = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(report.alreadyGone, 8)
        XCTAssertEqual(report.totalRemoved, 0)
    }

    func testRollbackOfAnUnknownBatchIsNotFound() {
        XCTAssertEqual(rollbackService().rollback(batchUuid: "nope"), .notFound)
    }

    // MARK: - Rows the user edited afterwards

    func testEditedRowsAreKeptByDefault() throws {
        let batch = try applyBatch(10)
        let states = db.fetchImportedRowStates(importBatchUuid: batch.uuid)
        let victim = try XCTUnwrap(states.first)

        // An ordinary local edit, which bumps updated_at away from the batch's applied_at.
        editByHand(victim.id)

        guard case .completed(let report) = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(report.editedKept, 1)
        XCTAssertEqual(report.totalRemoved, 9)
        XCTAssertEqual(liveCount(batch.uuid), 1, "the user's later edit is newer intent than the import")
    }

    func testEditedRowsAreRemovedWhenAsked() throws {
        let batch = try applyBatch(10)
        let victim = try XCTUnwrap(db.fetchImportedRowStates(importBatchUuid: batch.uuid).first)
        editByHand(victim.id)

        guard case .completed(let report) = rollbackService()
            .rollback(batchUuid: batch.uuid, policy: .removeEdited) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(report.editedRemoved, 1)
        XCTAssertEqual(report.totalRemoved, 10)
        XCTAssertEqual(liveCount(batch.uuid), 0)
    }

    /// Merely pushing a row must not look like an edit. `markAsSynced` deliberately leaves
    /// `updated_at` alone, which is the whole reason it is the right sentinel and `rev` is not.
    func testPushingARowDoesNotMakeItLookEdited() throws {
        let batch = try applyBatch(6)
        markAsPushed(batch.uuid, count: 6)
        for name in db.fetchAllCKRecordNames(table: "Transactions") {
            txRepo.markAsSynced(ckRecordName: name, pushedUpdatedAt: Date())
        }

        guard case .completed(let report) = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(report.editedKept, 0, "a push is not an edit")
        XCTAssertEqual(report.totalRemoved, 6)
    }

    func testRowsTheUserAlreadyDeletedAreCountedNotReprocessed() throws {
        let batch = try applyBatch(9)
        let doomed = db.fetchImportedRowStates(importBatchUuid: batch.uuid).prefix(3).map(\.id)
        try txRepo.deleteBatch(ids: Array(doomed))

        guard case .completed(let report) = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        // Never-pushed rows are hard-deleted, so the user's own delete removed them outright and
        // there is nothing left to classify.
        XCTAssertEqual(report.hardDeleted, 6)
        XCTAssertEqual(liveCount(batch.uuid), 0)
    }

    // MARK: - Deferral while a push is in flight

    /// A row mid-push still reads `ck_record_id IS NULL`, because `SyncEngine` assigns the record
    /// name only in the per-record success callback. Hard-deleting it there would orphan the cloud
    /// copy, which then returns on the next full pull as an untracked transaction.
    func testRollbackIsDeferredWhileASyncIsInFlight() throws {
        let batch = try applyBatch(10)

        XCTAssertEqual(rollbackService(syncInProgress: true).rollback(batchUuid: batch.uuid), .deferred)
        XCTAssertEqual(batchRepo.fetch(uuid: batch.uuid)?.status, .rollbackDeferred)
        XCTAssertEqual(liveCount(batch.uuid), 10, "nothing may be removed while the push is running")

        // Once the cycle settles, the persisted intent is honoured.
        XCTAssertEqual(rollbackService(syncInProgress: false).runDeferredRollbacks(), 1)
        XCTAssertEqual(batchRepo.fetch(uuid: batch.uuid)?.status, .rolledBack)
        XCTAssertEqual(liveCount(batch.uuid), 0)
    }

    func testRunDeferredRollbacksIsANoOpWithNothingPending() throws {
        _ = try applyBatch(4)
        XCTAssertEqual(rollbackService().runDeferredRollbacks(), 0)
    }

    // MARK: - The resurrection sweep

    func testMembershipSurvivesAHardDelete() throws {
        let batch = try applyBatch(11)
        guard case .completed = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }

        // The transactions are physically gone, but the batch still knows which uuids were its own —
        // which is the only thing that makes a returning row recognisable.
        XCTAssertEqual(
            db.fetchSingleInt("SELECT COUNT(*) FROM ImportBatchRows WHERE batch_uuid = ?;",
                              textBinding: batch.uuid), 11)
    }

    func testOrphanSweepRemovesAResurrectedRow() throws {
        let batch = try applyBatch(5)
        let uuids = db.fetchImportedRowStates(importBatchUuid: batch.uuid).compactMap(\.uuid)
        guard case .completed = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 0)

        // Simulate a pull handing back a row whose delete never reached the cloud.
        let resurrected = try XCTUnwrap(uuids.first)
        let localId = try db.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Back from the dead", amount: 1000))
        db.executeSyncUpdate("UPDATE Transactions SET uuid = ? WHERE id = ?;",
                             textBindings: [resurrected], intBindings: [localId])
        // Written straight through `db`, bypassing the repository that would normally invalidate its
        // static cache — so the cache still holds the post-rollback empty ledger until told otherwise.
        TransactionRepository.invalidateCache()
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 1)

        XCTAssertEqual(ImportOrphanSweep.runIfNeeded(db: db), 1)
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 0)
    }

    func testOrphanSweepIsANoOpWithNoRolledBackBatch() throws {
        _ = try applyBatch(5)
        XCTAssertEqual(ImportOrphanSweep.runIfNeeded(db: db), 0)
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 5)
    }

    // MARK: - Fingerprints

    func testRolledBackRowsStopCountingAsAlreadyImported() throws {
        let batch = try applyBatch(7)
        XCTAssertEqual(batchRepo.importedRowFingerprints().count, 7)

        guard case .completed = rollbackService().rollback(batchUuid: batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertTrue(batchRepo.importedRowFingerprints().isEmpty,
                      "re-importing rows you undid is a change of mind, not a duplicate")
    }
}
