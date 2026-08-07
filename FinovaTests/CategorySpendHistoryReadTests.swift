//
//  CategorySpendHistoryReadTests.swift
//  FinovaTests
//
//  Reading a category's closed-month history out of a real ledger.
//
//  Two ways to ship this feature silently broken, and both are pinned here:
//
//  1. `BudgetAllocation.usedAmount` is ALWAYS zero on a fetched row - `init(from:)` hard-sets it and
//     only `getAllocationsWithUsage` ever fills it in, one month at a time. Reading it would make every
//     ratio 0 and the app would report that no budget is ever spent.
//  2. `generateRecurringAllocationHorizon` materialises 36 months FORWARD with no spending behind them,
//     and `fetchAllAllocations()` returns every one. A window that leaked forward would read those as
//     0% and reach the same wrong answer by a different route.
//

import Foundation
import XCTest

@testable import Finova

final class CategorySpendHistoryReadTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private let groupId = "grp-spend-history"

    private var service: BudgetAllocationService!
    private var txRepo: TransactionRepository!
    private var allocationRepo: BudgetAllocationRepository!

    private var cardId: Int = 0

    /// Fixed so every window is deterministic. Mid-month, mid-year, so nothing straddles a boundary
    /// by accident - the boundary cases are `MonthAnchorArithmeticTests`' job.
    private let reference = Date(timeIntervalSince1970: 1_786_000_000)  // 2026-08-06

    /// The month on screen. Its own history is everything before it.
    private var viewedMonth: Int { reference.monthAnchor }
    private func closedMonth(_ monthsBack: Int) -> Int {
        reference.monthAnchor(offsetByMonths: -monthsBack)
    }
    private func futureMonth(_ monthsAhead: Int) -> Int {
        reference.monthAnchor(offsetByMonths: monthsAhead)
    }

    override func setUp() {
        super.setUp()
        userUID = "spendhistory_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaSpendHistory-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()

        allocationRepo = BudgetAllocationRepository(db: db)
        txRepo = TransactionRepository(db: db)
        service = BudgetAllocationService(
            allocationRepo: allocationRepo,
            transactionRepo: txRepo,
            budgetRepo: BudgetRepository(db: db),
            statementRepo: StatementRepository(db: db))

        cardId = CreditCardRepository(db: db).insertCard(
            CreditCard(
                name: "Visa", lastFourDigits: "4242", cardBrand: .visa,
                closingDay: 28, dueDay: 8, creditLimit: 900_000,
                cardColor: .blue, userId: userUID,
                isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date()
            )
        ) ?? 0
        XCTAssertGreaterThan(cardId, 0, "setup: card insert failed")

        // `excludingEarlyPaidInstallments()` reads settled ids from `DBHelper.shared`, NOT the injected
        // db. A colliding id left by another suite would silently drop rows from the usage side and the
        // ratios would come out low for no visible reason.
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

    private func allocate(
        _ amount: Int, month: Int, category: TransactionCategory = .market, group: String? = nil
    ) {
        do {
            _ = try allocationRepo.insertAllocation(
                BudgetAllocationModel(
                    monthDate: month,
                    categoryKey: category.key,
                    allocatedAmount: amount,
                    sharedGroupId: group))
        } catch {
            XCTFail("setup: allocation insert failed - \(error)")
        }
    }

    @discardableResult
    private func spend(
        _ amount: Int,
        month: Int,
        title: String,
        category: TransactionCategory = .market,
        type: String = "expense",
        dateTimestamp: Int? = nil,
        onCard: Bool = false,
        statementId: Int? = nil,
        isStatementSynthetic: Bool? = nil,
        group: String? = nil
    ) -> Int {
        try? txRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: title,
                category: category.key,
                amount: amount,
                type: type,
                dateTimestamp: dateTimestamp
                    ?? Int(Date.fromMonthAnchor(month).addingTimeInterval(10 * 86_400)
                        .timeIntervalSince1970),
                budgetMonthDate: month,
                creditCardId: onCard ? cardId : nil,
                statementId: statementId,
                isCreditCardStatement: isStatementSynthetic))
        guard let id = db.fetchSingleInt(
            "SELECT id FROM Transactions WHERE title = ?;", textBinding: title) else {
            XCTFail("setup: could not insert \(title)")
            return 0
        }
        // The insert path takes no scope argument, so scope is applied after the fact - the same way
        // `BudgetSummaryScopeTests` and `DeferredCardSpendingTests` do it.
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ?, user_id = ? WHERE id = ?;",
            orderedBindings: [group, userUID, id])
        TransactionRepository.invalidateCache()
        return id
    }

    private func statement(dueIn dueMonth: Int, closingIn closingMonth: Int) -> Int {
        let closing = Date.fromMonthAnchor(closingMonth).addingTimeInterval(27 * 86_400)
        let due = Date.fromMonthAnchor(dueMonth).addingTimeInterval(7 * 86_400)
        let id = (try? db.insertStatement(
            creditCardId: cardId,
            closingDate: Int(closing.timeIntervalSince1970),
            dueDate: Int(due.timeIntervalSince1970),
            totalAmount: 0, userId: userUID)) ?? 0
        XCTAssertGreaterThan(id, 0, "setup: statement insert failed")
        return id
    }

    /// Four closed months at the given ratios, so a verdict is reachable.
    private func seedRatios(_ ratios: [Double], category: TransactionCategory = .market) {
        for (index, ratio) in ratios.enumerated() {
            let month = closedMonth(index + 1)
            allocate(100_000, month: month, category: category)
            let used = Int((ratio * 100_000).rounded())
            if used > 0 {
                spend(
                    used, month: month, title: "\(category.key) spend \(index)", category: category)
            }
        }
    }

    private func read(
        _ category: TransactionCategory = .market, scope: LedgerScope = .personal
    ) -> CategorySpendHistory {
        service.spendHistory(
            for: category, before: viewedMonth, in: scope, asOf: reference)
    }

    // MARK: - The two traps

    /// Trap 1. If usage were read off the allocation row, every ratio would be zero and the feature
    /// would report that no budget is ever spent, with no error anywhere.
    func testUsageIsNotReadFromTheAllocationRow() {
        allocate(100_000, month: closedMonth(1))
        spend(60_000, month: closedMonth(1), title: "Groceries")

        let result = read()

        XCTAssertEqual(result.sampleCount, 1)
        XCTAssertGreaterThan(
            result.highestRatio, 0,
            "usage must come from transactions - BudgetAllocation.usedAmount is always 0 here")
        XCTAssertEqual(result.highestRatio, 0.6, accuracy: 0.0001)
    }

    /// Trap 2. The forward horizon generator leaves 36 months of allocations with no spending behind
    /// them, so a window that leaked forward would read them all as 0%.
    func testFutureAllocationsAreNeverSamples() {
        seedRatios([0.55, 0.58, 0.61, 0.64])
        for ahead in 1...12 {
            allocate(100_000, month: futureMonth(ahead))
        }

        let result = read()

        XCTAssertEqual(result.sampleCount, 4, "future months must not be sampled")
        XCTAssertEqual(result.lowestRatio, 0.55, accuracy: 0.0001)
    }

    func testTheViewedMonthIsNeverItsOwnSample() {
        seedRatios([0.55, 0.58, 0.61, 0.64])
        allocate(100_000, month: viewedMonth)
        spend(5_000, month: viewedMonth, title: "This month so far")

        let result = read()

        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(result.lowestRatio, 0.55, accuracy: 0.0001, "0.05 would be this month leaking in")
    }

    /// The agreement invariant: the ratio's numerator must be the same number the card puts on the
    /// category's row, or the two contradict each other in front of the user.
    func testUsageMatchesWhatGetAllocationsWithUsageReports() {
        let month = closedMonth(1)
        allocate(100_000, month: month)
        spend(37_500, month: month, title: "Groceries")
        spend(4_200, month: month, title: "Corner shop")

        let cardFigure = service.getAllocationsWithUsage(forMonth: month, in: .personal)
            .first { $0.category == .market }?.usedAmount

        XCTAssertEqual(cardFigure, 41_700, "precondition: this is what the card shows")
        XCTAssertEqual(read().highestRatio, 0.417, accuracy: 0.0001)
    }

    // MARK: - What counts as a sample

    func testAMonthWithSpendingButNoAllocationIsNotASample() {
        seedRatios([0.55, 0.58, 0.61, 0.64])
        spend(80_000, month: closedMonth(6), title: "Unbudgeted month")

        let result = read()

        XCTAssertEqual(
            result.sampleCount, 4,
            "fraction of plan used is undefined with no plan - it is not a sample")
    }

    func testAMonthAllocatedAndNeverSpentIsAZeroPercentSample() {
        // `seedRatios` covers months 1...3, so the never-spent month has to sit outside that range -
        // one allocation per category per month is all the repository permits.
        seedRatios([0.60, 0.62, 0.58])
        allocate(50_000, month: closedMonth(4))

        let result = read()

        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(
            result.lowestRatio, 0, accuracy: 0.0001,
            "a budgeted month with no spending is the signal this type exists to carry")
    }

    func testAZeroAmountAllocationIsNotASample() {
        seedRatios([0.55, 0.58, 0.61, 0.64])
        allocate(0, month: closedMonth(6))

        XCTAssertEqual(read().sampleCount, 4)
    }

    /// `BudgetAllocationRepository.insertAllocation` rejects a second row for the same category, month
    /// and scope, so this state is unreachable through the repository - the second row here goes in by
    /// raw SQL on purpose. It is still worth summing rather than picking one arbitrarily: the legacy
    /// UserDefaults-to-SQLite migration (`BudgetAllocationRepository:93`) writes straight to
    /// `db.insertBudgetAllocation` with no duplicate check, so old ledgers can hold a pair.
    func testDuplicateAllocationRowsInOneMonthAreSummedRatherThanPicked() {
        let month = closedMonth(1)
        allocate(60_000, month: month)
        try? db.executeGroupWriteChecked(
            """
            INSERT INTO BudgetAllocations
              (month_date, category_key, allocated_amount, is_recurring, user_id, sync_status)
            VALUES (?, ?, ?, 0, ?, 'pending');
            """,
            orderedBindings: [month, TransactionCategory.market.key, 40_000, userUID])
        spend(50_000, month: month, title: "Half of the combined plan")

        XCTAssertEqual(
            read().highestRatio, 0.5, accuracy: 0.0001,
            "50.000 against a summed 100.000 plan, not against either row alone")
    }

    func testOnlyTheRequestedCategoryIsSampled() {
        seedRatios([0.55, 0.58, 0.61, 0.64], category: .market)
        seedRatios([0.10, 0.12, 0.14, 0.16], category: .meals)

        XCTAssertEqual(read(.market).lowestRatio, 0.55, accuracy: 0.0001)
        XCTAssertEqual(read(.meals).highestRatio, 0.16, accuracy: 0.0001)
    }

    func testWindowIsAtMostTwelveClosedMonths() {
        seedRatios(Array(repeating: 0.5, count: 14))

        XCTAssertEqual(read().sampleCount, CategorySpendHistory.sampleWindow)
    }

    func testAnEmptyLedgerReportsNoHistory() {
        XCTAssertEqual(read(), .none)
        XCTAssertEqual(read().verdict, .notEnoughHistory)
    }

    // MARK: - Usage predicate

    func testIncomeDoesNotCountAsUsage() {
        let month = closedMonth(1)
        allocate(100_000, month: month)
        spend(60_000, month: month, title: "Groceries")
        spend(20_000, month: month, title: "Refund", type: "income")

        XCTAssertEqual(
            read().highestRatio, 0.6, accuracy: 0.0001,
            "expenses only, matching calculateUsageByCategory")
    }

    func testBucketsByBudgetMonthNotTransactionDate() {
        let month = closedMonth(1)
        allocate(100_000, month: month)
        // Booked against the closed month, but dated into the month on screen.
        spend(
            45_000, month: month, title: "Adjusted forward",
            dateTimestamp: Int(Date.fromMonthAnchor(viewedMonth).addingTimeInterval(86_400)
                .timeIntervalSince1970))

        XCTAssertEqual(read().highestRatio, 0.45, accuracy: 0.0001)
    }

    // MARK: - Card spending

    /// The deliberate inverse of `DeferredCardSpendingTests.testPurchaseOnNextMonthsStatementIsDeferred`:
    /// the same transaction, the opposite expectation. That figure reconciles the *balance*, which runs
    /// on a cash clock. This one is `used / allocated` inside one month, both sides on the purchase
    /// clock, so settlement timing is irrelevant to it.
    func testCardSpendingCountsInThePurchaseMonthLikeAnyOtherExpense() {
        let month = closedMonth(1)
        let stmt = statement(dueIn: viewedMonth, closingIn: month)
        allocate(100_000, month: month)
        spend(70_000, month: month, title: "Card groceries", onCard: true, statementId: stmt)

        XCTAssertEqual(
            read().highestRatio, 0.7, accuracy: 0.0001,
            "a card purchase consumed that month's plan regardless of when the bill lands")
    }

    /// Statement synthetics are category `.creditCard`, carry negative ids, and are built in memory
    /// inside `TransactionLedgerService` - they are never persisted, so they cannot reach this read.
    /// Pinned because a future change that started persisting them would double-count silently.
    func testStatementSyntheticsDoNotInflateTheRatio() {
        let month = closedMonth(1)
        let stmt = statement(dueIn: viewedMonth, closingIn: month)
        allocate(100_000, month: month)
        spend(70_000, month: month, title: "Card groceries", onCard: true, statementId: stmt)
        spend(
            70_000, month: month, title: "Visa invoice", category: .creditCard,
            onCard: true, statementId: stmt, isStatementSynthetic: true)

        XCTAssertEqual(read().highestRatio, 0.7, accuracy: 0.0001)
    }

    /// Installments are the real wrinkle, not cards: a split purchase consumes a slice of the plan in
    /// each of its months, which is what the card shows too.
    func testInstallmentsCountInEachInstallmentMonth() {
        for back in 1...4 {
            let month = closedMonth(back)
            allocate(100_000, month: month)
            spend(
                25_000, month: month, title: "Installment \(back) of 4", onCard: true)
        }

        let result = read()

        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(result.lowestRatio, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.highestRatio, 0.25, accuracy: 0.0001)
    }

    // MARK: - Scope

    func testPersonalHistoryDoesNotLeakIntoTheGroupRead() {
        for back in 1...4 {
            let month = closedMonth(back)
            allocate(100_000, month: month, group: nil)
            spend(60_000, month: month, title: "Mine \(back)", group: nil)
        }

        XCTAssertEqual(read(scope: .personal).sampleCount, 4)
        XCTAssertEqual(read(scope: .group(groupId)), .none)
    }

    func testGroupHistoryDoesNotLeakIntoThePersonalRead() {
        for back in 1...4 {
            let month = closedMonth(back)
            allocate(100_000, month: month, group: groupId)
            spend(30_000, month: month, title: "Ours \(back)", group: groupId)
        }

        XCTAssertEqual(read(scope: .personal), .none)

        let group = read(scope: .group(groupId))
        XCTAssertEqual(group.sampleCount, 4)
        XCTAssertEqual(group.highestRatio, 0.3, accuracy: 0.0001)
    }

    // MARK: - Verdicts end to end

    func testAConsistentLedgerReportsARange() {
        seedRatios([0.55, 0.58, 0.61, 0.64, 0.60, 0.57])

        guard case .consistent(_, _, let months) = read().verdict else {
            return XCTFail("six tight months should be consistent")
        }
        XCTAssertEqual(months, 6)
        XCTAssertEqual(read().percentRange.low, 55)
        XCTAssertEqual(read().percentRange.high, 64)
    }

    func testADivergentLedgerReportsVaried() {
        seedRatios([0.20, 0.90, 0.15, 0.85, 0.30, 0.95])

        guard case .varied = read().verdict else {
            return XCTFail("months that disagree this much must not be summarised as a tight range")
        }
    }

    func testThreeMonthsIsNotEnoughHistory() {
        seedRatios([0.55, 0.58, 0.61])

        XCTAssertEqual(read().sampleCount, 3)
        XCTAssertEqual(read().verdict, .notEnoughHistory)
    }
}
