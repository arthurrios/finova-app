//
//  ProjectionExplainerViewModelTests.swift
//  FinovaTests
//
//  The sheet that explains the allocations card's projected balance.
//
//  Its whole value is agreeing with the card, so most of these assert that it relabels
//  `AllocationBalanceProjection`'s terms rather than recomputing anything.
//

import Foundation
import XCTest

@testable import Finova

final class ProjectionExplainerViewModelTests: XCTestCase {

    private let anchor = 1_767_225_600

    private func allocation(
        _ category: TransactionCategory, allocated: Int, used: Int
    ) -> BudgetAllocation {
        BudgetAllocation(
            dbId: nil, monthDate: anchor, category: category,
            allocatedAmount: allocated, usedAmount: used)
    }

    private func viewModel(
        base: Int = 350_000,
        allocations: [BudgetAllocation] = [],
        deferredCardSpending: Int = 0,
        tense: AllocationBalanceProjection.Tense = .projected,
        balanceDay: Int = 31
    ) -> ProjectionExplainerViewModel {
        ProjectionExplainerViewModel(
            projection: AllocationBalanceProjection(
                base: base,
                allocations: allocations,
                deferredCardSpending: deferredCardSpending,
                tense: tense),
            balanceDay: balanceDay,
            allocations: allocations,
            monthAnchor: anchor,
            ledgerScope: .personal)
    }

    // MARK: - The formula agrees with the projection

    /// The point of the sheet. If the itemised lines did not reduce to the card's own figure, the
    /// explanation would be worse than no explanation.
    func testTheLinesReduceToTheProjectedFigure() {
        let model = viewModel(
            base: 350_000,
            allocations: [allocation(.market, allocated: 120_000, used: 45_000)],
            deferredCardSpending: 45_000)

        let lines = model.formulaLines
        let base = lines.first { $0.kind == .base }?.amount
        let subtractions = lines.filter { $0.kind == .subtraction }.reduce(0) { $0 + $1.amount }
        let result = lines.first { $0.kind == .result }?.amount

        XCTAssertEqual(base, 350_000)
        XCTAssertEqual(subtractions, 45_000 + 75_000, "card debt plus the unspent plan")
        XCTAssertEqual(result, 230_000)
        XCTAssertEqual((base ?? 0) - subtractions, result)
    }

    func testTheBaseIsFirstAndTheResultIsLast() {
        let lines = viewModel(
            allocations: [allocation(.market, allocated: 100_000, used: 10_000)],
            deferredCardSpending: 5_000
        ).formulaLines

        XCTAssertEqual(lines.first?.kind, .base)
        XCTAssertEqual(lines.last?.kind, .result)
        XCTAssertEqual(lines.filter { $0.kind == .base }.count, 1)
        XCTAssertEqual(lines.filter { $0.kind == .result }.count, 1)
    }

    /// A line that changes nothing is noise in an explanation.
    func testZeroTermsAreOmitted() {
        let noCardDebt = viewModel(
            allocations: [allocation(.market, allocated: 100_000, used: 10_000)],
            deferredCardSpending: 0)

        XCTAssertEqual(
            noCardDebt.formulaLines.filter { $0.kind == .subtraction }.count, 1,
            "only the unspent plan should appear")
    }

    func testAFullySpentPlanWithNoCardDebtShowsNoSubtractionsAtAll() {
        let model = viewModel(
            allocations: [allocation(.market, allocated: 100_000, used: 100_000)],
            deferredCardSpending: 0)

        let lines = model.formulaLines
        XCTAssertTrue(lines.filter { $0.kind == .subtraction }.isEmpty)
        // The base and the result still appear, or the sheet would explain nothing.
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first?.amount, lines.last?.amount)
    }

    /// Subtraction amounts are unsigned - the view adds the minus. Otherwise a negative stored here
    /// would render as a double minus.
    func testSubtractionAmountsAreUnsigned() {
        let lines = viewModel(
            allocations: [allocation(.market, allocated: 100_000, used: 0)],
            deferredCardSpending: 30_000
        ).formulaLines

        for line in lines where line.kind == .subtraction {
            XCTAssertGreaterThan(line.amount, 0)
        }
    }

    func testANegativeProjectionIsCarriedThroughToTheResult() {
        let model = viewModel(
            base: 20_000,
            allocations: [allocation(.market, allocated: 100_000, used: 0)])

        XCTAssertEqual(model.formulaLines.last?.amount, -80_000)
    }

    /// A closed month exempts nothing today, so the card term still appears. Pinned so that if the
    /// tense rule is ever revisited, this sheet is remembered as a second place it shows.
    func testAClosedMonthStillItemisesTheCardTerm() {
        let model = viewModel(
            allocations: [allocation(.market, allocated: 100_000, used: 40_000)],
            deferredCardSpending: 25_000,
            tense: .actual)

        let subtractions = model.formulaLines.filter { $0.kind == .subtraction }
        XCTAssertEqual(subtractions.count, 2)
        XCTAssertEqual(subtractions.reduce(0) { $0 + $1.amount }, 25_000 + 60_000)
    }

    // MARK: - Copy

    func testTheBalanceLineNamesTheDayItRefersTo() {
        let label = viewModel(balanceDay: 31).formulaLines.first?.label

        XCTAssertNotNil(label)
        XCTAssertTrue(
            label?.contains(31.localizedDayOfMonth) == true,
            "every figure on this card is end-of-period, so the day has to be named")
    }

    func testTheNoteExplainsWhyTheFigureIsUsuallyBeaten() {
        XCTAssertFalse(viewModel().formulaNote.isEmpty)
        XCTAssertNotEqual(
            viewModel().formulaNote, "projection.explainer.formula.note",
            "the key must be localized, not echoed back")
    }

    // MARK: - History table

    func testNoAllocationsMeansNoHistoryRowsAndAStandInMessage() {
        let model = viewModel(allocations: [])

        XCTAssertTrue(model.historyRows.isEmpty)
        XCTAssertNotNil(
            model.historyEmptyText, "an empty table must say why rather than render as a gap")
    }

    /// A fresh ledger has allocations but no closed months behind them, so every row falls to "not
    /// enough history" - and the table as a whole should then read as empty rather than as a wall of
    /// dashes.
    func testRowsWithNoRangeAtAllCollapseToTheStandInMessage() {
        let model = viewModel(
            allocations: [
                allocation(.market, allocated: 100_000, used: 10_000),
                allocation(.meals, allocated: 50_000, used: 5_000)
            ])

        XCTAssertEqual(model.historyRows.count, 2)
        XCTAssertTrue(
            model.historyRows.allSatisfy { $0.range == nil },
            "no closed months were seeded, so no row can have a range")
        XCTAssertNotNil(model.historyEmptyText)
    }

    func testRowsFollowTheOrderTheCardListsThem() {
        let model = viewModel(
            allocations: [
                allocation(.market, allocated: 100_000, used: 0),
                allocation(.meals, allocated: 50_000, used: 0),
                allocation(.utilities, allocated: 20_000, used: 0)
            ])

        XCTAssertEqual(
            model.historyRows.map(\.categoryName),
            [
                TransactionCategory.market.displayName,
                TransactionCategory.meals.displayName,
                TransactionCategory.utilities.displayName
            ])
    }

    func testEveryRowCarriesADetailEvenWithoutARange() {
        let model = viewModel(allocations: [allocation(.market, allocated: 100_000, used: 0)])

        for row in model.historyRows {
            XCTAssertFalse(row.detail.isEmpty, "a row with no range must still say why")
        }
    }
}
