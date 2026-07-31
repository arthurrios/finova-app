//
//  DerivedIdentityConvergenceTests.swift
//  FinovaTests
//
//  Step 1 gave generated rows a derived uuid, so two devices materialising the same month compute the
//  same identity. That is necessary but NOT sufficient: every resolver matches on `ck_record_id`, and
//  a row generated locally has no record name until it is pushed. So when device A pushes its copy,
//  device B — holding the same logical row, with the same derived uuid, but no record name — fails to
//  match it and inserts a duplicate.
//
//  These tests cover the missing link: a local row must be recognised by its uuid and adopt the
//  inbound record's name. Without that, derived identity buys nothing at runtime and the content
//  matchers can never be removed.
//

import CloudKit
import XCTest

@testable import Finova

final class DerivedIdentityConvergenceTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!

    /// Stands in for a recurring series both devices know about.
    private let parentUuid = "SERIES-PARENT-UUID"
    private let month = 1_700_000_000

    override func setUp() {
        super.setUp()
        userUID = "derivedconv_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        deviceA = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "A")
        deviceB = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "B")
    }

    override func tearDown() {
        deviceA.cleanup()
        deviceB.cleanup()
        mockCloud.reset()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// Materialises the month's instance on `device`, exactly as lazy generation does: insert, then
    /// stamp the derived identity. Returns the local id.
    @discardableResult
    private func generateInstance(on device: DeviceSimulator, title: String = "Netflix") -> Int {
        device.activate()
        try? device.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: title, amount: 5490, budgetMonthDate: month)
        )
        guard let id = device.db.fetchSingleInt(
            "SELECT id FROM Transactions WHERE title = ?;", textBinding: title) else { return 0 }
        device.db.assignDeterministicUuid(
            table: "Transactions", localId: id,
            uuid: DeterministicIdentity.recurringInstance(parentUuid: parentUuid, monthDate: month))
        TransactionRepository.invalidateCache()
        return id
    }

    private func liveRowCount(_ device: DeviceSimulator) -> Int {
        device.db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? -1
    }

    // MARK: - The gap derived identity alone does not close

    /// The whole point of step 1, and the case that made the content matchers necessary.
    ///
    /// Both devices materialise March independently — neither has synced, so neither row has a record
    /// name — then A pushes and B pulls. B must recognise A's record as the row it already holds.
    func testSameMonthGeneratedOnBothDevicesConvergesToOneRow() {
        generateInstance(on: deviceA)
        generateInstance(on: deviceB)

        deviceA.pushAll()
        deviceB.pullAll()

        XCTAssertEqual(
            liveRowCount(deviceB), 1,
            """
            Device B inserted a DUPLICATE. Both rows carry the same derived uuid, so B is holding the \
            same logical row twice — it just could not tell, because resolution matches on \
            `ck_record_id` and B's own copy has none until it is pushed. A local row must be matched \
            by its uuid and adopt the inbound record's name.
            """
        )
    }

    /// And having converged, B's row must be linked to A's CloudKit record — not merely deduplicated
    /// locally. Otherwise B pushes its copy under a second record name and the duplicate reappears in
    /// the cloud instead of the database.
    func testConvergedRowAdoptsTheInboundRecordName() {
        generateInstance(on: deviceA)
        generateInstance(on: deviceB)

        deviceA.pushAll()
        let pushedName = mockCloud.fetchAll(recordType: "Transaction").first?.recordID.recordName
        XCTAssertNotNil(pushedName, "setup: A should have pushed a record")

        deviceB.pullAll()

        XCTAssertEqual(
            deviceB.db.fetchSingleString(
                "SELECT ck_record_id FROM Transactions WHERE title = 'Netflix';"),
            pushedName,
            "B's row must take on A's record name, or B pushes a second record for the same row"
        )
    }

    /// Having adopted the name, a second sync must have nothing to say. This is the property that
    /// distinguishes real convergence from a duplicate that happens to be hidden.
    func testNothingIsPendingAfterConverging() {
        generateInstance(on: deviceA)
        generateInstance(on: deviceB)

        deviceA.pushAll()
        deviceB.pullAll()
        deviceB.pushAll()
        deviceA.pullAll()

        deviceA.activate()
        XCTAssertEqual(liveRowCount(deviceA), 1, "A must not gain a second copy either")
        deviceB.activate()
        XCTAssertTrue(
            deviceB.transactionRepo.fetchPendingSync().isEmpty,
            "A converged row has nothing left to push"
        )
        XCTAssertEqual(deviceA.dataFingerprint(), deviceB.dataFingerprint(), "Devices must agree")
    }

    // MARK: - Tombstones

    /// A deleted occurrence must STAY deleted.
    ///
    /// `hardDeleteLocal` leaves recurring/installment instances as a tombstone —
    /// `is_deleted = 1, ck_record_id = NULL` — whose whole purpose is to stop lazy generation
    /// recreating a month the user deleted. That shape is also exactly what uuid adoption looks for,
    /// so the adoption resurrected them: deleted occurrences reappeared as ghosts.
    func testATombstoneDoesNotAdoptAnInboundRecordName() {
        deviceA.activate()
        let id = generateInstance(on: deviceA, title: "DeletedMonth")

        // Exactly what hardDeleteLocal leaves for an instance.
        try? deviceA.db.executeGroupWriteChecked(
            """
            UPDATE Transactions SET is_deleted = 1, sync_status = 'synced', ck_record_id = NULL
             WHERE id = ?;
            """,
            orderedBindings: [id])
        TransactionRepository.invalidateCache()

        let adopted = deviceA.db.adoptCKRecordName(
            table: "Transactions",
            uuid: DeterministicIdentity.recurringInstance(parentUuid: parentUuid, monthDate: month),
            ckRecordName: "transaction-INBOUND-COPY")

        XCTAssertFalse(
            adopted,
            """
            A tombstone adopted an inbound record name. It shares the uuid and has a NULL             ck_record_id — the exact shape adoption matches — so the occurrence the user deleted             comes back as a ghost.
            """
        )
        XCTAssertEqual(
            deviceA.db.fetchSingleInt(
                "SELECT is_deleted FROM Transactions WHERE id = ?;", intBinding: id),
            1,
            "and it must remain a tombstone"
        )
    }

    // MARK: - Blast radius

    /// Genuinely different rows must stay different. Two distinct purchases that happen to share a
    /// title and amount are exactly what content matching used to merge, so uuid matching must not
    /// reintroduce that by being too eager.
    func testDistinctRowsWithIdenticalContentStaySeparate() {
        deviceA.activate()
        for _ in 0..<2 {
            try? deviceA.transactionRepo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(
                    title: "Coffee", amount: 1200, budgetMonthDate: month))
        }
        TransactionRepository.invalidateCache()
        XCTAssertEqual(liveRowCount(deviceA), 2, "setup: two distinct coffees")

        deviceA.pushAll()
        deviceB.pullAll()

        XCTAssertEqual(
            liveRowCount(deviceB), 2,
            "Two separate purchases with the same title, amount and month are two records — merging "
                + "them is the defect content matching caused"
        )
    }
}
