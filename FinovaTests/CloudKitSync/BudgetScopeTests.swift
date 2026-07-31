//
//  BudgetScopeTests.swift
//  FinovaTests
//
//  `Budgets.month_date` is a GLOBAL primary key, so a month can hold exactly one budget row —
//  a personal budget and a group budget for the same month are physically the same record.
//
//  In CloudKit the record name is `budget-<monthDate>`, so the ZONE is the only thing telling a
//  personal budget from a group one. But `ck_record_id` stores only the record name with no zone,
//  under a UNIQUE index. Two distinct cloud records therefore collapse onto one local row, and
//  `ConflictResolver.resolveBudget` lets whichever arrives second hijack the first.
//
//  These tests encode the behaviour Stage 2 must deliver. They are expected to fail until the
//  Budgets table is rebuilt with a uuid primary key and a scoped natural key.
//

import CloudKit
import XCTest

@testable import Finova

final class BudgetScopeTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!
    private let groupId = "grp-scope-test"

    /// A fixed month so personal and group budgets provably collide on the same key.
    private var month: Int { Date().monthAnchor }

    override func setUp() {
        super.setUp()
        userUID = "budgetscope_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        deviceA = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "A")
        deviceB = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "B")
        UserDefaultsManager.setSyncEnabled(true)
    }

    override func tearDown() {
        deviceA.cleanup()
        deviceB.cleanup()
        mockCloud.reset()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - The defect

    /// A personal budget and a group budget for the same month must be able to coexist.
    ///
    /// Today the second insert violates `month_date`'s primary key. Before the F7 fix that failure
    /// was discarded silently, so the record simply vanished; it is now at least reported.
    func testPersonalAndGroupBudgetForSameMonthCoexist() {
        deviceA.activate()

        try? deviceA.budgetRepo.insert(budget: BudgetModel(monthDate: month, amount: 100_000))
        try? deviceA.budgetRepo.insert(
            budget: BudgetModel(monthDate: month, amount: 250_000, sharedGroupId: groupId)
        )

        // Scoped accessors: this is Stage 2's contract — a month can hold one budget per scope,
        // each with its own amount and its own CloudKit identity.
        let personal = deviceA.budgetRepo.fetchBudget(byMonthDate: month, sharedGroupId: nil)
        let group = deviceA.budgetRepo.fetchBudget(byMonthDate: month, sharedGroupId: groupId)

        XCTAssertEqual(
            personal?.amount, 100_000,
            "A personal budget for \(month) must exist independently of the group's"
        )
        XCTAssertEqual(
            group?.amount, 250_000,
            """
            A group budget for \(month) must exist alongside the personal one, with its own amount.
            While `month_date` was a GLOBAL primary key the two were the same physical row and the \
            second insert was rejected outright.
            """
        )

        // `fetchBudgets()` is the PERSONAL list read. Since Stage 3f it filters on
        // `shared_group_id IS NULL`, so the group budget does not leak into the personal view.
        let personalList = deviceA.budgetRepo.fetchBudgets().filter { $0.monthDate == month }
        XCTAssertEqual(
            personalList.map(\.amount), [100_000],
            "The personal budget list must show only the personal budget for that month"
        )
        XCTAssertEqual(
            deviceA.db.fetchSingleInt("SELECT COUNT(*) FROM Budgets WHERE month_date = ?;",
                                      intBinding: month),
            2,
            "Both budgets still exist — they belong to different ledgers, not to one row"
        )
    }

    /// An inbound group budget must not overwrite the local personal budget for that month.
    ///
    /// `resolveBudget` falls back to matching on `monthDate` alone when no row carries the incoming
    /// CK record name, then calls `setCKRecordId` + `updateFromCloud` — hijacking the personal row
    /// and destroying the user's own figure.
    func testInboundGroupBudgetDoesNotHijackPersonalBudget() {
        deviceB.activate()
        try? deviceB.budgetRepo.insert(budget: BudgetModel(monthDate: month, amount: 100_000))

        // A group budget for the same month arrives from another member.
        let groupBudget = BudgetModel(monthDate: month, amount: 999_000, sharedGroupId: groupId)
        let record = groupBudget.toCKRecord(in: MockCloudStore.zoneID)
        record["sharedGroupId"] = groupId as CKRecordValue
        deviceB.resolver.resolveBudget(remote: groupBudget, ckRecord: record)

        let personal = deviceB.budgetRepo.fetchBudgets().filter { $0.monthDate == month }
        XCTAssertEqual(
            personal.first?.amount, 100_000,
            """
            The personal budget for \(month) was overwritten by an inbound GROUP budget.
            Personal and group budgets are separate records and must not share a row.
            """
        )
    }

    /// Two devices on one account must agree about budgets after syncing.
    func testBudgetConvergesAcrossDevices() {
        deviceA.activate()
        try? deviceA.budgetRepo.insert(budget: BudgetModel(monthDate: month, amount: 175_000))

        deviceA.pushAll()
        deviceB.pullAll()

        let onB = deviceB.budgetRepo.fetchBudgets().filter { $0.monthDate == month }
        XCTAssertEqual(onB.first?.amount, 175_000, "Device B must receive the budget")
        XCTAssertEqual(
            deviceA.dataFingerprint(), deviceB.dataFingerprint(),
            "Devices must agree after a budget sync"
        )
    }
}
