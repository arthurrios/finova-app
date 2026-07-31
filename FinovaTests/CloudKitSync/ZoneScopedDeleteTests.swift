//
//  ZoneScopedDeleteTests.swift
//  FinovaTests
//
//  CloudKit record names are unique per ZONE, not globally. The same name legitimately exists in two
//  zones at once — that is the property Transparent Mode is built on, and the property a record
//  passes through whenever it moves between zones.
//
//  `processDeletedRecord` used to discard `recordID.zoneID` and delete by name alone, so a deletion
//  aimed at ONE copy destroyed the OTHER. This is not hypothetical: it emptied a real personal ledger.
//
//      MirrorTagRestore untagged 451 transactions (group → personal). The next push wrote each to the
//      private zone and correctly withdrew its old group-zone copy. The push side protected the local
//      row via `orphanDeleteNames`. But when that withdrawal came back on a later fetch, the row now
//      living in the private zone was deleted under the shared name.
//
//  The same shape applies to revoking Transparent Mode: deleting a projection from a group zone would
//  take the author's personal row with it.
//

import CloudKit
import XCTest

@testable import Finova

final class ZoneScopedDeleteTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!

    private let recordName = "transaction-SHARED-NAME"
    private let groupId = "grp-zone-delete"

    private var personalZone: CKRecordZone.ID { CloudKitManager.privateZoneID }
    private var groupZone: CKRecordZone.ID { MockCloudStore.groupZoneID("grp-zone-delete") }

    override func setUp() {
        super.setUp()
        userUID = "zonedel_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaZoneDel-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// A local row holding `recordName`, in the given scope.
    private func seedRow(scope: String?) {
        let repo = TransactionRepository(db: db)
        try? repo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Rent", amount: 250_000))
        guard let id = db.fetchSingleInt("SELECT id FROM Transactions WHERE title = 'Rent';") else {
            return XCTFail("setup: insert failed")
        }
        repo.setCKRecordId(for: id, ckRecordName: recordName)
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ? WHERE id = ?;",
            orderedBindings: [scope, id])
        TransactionRepository.invalidateCache()
    }

    private func applies(from zone: CKRecordZone.ID) -> Bool {
        SyncEngine.deletionTargetsLocalRow(
            recordID: CKRecord.ID(recordName: recordName, zoneID: zone),
            table: "Transactions", db: db)
    }

    // MARK: - The bug that emptied a restored ledger

    /// THE regression. The row was restored to personal; the deletion is the withdrawal of its old
    /// group-zone copy. Applying it destroys the row.
    func testAGroupZoneDeletionMustNotTouchARowThatIsNowPersonal() {
        seedRow(scope: nil)

        XCTAssertFalse(
            applies(from: groupZone),
            """
            A deletion from a GROUP zone was applied to a row that now lives in the PERSONAL zone. \
            They share a record name because names are unique per zone, not globally — but they are \
            different copies. This is what emptied 451 restored transactions.
            """
        )
    }

    /// The Transparent Mode case: revoking publication deletes the projection from the group zone.
    /// The author's personal row must be untouched — it is the original, not the copy.
    func testRevokingAProjectionMustNotDeleteTheAuthorsPersonalRow() {
        seedRow(scope: nil)

        XCTAssertFalse(
            applies(from: groupZone),
            "Withdrawing a projection must remove the projection, not the row it was a copy of"
        )
    }

    /// And the mirror image: a row that genuinely lives in a group must not be removed by a deletion
    /// from the personal zone — that would be the stale-copy cleanup eating the live record.
    func testAPersonalZoneDeletionMustNotTouchAGroupRow() {
        seedRow(scope: groupId)

        XCTAssertFalse(applies(from: personalZone))
    }

    // MARK: - Real deletions still apply

    func testAPersonalDeletionAppliesToAPersonalRow() {
        seedRow(scope: nil)

        XCTAssertTrue(
            applies(from: personalZone),
            "A genuine deletion must still delete — the guard must not block real ones"
        )
    }

    func testAGroupDeletionAppliesToARowInThatGroup() {
        seedRow(scope: groupId)

        XCTAssertTrue(applies(from: groupZone))
    }

    /// Two groups are two scopes. A deletion from one must not reach a row belonging to the other.
    func testADeletionFromAnotherGroupsZoneDoesNotApply() {
        seedRow(scope: groupId)

        XCTAssertFalse(applies(from: MockCloudStore.groupZoneID("some-other-group")))
    }

    /// With no local row there is nothing to protect, and the repositories are no-ops. Letting it
    /// through keeps the tombstone bookkeeping in `deleteFromCloud` reachable.
    func testADeletionForAnUnknownRecordIsAllowedThrough() {
        XCTAssertTrue(applies(from: personalZone))
        XCTAssertTrue(applies(from: groupZone))
    }

    /// An empty-string scope is the same thing as NULL everywhere else in the schema, so it must be
    /// treated as personal here too rather than as a group named "".
    func testEmptyStringScopeCountsAsPersonal() {
        seedRow(scope: "")

        XCTAssertTrue(applies(from: personalZone))
        XCTAssertFalse(applies(from: groupZone))
    }
}
