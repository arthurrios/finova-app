//
//  ImportPersistenceTests.swift
//  FinovaTests
//
//  The apply half of CSV import: schema, batch records, and the bulk write.
//

import XCTest

@testable import Finova

final class ImportPersistenceTests: XCTestCase {

    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private var txRepo: TransactionRepository!
    private var batchRepo: ImportBatchRepository!
    private var applyService: ImportApplyService!

    override func setUp() {
        super.setUp()
        // The repository cache is static and keyed only on the user uid, not on the
        // DBHelper instance — so whatever ran before in this process can still be sitting
        // in it. Clearing on the way IN as well as out makes these suites independent of
        // execution order.
        TransactionRepository.invalidateCache()
        userUID = "test_import_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaImport-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        txRepo = TransactionRepository(db: db)
        batchRepo = ImportBatchRepository(db: db, currentUserId: { [userUID] in userUID })
        applyService = ImportApplyService(
            db: db, transactionRepo: txRepo, batchRepo: batchRepo,
            currentUserId: { [userUID] in userUID }, isSyncInProgress: { false })
    }

    override func tearDown() {
        // Mandatory: the cache is static, so DB isolation alone does not stop it leaking between tests.
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        // The WAL and SHM have to go too, or the next run inherits uncheckpointed commits.
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRows(_ count: Int, titlePrefix: String = "Row") -> [ImportableRow] {
        (0..<count).map { i in
            ImportableRow(
                model: CloudKitSyncTestHelpers.makeTransactionModel(
                    title: "\(titlePrefix) \(i)", amount: 1000 + i),
                fingerprint: "fp-\(titlePrefix)-\(i)",
                sourceLine: i + 2
            )
        }
    }

    private func makeRequest(rows: [ImportableRow], filename: String = "extrato.csv") -> ImportApplyRequest {
        ImportApplyRequest(
            sourceFilename: filename,
            fileHash: "sha-\(filename)",
            fileByteCount: 1234,
            bankPresetId: nil,
            columnMapping: #"{"date":0,"description":1,"amount":2}"#,
            rowsInFile: rows.count + 2,
            rowsSkipped: 1,
            rowsFailed: 1,
            rows: rows
        )
    }

    private func liveRowCount(batchUuid: String) -> Int {
        db.liveTransactionCount(importBatchUuid: batchUuid)
    }

    // MARK: - Migration and invariants

    func testMigrationIsIdempotentAcrossTwoOpens() {
        // A second DBHelper on the same file re-runs initializeDatabase in full.
        let second = DBHelper(path: dbPath)
        XCTAssertNotNil(second)

        XCTAssertEqual(
            db.fetchSingleInt(
                "SELECT COUNT(*) FROM pragma_table_info('Transactions') WHERE name = 'import_batch_uuid';"),
            1, "import_batch_uuid must be added exactly once")

        let version = db.fetchSingleInt("PRAGMA user_version;")
        XCTAssertEqual(version, 5, "schema should have settled at user_version 5")
    }

    func testImportTablesAreNotSyncable() {
        XCTAssertFalse(DBHelper.syncableTablesV1.contains("ImportBatches"))
        XCTAssertFalse(DBHelper.syncableTablesV1.contains("ImportBatchRows"))

        // No uuid backstop trigger should have been attached to them — if one had, the generic
        // identity machinery would treat them as records to be pushed.
        XCTAssertEqual(
            db.fetchSingleInt("""
                SELECT COUNT(*) FROM sqlite_master
                 WHERE type = 'trigger' AND lower(tbl_name) LIKE 'importbatch%';
                """),
            0, "the import tables must carry none of the syncable-table machinery")
    }

    /// The cheapest possible guard against reintroducing a full-app sync outage. An `import`-prefixed
    /// field that production CloudKit does not have makes the server reject the whole record and
    /// abandon every remaining batch.
    func testTransactionCKRecordCarriesNoImportField() throws {
        let batch = try applyService.apply(makeRequest(rows: makeRows(1)))
        let tx = try XCTUnwrap(txRepo.fetchAllTransactions().first)
        let record = tx.toCKRecord(in: CloudKitManager.privateZoneID, storedRecordName: nil, db: db)

        XCTAssertFalse(
            record.allKeys().contains { $0.lowercased().contains("import") },
            "no import field may ever reach CloudKit — see CloudKitSchemaFlags")
        XCTAssertEqual(batch.status, .applied)
    }

    // MARK: - Apply

    func testApplyWritesEveryRowWithTheBatchContract() throws {
        let rows = makeRows(120)
        let batch = try applyService.apply(makeRequest(rows: rows))

        XCTAssertEqual(batch.status, .applied)
        XCTAssertEqual(batch.rowsInserted, 120)
        XCTAssertEqual(liveRowCount(batchUuid: batch.uuid), 120)

        let states = db.fetchImportedRowStates(importBatchUuid: batch.uuid)
        XCTAssertEqual(states.count, 120)

        // One identical updated_at across the whole batch. This is what makes "edited since import"
        // an exact equality test rather than a tolerance comparison.
        let stamps = Set(states.compactMap(\.updatedAt))
        XCTAssertEqual(stamps.count, 1, "every row must share the batch's applied_at")
        XCTAssertEqual(stamps.first, batch.appliedAt.map { Int($0.timeIntervalSince1970) })

        // Every row carries a uuid, and they are distinct.
        let uuids = states.compactMap(\.uuid)
        XCTAssertEqual(uuids.count, 120)
        XCTAssertEqual(Set(uuids).count, 120)

        // Personal ledger, plain one-offs, and enrolled for push.
        XCTAssertEqual(db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE import_batch_uuid = ? AND shared_group_id IS NULL;",
            textBinding: batch.uuid), 120)
        XCTAssertEqual(db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE import_batch_uuid = ? AND sync_status = 'pending';",
            textBinding: batch.uuid), 120)
        XCTAssertEqual(db.fetchSingleInt("""
            SELECT COUNT(*) FROM Transactions WHERE import_batch_uuid = ?
              AND parent_transaction_id IS NULL AND (is_recurring IS NULL OR is_recurring = 0)
              AND (has_installments IS NULL OR has_installments = 0);
            """, textBinding: batch.uuid), 120)
    }

    func testMembershipIsRecordedForEveryRow() throws {
        let batch = try applyService.apply(makeRequest(rows: makeRows(40)))
        XCTAssertEqual(db.fetchSingleInt(
            "SELECT COUNT(*) FROM ImportBatchRows WHERE batch_uuid = ?;", textBinding: batch.uuid), 40)
        XCTAssertEqual(batchRepo.importedRowFingerprints().count, 40)
    }

    func testProgressIsMonotonicAndReachesTheTotal() throws {
        var seen: [Int] = []
        _ = try applyService.apply(makeRequest(rows: makeRows(450))) { done, total in
            XCTAssertEqual(total, 450)
            seen.append(done)
        }
        XCTAssertFalse(seen.isEmpty)
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertEqual(seen.last, 450)
    }

    /// The regression guard for the decision not to reach for `SyncChangeTracker.isSuppressed`. It is
    /// a plain non-atomic Bool already written from the CloudKit callback queue; a third writer races,
    /// and a throw would strand it `true` and silently kill sync for the session.
    func testApplyLeavesSyncSuppressionUntouched() throws {
        XCTAssertFalse(SyncChangeTracker.shared.isSuppressed)
        _ = try applyService.apply(makeRequest(rows: makeRows(300)))
        XCTAssertFalse(SyncChangeTracker.shared.isSuppressed)
    }

    func testApplyPostsExactlyOneTransactionDataChanged() throws {
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: .transactionDataChanged, object: nil, queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try applyService.apply(makeRequest(rows: makeRows(500)))
        XCTAssertEqual(posts, 1, "500 rows must not mean 500 ledger refreshes")
    }

    func testApplyRejectsMoreRowsThanTheBatchLimit() {
        let rows = makeRows(ImportApplyService.maxRowsPerBatch + 1)
        XCTAssertThrowsError(try applyService.apply(makeRequest(rows: rows))) { error in
            guard case ImportApplyError.tooManyRows(let count, let limit) = error else {
                return XCTFail("expected .tooManyRows, got \(error)")
            }
            XCTAssertEqual(count, ImportApplyService.maxRowsPerBatch + 1)
            XCTAssertEqual(limit, ImportApplyService.maxRowsPerBatch)
        }
        XCTAssertTrue(batchRepo.history(limit: 10).isEmpty, "a rejected import must leave no batch behind")
    }

    func testCancelMidApplyRemovesWhatWasAlreadyWritten() throws {
        var chunksSeen = 0
        let batch = try applyService.apply(
            makeRequest(rows: makeRows(900)),
            isCancelled: {
                chunksSeen += 1
                return chunksSeen > 2   // let two chunks land, then stop
            })

        XCTAssertEqual(batch.status, .cancelled)
        XCTAssertEqual(liveRowCount(batchUuid: batch.uuid), 0,
                       "a cancel is an immediate undo — nothing may survive it")
        XCTAssertEqual(txRepo.fetchAllTransactions().count, 0)
    }

    // MARK: - Crash recovery

    func testInterruptedApplyIsReconciledByRecounting() throws {
        // Simulate a crash: a batch stuck in `applying` with rows already committed.
        var batch = ImportBatch(
            userId: userUID, appliedAt: Date(), sourceFilename: "crash.csv", fileHash: "sha-crash",
            status: .preparing)
        batch = try batchRepo.create(batch)
        batch.status = .applying
        try batchRepo.update(batch)

        _ = try txRepo.insertImportedBatch(
            makeRows(37).map(\.model), batchUuid: batch.uuid, appliedAt: batch.appliedAt!)

        let needingRollback = batchRepo.reconcileInterrupted()
        XCTAssertTrue(needingRollback.isEmpty, "an interrupted apply settles without a rollback")

        let recovered = try XCTUnwrap(batchRepo.fetch(uuid: batch.uuid))
        XCTAssertEqual(recovered.status, .applied)
        XCTAssertEqual(recovered.rowsInserted, 37)
        XCTAssertNotNil(recovered.finishedAt)
    }

    func testInterruptedRollbackIsReturnedForRetry() throws {
        var batch = ImportBatch(
            userId: userUID, appliedAt: Date(), sourceFilename: "crash.csv", fileHash: "sha-crash2",
            status: .preparing)
        batch = try batchRepo.create(batch)
        batch.status = .rollingBack
        try batchRepo.update(batch)

        let needingRollback = batchRepo.reconcileInterrupted()
        XCTAssertEqual(needingRollback.map(\.uuid), [batch.uuid])
    }

    // MARK: - History

    func testHistoryIsScopedToTheCurrentUser() throws {
        _ = try applyService.apply(makeRequest(rows: makeRows(3), filename: "mine.csv"))

        let otherRepo = ImportBatchRepository(db: db, currentUserId: { "someone_else" })
        _ = try otherRepo.create(ImportBatch(
            userId: "someone_else", sourceFilename: "theirs.csv", fileHash: "sha-theirs",
            status: .applied))

        XCTAssertEqual(batchRepo.history(limit: 50).map(\.sourceFilename), ["mine.csv"])
        XCTAssertEqual(otherRepo.history(limit: 50).map(\.sourceFilename), ["theirs.csv"])
    }

    func testPriorImportsOfTheSameFileAreFound() throws {
        let request = makeRequest(rows: makeRows(2), filename: "extrato-julho.csv")
        _ = try applyService.apply(request)

        let priors = batchRepo.priorImports(ofFileHash: request.fileHash)
        XCTAssertEqual(priors.count, 1)
        XCTAssertEqual(priors.first?.sourceFilename, "extrato-julho.csv")
        XCTAssertTrue(batchRepo.priorImports(ofFileHash: "sha-never-seen").isEmpty)
    }
}
