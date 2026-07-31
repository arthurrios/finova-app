//
//  CKRecordIdDedupeTests.swift
//  FinovaTests
//
//  The `ck_record_id` deduplication used to run on EVERY database open, hard-deleting from financial
//  tables at each cold start, and it kept the row with the LOWEST local id. Local ids are assigned per
//  device, so "lowest id" names a different row on each one: two devices deduplicating the same pair
//  kept DIFFERENT survivors and then pushed them over each other.
//
//  These tests pin the two properties that fix that — the survivor is chosen by a value both devices
//  compute identically, and the pass runs once — plus the one that makes it safe to ship: it must not
//  touch a database that has nothing to deduplicate.
//

import XCTest

@testable import Finova

final class CKRecordIdDedupeTests: XCTestCase {
    private var dbPath: URL!
    private var userUID: String!

    override func setUp() {
        super.setUp()
        userUID = "dedupe_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaDedupe-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// Duplicates can only be planted by going around the unique index, which is exactly the state a
    /// pre-index database was left in. Dropping it reproduces that, then re-opening runs the migration.
    private func plantDuplicates(
        _ rows: [(title: String, rev: Int, revDevice: String)], sharedName: String
    ) -> DBHelper {
        let db = DBHelper(path: dbPath)
        let repo = TransactionRepository(db: db)

        for row in rows {
            try? repo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(title: row.title, amount: 1000)
            )
        }
        // The index is what stops two rows sharing a name; remove it to recreate the legacy state.
        db.executeSyncUpdate("DROP INDEX IF EXISTS idx_transactions_ck_record_id;")
        for row in rows {
            try? db.executeGroupWriteChecked(
                """
                UPDATE Transactions SET ck_record_id = ?, rev = ?, rev_device = ?
                 WHERE title = ?;
                """,
                orderedBindings: [sharedName, row.rev, row.revDevice, row.title]
            )
        }
        // Force the migration to re-run against the planted duplicates.
        db.executeSyncUpdate("PRAGMA user_version = 3;")
        return db
    }

    private func reopen() -> DBHelper { DBHelper(path: dbPath) }

    private func titles(_ db: DBHelper) -> [String] {
        (db.fetchSingleString(
            "SELECT COALESCE(group_concat(title), '') FROM Transactions ORDER BY title;") ?? "")
            .split(separator: ",").map(String.init).sorted()
    }

    // MARK: - Which row survives

    /// The property the old tie-break got wrong. `rev` is a logical clock, so both devices agree on
    /// which row is newer regardless of what local ids they happened to assign.
    func testKeepsTheHighestRev() {
        _ = plantDuplicates(
            [("older", 3, "deviceA"), ("newer", 7, "deviceB")], sharedName: "transaction-shared")

        XCTAssertEqual(
            titles(reopen()), ["newer"],
            "The survivor must be the highest rev — not the lowest local row id, which names a "
                + "different row on every device and made two devices disagree"
        )
    }

    /// Insertion order must not decide it. Same data, opposite order, same outcome.
    func testSurvivorDoesNotDependOnInsertionOrder() {
        _ = plantDuplicates(
            [("newer", 7, "deviceB"), ("older", 3, "deviceA")], sharedName: "transaction-shared")

        XCTAssertEqual(titles(reopen()), ["newer"])
    }

    /// With revs equal, `rev_device` decides — deterministically, and identically on both devices.
    func testEqualRevsBreakOnDeviceIdentifier() {
        _ = plantDuplicates(
            [("fromA", 5, "deviceA"), ("fromZ", 5, "deviceZ")], sharedName: "transaction-shared")

        XCTAssertEqual(
            titles(reopen()), ["fromZ"],
            "A tie on rev must resolve the same way everywhere, or the divergence returns"
        )
    }

    func testConsolidatesMoreThanTwo() {
        _ = plantDuplicates(
            [("a", 1, "d1"), ("b", 9, "d2"), ("c", 4, "d3")], sharedName: "transaction-shared")

        XCTAssertEqual(titles(reopen()), ["b"])
    }

    // MARK: - Blast radius

    /// Rows with distinct record names are not duplicates and must be left alone — as must rows with
    /// no record name at all, which have never been pushed.
    func testLeavesDistinctAndUnpushedRowsAlone() {
        let db = DBHelper(path: dbPath)
        let repo = TransactionRepository(db: db)
        for title in ["distinctOne", "distinctTwo", "neverPushed"] {
            try? repo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(title: title, amount: 1000))
        }
        db.executeSyncUpdate("DROP INDEX IF EXISTS idx_transactions_ck_record_id;")
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET ck_record_id = 'transaction-1' WHERE title = 'distinctOne';",
            orderedBindings: [])
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET ck_record_id = 'transaction-2' WHERE title = 'distinctTwo';",
            orderedBindings: [])
        db.executeSyncUpdate("PRAGMA user_version = 3;")

        XCTAssertEqual(
            titles(reopen()), ["distinctOne", "distinctTwo", "neverPushed"],
            "Only rows SHARING a ck_record_id are duplicates. A NULL ck_record_id means never pushed."
        )
    }

    // MARK: - Runs once

    /// It used to hard-delete on every database open. Re-opening must now do nothing at all.
    func testDoesNotRunAgainOnReopen() {
        _ = plantDuplicates(
            [("older", 3, "deviceA"), ("newer", 7, "deviceB")], sharedName: "transaction-shared")

        let first = reopen()
        let afterFirst = titles(first)
        XCTAssertEqual(afterFirst, ["newer"])

        let second = reopen()
        XCTAssertEqual(titles(second), afterFirst, "A second open must change nothing")
        XCTAssertEqual(
            second.fetchSingleInt("PRAGMA user_version;"), 4,
            "The pass is gated on user_version, so schema state travels with the file"
        )
    }

    /// The v4 gate must not be reachable before v2 and v3 have run — bumping the version inside
    /// `migrateSyncColumnsV3` would have skipped the Budgets rebuild and ProjectionSyncState on every
    /// existing install, because V3 runs before both of them.
    func testEarlierMigrationsStillRanOnAFreshDatabase() {
        let db = DBHelper(path: dbPath)

        XCTAssertEqual(
            db.fetchSingleInt(
                "SELECT COUNT(*) FROM pragma_table_info('Budgets') WHERE name = 'uuid' AND pk = 1;"),
            1,
            "v2 (Budgets uuid primary key) must have run"
        )
        XCTAssertEqual(
            db.fetchSingleInt(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='ProjectionSyncState';"),
            1,
            "v3 (ProjectionSyncState) must have run"
        )
        XCTAssertEqual(db.fetchSingleInt("PRAGMA user_version;"), 4, "and v4 must have completed")
    }

    /// The index the dedupe exists to enable. Without it the duplicates simply come back.
    func testUniqueIndexExistsAfterwards() {
        let db = DBHelper(path: dbPath)

        for table in ["transactions", "budgets", "creditcards", "creditcardstatements", "budgetallocations"] {
            XCTAssertEqual(
                db.fetchSingleInt(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_\(table)_ck_record_id';"),
                1,
                "idx_\(table)_ck_record_id must exist, or duplicate ck_record_ids can reappear"
            )
        }
    }
}
