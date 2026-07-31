//
//  LedgerScopeTests.swift
//  FinovaTests
//
//  Allocations were never queried by group. All twelve render sites called
//  `getAllocationsWithUsage(forMonth:)`, which is user-scoped — so a group rendered the viewer's
//  personal allocations regardless of context. The group-aware repository fetch and the group-aware
//  usage calculation had existed all along with ZERO callers.
//
//  These tests pin the connection: allocations and their usage must both come from the scope being
//  rendered, and never from the other one.
//

import XCTest

@testable import Finova

final class LedgerScopeTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private var service: BudgetAllocationService!
    private var allocationRepo: BudgetAllocationRepository!
    private var transactionRepo: TransactionRepository!
    private let groupId = "grp-ledger-scope"
    private let month = 1_700_000_000

    override func setUp() {
        super.setUp()
        userUID = "ledgerscope_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaScope-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        allocationRepo = BudgetAllocationRepository(db: db)
        transactionRepo = TransactionRepository(db: db)
        service = BudgetAllocationService(
            allocationRepo: allocationRepo,
            transactionRepo: transactionRepo,
            budgetRepo: BudgetRepository(db: db)
        )
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

    @discardableResult
    private func addAllocation(
        category: String, amount: Int, sharedGroupId: String? = nil
    ) -> Int? {
        try? allocationRepo.insertAllocation(
            BudgetAllocationModel(
                monthDate: month,
                categoryKey: category,
                allocatedAmount: amount,
                isRecurring: false,
                parentAllocationId: nil,
                sharedGroupId: sharedGroupId
            )
        )
    }

    private func addExpense(category: String, amount: Int, sharedGroupId: String? = nil) {
        try? transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "spend-\(category)-\(amount)", category: category,
                amount: amount, type: "expense", budgetMonthDate: month
            )
        )
        guard let id = transactionRepo.fetchAllTransactions()
            .first(where: { $0.title == "spend-\(category)-\(amount)" })?.id else { return }
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ? WHERE id = ?;",
            orderedBindings: [sharedGroupId, id]
        )
        TransactionRepository.invalidateCache()
    }

    // MARK: - Scope value

    func testScopeCarriesBothValues() {
        XCTAssertTrue(LedgerScope.personal.isPersonal)
        XCTAssertNil(LedgerScope.personal.groupId)
        XCTAssertEqual(
            LedgerScope.personal.localUid, userUID,
            "A personal read filters on user_id, so the scope has to carry the uid — a bare "
                + "group-id String? could not express it"
        )

        let group = LedgerScope.group(groupId)
        XCTAssertFalse(group.isPersonal)
        XCTAssertEqual(group.groupId, groupId)
        XCTAssertEqual(
            group.localUid, userUID,
            "Group scope still needs the uid, to tell the viewer's own records from other members'"
        )
    }

    func testScopeFromDataContext() {
        XCTAssertTrue(LedgerScope(DataContext.personal).isPersonal)

        let group = BudgetGroup(
            id: groupId, name: "Family", ownerId: userUID,
            ownerName: "Me", ownerEmail: "me@example.com"
        )
        XCTAssertEqual(LedgerScope(DataContext.group(group)).groupId, groupId)
    }

    // MARK: - Scoped allocation reads

    /// The headline defect: a group rendered the viewer's personal allocations.
    func testGroupScopeReturnsOnlyGroupAllocations() {
        addAllocation(category: "market", amount: 50_000)
        addAllocation(category: "transportation", amount: 20_000, sharedGroupId: groupId)

        let inGroup = service.getAllocationsWithUsage(forMonth: month, in: .group(groupId))

        XCTAssertEqual(
            inGroup.map(\.category.key), ["transportation"],
            "A group must render its OWN allocations — the personal one belongs to a different ledger"
        )
        XCTAssertEqual(inGroup.first?.allocatedAmount, 20_000)
    }

    /// The personal side of the read is NOT scoped yet, and that is deliberate.
    ///
    /// `fetchAllAllocations` filters on `user_id` only, so it still returns rows tagged to a group.
    /// Narrowing it to `shared_group_id IS NULL` today would empty the personal view for every user
    /// whose ledger the old Mirror Mode tagged — which is exactly the data the restore migration
    /// un-tags. The two changes have to land together; this test pins the current behaviour so the
    /// gap is visible rather than assumed fixed.
    func testPersonalScopeStillIncludesGroupTaggedRows_pendingUntagMigration() {
        addAllocation(category: "market", amount: 50_000)
        addAllocation(category: "meals", amount: 20_000, sharedGroupId: "some-other-group")

        let personal = service.getAllocationsWithUsage(forMonth: month, in: .personal)

        XCTAssertTrue(
            personal.contains { $0.category.key == "market" },
            "The personal allocation must be there"
        )
        XCTAssertTrue(
            personal.contains { $0.category.key == "meals" },
            "Documents the remaining gap: personal reads are user-scoped, not personal-scoped. "
                + "Tightening this is coupled to the un-tag migration, not to this change."
        )
    }

    /// Usage has to be computed in the same scope as the allocations it is filled into. Reading the
    /// allocations from a group and the spending from the viewer's own ledger produces a progress
    /// bar that matches neither.
    func testUsageComesFromTheSameScopeAsTheAllocations() {
        addAllocation(category: "market", amount: 100_000, sharedGroupId: groupId)
        addExpense(category: "market", amount: 7_000, sharedGroupId: groupId)
        addExpense(category: "market", amount: 3_000)  // personal — must NOT count in group scope

        let inGroup = service.getAllocationsWithUsage(forMonth: month, in: .group(groupId))

        XCTAssertEqual(
            inGroup.first?.usedAmount, 7_000,
            "Group usage must count only the group's transactions; including the viewer's personal "
                + "spending would overstate what the group has spent"
        )
    }

    /// The same deferral on the usage side: personal usage sums every transaction for the user,
    /// including group-tagged ones. Pinned rather than asserted-away.
    func testPersonalUsageStillCountsGroupSpending_pendingUntagMigration() {
        addAllocation(category: "market", amount: 100_000)
        addExpense(category: "market", amount: 3_000)
        addExpense(category: "market", amount: 7_000, sharedGroupId: groupId)

        let personal = service.getAllocationsWithUsage(forMonth: month, in: .personal)
            .first { $0.category.key == "market" }

        XCTAssertEqual(
            personal?.usedAmount, 10_000,
            "Documents the remaining gap: personal usage is user-scoped. It tightens to 3_000 when "
                + "the un-tag migration lands and personal reads exclude group-tagged rows."
        )
    }

    /// Both ledgers can hold an allocation for the same category and month. They are separate
    /// records and must not be merged or shadow one another.
    func testSameCategoryInBothScopesStaysSeparate() {
        addAllocation(category: "market", amount: 50_000)
        addAllocation(category: "market", amount: 90_000, sharedGroupId: groupId)

        let personal = service.getAllocationsWithUsage(forMonth: month, in: .personal)
            .first { $0.category.key == "market" }
        let inGroup = service.getAllocationsWithUsage(forMonth: month, in: .group(groupId))
            .first { $0.category.key == "market" }

        XCTAssertEqual(personal?.allocatedAmount, 50_000)
        XCTAssertEqual(inGroup?.allocatedAmount, 90_000)
    }
}
