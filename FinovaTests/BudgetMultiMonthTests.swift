//
//  BudgetMultiMonthTests.swift
//  FinovaTests
//
//  "Create budgets for many months at once": one save writes the same amount to every month in a
//  range, in one transaction. Months that already have a budget are replaced or kept, as the user
//  picks. A single-month save must behave exactly as before.
//

import XCTest

@testable import Finova

final class BudgetMultiMonthTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var repo: BudgetRepository!
    private var viewModel: BudgetsViewModel!

    /// January 2031, local time, as the app stores it.
    private var january: Int!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "budgetmulti_\(UUID().uuidString)"
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaBudgetMulti-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        repo = BudgetRepository(db: db)
        viewModel = BudgetsViewModel(budgetRepo: repo)
        january = Calendar.current.date(from: DateComponents(year: 2031, month: 1, day: 1))!.monthAnchor
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    private func month(_ offset: Int) -> Int {
        BudgetsViewModel.monthAnchor(january, plusMonths: offset)
    }

    private func monthYear(_ anchor: Int) -> String {
        DateFormatter.monthYearFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(anchor)))
    }

    private func amounts() -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: repo.fetchBudgets().map { ($0.monthDate, $0.amount) })
    }

    // MARK: - Month range

    func testMonthAnchorsCoverEveryMonthAcrossAYearEnd() {
        let start = month(10)  // November 2031
        let end = month(14)  // March 2032
        let anchors = BudgetsViewModel.monthAnchors(from: start, through: end)
        XCTAssertEqual(anchors, (10...14).map(month))
        XCTAssertEqual(Set(anchors).count, 5, "one anchor per calendar month")
    }

    func testMonthAnchorsIsEmptyWhenEndIsBeforeStart() {
        XCTAssertEqual(BudgetsViewModel.monthAnchors(from: month(3), through: month(1)), [])
    }

    // MARK: - Range write

    func testOneSaveWritesTheAmountToEveryMonthInTheRange() {
        let result = viewModel.addBudgets(
            amount: 300_000, monthYearDate: monthYear(january), endMonth: month(5), replaceExisting: true)

        guard case .success = result else { return XCTFail("save failed: \(result)") }
        let stored = amounts()
        XCTAssertEqual(stored.count, 6)
        for offset in 0...5 {
            XCTAssertEqual(stored[month(offset)], 300_000, "month +\(offset)")
        }
    }

    // MARK: - Conflicts

    func testExistingMonthsAreListedInCalendarOrder() throws {
        try repo.insert(budget: BudgetModel(monthDate: month(4), amount: 1))
        try repo.insert(budget: BudgetModel(monthDate: month(1), amount: 1))
        try repo.insert(budget: BudgetModel(monthDate: month(9), amount: 1))  // outside the range

        XCTAssertEqual(
            viewModel.existingBudgetMonths(monthYearDate: monthYear(january), endMonth: month(5)),
            [month(1), month(4)])
    }

    func testReplaceOverwritesTheMonthsThatAlreadyHaveABudget() throws {
        try repo.insert(budget: BudgetModel(monthDate: month(1), amount: 50_000))
        try repo.insert(budget: BudgetModel(monthDate: month(2), amount: 60_000))

        let result = viewModel.addBudgets(
            amount: 300_000, monthYearDate: monthYear(january), endMonth: month(3), replaceExisting: true)

        guard case .success = result else { return XCTFail("save failed: \(result)") }
        XCTAssertEqual(amounts(), [month(0): 300_000, month(1): 300_000, month(2): 300_000, month(3): 300_000])
        XCTAssertEqual(repo.fetchBudgets().count, 4, "a replaced month must not gain a second row")
    }

    func testKeepExistingFillsOnlyTheEmptyMonths() throws {
        try repo.insert(budget: BudgetModel(monthDate: month(1), amount: 50_000))
        try repo.insert(budget: BudgetModel(monthDate: month(2), amount: 60_000))

        let result = viewModel.addBudgets(
            amount: 300_000, monthYearDate: monthYear(january), endMonth: month(3), replaceExisting: false)

        guard case .success = result else { return XCTFail("save failed: \(result)") }
        XCTAssertEqual(amounts(), [month(0): 300_000, month(1): 50_000, month(2): 60_000, month(3): 300_000])
    }

    // MARK: - All or nothing

    func testAFailureMidwayWritesNoMonthAtAll() throws {
        try repo.insert(budget: BudgetModel(monthDate: month(1), amount: 50_000))
        // Make the database refuse the fourth month, after three months were already written.
        db.executeSyncUpdate(
            """
            CREATE TRIGGER fail_one_budget BEFORE INSERT ON Budgets
            WHEN NEW.month_date = \(month(3))
            BEGIN SELECT RAISE(ABORT, 'forced failure'); END;
            """)

        let result = viewModel.addBudgets(
            amount: 300_000, monthYearDate: monthYear(january), endMonth: month(5), replaceExisting: true)

        guard case .failure = result else { return XCTFail("the forced failure must surface") }
        XCTAssertEqual(
            amounts(), [month(1): 50_000],
            "the rollback must undo the months written before the failure, and the replace too")
    }

    // MARK: - Single month is unchanged

    func testSingleMonthSaveStillWritesOneMonthAndStillReportsAnExistingBudget() {
        guard case .success = viewModel.addBudget(amount: 120_000, monthYearDate: monthYear(month(2))) else {
            return XCTFail("single save failed")
        }
        XCTAssertEqual(amounts(), [month(2): 120_000])

        // A second save to the same month still asks before overwriting.
        let again = viewModel.addBudget(amount: 999, monthYearDate: monthYear(month(2)))
        guard case .failure(BudgetsViewModel.BudgetError.budgetAlreadyExists) = again else {
            return XCTFail("expected budgetAlreadyExists, got \(again)")
        }
        XCTAssertEqual(amounts(), [month(2): 120_000])

        guard case .success = viewModel.forceUpdateBudget(amount: 999, monthYearDate: monthYear(month(2))) else {
            return XCTFail("overwrite failed")
        }
        XCTAssertEqual(amounts(), [month(2): 999])
    }
}
