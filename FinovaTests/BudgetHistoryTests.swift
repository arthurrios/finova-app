//
//  BudgetHistoryTests.swift
//  FinovaTests
//
//  The budget history screen's arithmetic: where each month landed against its plan, the scores the
//  insight tiles show, and how allocations and spending become one series per filter.
//
//  All pure - `BudgetHistory` takes arrays and dictionaries, so nothing here touches the database.
//

import Foundation
import XCTest

@testable import Finova

final class BudgetHistoryTests: XCTestCase {

    /// January to June 2026, as real month anchors in the device's time zone - the transaction filters
    /// compare a date's own month, so these must be true month starts.
    private let anchors = (0..<6).map {
        Date(timeIntervalSince1970: 1_768_521_600).monthAnchor(offsetByMonths: $0)
    }
    private var current: Int { anchors.last! }

    private func month(
        _ index: Int, planned: Int, spent: Int, isCurrent: Bool = false
    ) -> BudgetHistoryMonth {
        BudgetHistoryMonth(
            monthAnchor: anchors[index], planned: planned, spent: spent, isCurrent: isCurrent)
    }

    /// A series over `anchors`, the last month open. Each pair is (planned, spent).
    private func series(_ pairs: [(Int, Int)]) -> BudgetHistorySeries {
        BudgetHistorySeries(
            filter: .wholeMonth,
            months: pairs.enumerated().map { index, pair in
                month(index, planned: pair.0, spent: pair.1, isCurrent: index == pairs.count - 1)
            })
    }

    // MARK: - Month status

    func testClosedMonthAtOrUnderItsPlanIsWithin() {
        XCTAssertEqual(month(0, planned: 100, spent: 100).status, .within)
        XCTAssertEqual(month(0, planned: 100, spent: 0).status, .within)
    }

    func testMonthPastItsPlanIsOverEvenWhileOpen() {
        // An open month already over cannot be rescued by the days left in it.
        XCTAssertEqual(month(0, planned: 100, spent: 101).status, .over)
        XCTAssertEqual(month(0, planned: 100, spent: 101, isCurrent: true).status, .over)
    }

    func testOpenMonthUnderItsPlanIsInProgressNotWithin() {
        XCTAssertEqual(month(0, planned: 100, spent: 40, isCurrent: true).status, .inProgress)
    }

    func testSpendingWithNoPlanIsNoPlanAndNothingAtAllIsEmpty() {
        XCTAssertEqual(month(0, planned: 0, spent: 50).status, .noPlan)
        XCTAssertEqual(month(0, planned: 0, spent: 0).status, .empty)
    }

    func testSplitDrawsTheOverspendAsItsOwnPiece() {
        let over = month(0, planned: 100, spent: 130)
        XCTAssertEqual(over.spentWithinPlan, 100)
        XCTAssertEqual(over.spentOverPlan, 30)
        XCTAssertEqual(over.difference, -30)
        XCTAssertEqual(over.percentUsed, 130)

        let under = month(0, planned: 100, spent: 70)
        XCTAssertEqual(under.spentWithinPlan, 70)
        XCTAssertEqual(under.spentOverPlan, 0)
        XCTAssertEqual(under.difference, 30)
    }

    func testNoPlanHasNoRatioAndDrawsAllSpendingAsOnePiece() {
        let unplanned = month(0, planned: 0, spent: 50)
        XCTAssertNil(unplanned.ratio)
        XCTAssertNil(unplanned.percentUsed)
        XCTAssertEqual(unplanned.spentWithinPlan, 50)
        XCTAssertEqual(unplanned.spentOverPlan, 0)
    }

    // MARK: - Scores

    func testOpenMonthIsNeverScored() {
        // Five closed months on plan and an open month already over: the score is still 5 of 5.
        let history = series([(100, 90), (100, 90), (100, 90), (100, 90), (100, 90), (100, 200)])
        XCTAssertEqual(history.scoredMonths.count, 5)
        XCTAssertEqual(history.monthsOnPlan, 5)
        XCTAssertEqual(history.streak, 5)
        XCTAssertEqual(history.usageRange?.low, 90)
        XCTAssertEqual(history.usageRange?.high, 90)
    }

