//
//  BudgetHistoryForecastTests.swift
//  FinovaTests
//
//  The months ahead on the budget history screen: what each filter reads from one projected month, that
//  a month with no budget never reads as a plan of zero, that a projected month reaches no score, that
//  the view model moves through past and projected months as one run, and that a month carries the
//  dashboard's own projection.
//
//  Pure, like `BudgetHistoryTests`, apart from the one test that configures a real `BudgetCard`.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class BudgetHistoryForecastTests: XCTestCase {

    /// 15 October 2026, so the window is fixed whatever day the suite runs.
    private let reference = Date(timeIntervalSince1970: 1_792_065_600)

    private func anchor(_ offset: Int) -> Int { reference.monthAnchor(offsetByMonths: offset) }

    private func allocation(
        _ category: TransactionCategory, planned: Int, used: Int, month: Int
    ) -> BudgetAllocation {
        var allocation = BudgetAllocation(
            dbId: nil, monthDate: month, category: category, allocatedAmount: planned,
            isRecurring: false, parentAllocationId: nil, sharedGroupId: nil)
        allocation.setUsedAmount(used)
        return allocation
    }

    /// Budget 10.000: groceries planned 3.000 with 1.000 dated, meals planned 2.000 and already 2.500,
    /// and 1.200 of taxes in a category with no allocation.
    private func month(
        _ offset: Int = 1, budget: Int = 10_000, balance: Int? = 50_000, deferred: Int = 0
    ) -> BudgetForecastMonth {
        let anchor = anchor(offset)
        return BudgetForecastMonth(
            monthAnchor: anchor,
            allocations: [
                allocation(.groceries, planned: 3_000, used: 1_000, month: anchor),
                allocation(.meals, planned: 2_000, used: 2_500, month: anchor),
            ],
            summary: UnallocatedBudgetSummary(
                monthDate: anchor, totalBudget: budget, totalAllocated: 5_000,
                totalUsedInUnallocatedCategories: 1_200),
            unallocatedSpending: [
                UnallocatedCategorySpending(category: .taxes, spentAmount: 1_200, monthDate: anchor)
            ],
            closingBalance: balance,
            deferredCardSpending: deferred,
            statementsDue: 700)
    }

    private func emptyMonth(_ offset: Int) -> BudgetForecastMonth {
        let anchor = anchor(offset)
        return BudgetForecastMonth(
            monthAnchor: anchor, allocations: [],
            summary: UnallocatedBudgetSummary(
                monthDate: anchor, totalBudget: 0, totalAllocated: 0, totalUsedInUnallocatedCategories: 0),
            unallocatedSpending: [], closingBalance: nil, deferredCardSpending: 0, statementsDue: 0)
    }

    private func figures(
        _ month: BudgetForecastMonth, _ filter: BudgetHistoryFilter
    ) -> BudgetForecastFigures {
        BudgetForecast(months: [month]).figures(for: filter)[0]
    }

    // MARK: - Filters

    func testWholeMonthExpectsTheFullPlanPlusWhatIsDatedOutsideIt() {
        let whole = figures(month(), .wholeMonth)

        XCTAssertEqual(whole.planned, 10_000)
        // Groceries at their plan, meals at the 2.500 already past theirs.
        XCTAssertEqual(whole.inside, 5_500)
        XCTAssertEqual(whole.outside, 1_200)
        XCTAssertEqual(whole.expected, 6_700)
        XCTAssertEqual(whole.difference, 3_300)
        XCTAssertEqual(whole.status, .fits)
    }

    func testCategoryReadsItsPlanAgainstItsDatedRows() {
        let groceries = figures(month(), .category(.groceries))

        XCTAssertEqual(groceries.planned, 3_000)
        XCTAssertEqual(groceries.expected, 1_000)
        XCTAssertEqual(groceries.difference, 2_000)
        XCTAssertEqual(groceries.status, .fits)
    }

    func testCategoryPastItsPlanIsShort() {
        let meals = figures(month(), .category(.meals))

        XCTAssertEqual(meals.status, .short)
        XCTAssertEqual(meals.difference, -500)
    }

    func testCategoryWithNoAllocationThatMonthHasRowsButNoPlan() {
        let taxes = figures(month(), .category(.taxes))

        XCTAssertFalse(taxes.hasPlan)
        XCTAssertEqual(taxes.expected, 1_200)
        XCTAssertEqual(taxes.status, .noPlan)
    }

    func testOutsideReadsTheUnallocatedBudgetAgainstOutsideRows() {
        let outside = figures(month(), .outsideAllocations)

        XCTAssertEqual(outside.planned, 5_000)
        XCTAssertEqual(outside.expected, 1_200)
        XCTAssertEqual(outside.difference, 3_800)
    }

    func testOutsideHasNoPlanWhenTheCategoriesTookTheBudget() {
        let outside = figures(month(budget: 4_000), .outsideAllocations)

        XCTAssertFalse(outside.hasPlan)
        XCTAssertEqual(outside.status, .noPlan)
    }

    func testRowsFollowTheFilterAndHideTheInstallmentSummaryRow() {
        let forecast = BudgetForecast(months: [month()])
        let anchor = anchor(1)
        func row(_ amount: Int, _ category: TransactionCategory, month: Int? = nil, summary: Bool = false) -> Transaction {
            Transaction(
                data: UITransactionData(
                    id: nil, title: "t", amount: amount, dateTimestamp: month ?? anchor,
                    budgetMonthDate: month ?? anchor, isRecurring: nil, hasInstallments: summary,
                    parentTransactionId: nil, installmentNumber: nil, totalInstallments: nil,
                    originalAmount: nil, creditCardId: nil, isCreditCardStatement: nil,
                    category: category, type: .expense))
        }
        let rows = [
            row(100, .groceries), row(900, .taxes), row(50, .groceries, month: self.anchor(2)),
            row(0, .taxes, summary: true),
        ]

        XCTAssertEqual(forecast.transactions(for: .wholeMonth, month: anchor, in: rows).map(\.amount), [900, 100])
        XCTAssertEqual(forecast.transactions(for: .category(.groceries), month: anchor, in: rows).map(\.amount), [100])
        XCTAssertEqual(forecast.transactions(for: .outsideAllocations, month: anchor, in: rows).map(\.amount), [900])
    }

    // MARK: - No budget

    func testAMonthWithNoBudgetHasNoPlanRatherThanAPlanOfZero() {
        let whole = figures(month(budget: 0), .wholeMonth)

        XCTAssertFalse(whole.hasPlan)
        XCTAssertNil(whole.percentExpected)
        XCTAssertEqual(whole.status, .noPlan)
        XCTAssertEqual(whole.expected, 6_700)
        XCTAssertEqual(whole.overPlan, 0)
        XCTAssertEqual(
            BudgetHistoryViewModel.forecastStatusText(for: whole, hidden: false),
            "budgetHistory.forecast.noBudget".localized)
    }

    func testAMonthWithNothingAtAllIsEmpty() {
        XCTAssertEqual(figures(emptyMonth(1), .wholeMonth).status, .empty)
        XCTAssertTrue(BudgetForecast(months: [emptyMonth(1)]).isEmpty)
    }

    // MARK: - Chart pieces

    func testBarPiecesAddUpToWhatIsExpected() {
        let short = figures(month(budget: 6_000), .wholeMonth)

        XCTAssertEqual(short.insideWithinPlan, 5_500)
        XCTAssertEqual(short.outsideWithinPlan, 500)
        XCTAssertEqual(short.overPlan, 700)
        XCTAssertEqual(short.insideWithinPlan + short.outsideWithinPlan + short.overPlan, short.expected)
    }

    // MARK: - Dashboard

    /// The same values through the real card and through a projected month.
    func testAFutureMonthCarriesTheDashboardProjection() throws {
        let anchor = anchor(1)
        let allocations = [
            allocation(.groceries, planned: 3_000, used: 1_000, month: anchor),
            allocation(.meals, planned: 2_000, used: 2_500, month: anchor),
        ]
        let summary = UnallocatedBudgetSummary(
            monthDate: anchor, totalBudget: 10_000, totalAllocated: 5_000,
            totalUsedInUnallocatedCategories: 1_200)
        let spending = [UnallocatedCategorySpending(category: .taxes, spentAmount: 1_200, monthDate: anchor)]

        let farAhead = Date().monthAnchor(offsetByMonths: 2)
        let card = BudgetCard()
        card.configure(
            month: "Nov", year: "2026", allocations: allocations, unallocatedSummary: summary,
            unallocatedSpending: spending, monthAnchor: farAhead,
            monthData: MonthBudgetCardType(
                date: Date.fromMonthAnchor(farAhead), month: "Nov", usedValue: 4_700, budgetLimit: 10_000,
                finalBalance: 50_000, currentBalance: 50_000, previousBalance: 40_000),
            deferredCardSpending: 300)

        let month = BudgetForecastMonth(
            monthAnchor: anchor, allocations: allocations, summary: summary,
            unallocatedSpending: spending, closingBalance: 50_000, deferredCardSpending: 300,
            statementsDue: 0)

        let dashboard = try XCTUnwrap(card.projection)
        XCTAssertEqual(month.projection, dashboard)
        // 50.000 - 300 deferred - 2.000 groceries unspent.
        XCTAssertEqual(month.projection?.projected, 47_700)
        // The month's own figures are the card's terms, added up.
        XCTAssertEqual(
            month.inside + month.outside,
            dashboard.usedWithinAllocations + dashboard.unspentAllocations + dashboard.overspent)
    }

    func testNoLedgerRowMeansNoProjectionLikeTheCard() {
        XCTAssertNil(month(balance: nil).projection)
    }

    // MARK: - Stats

    private final class StubReader: BudgetHistoryReading {
        let stored: BudgetHistory
        let ahead: BudgetForecast
        init(_ history: BudgetHistory, _ forecast: BudgetForecast) {
            stored = history
            ahead = forecast
        }
        func history(in scope: LedgerScope, includeWholeMonth: Bool, asOf reference: Date) -> BudgetHistory {
            stored
        }
        func expenses(in scope: LedgerScope) -> [Transaction] { [] }
        func forecast(in scope: LedgerScope, asOf reference: Date) -> BudgetForecast { ahead }
    }

    /// Five closed months on plan, then the open one.
    private var pastHistory: BudgetHistory {
        let anchors = (-5...0).map(anchor)
        let totals = anchors.reduce(into: [Int: BudgetHistory.MonthTotal]()) {
            $0[$1] = .init(budget: 1_000, used: 900)
        }
        return BudgetHistory(
            monthAnchors: anchors, currentAnchor: anchors.last!, allocations: [], spentByCategory: [:],
            monthTotals: totals)
    }

    private func makeViewModel(
        forecast: BudgetForecast, filter: BudgetHistoryFilter = .wholeMonth, month: Int? = nil
    ) -> BudgetHistoryViewModel {
        let suite = "BudgetHistoryForecastTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let viewModel = BudgetHistoryViewModel(
            ledgerScope: .personal, filter: filter, monthAnchor: month,
            service: StubReader(pastHistory, forecast), reference: { self.reference }, defaults: defaults)
        viewModel.load()
        return viewModel
    }

    private var sixMonths: BudgetForecast {
        BudgetForecast(months: (1...BudgetForecast.monthsAhead).map { month($0, budget: 100) })
    }

    func testProjectedMonthsReachNoScoreAndNoSavings() {
        let without = makeViewModel(forecast: .empty)
        let with = makeViewModel(forecast: sixMonths)

        XCTAssertEqual(with.series, without.series)
        XCTAssertEqual(with.series.monthsOnPlan, 5)
        XCTAssertEqual(with.series.streak, 5)
        XCTAssertEqual(with.series.usageRange?.low, without.series.usageRange?.low)
        XCTAssertEqual(with.series.usageRange?.high, without.series.usageRange?.high)
        XCTAssertEqual(with.savings, without.savings)
        XCTAssertEqual(with.savingsStartOptions, without.savingsStartOptions)
        XCTAssertFalse(with.series.months.contains { $0.monthAnchor > anchor(0) })

        // Selecting a month ahead moves none of them either.
        with.select(month: anchor(3))
        XCTAssertEqual(with.selectedForecast?.monthAnchor, anchor(3))
        XCTAssertEqual(with.savings, without.savings)
        XCTAssertEqual(with.savingsEnd, anchor(0))
        XCTAssertEqual(with.series.streak, 5)
    }

    func testSeriesInitializerNeverTakesMonthsPastTheOpenOne() {
        XCTAssertEqual(pastHistory.monthAnchors.last, anchor(0))
        XCTAssertEqual(pastHistory.closedMonthAnchors.last, anchor(-1))
    }

    // MARK: - View model

    func testArrowsWalkFromThePastIntoTheForecastAndStopAtItsEnd() {
        let viewModel = makeViewModel(forecast: sixMonths)

        XCTAssertEqual(viewModel.neighbour(by: 1), anchor(1))
        XCTAssertEqual(viewModel.neighbour(by: -1), anchor(-1))

        viewModel.select(month: anchor(1))
        XCTAssertEqual(viewModel.displayedAnchor, anchor(1))
        XCTAssertEqual(viewModel.neighbour(by: -1), anchor(0))

        viewModel.select(month: anchor(BudgetForecast.monthsAhead))
        XCTAssertNil(viewModel.neighbour(by: 1))
    }

    func testAMonthPastTheForecastCannotBeSelected() {
        let viewModel = makeViewModel(forecast: sixMonths)

        viewModel.select(month: anchor(BudgetForecast.monthsAhead + 1))

        XCTAssertEqual(viewModel.selectedAnchor, anchor(0))
    }

    func testOpeningOnAMonthAheadSelectsIt() {
        let viewModel = makeViewModel(forecast: sixMonths, month: anchor(2))

        XCTAssertEqual(viewModel.selectedForecast?.monthAnchor, anchor(2))
    }

    func testOpeningPastTheForecastFallsBackToTheOpenMonth() {
        let viewModel = makeViewModel(forecast: sixMonths, month: anchor(9))

        XCTAssertEqual(viewModel.selectedAnchor, anchor(0))
        XCTAssertNil(viewModel.selectedForecast)
    }

    func testChangingFilterKeepsTheProjectedMonthSelected() {
        let viewModel = makeViewModel(forecast: sixMonths, month: anchor(2))

        viewModel.select(filter: .category(.groceries))

        XCTAssertEqual(viewModel.selectedForecast?.monthAnchor, anchor(2))
        XCTAssertEqual(viewModel.selectedForecast?.planned, 3_000)
    }

    func testChangingRangeKeepsTheProjectedMonthSelected() {
        let viewModel = makeViewModel(forecast: sixMonths, month: anchor(2))

        viewModel.select(range: .twelveMonths)
        viewModel.select(range: .sixMonths)

        XCTAssertEqual(viewModel.selectedAnchor, anchor(2))
    }

    func testACategoryPlannedOnlyAheadIsOfferedWithNoPastBars() {
        let viewModel = makeViewModel(forecast: sixMonths)
        XCTAssertTrue(viewModel.filters.contains(.category(.groceries)))

        viewModel.select(filter: .category(.groceries))

        XCTAssertTrue(viewModel.series.months.isEmpty)
        XCTAssertEqual(viewModel.selectedForecast?.monthAnchor, anchor(1))
        XCTAssertEqual(viewModel.savings, .none)
    }

    func testOnlyAForecastIsNotAnEmptyScreen() {
        let suite = "BudgetHistoryForecastTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let viewModel = BudgetHistoryViewModel(
            ledgerScope: .personal, service: StubReader(.empty, sixMonths),
            reference: { self.reference }, defaults: defaults)
        viewModel.load()

        XCTAssertFalse(viewModel.isEmpty)
    }

    func testWithNothingAheadThePastBarsKeepTheChart() {
        let viewModel = makeViewModel(forecast: BudgetForecast(months: (1...6).map(emptyMonth)))

        XCTAssertTrue(viewModel.forecastMonths.isEmpty)
        XCTAssertNil(viewModel.neighbour(by: 1))

        viewModel.select(month: anchor(1))
        XCTAssertEqual(viewModel.selectedAnchor, anchor(0))
    }

    func testAFilterWithNothingAheadShowsNoColumnsWhileTheOthersDo() {
        let viewModel = makeViewModel(forecast: sixMonths)
        XCTAssertEqual(viewModel.forecastMonths.count, BudgetForecast.monthsAhead)

        viewModel.select(filter: .category(.market))

        XCTAssertTrue(viewModel.forecastMonths.isEmpty)
    }

    func testDetailListsRowsOfTheChosenFilter() throws {
        let viewModel = makeViewModel(forecast: sixMonths, month: anchor(1))

        let detail = try XCTUnwrap(viewModel.forecastDetail(try XCTUnwrap(viewModel.selectedForecast)))

        XCTAssertEqual(detail.month.statementsDue, 700)
        XCTAssertEqual(detail.scheduledCount, 0)
    }

    // MARK: - Text

    func testHiddenValuesLeaveNoAmountInStatusOrVoiceOver() {
        let fits = figures(month(), .wholeMonth)
        let short = figures(month(budget: 6_000), .wholeMonth)

        for month in [fits, short] {
            let status = BudgetHistoryViewModel.forecastStatusText(for: month, hidden: true)
            let spoken = BudgetHistoryViewModel.forecastAccessibilityValue(for: month, hidden: true)
            for amount in [month.expected, month.planned, abs(month.difference)] {
                XCTAssertFalse(status.contains(amount.currencyString))
                XCTAssertFalse(spoken.contains(amount.currencyString))
            }
        }
    }

    func testAWholeMonthLeadsWithItsBalanceAndACategoryKeepsItsReadout() {
        let viewModel = makeViewModel(forecast: BudgetForecast(months: [month()]), month: anchor(1))
        let whole = figures(month(), .wholeMonth)

        // 50.000 - 2.000 of groceries left. Meals are past their plan.
        XCTAssertEqual(viewModel.forecastBalance(for: whole), 48_000)
        XCTAssertNil(viewModel.forecastBalance(for: figures(month(), .category(.groceries))))
        XCTAssertNil(viewModel.forecastBalance(for: figures(month(), .outsideAllocations)))
    }

    func testAMonthWithNoBalanceKeepsItsReadout() {
        let noBalance = month(balance: nil)
        let viewModel = makeViewModel(forecast: BudgetForecast(months: [noBalance]), month: anchor(1))

        XCTAssertNil(viewModel.forecastBalance(for: figures(noBalance, .wholeMonth)))
    }

    func testVoiceOverReadsTheBalanceAndHiddenValuesMaskIt() {
        let whole = figures(month(), .wholeMonth)
        let spoken = BudgetHistoryViewModel.forecastAccessibilityValue(for: whole, hidden: false, balance: 48_000)
        XCTAssertTrue(
            spoken.contains(
                String(format: "budgetHistory.forecast.a11y.balance.format".localized, 48_000.currencyString)))

        let masked = BudgetHistoryViewModel.forecastAccessibilityValue(for: whole, hidden: true, balance: 48_000)
        XCTAssertFalse(masked.contains(48_000.currencyString))
        XCTAssertTrue(masked.contains("budgetHistory.forecast.readout.balance".localized))
    }

    func testVoiceOverSaysTheValueIsProjected() {
        for hidden in [false, true] {
            XCTAssertTrue(
                BudgetHistoryViewModel.forecastAccessibilityValue(
                    for: figures(month(), .wholeMonth), hidden: hidden
                ).hasPrefix("budgetHistory.forecast.badge".localized))
        }
    }
}

