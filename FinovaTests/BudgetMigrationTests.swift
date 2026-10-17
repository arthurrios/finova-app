//
//  BudgetMigrationTests.swift
//  FinovaTests
//
//  Stage 2 rebuilds the Budgets table (CREATE / copy / DROP / rename) over real financial data.
//  These tests exercise the properties that make that safe to ship: nothing is lost, the new keys
//  hold, and running it again is a no-op.
//

import XCTest

@testable import Finova

final class BudgetMigrationTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!

    override func setUp() {
        super.setUp()
        userUID = "budgetmig_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaMig-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    private func budgetCount() -> Int {
        db.fetchSingleInt("SELECT COUNT(*) FROM Budgets;") ?? -1
    }

    // MARK: - Post-migration schema

    /// The rebuild must have run and left the new key structure in place.
    func testSchemaIsAtVersion2WithUuidPrimaryKey() {
        let hasUuid = db.fetchSingleInt(
            "SELECT COUNT(*) FROM pragma_table_info('Budgets') WHERE name = 'uuid';"
        ) ?? 0
        XCTAssertEqual(hasUuid, 1, "Budgets must carry a uuid column after the rebuild")

        let pkIsUuid = db.fetchSingleInt(
            "SELECT COUNT(*) FROM pragma_table_info('Budgets') WHERE name = 'uuid' AND pk = 1;"
        ) ?? 0
        XCTAssertEqual(pkIsUuid, 1, "uuid must be the PRIMARY KEY, replacing month_date")

        let monthIsNotPk = db.fetchSingleInt(
            "SELECT COUNT(*) FROM pragma_table_info('Budgets') WHERE name = 'month_date' AND pk = 1;"
        ) ?? -1
        XCTAssertEqual(monthIsNotPk, 0, "month_date must no longer be a primary key")

        let scopedIndex = db.fetchSingleInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_budgets_scope_month';"
        ) ?? 0
        XCTAssertEqual(scopedIndex, 1, "The scoped natural key index must exist")
    }

    /// Every inserted row must get a non-null uuid, even though inserts never supply one —
    /// `uuid` is NOT NULL, so the value has to come from the column DEFAULT.
    func testEveryBudgetGetsAUuid() {
        for i in 0..<5 {
            try? db.insertBudget(monthDate: 1_700_000_000 + i, amount: 1000 * (i + 1))
        }
        let nulls = db.fetchSingleInt("SELECT COUNT(*) FROM Budgets WHERE uuid IS NULL;") ?? -1
        XCTAssertEqual(nulls, 0, "Budgets.uuid is NOT NULL and must be populated by the DEFAULT")

        let distinct = db.fetchSingleInt("SELECT COUNT(DISTINCT uuid) FROM Budgets;") ?? 0
        XCTAssertEqual(distinct, budgetCount(), "Every budget's uuid must be unique")
    }

    // MARK: - The scoped natural key

    /// One budget per (user, scope, month) — and NULLs must not defeat it. SQLite treats NULLs as
    /// distinct in a UNIQUE index, so the index has to COALESCE them or duplicate personal budgets
    /// slip through.
    func testDuplicatePersonalBudgetForSameMonthIsRejected() {
        let month = 1_700_000_000
        try? db.insertBudget(monthDate: month, amount: 100)
        let after1 = budgetCount()

        // Second personal budget for the same month must be rejected by idx_budgets_scope_month.
        try? db.insertBudget(monthDate: month, amount: 200)

        XCTAssertEqual(
            budgetCount(), after1,
            "A second PERSONAL budget for the same month must be rejected — both have a NULL "
                + "shared_group_id, which a non-COALESCE unique index would treat as distinct"
        )
    }

    func testSameMonthDifferentScopesAreAllowed() {
        let month = 1_700_000_000
        try? db.insertBudget(monthDate: month, amount: 100)
        try? db.insertBudget(monthDate: month, amount: 200, sharedGroupId: "grp-1")
        try? db.insertBudget(monthDate: month, amount: 300, sharedGroupId: "grp-2")

        XCTAssertEqual(
            budgetCount(), 3,
            "Personal + two groups for the same month are three distinct budgets"
        )
    }

    // MARK: - Migration safety

    /// Re-opening the same database must not re-run the rebuild or disturb the rows. A migration
    /// that is not idempotent is a migration that eventually eats data.
    func testReopeningDatabaseIsANoOp() {
        try? db.insertBudget(monthDate: 1_700_000_000, amount: 4242)
        try? db.insertBudget(monthDate: 1_700_000_001, amount: 777, sharedGroupId: "grp-1")
        let before = budgetCount()
        let uuidsBefore = db.fetchSingleString("SELECT group_concat(uuid) FROM Budgets ORDER BY uuid;")

        // Second DBHelper over the same file re-runs the whole migration chain.
        let reopened = DBHelper(path: dbPath)

        XCTAssertEqual(
            reopened.fetchSingleInt("SELECT COUNT(*) FROM Budgets;") ?? -1, before,
            "Re-opening must not add or drop rows"
        )
        XCTAssertEqual(
            reopened.fetchSingleString("SELECT group_concat(uuid) FROM Budgets ORDER BY uuid;"),
            uuidsBefore,
            "Re-opening must not re-mint identities — that would orphan the CloudKit records"
        )
    }

    /// The snapshot taken before the destructive step must be a real, openable database.
    func testSnapshotIsUsable() {
        try? db.insertBudget(monthDate: 1_700_000_000, amount: 5150)
        guard let snap = db.snapshotDatabase(tag: "unit-test") else {
            return XCTFail("Snapshot was not created")
        }
        defer { try? FileManager.default.removeItem(at: snap) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: snap.path), "Snapshot file must exist")

        let restored = DBHelper(path: snap)
        XCTAssertEqual(
            restored.fetchSingleInt("SELECT amount FROM Budgets WHERE month_date = 1700000000;"),
            5150,
            "The snapshot must contain the data — VACUUM INTO checkpoints the WAL, unlike a file copy"
        )
    }
}
