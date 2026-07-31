//
//  MirrorTagRestoreTests.swift
//  FinovaTests
//
//  The restore migration runs an UPDATE across four tables of real financial data. Exactly one
//  predicate keeps it safe, and these tests exist to stop that predicate drifting:
//
//      WHERE created_by_uid = ? AND shared_group_id IS NOT NULL
//
//  Using `user_id` instead would be catastrophic and would LOOK correct in casual testing:
//  `executeCloudInsert` stamps the RECEIVER's uid as `user_id` on every inbound record, so another
//  member's transaction carries your uid on your device. Un-tagging by `user_id` would strip the
//  group tag off their records and erase their contribution from the group, for everyone.
//
//  The tests drive `restore(db:uid:)` — the pure core — rather than `runOnceIfNeeded()`, which
//  reaches for `DBHelper.shared`, `UserDefaults` one-shot flags and a live sync engine.
//

import XCTest

@testable import Finova

final class MirrorTagRestoreTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var meUID: String!
    private let otherUID = "member-someone-else"
    private let groupId = "grp-restore"

    override func setUp() {
        super.setUp()
        meUID = "restore_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = meUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaRestore-\(UUID().uuidString).sqlite")
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

    /// Inserts a transaction and forces its scope + authorship, standing in for a row Mirror Mode
    /// tagged (`createdBy = me`) or one that arrived from another member (`createdBy = them`).
    private func makeTaggedTransaction(title: String, createdBy: String?, group: String?) {
        try? TransactionRepository(db: db).insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: title, amount: 1234)
        )
        guard let id = TransactionRepository(db: db).fetchAllTransactions()
            .first(where: { $0.title == title })?.id
        else {
            // Once a row is group-tagged it leaves the personal read, so look it up directly.
            guard let raw = db.fetchSingleInt(
                "SELECT id FROM Transactions WHERE title = ?;", textBinding: title
            ) else { return XCTFail("setup: could not insert \(title)") }
            apply(id: raw, createdBy: createdBy, group: group)
            return
        }
        apply(id: id, createdBy: createdBy, group: group)
    }

    private func apply(id: Int, createdBy: String?, group: String?) {
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET created_by_uid = ?, shared_group_id = ?, sync_status = 'synced' WHERE id = ?;",
            orderedBindings: [createdBy, group, id]
        )
        TransactionRepository.invalidateCache()
    }

    private func scope(of title: String) -> String? {
        db.fetchSingleString("SELECT shared_group_id FROM Transactions WHERE title = ?;", textBinding: title)
    }

    private func syncStatus(of title: String) -> String? {
        db.fetchSingleString("SELECT sync_status FROM Transactions WHERE title = ?;", textBinding: title)
    }

    // MARK: - What gets restored

    func testRestoresRowsThisUserAuthored() {
        makeTaggedTransaction(title: "MyMirroredRow", createdBy: meUID, group: groupId)

        MirrorTagRestore.restore(db: db, uid: meUID)

        XCTAssertNil(
            scope(of: "MyMirroredRow"),
            "A row this user authored and Mirror Mode tagged must go back to being personal"
        )
    }

    /// The invariant the whole migration rests on.
    func testNeverUntagsAnotherMembersRow() {
        // Exactly the shape that makes `user_id` the wrong key: the row is authored by someone
        // else, but `executeCloudInsert` stamped THIS device's uid on it as user_id.
        makeTaggedTransaction(title: "TheirRow", createdBy: otherUID, group: groupId)
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET user_id = ? WHERE title = 'TheirRow';",
            orderedBindings: [meUID]
        )

        MirrorTagRestore.restore(db: db, uid: meUID)

        XCTAssertEqual(
            scope(of: "TheirRow"), groupId,
            """
            Another member's record was un-tagged. On this device it carries OUR user_id — that is \
            what `executeCloudInsert` writes — so keying the migration on `user_id` instead of \
            `created_by_uid` erases their contribution from the group for everyone.
            """
        )
    }

    /// Authorship was only recorded from a certain build onwards. Leaving a row tagged is a
    /// cosmetic error the user can fix; un-tagging someone else's row destroys data.
    func testLeavesUnknownAuthorshipTagged() {
        makeTaggedTransaction(title: "UnknownAuthor", createdBy: nil, group: groupId)

        MirrorTagRestore.restore(db: db, uid: meUID)

        XCTAssertEqual(
            scope(of: "UnknownAuthor"), groupId,
            "created_by_uid IS NULL means UNKNOWN, not 'mine' — it must be left tagged"
        )
    }

    func testLeavesPersonalRowsAlone() {
        makeTaggedTransaction(title: "AlreadyPersonal", createdBy: meUID, group: nil)

        MirrorTagRestore.restore(db: db, uid: meUID)

        XCTAssertNil(scope(of: "AlreadyPersonal"))
        XCTAssertEqual(
            syncStatus(of: "AlreadyPersonal"), "synced",
            "An untouched row must not be marked pending — that would push it for no reason and "
                + "give the other device something to fight over"
        )
    }

    // MARK: - Consequences

    /// Restored rows must be queued for push, or the group-zone copy is never withdrawn and the
    /// record stays visible to the group forever.
    func testRestoredRowsAreQueuedForPush() {
        makeTaggedTransaction(title: "NeedsPush", createdBy: meUID, group: groupId)

        MirrorTagRestore.restore(db: db, uid: meUID)

        XCTAssertEqual(syncStatus(of: "NeedsPush"), "pending")
    }

    /// Running it twice must be a no-op. The one-shot flag normally prevents this, but a migration
    /// that is only safe because a UserDefaults key survived is not safe.
    func testRunningTwiceChangesNothingMore() {
        makeTaggedTransaction(title: "Mine", createdBy: meUID, group: groupId)
        makeTaggedTransaction(title: "Theirs", createdBy: otherUID, group: groupId)

        MirrorTagRestore.restore(db: db, uid: meUID)
        let afterFirst = (scope(of: "Mine"), scope(of: "Theirs"))
        MirrorTagRestore.restore(db: db, uid: meUID)

        XCTAssertEqual(scope(of: "Mine"), afterFirst.0)
        XCTAssertEqual(scope(of: "Theirs"), afterFirst.1)
        XCTAssertEqual(scope(of: "Theirs"), groupId)
    }

    /// The point of the whole exercise: a restored row is visible in the personal ledger again.
    /// Personal reads were tightened to `shared_group_id IS NULL` in the same change, so before the
    /// restore a mirrored user would see nothing.
    func testRestoredRowReappearsInThePersonalLedger() {
        makeTaggedTransaction(title: "ComingHome", createdBy: meUID, group: groupId)

        XCTAssertFalse(
            TransactionRepository(db: db).fetchAllTransactions().contains { $0.title == "ComingHome" },
            "setup: while tagged, the row belongs to the group's ledger"
        )

        MirrorTagRestore.restore(db: db, uid: meUID)
        TransactionRepository.invalidateCache()

        XCTAssertTrue(
            TransactionRepository(db: db).fetchAllTransactions().contains { $0.title == "ComingHome" },
            "After the restore the row is personal again and must appear in the personal ledger"
        )
    }
}
