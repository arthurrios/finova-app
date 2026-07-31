//
//  BudgetRecordNameTests.swift
//  FinovaTests
//
//  Stage 2 let a personal and a group budget for the same month coexist as two local rows. It did
//  not give them two CloudKit identities.
//
//  `CKBudgetAdapter` derives the record name from the month alone — `budget-<monthDate>` — so both
//  rows want the same name. In CloudKit that is fine: names are unique per ZONE, and the two live in
//  different zones. Locally it is not: `idx_budgets_ck_record_id` is UNIQUE on `ck_record_id`, so
//  whichever row stores the name second is rejected. Its `ck_record_id` stays NULL, which means
//  `markAsSynced` can never match it — so it is pushed again on every single sync cycle, forever.
//
//  Scoping `ck_record_id` locally instead would be worse: ~20 sites look budgets up by record name
//  alone, and `hardDeleteByCKRecordName` would then delete BOTH rows. Making the NAME carry the
//  scope keeps every one of those lookups correct and unchanged.
//

import CloudKit
import XCTest

@testable import Finova

final class BudgetRecordNameTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var repo: BudgetRepository!
    private var userUID: String!
    private let groupId = "grp-budget-name"
    private let month = 1_700_000_000

    override func setUp() {
        super.setUp()
        userUID = "budgetname_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaBName-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        repo = BudgetRepository(db: db)
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    private func storedName(sharedGroupId: String?) -> String? {
        db.fetchSingleString(
            "SELECT ck_record_id FROM Budgets WHERE month_date = ? AND COALESCE(shared_group_id,'') = ?;",
            orderedBindings: [month, sharedGroupId ?? ""]
        )
    }

    // MARK: - The names themselves

    /// The personal name must NOT change. Every budget already in CloudKit is stored under
    /// `budget-<monthDate>`, and CKRecord names are immutable — a new name means delete + create,
    /// which a device on an older build would see as a deletion and apply.
    func testPersonalBudgetKeepsItsHistoricalRecordName() {
        let record = BudgetModel(monthDate: month, amount: 100_000)
            .toCKRecord(in: MockCloudStore.zoneID)

        XCTAssertEqual(record.recordID.recordName, "budget-\(month)")
    }

    func testGroupBudgetNameCarriesTheGroup() {
        let record = BudgetModel(monthDate: month, amount: 250_000, sharedGroupId: groupId)
            .toCKRecord(in: MockCloudStore.groupZoneID(groupId))

        XCTAssertEqual(
            record.recordID.recordName, "budget-\(month)-\(groupId)",
            "A group budget needs a name of its own, or it collides with the personal budget for "
                + "the same month in the local ck_record_id unique index"
        )
    }

    func testTwoGroupsForTheSameMonthGetDistinctNames() {
        let a = BudgetModel(monthDate: month, amount: 1, sharedGroupId: "grp-a")
            .toCKRecord(in: MockCloudStore.groupZoneID("grp-a")).recordID.recordName
        let b = BudgetModel(monthDate: month, amount: 2, sharedGroupId: "grp-b")
            .toCKRecord(in: MockCloudStore.groupZoneID("grp-b")).recordID.recordName

        XCTAssertNotEqual(a, b)
    }

    // MARK: - The defect this closes

    /// The failure that made a group budget permanently pending: both rows try to store the same
    /// name, the UNIQUE index rejects the second, and a row with a NULL `ck_record_id` can never be
    /// marked synced.
    func testBothScopesCanStoreTheirRecordName() {
        try? repo.insert(budget: BudgetModel(monthDate: month, amount: 100_000))
        try? repo.insert(budget: BudgetModel(monthDate: month, amount: 250_000, sharedGroupId: groupId))

        let personalName = BudgetModel(monthDate: month, amount: 100_000)
            .toCKRecord(in: MockCloudStore.zoneID).recordID.recordName
        let groupName = BudgetModel(monthDate: month, amount: 250_000, sharedGroupId: groupId)
            .toCKRecord(in: MockCloudStore.groupZoneID(groupId)).recordID.recordName

        repo.setCKRecordId(forMonthDate: month, sharedGroupId: nil, ckRecordName: personalName)
        repo.setCKRecordId(forMonthDate: month, sharedGroupId: groupId, ckRecordName: groupName)

        XCTAssertEqual(storedName(sharedGroupId: nil), personalName)
        XCTAssertEqual(
            storedName(sharedGroupId: groupId), groupName,
            """
            The group budget has no CloudKit identity stored. `markAsSynced` matches on \
            `ck_record_id`, so it can never mark this row synced — it will be pushed again on every \
            sync cycle for as long as the row exists.
            """
        )
    }

    /// And with identities stored, each row can be marked synced independently — the property that
    /// actually stops the endless re-push.
    func testMarkingOneScopeSyncedDoesNotAffectTheOther() {
        try? repo.insert(budget: BudgetModel(monthDate: month, amount: 100_000))
        try? repo.insert(budget: BudgetModel(monthDate: month, amount: 250_000, sharedGroupId: groupId))

        let personalName = "budget-\(month)"
        let groupName = "budget-\(month)-\(groupId)"
        repo.setCKRecordId(forMonthDate: month, sharedGroupId: nil, ckRecordName: personalName)
        repo.setCKRecordId(forMonthDate: month, sharedGroupId: groupId, ckRecordName: groupName)

        repo.markAsSynced(ckRecordName: personalName)

        XCTAssertEqual(
            db.fetchSingleString(
                "SELECT sync_status FROM Budgets WHERE month_date = ? AND shared_group_id IS NULL;",
                intBinding: month),
            "synced"
        )
        XCTAssertEqual(
            db.fetchSingleString(
                "SELECT sync_status FROM Budgets WHERE month_date = ? AND shared_group_id = ?;",
                orderedBindings: [month, groupId]),
            "pending",
            "Distinct names mean distinct identities: syncing one scope must not mark the other "
                + "synced, which would drop its pending edit"
        )
    }

    /// A record arriving under either name must land on the row for its own scope. `resolveBudget`
    /// matches on (month, scope) read from the record's fields, so the name is not what routes it —
    /// but the name it then stores must not be the other scope's.
    func testInboundGroupBudgetStoresItsOwnName() {
        try? repo.insert(budget: BudgetModel(monthDate: month, amount: 100_000))

        let remote = BudgetModel(monthDate: month, amount: 999_000, sharedGroupId: groupId)
        let record = remote.toCKRecord(in: MockCloudStore.groupZoneID(groupId))
        record["sharedGroupId"] = groupId as CKRecordValue
        ConflictResolver(db: db).resolveBudget(remote: remote, ckRecord: record)

        XCTAssertEqual(
            db.fetchSingleInt(
                "SELECT amount FROM Budgets WHERE month_date = ? AND shared_group_id IS NULL;",
                intBinding: month),
            100_000,
            "The personal budget must be untouched by an inbound group budget"
        )
        XCTAssertNotEqual(
            storedName(sharedGroupId: groupId), "budget-\(month)",
            "The group row must not claim the personal record's name"
        )
    }
}
