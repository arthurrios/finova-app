//
//  BudgetHistoryViewModelTests.swift
//  FinovaTests
//
//  The history screen's navigation and savings start: the month arrows stop at the ends of the bars
//  on screen, the start-month menu begins at the first planned month, and the chosen start is
//  remembered per ledger and only ever changed by the user. Also pins the history button on the
//  front of the month card.
//
//  The view model reads through `BudgetHistoryReading`, so a stub hands it a fixed history and
//  nothing here touches the database.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class BudgetHistoryViewModelTests: XCTestCase {

    /// 15 October 2026, so the window is fixed whatever day the suite runs.
    private let reference = Date(timeIntervalSince1970: 1_792_065_600)

    private final class StubReader: BudgetHistoryReading {
        var history: BudgetHistory
        init(_ history: BudgetHistory) { self.history = history }
        func history(in scope: LedgerScope, includeWholeMonth: Bool, asOf reference: Date) -> BudgetHistory {
            history
        }
        func expenses(in scope: LedgerScope) -> [Transaction] { [] }
    }

    /// Thirteen months ending at `reference`, oldest first.
    private func anchors(endingAt date: Date) -> [Int] {
        (0..<BudgetHistory.minimumWindowMonths).reversed().map { date.monthAnchor(offsetByMonths: -$0) }
    }

    /// A whole-month history with a budget and some spending from `plannedFrom` on.
    private func history(anchors: [Int], plannedFrom first: Int = 0) -> BudgetHistory {
        var totals: [Int: BudgetHistory.MonthTotal] = [:]
        for (index, anchor) in anchors.enumerated() {
            totals[anchor] = index >= first
                ? .init(budget: 1_000, used: 900) : .init(budget: nil, used: 400)
        }
        return BudgetHistory(
            monthAnchors: anchors, currentAnchor: anchors.last!, allocations: [], spentByCategory: [:],
            monthTotals: totals)
    }

    /// A private suite per test, so a remembered start never leaks between tests or into the app.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BudgetHistoryViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeViewModel(
        _ reader: StubReader, monthAnchor: Int? = nil,
        scope: LedgerScope = LedgerScope(groupId: nil, localUid: "test-user")
    ) -> BudgetHistoryViewModel {
        let viewModel = BudgetHistoryViewModel(
            ledgerScope: scope,
            monthAnchor: monthAnchor,
            service: reader,
            reference: { [reference] in reference },
            defaults: defaults)
        viewModel.load()
        return viewModel
    }

    // MARK: - Month arrows

    func testArrowsFromTheOpenMonthGoBackButNotForward() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(StubReader(history(anchors: months)))

        XCTAssertEqual(viewModel.selectedAnchor, months.last)
        XCTAssertEqual(viewModel.neighbour(by: -1), months[months.count - 2])
        XCTAssertNil(viewModel.neighbour(by: 1))
    }

    func testArrowsStepBothWaysFromAMiddleMonth() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(StubReader(history(anchors: months)), monthAnchor: months[10])

        XCTAssertEqual(viewModel.neighbour(by: -1), months[9])
        XCTAssertEqual(viewModel.neighbour(by: 1), months[11])
    }

    func testBackArrowStopsAtTheFirstBarOfSixMonths() {
        let months = anchors(endingAt: reference)
        // The sixth bar from the end is the first one on screen at 6M.
        let viewModel = makeViewModel(StubReader(history(anchors: months)), monthAnchor: months[7])

        XCTAssertEqual(viewModel.range, .sixMonths)
        XCTAssertEqual(viewModel.series.months.first?.monthAnchor, months[7])
        XCTAssertNil(viewModel.neighbour(by: -1))
        XCTAssertEqual(viewModel.neighbour(by: 1), months[8])
    }

    func testBackArrowStopsAtTheFirstBarOfTwelveMonths() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(StubReader(history(anchors: months)), monthAnchor: months[1])

        // A month older than six opens the longer range, so the arrows can reach it.
        XCTAssertEqual(viewModel.range, .twelveMonths)
        XCTAssertEqual(viewModel.series.months.first?.monthAnchor, months[1])
        XCTAssertNil(viewModel.neighbour(by: -1))
        XCTAssertEqual(viewModel.neighbour(by: 1), months[2])
    }

    // MARK: - Savings start

    func testStartOptionsBeginAtTheFirstPlannedMonthAndLeaveOutTheOpenOne() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(StubReader(history(anchors: months, plannedFrom: 5)))

        XCTAssertEqual(viewModel.savingsStartOptions, Array(months[5..<(months.count - 1)]))
    }

    func testNoPlanAnywhereOffersNoStartMonths() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(
            StubReader(history(anchors: months, plannedFrom: months.count)))
        XCTAssertEqual(viewModel.savingsStartOptions, [])
    }

    func testStartMonthCountsFromItself() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(StubReader(history(anchors: months)))
        let all = viewModel.savings

        viewModel.select(savingsStart: months[10])

        XCTAssertEqual(all.months, 12)
        XCTAssertEqual(viewModel.savings.months, 2)
        XCTAssertEqual(viewModel.savings.net, 200)
    }

    func testSavedFollowsTheSelectedMonth() {
        let months = anchors(endingAt: reference)
        let viewModel = makeViewModel(StubReader(history(anchors: months)))

        // The open month counts up to the month before it: all 12 closed months.
        XCTAssertEqual(viewModel.savings.months, 12)
        XCTAssertEqual(viewModel.savingsEndMonth, months[11])

        viewModel.select(month: months[9])
        XCTAssertEqual(viewModel.savings.months, 10)
        XCTAssertEqual(viewModel.savingsEndMonth, months[9])
    }

    func testStartIsKeptEvenWhenTheWindowMovesPastIt() {
        // Only the user changes the start. A month later the window no longer shows it, and the total
        // still counts from it rather than quietly switching to "since the start".
        let months = anchors(endingAt: reference)
        let reader = StubReader(history(anchors: months))
        let viewModel = makeViewModel(reader)
        viewModel.select(savingsStart: months[0])

        let later = anchors(endingAt: reference.addingTimeInterval(32 * 86_400))
        reader.history = history(anchors: later)
        viewModel.load()

        XCTAssertFalse(later.contains(months[0]))
        XCTAssertEqual(viewModel.savingsStart, months[0])
    }

    func testStartIsRememberedWhenTheScreenOpensAgain() {
        let months = anchors(endingAt: reference)
        makeViewModel(StubReader(history(anchors: months))).select(savingsStart: months[4])

        let reopened = makeViewModel(StubReader(history(anchors: months)))

        XCTAssertEqual(reopened.savingsStart, months[4])
        XCTAssertEqual(reopened.savings.months, 8)
    }

    func testChoosingSinceTheStartIsRememberedToo() {
        let months = anchors(endingAt: reference)
        let first = makeViewModel(StubReader(history(anchors: months)))
        first.select(savingsStart: months[4])
        first.select(savingsStart: nil)

        XCTAssertNil(makeViewModel(StubReader(history(anchors: months))).savingsStart)
    }

    func testEachLedgerRemembersItsOwnStart() {
        let months = anchors(endingAt: reference)
        let group = LedgerScope(groupId: "house", localUid: "test-user")
        makeViewModel(StubReader(history(anchors: months))).select(savingsStart: months[4])
        makeViewModel(StubReader(history(anchors: months)), scope: group)
            .select(savingsStart: months[9])

        XCTAssertEqual(makeViewModel(StubReader(history(anchors: months))).savingsStart, months[4])
        XCTAssertEqual(
            makeViewModel(StubReader(history(anchors: months)), scope: group).savingsStart, months[9])
    }

    // MARK: - Month card front

    private final class FlipDelegateSpy: MonthCardFlipDelegate {
        var historyMonth: Int?
        func didRequestFlip(isShowingBudgetView: Bool) {}
        func didSelectAllocationCategory(_ category: TransactionCategory) {}
        func didSelectAllocationTag(_ tagId: String?) {}
        func didTapAllocation(_ allocation: BudgetAllocation) {}
        func didTapUnallocatedSpending(_ spending: UnallocatedCategorySpending) {}
        func didTapBudgetsConfig(forMonth monthAnchor: Int) {}
        func didTapBudgetHistory(forMonth monthAnchor: Int) { historyMonth = monthAnchor }
        func didTapDefineBudget(forMonth monthAnchor: Int) {}
    }

    private func button(labelled label: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityLabel == label { return button }
        for subview in view.subviews {
            if let found = button(labelled: label, in: subview) { return found }
        }
        return nil
    }

    func testFrontOfTheMonthCardOpensHistoryForItsMonth() {
        let card = MonthBudgetCard()
        let spy = FlipDelegateSpy()
        card.flipDelegate = spy
        card.configure(data: MonthBudgetCardType(
            date: reference, month: "October", usedValue: 100_000, budgetLimit: 350_000,
            finalBalance: 428_000, currentBalance: 428_000, previousBalance: 0))

        let historyButton = button(labelled: "budgetHistory.a11y.open".localized, in: card)
        XCTAssertNotNil(historyButton, "the front of the card has no history button")
        historyButton?.sendActions(for: .touchUpInside)

        XCTAssertEqual(spy.historyMonth, reference.monthAnchor)
    }
}