    func testMonthsWithoutAPlanAreLeftOutOfTheScore() {
        let history = series([(0, 80), (100, 90), (100, 120), (0, 0), (100, 50), (100, 10)])
        XCTAssertEqual(history.scoredMonths.count, 3)
        XCTAssertEqual(history.monthsOnPlan, 2)
    }

    func testStreakCountsBackFromTheLatestClosedMonthAndStopsAtAMiss() {
        let history = series([(100, 90), (100, 120), (100, 90), (100, 80), (100, 70), (100, 10)])
        XCTAssertEqual(history.streak, 3)
    }

    func testStreakIsZeroWhenTheLastClosedMonthWentOver() {
        let history = series([(100, 90), (100, 90), (100, 90), (100, 90), (100, 120), (100, 10)])
        XCTAssertEqual(history.streak, 0)
    }

    func testAMonthWithNoPlanEndsTheStreak() {
        let history = series([(100, 90), (100, 90), (100, 90), (0, 50), (100, 90), (100, 10)])
        XCTAssertEqual(history.streak, 1)
    }

    func testUsageRangeIsUnclampedSoOverspendShowsPastAHundred() {
        let history = series([(100, 60), (100, 140), (100, 95), (100, 10)])
        XCTAssertEqual(history.usageRange?.low, 60)
        XCTAssertEqual(history.usageRange?.high, 140)
    }

    func testNoScoredMonthsMeansNoRange() {
        XCTAssertNil(series([(0, 50), (100, 10)]).usageRange)
    }

    // MARK: - Savings

    func testSavingsNetWhatMonthsLeftAgainstWhatOthersOverspent() {
        // 100 left, 30 over, 50 left; the open month's 90 left is not saved yet.
        let savings = series([(200, 100), (100, 130), (100, 50), (100, 10)]).savings()
        XCTAssertEqual(savings.saved, 150)
        XCTAssertEqual(savings.overspent, 30)
        XCTAssertEqual(savings.net, 120)
        XCTAssertEqual(savings.months, 3)
    }

    func testSavingsSkipMonthsWithoutAPlan() {
        // Unplanned spending is not an overspend of anything.
        let savings = series([(0, 500), (100, 40), (100, 10)]).savings()
        XCTAssertEqual(savings.net, 60)
        XCTAssertEqual(savings.months, 1)
    }

    func testSavingsCountFromTheStartMonthOnward() {
        let history = series([(100, 0), (100, 0), (100, 150), (100, 80), (100, 10)])
        XCTAssertEqual(history.savings(from: anchors[2]).net, -30)
        XCTAssertEqual(history.savings(from: anchors[2]).months, 2)
        XCTAssertEqual(history.savings(from: nil).net, 170)
    }

    func testSavingsCanBeNegative() {
        XCTAssertEqual(series([(100, 180), (100, 10)]).savings().net, -80)
    }

    func testNothingToCountIsNone() {
        XCTAssertEqual(series([(0, 0), (100, 10)]).savings(), .none)
    }

    func testOutsideAllocationsMakesTheCategoriesAddUpToTheWholeMonth() {
        // Closed months 3 and 4: budget 1_000, all spending 800 -> whole month saves 200 a month.
        // Groceries plans 500 and spends 450 (+50), meals plans 300 and spends 330 (-30).
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [
                allocation(.groceries, 3, 500), allocation(.groceries, 4, 500),
                allocation(.meals, 3, 300), allocation(.meals, 4, 300),
            ],
            spentByCategory: [
                "groceries": [anchors[3]: 450, anchors[4]: 450],
                "meals": [anchors[3]: 330, anchors[4]: 330],
            ],
            monthTotals: [
                anchors[3]: .init(budget: 1_000, used: 800),
                anchors[4]: .init(budget: 1_000, used: 800),
            ])

