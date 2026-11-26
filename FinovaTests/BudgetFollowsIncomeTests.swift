//
//  BudgetFollowsIncomeTests.swift
//  FinovaTests
//
//  "Budget follows income": a month's budget is its counted income × a percent. These tests cover
//  the math and rounding, which rows count as income, the recompute after a real add/edit/delete
//  (through the repository paths that post `.transactionDataChanged`), a foreign income counting
//  with its reais amount, the per-month opt-out, and months with no income.
//

import XCTest

@testable import Finova

final class BudgetFollowsIncomeTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var txRepo: TransactionRepository!
    private var budgetRepo: BudgetRepository!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var service: BudgetFollowsIncomeService!

    private var current: Int { Date().monthAnchor }
    private func month(_ offset: Int) -> Int { BudgetsViewModel.monthAnchor(current, plusMonths: offset) }

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "follows_\(UUID().uuidString)"
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaFollowsIncome-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()
        txRepo = TransactionRepository(db: db)
        budgetRepo = BudgetRepository(db: db)
        suiteName = "follows-income-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = BudgetFollowsIncomeService(
            defaults: defaults, budgetRepo: budgetRepo, transactionRepo: txRepo, db: db,
            userKey: { "test" })
    }

    override func tearDown() {
        service.stop()
        defaults.removePersistentDomain(forName: suiteName)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Fixture

    @discardableResult
    private func addIncome(
        _ amount: Int, month anchor: Int, creditCardId: Int? = nil, foreign: ForeignAmount? = nil,
        title: String = UUID().uuidString
    ) throws -> Int {
        try txRepo.insertTransaction(model(amount, month: anchor, creditCardId: creditCardId, foreign: foreign, title: title))
        TransactionRepository.invalidateCache()
        return try XCTUnwrap(db.fetchSingleInt("SELECT id FROM Transactions WHERE title = ?;", textBinding: title))
    }

    private func model(
        _ amount: Int, month anchor: Int, id: Int? = nil, creditCardId: Int? = nil,
        foreign: ForeignAmount? = nil, title: String
    ) -> TransactionModel {
        TransactionModel(
            id: id, title: title, category: TransactionCategory.salary.key, amount: amount, type: "income",
            dateTimestamp: Int(Date.fromMonthAnchor(anchor).addingTimeInterval(9 * 86_400).timeIntervalSince1970),
            budgetMonthDate: anchor, creditCardId: creditCardId, foreign: foreign)
    }

    private func budget(_ anchor: Int) -> Int? {
        budgetRepo.fetchBudgets().first { $0.monthDate == anchor }?.amount
    }

    // MARK: - Percent math and rounding

    func testBudgetIsIncomeTimesPercentRoundedHalfUp() {
        XCTAssertEqual(BudgetFollowsIncomeService.budget(income: 10_000, percent: 80), 8_000)
        XCTAssertEqual(BudgetFollowsIncomeService.budget(income: 333, percent: 50), 167, "166.5 rounds up")
        XCTAssertEqual(BudgetFollowsIncomeService.budget(income: 1, percent: 50), 1, "0.5 rounds up")
        XCTAssertEqual(BudgetFollowsIncomeService.budget(income: 1, percent: 49), 0, "0.49 rounds down")
        XCTAssertEqual(BudgetFollowsIncomeService.budget(income: 2_188_885, percent: 80), 1_751_108)
        XCTAssertEqual(BudgetFollowsIncomeService.budget(income: 0, percent: 80), 0)
    }

    // MARK: - Which rows count

    func testOnlyPlainCashIncomeCounts() throws {
        try addIncome(100_000, month: current)
        try addIncome(5_000, month: current, creditCardId: 999)  // card refund / card credit

        let paymentCredit = try addIncome(7_000, month: current)
        XCTAssertTrue(db.setStatementPaymentLink(transactionId: paymentCredit, paymentId: 12345))

        let refund = try addIncome(3_000, month: current)
        XCTAssertTrue(db.setCancellationRefund(transactionId: refund, isRefund: true))

        let settlement = try addIncome(2_000, month: current)
        XCTAssertTrue(db.setEarlyPayment(transactionId: settlement, isEarlyPayment: true))

        try addIncome(9_999, month: month(1))  // another month
        TransactionRepository.invalidateCache()

        let byMonth = BudgetFollowsIncomeService.incomeByMonth(service.countedIncome())
        XCTAssertEqual(byMonth[current], 100_000)
        XCTAssertEqual(byMonth[month(1)], 9_999)
    }

    // MARK: - Recompute on income add / edit / delete

    func testBudgetFollowsIncomeAddEditAndDelete() throws {
        service.enable(percent: 80, includePastMonths: false)
        service.start()
        XCTAssertEqual(budget(current), 0, "on, with no income yet: 0")

        // Add: the repository posts .transactionDataChanged.
        let id = try addIncome(500_000, month: current, title: "salary")
        XCTAssertEqual(budget(current), 400_000)

        // Edit.
        try txRepo.updateTransactionDirectly(model(1_000_000, month: current, id: id, title: "salary"))
        XCTAssertEqual(budget(current), 800_000)

        // Delete.
        try txRepo.deleteBatch(ids: [id])
        XCTAssertEqual(budget(current), 0)
    }

    func testChangingThePercentRecomputes() throws {
        try addIncome(500_000, month: current)
        service.enable(percent: 100, includePastMonths: false)
        XCTAssertEqual(budget(current), 500_000)
        service.setPercent(70)
        XCTAssertEqual(budget(current), 350_000)
    }

    // MARK: - Foreign income counts in reais

    func testForeignIncomeCountsWithItsReaisAmountAndFollowsTheRate() throws {
        service.enable(percent: 100, includePastMonths: false)
        service.start()
        // US$ 1,000.00 at 5.7651 → R$ 5,765.10 in `amount`.
        let usd = ForeignAmount(currency: "USD", amount: 100_000, rateMicros: 5_765_100)
        let id = try addIncome(576_510, month: current, foreign: usd, title: "usd salary")
        XCTAssertEqual(budget(current), 576_510, "the reais amount counts, not the dollar amount")

        // A rate refresh rewrites `amount`; the budget moves with it.
        var refreshed = usd
        refreshed.rateMicros = 6_000_000
        try txRepo.updateTransactionDirectly(
            model(600_000, month: current, id: id, foreign: refreshed, title: "usd salary"))
        XCTAssertEqual(budget(current), 600_000)
    }

    // MARK: - Per-month opt-out

    func testAnOptedOutMonthKeepsItsFixedBudget() throws {
        service.enable(percent: 100, includePastMonths: false)
        service.start()
        service.optOut(month: current)
        try budgetRepo.update(budget: BudgetModel(monthDate: current, amount: 123_400))

        try addIncome(500_000, month: current)
        XCTAssertEqual(budget(current), 123_400, "a fixed month does not follow income")
        XCTAssertFalse(service.follows(month: current))

        service.optIn(month: current)
        XCTAssertEqual(budget(current), 500_000, "after opting back in it follows income again")
    }

    func testTurningItOffKeepsTheBudgetsAndStopsFollowing() throws {
        service.enable(percent: 100, includePastMonths: false)
        service.start()
        try addIncome(500_000, month: current)
        service.disable()
        try addIncome(100_000, month: current)
        XCTAssertEqual(budget(current), 500_000)
    }

    // MARK: - Months with no income

    func testCurrentAndFutureMonthsWithNoIncomeGetZero() throws {
        try addIncome(500_000, month: month(2))
        service.enable(percent: 100, includePastMonths: false)
        XCTAssertEqual(budget(current), 0)
        XCTAssertEqual(budget(month(1)), 0)
        XCTAssertEqual(budget(month(2)), 500_000)
        XCTAssertNil(budget(month(3)), "nothing is written past the last month with income")
    }

    func testPastMonthWithNoIncomeKeepsItsBudgetOrStaysEmpty() throws {
        try addIncome(300_000, month: month(-3))
        try budgetRepo.insert(budget: BudgetModel(monthDate: month(-2), amount: 77_700))

        service.enable(percent: 100, includePastMonths: true)

        XCTAssertEqual(budget(month(-3)), 300_000, "a past month with income is recomputed")
        XCTAssertEqual(budget(month(-2)), 77_700, "a past month with no income keeps its budget")
        XCTAssertNil(budget(month(-1)), "a past month with no income and no budget stays empty")
        XCTAssertEqual(budget(current), 0, "the current month with no income gets 0")
        XCTAssertFalse(service.follows(month: month(-2)))
        XCTAssertTrue(service.follows(month: month(-3)))
    }

    func testFromThisMonthOnLeavesPastMonthsAlone() throws {
        try addIncome(300_000, month: month(-1))
        try budgetRepo.insert(budget: BudgetModel(monthDate: month(-1), amount: 10_000))
        service.enable(percent: 100, includePastMonths: false)
        XCTAssertEqual(budget(month(-1)), 10_000)
    }
}
