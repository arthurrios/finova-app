//
//  ProjectionStateTests.swift
//  FinovaTests
//
//  Transparent Mode publishes a personal row by writing a COPY of it into each group zone the
//  author publishes into. The copy reuses the personal record's name — CloudKit names are unique
//  per zone — which is what lets it need no identity of its own.
//
//  That sharing of names is also the sharpest edge in the design, and these tests guard it:
//
//  - `ck_system_fields` is a COLUMN on the record's own row, keyed by `ck_record_id` with NO zone.
//    A projection saving its system fields there would overwrite the personal record's, making
//    `lastSyncedZone` report the group zone; `staleZoneCopy` would then conclude the record had
//    moved and delete the personal copy. That is the Mirror Mode corruption, re-entering by a new
//    door. Projections therefore keep their sync state in `ProjectionSyncState`, keyed by zone.
//  - The stored zone set is what makes revoking transparency actually un-share a record: the push
//    path deletes projections whose zone is no longer published.
//
//  NOTE: the end-to-end fan-out (personal row → N group zones on a real push) is not covered here.
//  It runs inside `SyncEngine.pushLocalChanges`, which is gated behind a live Firebase user that no
//  test can currently produce — the same blocker that has 18 SyncEngineTests failing. Task #22
//  (injectable authentication) unblocks it. What is covered is every decision and every piece of
//  state that fan-out depends on.
//

import CloudKit
import XCTest

@testable import Finova