        let categories = history.categories.reduce(0) { $0 + $1.savings(from: nil).net }
        let outside = history.outsideAllocations(from: nil)
        XCTAssertEqual(categories, 40)
        XCTAssertEqual(outside, 360)
        XCTAssertEqual(categories + (outside ?? 0), history.wholeMonth.savings(from: nil).net)
        // From month 4 on, each side halves.
        XCTAssertEqual(history.outsideAllocations(from: anchors[4]), 180)
    }

    func testOutsideSeriesIsUnallocatedBudgetAgainstUnplannedSpending() {
        // Month 3: budget 1_000, groceries planned 500. Travel had no allocation and spent 120.
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 3, 500)],
            spentByCategory: [
                "groceries": [anchors[3]: 450],
                "travel": [anchors[3]: 120],
            ],
            monthTotals: [anchors[3]: .init(budget: 1_000, used: 600)])

        let month = history.series(for: .outsideAllocations)?.month(anchors[3])
        XCTAssertEqual(month?.planned, 500)
        XCTAssertEqual(month?.spent, 120)
        // Whole 400 - groceries 50 = 350 outside; the series explains 380, the card's date clock 30 less.
        XCTAssertEqual(history.outsideAllocations(from: nil), 350)
        XCTAssertEqual(history.series(for: .outsideAllocations)?.savings(from: nil).net, 380)
        XCTAssertEqual(history.outsideTiming(from: nil), -30)
    }

    func testOverAllocatedMonthHasNoOutsidePlan() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 3, 1_200)],
            spentByCategory: ["groceries": [anchors[3]: 900]],
            monthTotals: [anchors[3]: .init(budget: 1_000, used: 900)])
        XCTAssertEqual(history.series(for: .outsideAllocations)?.month(anchors[3])?.hasPlan, false)
    }

    func testNoCategoriesMeansNoOutsideSeries() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current, allocations: [], spentByCategory: [:],
            monthTotals: [anchors[3]: .init(budget: 1_000, used: 900)])
        XCTAssertNil(history.series(for: .outsideAllocations))
    }

    func testNothingOutsideWhenTheWholeMonthHasNothingToCount() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 3, 500)],
            spentByCategory: ["groceries": [anchors[3]: 450]],
            monthTotals: [:])
        XCTAssertNil(history.outsideAllocations(from: nil))
    }

    // MARK: - Up to a month

    func testSavingsThroughAMonthStopAtThatMonth() {
        // Saved per closed month: +100, -30, +50; the open month never counts.
        let history = series([(200, 100), (100, 130), (100, 50), (100, 10)])
        XCTAssertEqual(history.savings(through: anchors[0]).net, 100)
        XCTAssertEqual(history.savings(through: anchors[1]).net, 70)
        XCTAssertEqual(history.savings(through: anchors[3]).net, 120)
        XCTAssertEqual(history.savings(from: anchors[1], through: anchors[2]).net, 20)
        XCTAssertEqual(history.savings(from: anchors[2], through: anchors[1]), .none)
    }

    func testOutsideAllocationsFollowTheSameMonths() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 3, 500), allocation(.groceries, 4, 500)],
            spentByCategory: ["groceries": [anchors[3]: 450, anchors[4]: 450]],
            monthTotals: [
                anchors[3]: .init(budget: 1_000, used: 800),
                anchors[4]: .init(budget: 1_000, used: 800),
            ])
        // Through month 3 only: whole 200 - groceries 50.
        XCTAssertEqual(history.outsideAllocations(from: nil, through: anchors[3]), 150)
        XCTAssertEqual(history.outsideAllocations(from: nil, through: nil), 300)
    }

    // MARK: - Transactions behind a bar

    private func expense(
        _ title: String, _ category: TransactionCategory, amount: Int,
        dated dateIndex: Int, budgetMonth budgetIndex: Int, statement: Bool = false, day: Int = 15,
        installmentParent: Bool = false
    ) -> Transaction {
        // Mid-month by default, so the date's month does not depend on the time zone.
        let date = anchors[dateIndex] + day * 86_400
        let model = TransactionModel(
            title: title, category: category.key, amount: amount, type: "expense",
            dateTimestamp: date, budgetMonthDate: anchors[budgetIndex],
            hasInstallments: installmentParent ? true : nil,
            isCreditCardStatement: statement ? true : nil)
        return Transaction(data: try! UITransactionData(from: model.data))
    }

    func testCategoryBarListsItsBudgetMonthExpensesBiggestFirst() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 3, 500)], spentByCategory: [:], monthTotals: [:])
        let expenses = [
            expense("Small", .groceries, amount: 100, dated: 3, budgetMonth: 3),
            expense("Big", .groceries, amount: 300, dated: 3, budgetMonth: 3),
            // Dated in month 3 but billed to month 4, so it belongs to month 4's bar.
            expense("Card", .groceries, amount: 999, dated: 3, budgetMonth: 4),
            expense("Other", .meals, amount: 50, dated: 3, budgetMonth: 3),
        ]
        let titles = history.transactions(for: .category(.groceries), month: anchors[3], in: expenses)
            .map(\.title)
        XCTAssertEqual(titles, ["Big", "Small"])
    }

    func testWholeMonthListsExpensesByDateWithoutStatementPayments() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current, allocations: [], spentByCategory: [:],
            monthTotals: [:])
        let expenses = [
            expense("Card", .groceries, amount: 999, dated: 3, budgetMonth: 4),
            expense("Statement", .creditCard, amount: 5_000, dated: 3, budgetMonth: 3, statement: true),
            expense("Next month", .meals, amount: 10, dated: 4, budgetMonth: 3),
        ]
        let titles = history.transactions(for: .wholeMonth, month: anchors[3], in: expenses).map(\.title)
        XCTAssertEqual(titles, ["Card"])
    }

    func testOutsideListsOnlyCategoriesWithNoAllocationThatMonth() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            // Groceries planned in month 3 only; travel never.
            allocations: [allocation(.groceries, 3, 500)], spentByCategory: [:], monthTotals: [:])
        let expenses = [
            expense("Groceries 3", .groceries, amount: 100, dated: 3, budgetMonth: 3),
            expense("Groceries 4", .groceries, amount: 200, dated: 4, budgetMonth: 4),
            expense("Travel 3", .travel, amount: 300, dated: 3, budgetMonth: 3),
        ]
        XCTAssertEqual(
            history.transactions(for: .outsideAllocations, month: anchors[3], in: expenses).map(\.title),
            ["Travel 3"])
        XCTAssertEqual(
            history.transactions(for: .outsideAllocations, month: anchors[4], in: expenses).map(\.title),
            ["Groceries 4"])
    }

    // MARK: - What made Saved

    func testWholeMonthIsExplainedByCategoriesAndTheRemainder() {
        // Months 1 and 2: budget 1_000, used 900 -> whole month saves 200.
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [
                allocation(.groceries, 1, 500), allocation(.groceries, 2, 500),
                allocation(.meals, 1, 200), allocation(.meals, 2, 200),
            ],
            spentByCategory: [
                "groceries": [anchors[1]: 400, anchors[2]: 450],
                "meals": [anchors[1]: 260, anchors[2]: 240],
            ],
            monthTotals: [
                anchors[1]: .init(budget: 1_000, used: 900),
                anchors[2]: .init(budget: 1_000, used: 900),
            ])

        let result = history.contributors(for: .wholeMonth, from: nil, through: nil)
        XCTAssertEqual(result?.total, 200)
        // Groceries +150, meals -100, the remainder 200 - 50 = +150.
        XCTAssertEqual(result?.savers.map(\.part), [.category(.groceries), .outsideAllocations])
        XCTAssertEqual(result?.overspenders.map(\.part), [.category(.meals)])
        XCTAssertEqual(result?.others, 0)
        XCTAssertEqual(result?.firstMonth, anchors[1])
        XCTAssertEqual(result?.lastMonth, anchors[2])
    }

    func testOnlyThreeNamedPerSideAndTheRestAddUp() {
        // Five closed months: +50, +40, +30, +20, -10; the sixth is open.
        let wrapped = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            wholeMonth: series([(100, 50), (100, 60), (100, 70), (100, 80), (100, 110), (100, 1)]),
            categories: [])
        let result = wrapped.contributors(for: .wholeMonth, from: nil, through: nil)
        XCTAssertEqual(result?.savers.map(\.net), [50, 40, 30])
        XCTAssertEqual(result?.overspenders.map(\.net), [-10])
        XCTAssertEqual(result?.others, 20)
        XCTAssertEqual(result?.othersCount, 1)
        XCTAssertEqual(result?.total, 130)
    }

    func testCategoryIsExplainedByItsMonthsWithinThePeriod() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [
                allocation(.groceries, 1, 500), allocation(.groceries, 2, 500),
                allocation(.groceries, 3, 500),
            ],
            spentByCategory: ["groceries": [anchors[1]: 450, anchors[2]: 520, anchors[3]: 100]],
            monthTotals: [:])
        let result = history.contributors(for: .category(.groceries), from: anchors[2], through: anchors[3])
        XCTAssertEqual(result?.savers, [.init(part: .month(anchors[3]), net: 400)])
        XCTAssertEqual(result?.overspenders, [.init(part: .month(anchors[2]), net: -20)])
        XCTAssertEqual(result?.total, 380)
        XCTAssertNil(history.contributors(for: .category(.groceries), from: anchors[4], through: nil))
    }

    func testParentInstallmentsNeverShow() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.education, 3, 500)], spentByCategory: [:], monthTotals: [:])
        let expenses = [
            expense("Student card", .education, amount: 0, dated: 3, budgetMonth: 3, installmentParent: true),
            expense("Course", .education, amount: 120, dated: 3, budgetMonth: 3),
        ]
        XCTAssertEqual(
            history.transactions(for: .category(.education), month: anchors[3], in: expenses).map(\.title),
            ["Course"])
        XCTAssertEqual(
            history.transactions(for: .wholeMonth, month: anchors[3], in: expenses).map(\.title), ["Course"])
    }

    func testOutsideDifferencesNameTheirReasonAndAddUp() {
        // Month 1: budget 1_000, groceries 500 -> 500 unallocated, outside spends 100 -> +400.
        //   The card used 700 against groceries 450 + outside 100 = 550: 150 counted in another month.
        // Month 2: budget 1_000, groceries 1_100 -> categories above the budget, no outside plan.
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 1, 500), allocation(.groceries, 2, 1_100)],
            spentByCategory: [
                "groceries": [anchors[1]: 450, anchors[2]: 1_000],
                "travel": [anchors[1]: 100, anchors[2]: 200],
            ],
            monthTotals: [
                anchors[1]: .init(budget: 1_000, used: 700),
                anchors[2]: .init(budget: 1_000, used: 1_200),
            ])

        let differences = history.outsideDifferences(from: nil, through: nil)
        XCTAssertEqual(differences.map(\.reason), [.categoriesAboveBudget, .otherMonth])
        // Month 2: whole -200, groceries +100 -> -300 the outside series cannot hold.
        XCTAssertEqual(differences.first?.months, [anchors[2]])
        XCTAssertEqual(differences.first?.amount, -300)
        XCTAssertEqual(differences.last?.amount, -150)
        XCTAssertEqual(differences.reduce(0) { $0 + $1.amount }, history.outsideTiming(from: nil, through: nil))
    }

    func testOthersKeepsItsPartsBiggestFirst() {
        // Five closed months: +50, +40, +30, +20, -10. Others holds the +20.
        let wrapped = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            wholeMonth: series([(100, 50), (100, 60), (100, 70), (100, 80), (100, 110), (100, 1)]),
            categories: [])
        let result = wrapped.contributors(for: .wholeMonth, from: nil, through: nil)
        XCTAssertEqual(result?.rest.map(\.net), [20])
        XCTAssertEqual(result?.others, 20)
    }

    func testClosedMonthAnchorsLeaveOutTheOpenMonth() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current, allocations: [], spentByCategory: [:],
            monthTotals: [:])
        XCTAssertEqual(history.closedMonthAnchors, Array(anchors.dropLast()))
    }

    // MARK: - Trimming and windows

    func testLeadingEmptyMonthsAreTrimmedButGapsInsideAreKept() {
        let trimmed = series([(0, 0), (0, 0), (100, 50), (0, 0), (100, 60), (100, 10)])
            .trimmingLeadingEmptyMonths()
        XCTAssertEqual(trimmed.months.map(\.monthAnchor), Array(anchors[2...]))
    }

    func testTrimmingAlwaysKeepsTheOpenMonth() {
        let trimmed = series([(0, 0), (0, 0), (0, 0)]).trimmingLeadingEmptyMonths()
        XCTAssertEqual(trimmed.months.map(\.monthAnchor), [anchors[2]])
    }

    func testSuffixKeepsTheMostRecentMonths() {
        let lastThree = series([(1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6)]).suffix(3)
        XCTAssertEqual(lastThree.months.map(\.monthAnchor), Array(anchors[3...]))
    }

    // MARK: - Building from the ledger

    private func allocation(
        _ category: TransactionCategory, _ index: Int, _ amount: Int
    ) -> BudgetAllocation {
        BudgetAllocation(monthDate: anchors[index], category: category, allocatedAmount: amount)
    }

    func testCategoryMonthsPairTheirAllocationWithTheirSpending() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.groceries, 4, 500), allocation(.groceries, 5, 500)],
            spentByCategory: ["groceries": [anchors[4]: 650, anchors[5]: 120]],
            monthTotals: [:])

        let groceries = history.series(for: .category(.groceries))
        XCTAssertEqual(groceries?.month(anchors[4])?.status, .over)
        XCTAssertEqual(groceries?.month(anchors[4])?.spent, 650)
        XCTAssertEqual(groceries?.month(anchors[5])?.status, .inProgress)
        XCTAssertEqual(groceries?.month(anchors[3])?.status, .empty)
    }

    func testTwoRowsForOneCategoryAndMonthAreSummed() {
        // A legacy ledger can hold a pair; measuring against one would judge spending by half a plan.
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [allocation(.meals, 2, 100), allocation(.meals, 2, 50)],
            spentByCategory: [:], monthTotals: [:])
        XCTAssertEqual(history.series(for: .category(.meals))?.month(anchors[2])?.planned, 150)
    }

    func testCategoriesWithNoPlanInTheWindowGetNoChip() {
        let outside = BudgetAllocation(
            monthDate: anchors[0] - 2_678_400, category: .travel, allocatedAmount: 900)
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [outside, allocation(.gifts, 1, 0)],
            spentByCategory: ["travel": [anchors[1]: 300], "gifts": [anchors[1]: 20]],
            monthTotals: [:])

        XCTAssertNil(history.series(for: .category(.travel)))
        XCTAssertNil(history.series(for: .category(.gifts)))
        XCTAssertEqual(history.filters, [.wholeMonth])
    }

    func testCategoriesAreOrderedByThisMonthsPlanThenByTheWindowsTotal() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current,
            allocations: [
                allocation(.meals, 5, 200),
                allocation(.groceries, 5, 800),
                // No plan this month, but the biggest plan across the window.
                allocation(.travel, 1, 5_000),
                allocation(.gifts, 1, 10),
            ],
            spentByCategory: [:], monthTotals: [:])

        XCTAssertEqual(
            history.filters,
            [.wholeMonth, .category(.groceries), .category(.meals), .category(.travel), .category(.gifts)])
    }

    func testWholeMonthComesFromTheMonthTotals() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current, allocations: [], spentByCategory: [:],
            monthTotals: [
                anchors[3]: .init(budget: 1_000, used: 1_200),
                anchors[4]: .init(budget: nil, used: 300),
            ])

        XCTAssertEqual(history.wholeMonth.month(anchors[3])?.status, .over)
        XCTAssertEqual(history.wholeMonth.month(anchors[4])?.status, .noPlan)
        XCTAssertEqual(history.wholeMonth.month(anchors[0])?.status, .empty)
        XCTAssertFalse(history.isEmpty)
    }

    func testANewLedgerIsEmpty() {
        let history = BudgetHistory(
            monthAnchors: anchors, currentAnchor: current, allocations: [], spentByCategory: [:],
            monthTotals: [:])
        XCTAssertTrue(history.isEmpty)
    }
}
