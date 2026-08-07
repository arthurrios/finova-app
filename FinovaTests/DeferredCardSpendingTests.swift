//
//  DeferredCardSpendingTests.swift
//  FinovaTests
//
//  Card spending that consumed a month's plan but has not reached that month's balance.
//
//  The allocations card projects `base - deferredCardSpending - unspentAllocations`, and the first two
//  terms come from code that has always bucketed a card purchase differently: `TransactionLedgerService`
//  keeps card purchases out of the balance entirely and represents them by the statement synthetic,
//  dated to the statement's due date, while `calculateUsageByCategory` counts the purchase under its own
//  `budgetMonthDate`.
//
//  So adding a card expense in a category with headroom used to make the projected end-of-month balance
//  go *up* by the amount spent: usage rose, `unspentAllocations` fell, and nothing came off `base`.
//  This suite pins the correction, whose whole job is to cancel that usage contribution back out —
//  which is why nearly every test here is really about agreeing with `calculateUsageByCategory`.
//

import XCTest

@testable import Finova

final class DeferredCardSpendingTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private let groupId = "grp-deferred-card"

    private var service: BudgetAllocationService!
    private var txRepo: TransactionRepository!
    private var allocationRepo: BudgetAllocationRepository!

    private var cardId: Int = 0
    /// Anchors for the month under test and the one after it.
    private var thisMonth: Int = 0
    private var nextMonth: Int = 0

    override func setUp() {
        super.setUp()
        userUID = "deferredcard_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaDeferredCard-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        thisMonth = Date().monthAnchor
        nextMonth = cal.date(byAdding: .month, value: 1, to: Date.fromMonthAnchor(thisMonth))!
            .monthAnchor

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

        // Same shared-database hazard `BudgetSummaryScopeTests` guards: `excludingEarlyPaidInstallments`
        // reads settled ids from `DBHelper.shared`, not the injected db, so a colliding id from another
        // suite would silently drop rows from both the usage and the deferred figure.
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

    /// A statement on the test card, due in `dueMonth`. The due month is what matters: the synthetic
    /// debit that carries these charges into a balance is dated to `dueDate`.
    private func statement(dueIn dueMonth: Int, closingIn closingMonth: Int? = nil) -> Int {
        let closing = Date.fromMonthAnchor(closingMonth ?? dueMonth).addingTimeInterval(27 * 86_400)
        let due = Date.fromMonthAnchor(dueMonth).addingTimeInterval(7 * 86_400)
        let id = (try? db.insertStatement(
            creditCardId: cardId,
            closingDate: Int(closing.timeIntervalSince1970),
            dueDate: Int(due.timeIntervalSince1970),
            totalAmount: 0, userId: userUID)) ?? 0
        XCTAssertGreaterThan(id, 0, "setup: statement insert failed")
        return id
    }

    /// An expense (or income) in `budgetMonth`, optionally on the card and a statement.
    ///
    /// `dateTimestamp` defaults to the same month so the common case needs no thought; the one test that
    /// cares about the two disagreeing passes it explicitly.
    @discardableResult
    private func spend(
        _ amount: Int,
        title: String,
        category: TransactionCategory = .market,
        type: String = "expense",
        budgetMonth: Int? = nil,
        dateTimestamp: Int? = nil,
        onCard: Bool = false,
        statementId: Int? = nil,
        isStatementSynthetic: Bool? = nil,
        group: String? = nil
    ) -> Int {
        let month = budgetMonth ?? thisMonth
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
        // The insert path takes no scope argument, so scope is applied after the fact — the same way
        // `BudgetSummaryScopeTests` and `StatementScopeTests` do it.
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET shared_group_id = ?, user_id = ? WHERE id = ?;",
            orderedBindings: [group, userUID, id])
        TransactionRepository.invalidateCache()
        return id
    }

    private func deferred(_ scope: LedgerScope = .personal) -> Int {
        service.deferredCardSpending(forMonth: thisMonth, in: scope)
    }

    private func usage(_ scope: LedgerScope = .personal) -> Int {
        service.getAllocationsWithUsage(forMonth: thisMonth, in: scope)
            .reduce(0) { $0 + $1.usedAmount }
    }

    // MARK: - The reported case

    /// The bug, end to end: a card purchase in the current month landing on next month's statement.
    func testPurchaseOnNextMonthsStatementIsDeferred() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(15_000, title: "Market run", onCard: true, statementId: stmt)

        XCTAssertEqual(deferred(), 15_000)
    }

    /// The purchase must be *counted against the plan* for the correction to be needed at all — this is
    /// the invariant the whole term rests on, so assert both halves together.
    func testTheSamePurchaseIsCountedAgainstThePlanItIsSubtractedFrom() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(15_000, title: "Market run", onCard: true, statementId: stmt)

        _ = try? allocationRepo.insertAllocation(
            BudgetAllocationModel(
                monthDate: thisMonth, categoryKey: TransactionCategory.market.key,
                allocatedAmount: 50_000))

        XCTAssertEqual(usage(), 15_000, "usage counts the purchase in its purchase month")
        XCTAssertEqual(
            deferred(), 15_000,
            "so exactly that much must come off the base, or the projection rises by a spend")
    }

    /// A statement due inside the month under test is already in that month's balance, so subtracting it
    /// would charge the user twice.
    func testPurchaseOnThisMonthsStatementIsNotDeferred() {
        let stmt = statement(dueIn: thisMonth)
        spend(15_000, title: "Early buy", onCard: true, statementId: stmt)

        XCTAssertEqual(deferred(), 0)
    }

    /// The closing date can fall in a different month from the due date. The due date wins: that is the
    /// date the synthetic debit carries, and therefore the month the balance takes the hit.
    func testSettlementFollowsTheDueMonthNotTheClosingMonth() {
        let closesThisMonthDueNext = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(9_000, title: "Closes now pays later", onCard: true, statementId: closesThisMonthDueNext)

        XCTAssertEqual(deferred(), 9_000)
    }

    func testOnlyTheDeferredPortionIsSubtractedWhenBothStatementsExist() {
        let settled = statement(dueIn: thisMonth)
        let pending = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(4_000, title: "Paid this month", onCard: true, statementId: settled)
        spend(11_000, title: "Pays next month", onCard: true, statementId: pending)

        XCTAssertEqual(deferred(), 11_000)
    }

    // MARK: - Rows that must not be counted

    /// Cash and debit spending is already inside `base`. Subtracting it would double-charge the month.
    func testCashSpendingIsNeverDeferred() {
        spend(20_000, title: "Cash groceries", onCard: false)

        XCTAssertEqual(deferred(), 0)
    }

    /// A statement synthetic *is* the balance hit. Counting it would subtract the debt a second time.
    func testStatementSyntheticsAreNotCounted() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(
            30_000, title: "Visa invoice", category: .creditCard, onCard: true,
            statementId: stmt, isStatementSynthetic: true)

        XCTAssertEqual(deferred(), 0)
    }

    /// `calculateUsageByCategory` filters to `.expense`, so a card refund never lowers `usedAmount`. It
    /// must not lower what is subtracted here either, or the two sides stop cancelling.
    func testCardIncomeDoesNotReduceTheDeferredTotal() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(15_000, title: "Market run", onCard: true, statementId: stmt)
        spend(6_000, title: "Market refund", type: "income", onCard: true, statementId: stmt)

        XCTAssertEqual(
            deferred(), 15_000,
            "expenses only — a refund does not reduce usage, so it cannot reduce the subtraction")
    }

    func testAnotherMonthsCardSpendingIsIgnored() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(
            15_000, title: "Next month's buy", budgetMonth: nextMonth, onCard: true,
            statementId: stmt)

        XCTAssertEqual(deferred(), 0, "this month's card debt only")
    }

    /// Usage buckets on `budgetMonthDate`, which a business-day adjustment can push into a different
    /// month from the transaction date. This has to follow usage, not the calendar.
    func testBucketsByBudgetMonthNotTransactionDate() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        // Dated into next month, but booked against this month's plan.
        spend(
            7_500, title: "Adjusted forward",
            dateTimestamp: Int(Date.fromMonthAnchor(nextMonth).addingTimeInterval(86_400)
                .timeIntervalSince1970),
            onCard: true, statementId: stmt)

        XCTAssertEqual(
            deferred(), 7_500,
            "it must agree with usage's budgetMonthDate bucket, not the transaction date")
    }

    // MARK: - No statement to settle against

    /// A card purchase attached to no live statement never appears in any month's balance: the cash
    /// filter drops the purchase and no synthetic covers it. Treating it as settled would credit the
    /// projection with money that is gone.
    func testCardSpendingWithNoStatementStaysDeferred() {
        spend(12_000, title: "Orphaned charge", onCard: true, statementId: nil)

        XCTAssertEqual(deferred(), 12_000)
    }

    func testCardSpendingPointingAtAMissingStatementStaysDeferred() {
        spend(12_000, title: "Dangling charge", onCard: true, statementId: 99_999)

        XCTAssertEqual(deferred(), 12_000)
    }

    // MARK: - Scope

    /// The figure cancels the allocations' card spending, so it has to be read from the same ledger the
    /// allocations were. A group must not have the viewer's personal card debt taken off its balance.
    func testPersonalCardDebtDoesNotLeakIntoTheGroupFigure() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(15_000, title: "My own card buy", onCard: true, statementId: stmt, group: nil)

        XCTAssertEqual(deferred(.group(groupId)), 0)
        XCTAssertEqual(deferred(.personal), 15_000)
    }

    func testGroupCardDebtDoesNotLeakIntoThePersonalFigure() {
        let stmt = statement(dueIn: nextMonth, closingIn: thisMonth)
        spend(21_000, title: "Group card buy", onCard: true, statementId: stmt, group: groupId)

        XCTAssertEqual(deferred(.personal), 0)
        XCTAssertEqual(deferred(.group(groupId)), 21_000)
    }

    // MARK: - Bounds

    func testNothingToDeferIsZeroNotAnError() {
        XCTAssertEqual(deferred(), 0)
    }

    /// The subtraction can never exceed what the plan was charged, or the projection would drop below
    /// the real outcome. `deferred <= usage` for the same month is the safety property.
    func testDeferredNeverExceedsTheMonthsUsage() {
        let pending = statement(dueIn: nextMonth, closingIn: thisMonth)
        let settled = statement(dueIn: thisMonth)
        spend(15_000, title: "Card pending", onCard: true, statementId: pending)
        spend(4_000, title: "Card settled", onCard: true, statementId: settled)
        spend(9_000, title: "Cash spend", onCard: false)

        _ = try? allocationRepo.insertAllocation(
            BudgetAllocationModel(
                monthDate: thisMonth, categoryKey: TransactionCategory.market.key,
                allocatedAmount: 100_000))

        XCTAssertEqual(usage(), 28_000, "all three expenses consumed the plan")
        XCTAssertEqual(deferred(), 15_000, "only the one awaiting a later statement")
        XCTAssertLessThanOrEqual(deferred(), usage())
    }
}
