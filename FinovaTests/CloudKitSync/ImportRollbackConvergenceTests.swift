//
//  ImportRollbackConvergenceTests.swift
//  FinovaTests
//
//  Import and undo, across two devices.
//
//  The property under test is that a rollback is an ORDINARY delete as far as sync is concerned. It
//  needs no special case in the delete-vs-edit policy, no new conflict rule, and nothing on the wire
//  — which is what lets the batch record stay local.
//

import XCTest

@testable import Finova

final class ImportRollbackConvergenceTests: XCTestCase {

    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!
    private var userUID: String!

    override func setUp() {
        super.setUp()
        // The repository cache is static and keyed only on the user uid, not on the
        // DBHelper instance — so whatever ran before in this process can still be sitting
        // in it. Clearing on the way IN as well as out makes these suites independent of
        // execution order.
        TransactionRepository.invalidateCache()
        userUID = "test_import_conv_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        deviceA = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "A")
        deviceB = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "B")
    }

    override func tearDown() {
        deviceA?.cleanup()
        deviceB?.cleanup()
        mockCloud?.reset()
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func importOnA(_ count: Int) throws -> ImportBatch {
        deviceA.activate()
        let batchRepo = ImportBatchRepository(db: deviceA.db, currentUserId: { [userUID] in userUID })
        let service = ImportApplyService(
            db: deviceA.db, transactionRepo: deviceA.transactionRepo,
            batchRepo: batchRepo, currentUserId: { [userUID] in userUID },
            isSyncInProgress: { false })

        let rows = (0..<count).map { index in
            ImportableRow(
                model: CloudKitSyncTestHelpers.makeTransactionModel(
                    title: "Imported \(index)", amount: 1_000 + index),
                fingerprint: "fp-\(index)",
                sourceLine: index + 2)
        }
        return try service.apply(ImportApplyRequest(
            sourceFilename: "extrato.csv", fileHash: "sha-extrato", fileByteCount: 100,
            bankPresetId: nil, columnMapping: "{}", rowsInFile: count,
            rowsSkipped: 0, rowsFailed: 0, rows: rows))
    }

    private func rollbackOnA(_ batchUuid: String) -> ImportRollbackOutcome {
        deviceA.activate()
        let batchRepo = ImportBatchRepository(db: deviceA.db, currentUserId: { [userUID] in userUID })
        return ImportRollbackService(
            db: deviceA.db, transactionRepo: deviceA.transactionRepo,
            batchRepo: batchRepo, isSyncInProgress: { false }
        ).rollback(batchUuid: batchUuid)
    }

    private func liveCount(on device: DeviceSimulator) -> Int {
        device.activate()
        return device.transactionRepo.fetchAllTransactions().count
    }

    // MARK: - The main convergence cycle

    func testImportOnAThenRollbackOnAConvergesOnB() throws {
        let batch = try importOnA(40)
        XCTAssertEqual(liveCount(on: deviceA), 40)

        deviceA.activate(); deviceA.pushAll()
        deviceB.activate(); deviceB.pullAll()
        XCTAssertEqual(liveCount(on: deviceB), 40, "B receives the imported transactions")
        XCTAssertEqual(deviceA.dataFingerprint(), deviceB.dataFingerprint())

        // The cloud-agnostic assertion: the ledger is empty on A BEFORE anything is pushed.
        guard case .completed(let report) = rollbackOnA(batch.uuid) else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(report.totalRemoved, 40)
        XCTAssertEqual(liveCount(on: deviceA), 0, "undo takes effect locally, with no network")

        deviceA.activate(); deviceA.pushTransactionDeletes()
        deviceB.activate(); deviceB.pullTransactionDeletes()
        XCTAssertEqual(liveCount(on: deviceB), 0)
        XCTAssertEqual(deviceA.dataFingerprint(), deviceB.dataFingerprint())

        // Nothing resurrects on a subsequent full pull on either side.
        deviceA.activate(); deviceA.pullAll()
        deviceB.activate(); deviceB.pullAll()
        XCTAssertEqual(liveCount(on: deviceA), 0)
        XCTAssertEqual(liveCount(on: deviceB), 0)
        XCTAssertEqual(deviceA.dataFingerprint(), deviceB.dataFingerprint())
    }

    /// Imported rows are hard-deleted when they were never pushed, so no permanent tombstone is left
    /// behind — the `parent_transaction_id IS NOT NULL` branch of `hardDeleteLocal` must not apply.
    func testRolledBackRowsLeaveNoTombstone() throws {
        let batch = try importOnA(10)
        deviceA.activate(); deviceA.pushAll()

        guard case .completed = rollbackOnA(batch.uuid) else { return XCTFail("expected .completed") }
        deviceA.activate(); deviceA.pushTransactionDeletes()

        let remaining = deviceA.db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE import_batch_uuid = ?;", textBinding: batch.uuid)
        XCTAssertEqual(remaining, 0, "a one-off leaves no skeleton row behind")
    }

    // MARK: - The batch record stays put

    func testBatchMetadataDoesNotTravel() throws {
        let batch = try importOnA(12)
        deviceA.activate(); deviceA.pushAll()
        deviceB.activate(); deviceB.pullAll()

        XCTAssertEqual(
            deviceB.db.fetchSingleInt("SELECT COUNT(*) FROM ImportBatches;"), 0,
            "the batch record is local by design — see ImportBatch")
        XCTAssertEqual(
            deviceB.db.fetchSingleInt(
                "SELECT COUNT(*) FROM Transactions WHERE import_batch_uuid IS NOT NULL;"), 0,
            "the batch link must not be a CloudKit field")

        // A still knows, so undo remains available where the import happened.
        deviceA.activate()
        XCTAssertNotNil(
            ImportBatchRepository(db: deviceA.db, currentUserId: { [userUID] in userUID })
                .fetch(uuid: batch.uuid))
    }

    /// The most important convergence case: B edited a row and has not pushed, A rolls the import
    /// back. The existing "recreation wins" policy already covers this, and rollback needs no special
    /// case because it IS a delete.
    func testRollbackObeysRecreationWins() throws {
        let batch = try importOnA(3)
        deviceA.activate(); deviceA.pushAll()
        deviceB.activate(); deviceB.pullAll()
        XCTAssertEqual(liveCount(on: deviceB), 3)

        // B edits one row locally and does not push it yet.
        deviceB.activate()
        let target = try XCTUnwrap(deviceB.transactionRepo.fetchAllTransactions().first)
        try deviceB.transactionRepo.updateSingleTransactionOnly(
            id: try XCTUnwrap(target.id), title: "Edited on B", category: .meals,
            type: .expense, amount: 4_242, date: target.date)

        guard case .completed = rollbackOnA(batch.uuid) else { return XCTFail("expected .completed") }
        deviceA.activate(); deviceA.pushTransactionDeletes()

        deviceB.activate(); deviceB.pullTransactionDeletes()
        XCTAssertEqual(liveCount(on: deviceB), 1, "B's unpushed edit survives the remote delete")

        deviceB.activate(); deviceB.pushAll()
        deviceA.activate(); deviceA.pullAll()

        XCTAssertEqual(liveCount(on: deviceA), 1)
        XCTAssertEqual(liveCount(on: deviceB), 1)
        XCTAssertEqual(deviceA.dataFingerprint(), deviceB.dataFingerprint(),
                       "both devices agree on the surviving row")
    }

    /// A second device that has never imported anything must still be able to run the sweep safely.
    func testOrphanSweepIsHarmlessOnADeviceThatNeverImported() throws {
        try importOnA(5)
        deviceA.activate(); deviceA.pushAll()
        deviceB.activate(); deviceB.pullAll()

        XCTAssertEqual(ImportOrphanSweep.runIfNeeded(db: deviceB.db), 0)
        XCTAssertEqual(liveCount(on: deviceB), 5, "B's rows must not be touched")
    }
}