final class ProjectionStateTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private let groupId = "grp-projection"
    private var groupZone: CKRecordZone.ID { MockCloudStore.groupZoneID(groupId) }

    override func setUp() {
        super.setUp()
        userUID = "projection_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaProj-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// Inserts a transaction and returns (localId, ckRecordName).
    @discardableResult
    private func makePersonalTransaction(title: String = "Groceries") -> (Int, String) {
        let repo = TransactionRepository(db: db)
        try? repo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: title, amount: 4200)
        )
        guard let id = repo.fetchAllTransactions().first(where: { $0.title == title })?.id else {
            XCTFail("setup: transaction insert failed")
            return (0, "")
        }
        let name = "transaction-\(UUID().uuidString)"
        repo.setCKRecordId(for: id, ckRecordName: name)
        return (id, name)
    }

    private func fakeSystemFields(recordName: String, zoneID: CKRecordZone.ID) -> Data {
        let record = CKRecord(
            recordType: "Transaction",
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    // MARK: - Telling a projection from a group record

    /// A group-zone copy of a row that is still personal locally is a projection.
    func testGroupZoneCopyOfAPersonalRowIsAProjection() {
        let (_, name) = makePersonalTransaction()

        XCTAssertTrue(
            SyncEngine.isProjection(
                recordName: name, table: "Transactions", zoneID: groupZone, db: db
            ),
            "The local row is personal, so the group-zone copy can only be a published projection"
        )
    }

    /// A row the user genuinely moved into the group is a group record, not a projection — its
    /// system fields belong on the row, and it must not be treated as revocable.
    func testGroupZoneCopyOfAGroupTaggedRowIsNotAProjection() {
        let (id, name) = makePersonalTransaction(title: "GroupExpense")
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ? WHERE id = ?;",
            orderedBindings: [groupId, id]
        )

        XCTAssertFalse(
            SyncEngine.isProjection(
                recordName: name, table: "Transactions", zoneID: groupZone, db: db
            ),
            "A row tagged to this group owns its group-zone record — it is not a projection of it"
        )
    }

    /// A copy in a DIFFERENT group's zone is still a projection of a row tagged elsewhere: it is
    /// not that zone's own record, so it must never write to the row's system fields.
    func testCopyInAnotherGroupsZoneIsAProjection() {
        let (id, name) = makePersonalTransaction(title: "TaggedElsewhere")
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ? WHERE id = ?;",
            orderedBindings: ["some-other-group", id]
        )

        XCTAssertTrue(
            SyncEngine.isProjection(
                recordName: name, table: "Transactions", zoneID: groupZone, db: db
            )
        )
    }

    func testPrivateZoneCopyIsNeverAProjection() {
        let (_, name) = makePersonalTransaction()

        XCTAssertFalse(
            SyncEngine.isProjection(
                recordName: name, table: "Transactions",
                zoneID: CloudKitManager.privateZoneID, db: db
            ),
            "The personal zone holds the record itself — a projection only ever lives in a group zone"
        )
    }

    /// The projection-skip guard must NOT depend on authorship.
    ///
    /// It used to also require `createdByUid == currentUser.uid`, and that destroyed data the first
    /// time Transparent Mode was enabled on real data. Rows predating authorship tracking have
    /// `created_by_uid IS NULL`, the adapter then writes no `createdByUid` at all, the comparison
    /// fails, and the record is processed as an ordinary GROUP record — which re-tags the personal row
    /// and removes it from the personal ledger.
    ///
    /// Name plus scope is sufficient and stronger: record names are `<type>-<uuid>`, unique per record
    /// identity, so a group-zone record sharing a name with a local row of mine IS a copy of it.
    func testAProjectionIsRecognisedWithoutAnyAuthorship() {
        let (_, name) = makePersonalTransaction(title: "NoAuthor")
        // The state 822 of the reporter's rows were in.
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET created_by_uid = NULL WHERE ck_record_id = ?;",
            orderedBindings: [name])

        XCTAssertTrue(
            SyncEngine.isProjection(
                recordName: name, table: "Transactions", zoneID: groupZone, db: db),
            """
            A group-zone copy of a personal row was not recognised as a projection once authorship was             absent. The pull path then applies it as a group record, re-tagging the personal row — the             exact corruption Transparent Mode exists to avoid, and it reached a real ledger.
            """
        )
    }

    /// And the discrimination that must survive: a row genuinely moved INTO the group is not a
    /// projection, authorship or no authorship.
    func testARowMovedIntoTheGroupIsStillNotAProjectionWithoutAuthorship() {
        let (id, name) = makePersonalTransaction(title: "GenuinelyGrouped")
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ?, created_by_uid = NULL WHERE id = ?;",
            orderedBindings: [groupId, id])

        XCTAssertFalse(
            SyncEngine.isProjection(
                recordName: name, table: "Transactions", zoneID: groupZone, db: db),
            "Dropping the authorship condition must not make genuine group records look like copies"
        )
    }

    // MARK: - Sync state is kept apart

    /// The property that keeps the personal record safe: a projection's system fields and the
    /// record's own must be independently addressable, or saving one destroys the other.
    func testProjectionSystemFieldsDoNotDisturbTheRecordsOwn() {
        let (_, name) = makePersonalTransaction()
        let personal = fakeSystemFields(recordName: name, zoneID: CloudKitManager.privateZoneID)
        db.saveSystemFields(personal, ckRecordName: name, table: "Transactions")

        db.saveProjectionSystemFields(
            fakeSystemFields(recordName: name, zoneID: groupZone),
            recordName: name, zoneName: groupZone.zoneName, zoneOwner: groupZone.ownerName
        )

        XCTAssertEqual(
            db.fetchSystemFields(ckRecordName: name, table: "Transactions"), personal,
            """
            Saving a projection's system fields overwrote the personal record's. `lastSyncedZone` \
            would now report the group zone, `staleZoneCopy` would conclude the record had moved, \
            and the personal copy would be deleted from CloudKit.
            """
        )
    }

    func testProjectionSystemFieldsRoundTripPerZone() {
        let (_, name) = makePersonalTransaction()
        let zoneA = MockCloudStore.groupZoneID("grp-a")
        let zoneB = MockCloudStore.groupZoneID("grp-b")
        let fieldsA = fakeSystemFields(recordName: name, zoneID: zoneA)
        let fieldsB = fakeSystemFields(recordName: name, zoneID: zoneB)

        db.saveProjectionSystemFields(
            fieldsA, recordName: name, zoneName: zoneA.zoneName, zoneOwner: zoneA.ownerName)
        db.saveProjectionSystemFields(
            fieldsB, recordName: name, zoneName: zoneB.zoneName, zoneOwner: zoneB.ownerName)

        XCTAssertEqual(
            db.fetchProjectionSystemFields(recordName: name, zoneName: zoneA.zoneName), fieldsA,
            "Each zone's projection carries its own recordChangeTag and must be stored separately"
        )
        XCTAssertEqual(
            db.fetchProjectionSystemFields(recordName: name, zoneName: zoneB.zoneName), fieldsB
        )
    }

    func testResavingAProjectionUpdatesRatherThanDuplicating() {
        let (_, name) = makePersonalTransaction()
        let first = fakeSystemFields(recordName: name, zoneID: groupZone)
        db.saveProjectionSystemFields(
            first, recordName: name, zoneName: groupZone.zoneName, zoneOwner: groupZone.ownerName)

        let second = fakeSystemFields(recordName: "\(name)-changed", zoneID: groupZone)
        db.saveProjectionSystemFields(
            second, recordName: name, zoneName: groupZone.zoneName, zoneOwner: groupZone.ownerName)

        XCTAssertEqual(db.projectionZones(recordName: name).count, 1, "One row per (record, zone)")
        XCTAssertEqual(
            db.fetchProjectionSystemFields(recordName: name, zoneName: groupZone.zoneName), second,
            "The newest change tag must win — a stale one makes every later push fail as conflicted"
        )
    }

    // MARK: - Revocation

    /// The push path withdraws a projection by comparing the stored zones against the zones the
    /// author currently publishes to. Without an accurate stored set, turning transparency off
    /// would leave the record visible to the group forever.
    func testStoredZonesDriveRevocation() {
        let (_, name) = makePersonalTransaction()
        let zoneA = MockCloudStore.groupZoneID("grp-a")
        let zoneB = MockCloudStore.groupZoneID("grp-b")
        for zone in [zoneA, zoneB] {
            db.saveProjectionSystemFields(
                fakeSystemFields(recordName: name, zoneID: zone),
                recordName: name, zoneName: zone.zoneName, zoneOwner: zone.ownerName
            )
        }

        XCTAssertEqual(
            Set(db.projectionZones(recordName: name).map(\.zoneName)),
            [zoneA.zoneName, zoneB.zoneName]
        )

        // Transparency revoked for grp-a: the push path deletes that projection and forgets it.
        db.deleteProjectionState(recordName: name, zoneName: zoneA.zoneName)

        XCTAssertEqual(
            db.projectionZones(recordName: name).map(\.zoneName), [zoneB.zoneName],
            "A revoked zone must drop out of the set, or the engine keeps re-deleting it every sync"
        )
    }

    /// Leaving or deleting a group makes its zone unreachable. The projections into it must be
    /// forgotten wholesale, or every subsequent push retries a delete that cannot succeed.
    func testForgettingAZoneClearsEveryProjectionIntoIt() {
        let zone = MockCloudStore.groupZoneID("grp-gone")
        for i in 0..<3 {
            let name = "transaction-\(i)"
            db.saveProjectionSystemFields(
                fakeSystemFields(recordName: name, zoneID: zone),
                recordName: name, zoneName: zone.zoneName, zoneOwner: zone.ownerName
            )
        }

        db.deleteProjectionState(zoneName: zone.zoneName)

        for i in 0..<3 {
            XCTAssertTrue(
                db.projectionZones(recordName: "transaction-\(i)").isEmpty,
                "Every projection into a departed group's zone must be forgotten"
            )
        }
    }

    /// The zone owner is stored alongside, because it decides which database the delete goes to:
    /// a zone we own is in the private DB, someone else's is in the shared DB. Losing it would
    /// send the withdrawal to the wrong database, where it silently does nothing.
    func testZoneOwnerIsRetainedForDatabaseRouting() {
        let (_, name) = makePersonalTransaction()
        let memberZone = CKRecordZone.ID(zoneName: "Group-owned-elsewhere", ownerName: "_otherUser")
        db.saveProjectionSystemFields(
            fakeSystemFields(recordName: name, zoneID: memberZone),
            recordName: name, zoneName: memberZone.zoneName, zoneOwner: memberZone.ownerName
        )

        XCTAssertEqual(db.projectionZones(recordName: name).first?.zoneOwner, "_otherUser")
    }

    // MARK: - Harness

    /// The mock cloud was keyed by record name alone, which collapsed a projection onto the record
    /// it is a copy of — the two share a name by design. No projection test can mean anything until
    /// the store can hold both.
    func testMockCloudKeepsSameNamedRecordsInDifferentZonesApart() {
        let cloud = MockCloudStore()
        let name = "transaction-shared-name"
        let personalID = CKRecord.ID(recordName: name, zoneID: MockCloudStore.zoneID)
        let projectionID = CKRecord.ID(recordName: name, zoneID: groupZone)

        let personal = CKRecord(recordType: "Transaction", recordID: personalID)
        personal["title"] = "personal" as CKRecordValue
        let projection = CKRecord(recordType: "Transaction", recordID: projectionID)
        projection["title"] = "projection" as CKRecordValue
        cloud.save([personal, projection])

        XCTAssertEqual(
            cloud.zonesHolding(recordName: name),
            [MockCloudStore.zoneID.zoneName, groupZone.zoneName],
            "Both copies must exist — CloudKit record names are unique per zone, not globally"
        )
        XCTAssertEqual(cloud.fetch(recordID: personalID)?["title"] as? String, "personal")
        XCTAssertEqual(cloud.fetch(recordID: projectionID)?["title"] as? String, "projection")

        // Withdrawing the projection must leave the personal record untouched.
        cloud.delete(recordID: projectionID)
        XCTAssertEqual(cloud.zonesHolding(recordName: name), [MockCloudStore.zoneID.zoneName])
        XCTAssertNotNil(cloud.fetch(recordID: personalID))
    }
}
