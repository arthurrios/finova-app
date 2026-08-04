//
//  BudgetSummaryScopeTests.swift
//  FinovaTests
//
//  The budget card's summary must come from the ledger the card is rendering.
//
//  `getAllocationsWithUsage(forMonth:in:)` was made scope-aware; the two readers beside it —
//  `getUnallocatedSummary` and `getUnallocatedCategoriesWithSpending` — were not. They read the
//  personal budget row, the personal allocation set and the personal usage regardless of context.
//
//  That is worse than a cosmetic mismatch, because `BudgetCard.configure` gates its ENTIRE face on
//  `totalBudget > 0`. A group with a budget and allocations, viewed by a member with no personal
//  budget for that month, produced `totalBudget = 0` and collapsed the card to the "define your
//  budget" empty state: no donut, no footer metrics, no projection blocks — while the group's
//  allocations sat right there in the database.
//

import XCTest

@testable import Finova

final class BudgetSummaryScopeTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private let groupId = "grp-budget-summary-scope"
    private var monthAnchor: Int = 0

    private var service: BudgetAllocationService!
    private var allocationRepo: BudgetAllocationRepository!
    private var budgetRepo: BudgetRepository!
    private var txRepo: TransactionRepository!

    override func setUp() {
        super.setUp()
        userUID = "budgetscope_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaBudgetScope-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()

        monthAnchor = Date().monthAnchor
        allocationRepo = BudgetAllocationRepository(db: db)
        budgetRepo = BudgetRepository(db: db)
        txRepo = TransactionRepository(db: db)
        service = BudgetAllocationService(
            allocationRepo: allocationRepo, transactionRepo: txRepo, budgetRepo: budgetRepo)

        // `excludingEarlyPaidInstallments()` (inside `calculateUsageByCategory`) reads settled ids
        // from `DBHelper.shared`, NOT from the injected db. If another suite left settled rows there
        // whose ids collide with this suite's, usage would silently drop transactions — fail loudly
        // with the reason rather than producing mysterious totals.
        XCTAssertTrue(
            DBHelper.shared.settledInstallmentIds().isEmpty,
            "setup: another suite left settled installments in the shared database")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Fixture

    /// The month's budget total in one scope. `nil` group means the personal budget.
    private func setBudget(_ amount: Int, group: String?) {
        do {
            try budgetRepo.insert(
                budget: BudgetModel(monthDate: monthAnchor, amount: amount, sharedGroupId: group))
        } catch {
            XCTFail("setup: budget insert failed — \(error)")
        }
    }

    private func allocate(_ category: TransactionCategory, _ amount: Int, group: String?) {
        do {
            _ = try allocationRepo.insertAllocation(
                BudgetAllocationModel(
                    monthDate: monthAnchor,
                    categoryKey: category.key,
                    allocatedAmount: amount,
                    sharedGroupId: group))
        } catch {
            XCTFail("setup: allocation insert failed — \(error)")
        }
    }

    /// An expense in the month, booked to one scope. Written personal-then-retagged, the same way
    /// `StatementScopeTests` does it: the repository's insert path has no scope argument.
    private func spend(
        _ category: TransactionCategory, _ amount: Int, group: String?, title: String
    ) {
        try? txRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: title, category: category.key, amount: amount, budgetMonthDate: monthAnchor))
        guard let id = db.fetchSingleInt(
            "SELECT id FROM Transactions WHERE title = ?;", textBinding: title) else {
            return XCTFail("setup: could not insert \(title)")
        }
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ?, user_id = ? WHERE id = ?;",
            orderedBindings: [group, userUID, id])
        TransactionRepository.invalidateCache()
    }

    // MARK: - The budget total

    /// The reported symptom, reduced: the group has a budget and an allocation, the viewer has no
    /// personal budget row at all for the month.
    func testGroupSummaryReadsTheGroupsBudgetNotThePersonalOne() {
        setBudget(400_000, group: groupId)
        allocate(.meals, 100_000, group: groupId)

        let summary = service.getUnallocatedSummary(forMonth: monthAnchor, in: .group(groupId))

        XCTAssertEqual(
            summary.totalBudget, 400_000,
            """
            The group's budget total was read from the personal ledger, where there is no row — so \
            it came back 0 and BudgetCard showed "define your budget" over the group's real \
            allocations.
            """
        )
        XCTAssertEqual(summary.totalAllocated, 100_000, "and the group's allocation must be counted")
        XCTAssertEqual(summary.unallocatedAmount, 300_000)
    }

    /// Symmetry: narrowing the group path must not hand group figures to the personal card.
    func testPersonalSummaryIsUnaffectedByGroupRows() {
        setBudget(300_000, group: nil)
        setBudget(400_000, group: groupId)
        allocate(.meals, 50_000, group: nil)
        allocate(.meals, 100_000, group: groupId)

        let personal = service.getUnallocatedSummary(forMonth: monthAnchor, in: .personal)
        XCTAssertEqual(personal.totalBudget, 300_000)
        XCTAssertEqual(personal.totalAllocated, 50_000, "the group's allocation is not the user's")

        let group = service.getUnallocatedSummary(forMonth: monthAnchor, in: .group(groupId))
        XCTAssertEqual(group.totalBudget, 400_000)
        XCTAssertEqual(group.totalAllocated, 100_000)
    }

    /// A DIFFERENT group's budget is not this group's either.
    func testAnotherGroupsBudgetIsExcluded() {
        setBudget(900_000, group: "some-other-group")

        XCTAssertEqual(
            service.getUnallocatedSummary(forMonth: monthAnchor, in: .group(groupId)).totalBudget, 0)
        XCTAssertEqual(
            service.getUnallocatedSummary(forMonth: monthAnchor, in: .personal).totalBudget, 0)
    }

    // MARK: - Unallocated spending

    /// Usage has to come from the same ledger as the allocations, or the group's "spent outside a
    /// budget" figure is really the viewer's own spending.
    func testGroupUnallocatedSpendingComesFromGroupTransactions() {
        setBudget(400_000, group: groupId)
        allocate(.meals, 100_000, group: groupId)

        spend(.meals, 30_000, group: groupId, title: "GroupDinner")          // allocated category
        spend(.transportation, 20_000, group: groupId, title: "GroupTaxi")   // unallocated
        spend(.transportation, 90_000, group: nil, title: "PersonalTaxi")    // another ledger

        let summary = service.getUnallocatedSummary(forMonth: monthAnchor, in: .group(groupId))
        XCTAssertEqual(
            summary.totalUsedInUnallocatedCategories, 20_000,
            """
            Only the group's unallocated spending counts. Reading personal usage here charged the \
            group's summary with the viewer's own 90_000 taxi.
            """
        )

        let unallocated = service.getUnallocatedCategoriesWithSpending(
            forMonth: monthAnchor, in: .group(groupId))
        XCTAssertEqual(unallocated.count, 1, "meals is allocated in this group, so only transportation")
        XCTAssertEqual(unallocated.first?.category, .transportation)
        XCTAssertEqual(unallocated.first?.spentAmount, 20_000)
    }

    /// The same reads in personal scope see only the personal expense — including for `meals`,
    /// which has no personal allocation and no personal spending.
    func testPersonalUnallocatedSpendingComesFromPersonalTransactions() {
        allocate(.meals, 100_000, group: groupId)
        spend(.meals, 30_000, group: groupId, title: "GroupDinner")
        spend(.transportation, 90_000, group: nil, title: "PersonalTaxi")

        let unallocated = service.getUnallocatedCategoriesWithSpending(
            forMonth: monthAnchor, in: .personal)

        XCTAssertEqual(unallocated.count, 1)
        XCTAssertEqual(unallocated.first?.category, .transportation)
        XCTAssertEqual(unallocated.first?.spentAmount, 90_000)
    }

    // MARK: - What the card does with it

    /// Whether the card is showing the "define a budget" empty state rather than its real face
    /// (donut, footer metrics, projection blocks). Located by identifier, the same way
    /// `BudgetCardLayoutTests` reaches the projection blocks.
    private func isShowingNoBudgetState(_ card: BudgetCard) -> Bool {
        guard let view = card.subviews.first(where: {
            $0.accessibilityIdentifier == BudgetCard.noBudgetStateIdentifier
        }) else {
            XCTFail("the no-budget state view is not a direct subview any more")
            return false
        }
        return !view.isHidden
    }

    /// Second line of defence for the same symptom: even with the summary correctly scoped, a group
    /// can hold allocations with no budget total for the month (nobody set one). Gating the card on
    /// the total alone still threw the allocations away.
    func testCardRendersGroupAllocationsWithNoBudgetTotal() {
        allocate(.meals, 100_000, group: groupId)  // no budget row in any scope

        let allocations = service.getAllocationsWithUsage(
            forMonth: monthAnchor, in: .group(groupId))
        let summary = service.getUnallocatedSummary(forMonth: monthAnchor, in: .group(groupId))

        XCTAssertEqual(allocations.count, 1, "setup: the group allocation must be visible")
        XCTAssertEqual(summary.totalBudget, 0, "setup: and there is deliberately no budget total")

        let card = BudgetCard()
        card.configure(
            month: "March", year: "2026", allocations: allocations,
            unallocatedSummary: summary, unallocatedSpending: [], monthAnchor: monthAnchor)

        XCTAssertFalse(
            isShowingNoBudgetState(card),
            """
            The card fell back to "define your budget" while holding a real allocation. Allocations \
            alone are enough to render the face.
            """
        )
    }

    /// …but an empty ledger must still get the prompt, or the empty state would never appear.
    func testCardStillPromptsWhenThereIsNothingAtAll() {
        let summary = service.getUnallocatedSummary(forMonth: monthAnchor, in: .group(groupId))

        let card = BudgetCard()
        card.configure(
            month: "March", year: "2026", allocations: [],
            unallocatedSummary: summary, unallocatedSpending: [], monthAnchor: monthAnchor)

        XCTAssertTrue(isShowingNoBudgetState(card), "no budget and no allocations is the empty state")
    }
}