/// `BudgetHistoryService.forecast` against a real database: the month it reads must equal the month the
/// dashboard's card builds from the same ledger, through the same services.
final class BudgetForecastDashboardParityTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private var txRepo: TransactionRepository!
    private var allocationRepo: BudgetAllocationRepository!
    private var budgetRepo: BudgetRepository!
    private var allocationService: BudgetAllocationService!
    private var cardId = 0

    private let reference = Date()
    private var thisMonth: Int { reference.monthAnchor }
    private var nextMonth: Int { reference.monthAnchor(offsetByMonths: 1) }
    private var monthAfter: Int { reference.monthAnchor(offsetByMonths: 2) }

    override func setUp() {
        super.setUp()
        userUID = "forecast_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaForecast-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()

        txRepo = TransactionRepository(db: db)
        allocationRepo = BudgetAllocationRepository(db: db)
        budgetRepo = BudgetRepository(db: db)
        allocationService = BudgetAllocationService(
            allocationRepo: allocationRepo, transactionRepo: txRepo, budgetRepo: budgetRepo,
            statementRepo: StatementRepository(db: db))
        cardId = CreditCardRepository(db: db).insertCard(
            CreditCard(
                name: "Visa", lastFourDigits: "4242", cardBrand: .visa,
                closingDay: 28, dueDay: 8, creditLimit: 900_000,
                cardColor: .blue, userId: userUID,
                isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())
        ) ?? 0
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    private func add(
        _ amount: Int, _ category: TransactionCategory, month: Int, type: String = "expense",
        onCard: Bool = false, statementId: Int? = nil
    ) throws {
        try txRepo.insertTransaction(
            TransactionTestFixtures.makeTransactionModel(
                title: "t", category: category.key, amount: amount, type: type,
                dateTimestamp: Int(Date.fromMonthAnchor(month).addingTimeInterval(10 * 86_400).timeIntervalSince1970),
                budgetMonthDate: month, creditCardId: onCard ? cardId : nil, statementId: statementId))
    }

    func testTheServiceReadsTheMonthTheDashboardCardBuilds() throws {
        let month = nextMonth
        try budgetRepo.insert(budget: BudgetModel(monthDate: month, amount: 100_000))
        _ = try allocationRepo.insertAllocation(
            BudgetAllocationModel(
                monthDate: month, categoryKey: TransactionCategory.market.key, allocatedAmount: 40_000,
                isRecurring: false))

        try add(500_000, .salary, month: thisMonth, type: "income")
        try add(12_000, .market, month: month)
        try add(8_000, .meals, month: month)
        // Charged to next month's plan, on a statement that settles the month after: the deferred term.
        let due = Date.fromMonthAnchor(monthAfter).addingTimeInterval(7 * 86_400)
        let statementId = try db.insertStatement(
            creditCardId: cardId,
            closingDate: Int(Date.fromMonthAnchor(month).addingTimeInterval(27 * 86_400).timeIntervalSince1970),
            dueDate: Int(due.timeIntervalSince1970), totalAmount: 0, userId: userUID)
        try add(5_000, .market, month: month, onCard: true, statementId: statementId)
        // After the month: must not reach its closing balance.
        try add(30_000, .market, month: monthAfter)
        TransactionRepository.invalidateCache()

        let service = BudgetHistoryService(
            allocationRepo: allocationRepo, transactionRepo: txRepo, budgetRepo: budgetRepo)
        let forecast = service.forecast(in: .personal, asOf: reference)
        XCTAssertEqual(
            forecast.months.map(\.monthAnchor),
            (1...BudgetForecast.monthsAhead).map { reference.monthAnchor(offsetByMonths: $0) })
        let read = try XCTUnwrap(forecast.month(month))

        // What `MonthCarouselCell.rebuildAllocationsUI` hands the card, on the dashboard's wider range.
        let ledger = TransactionLedgerService(transactionRepo: txRepo, budgetRepo: budgetRepo)
        let monthData = try XCTUnwrap(
            ledger.calculateMonthlyData(for: -2...7, referenceDate: reference)
                .first { $0.date.monthAnchor == month })
        let commitment = try XCTUnwrap(
            allocationService.balanceCommitments(
                monthsAhead: SeriesMonths.carouselRange.upperBound,
                statementsDue: ledger.statementsDueByMonth(), in: .personal, asOf: reference)[month])
        let card = BudgetCard()
        card.configure(
            month: "Next", year: "Year",
            allocations: allocationService.getAllocationsWithUsage(forMonth: month, in: .personal),
            unallocatedSummary: allocationService.getUnallocatedSummary(forMonth: month, in: .personal),
            unallocatedSpending: allocationService.getUnallocatedCategoriesWithSpending(
                forMonth: month, in: .personal),
            monthAnchor: month, monthData: monthData,
            deferredCardSpending: commitment.outstandingCard,
            reservedPlan: commitment.reservedPlan)

        let dashboard = try XCTUnwrap(card.projection)
        XCTAssertEqual(read.projection, dashboard)
        XCTAssertEqual(dashboard.base, monthData.finalBalance)

        // 500.000 in, 20.000 out in cash, 5.000 deferred, 23.000 of the plan unspent.
        XCTAssertEqual(read.projection?.base, 480_000)
        XCTAssertEqual(read.projection?.deferredCardSpending, 5_000)
        XCTAssertEqual(read.projection?.projected, 452_000)
        XCTAssertEqual(read.budget, 100_000)
        XCTAssertEqual(read.inside, 40_000)
        XCTAssertEqual(read.outside, 8_000)
    }
}
