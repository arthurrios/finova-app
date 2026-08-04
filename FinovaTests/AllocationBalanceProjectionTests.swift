//
//  AllocationBalanceProjectionTests.swift
//  FinovaTests
//
//  Projected end-of-month balance, and the saved-vs-overspent comparison, on the allocations card.
//

import Foundation
import XCTest

@testable import Finova

final class AllocationBalanceProjectionTests: XCTestCase {

    private let anchor = 1_767_225_600  // arbitrary; the type never reads a date

    private func allocation(
        _ category: TransactionCategory,
        allocated: Int,
        used: Int
    ) -> BudgetAllocation {
        BudgetAllocation(
            dbId: nil,
            monthDate: anchor,
            category: category,
            allocatedAmount: allocated,
            usedAmount: used
        )
    }

    /// The two bar segments must always describe a whole, or nothing at all - the bar fills the
    /// width once anything has been spent, so the comparison stays readable.
    private func assertSharesNormalised(
        _ projection: AllocationBalanceProjection,
        line: UInt = #line
    ) {
        let shares = projection.barShares
        let sum = shares.withinPlan + shares.beyondPlan
        if sum == 0 {
            XCTAssertEqual(shares.withinPlan, 0, line: line)
            XCTAssertEqual(shares.beyondPlan, 0, line: line)
        } else {
            XCTAssertEqual(sum, 1.0, accuracy: 0.0001, line: line)
        }
        XCTAssertGreaterThanOrEqual(shares.withinPlan, 0, line: line)
        XCTAssertGreaterThanOrEqual(shares.beyondPlan, 0, line: line)
    }

    // MARK: - Projection arithmetic

    func testProjectedIsBalanceMinusUnspentAllocations() {
        let allocations = [
            allocation(.meals, allocated: 90_000, used: 52_000),
            allocation(.savings, allocated: 48_000, used: 0),
        ]
        let projection = AllocationBalanceProjection(
            base: 428_000, allocations: allocations, tense: .projected)

        XCTAssertEqual(
            projection.unspentAllocations,
            allocations.reduce(0) { $0 + max(0, $1.remainingAmount) })
        XCTAssertEqual(projection.base - projection.unspentAllocations, projection.projected)
    }

    func testNoAllocationsLeavesBalanceUntouchedAndPlotsNothing() {
        let projection = AllocationBalanceProjection(base: 428_000, allocations: [], tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 0)
        XCTAssertEqual(projection.overspent, 0)
        XCTAssertEqual(projection.netSaved, 0)
        XCTAssertEqual(projection.projected, 428_000)
        XCTAssertFalse(projection.isOverCommitted)
        assertSharesNormalised(projection)
    }

    func testOnlyUnspentRemainderIsSubtracted() {
        // 60.000 allocated, 40.000 already spent. That 40.000 is already inside `base`, so only
        // the outstanding 20.000 may be charged again.
        let projection = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.meals, allocated: 60_000, used: 40_000)],
            tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 20_000)
        XCTAssertEqual(projection.projected, 80_000)
    }

    func testOverspentAllocationClampsAndDoesNotCreditTheProjection() {
        // Spent 70.000 against a 50.000 budget. The overspend is already reflected in `base`;
        // a negative remainder must not add money back.
        let projection = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.meals, allocated: 50_000, used: 70_000)],
            tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 0)
        XCTAssertEqual(
            projection.projected, 100_000,
            "an overspent category must not raise the projection")
    }

    func testOverspentCategoryDoesNotOffsetAnotherCategorysHeadroom() {
        let projection = AllocationBalanceProjection(
            base: 100_000,
            allocations: [
                allocation(.meals, allocated: 50_000, used: 70_000),      // over by 20.000
                allocation(.transportation, allocated: 30_000, used: 0),  // fully outstanding
            ],
            tense: .projected)

        XCTAssertEqual(
            projection.unspentAllocations, 30_000,
            "clamping must be per-allocation, not on the sum")
        XCTAssertEqual(projection.projected, 70_000)
    }

    func testNegativeBaseIsCarriedThrough() {
        let projection = AllocationBalanceProjection(
            base: -20_000,
            allocations: [allocation(.meals, allocated: 10_000, used: 0)],
            tense: .projected)

        XCTAssertEqual(projection.projected, -30_000)
        XCTAssertTrue(projection.isOverCommitted)
    }

    // MARK: - Over-committed

    func testAllocationsExceedingBaseGoNegativeAndFlagOverCommitted() {
        let projection = AllocationBalanceProjection(
            base: 50_000,
            allocations: [allocation(.utilities, allocated: 90_000, used: 0)],
            tense: .projected)

        XCTAssertEqual(projection.projected, -40_000)
        XCTAssertTrue(projection.isOverCommitted)
        XCTAssertEqual(projection.shortfall, 40_000)
    }

    func testShortfallIsZeroWhenTheBalanceCoversTheAllocations() {
        let projection = AllocationBalanceProjection(
            base: 500_000,
            allocations: [allocation(.meals, allocated: 90_000, used: 0)],
            tense: .projected)

        XCTAssertFalse(projection.isOverCommitted)
        XCTAssertEqual(projection.shortfall, 0)
    }

    func testClosedMonthIsNeverFlaggedOverCommitted() {
        let actual = AllocationBalanceProjection(
            base: 50_000,
            allocations: [allocation(.utilities, allocated: 90_000, used: 0)],
            tense: .actual)

        XCTAssertLessThan(actual.projected, 0)
        XCTAssertFalse(
            actual.isOverCommitted,
            "a month that already closed cannot be over-committed")
    }

    // MARK: - Saved vs overspent

    /// Funding a savings or investment allocation debits the account, so it is not money kept -
    /// savings categories get no special treatment here.
    func testFundedSavingsAllocationsAreNotCountedAsSaved() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [
                allocation(.investments, allocated: 40_000, used: 40_000),  // fully funded
                allocation(.meals, allocated: 90_000, used: 90_000),        // fully spent
            ],
            tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 0)
        XCTAssertEqual(projection.usedWithinAllocations, 130_000)
        XCTAssertEqual(
            projection.totalSaved, 0,
            "money debited to a fund left the account, just like any other spend")
    }

    /// Cap never earmarked to a category is money the user neither planned to spend nor spent.
    func testUnallocatedHeadroomCountsAsSaved() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 90_000, used: 52_000)],
            unallocatedHeadroom: 26_500,
            tense: .projected)

        XCTAssertEqual(projection.unallocatedHeadroom, 26_500)
        XCTAssertEqual(projection.totalSaved, 38_000 + 26_500)
    }

    func testOverAllocationDoesNotReadAsNegativeSaving() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 90_000, used: 0)],
            unallocatedHeadroom: -20_000,  // allocated beyond the cap
            tense: .projected)

        XCTAssertEqual(projection.unallocatedHeadroom, 0)
        XCTAssertEqual(projection.totalSaved, 90_000)
    }

    func testSavedTermsDoNotOverlap() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [
                allocation(.meals, allocated: 90_000, used: 52_000),        // 38.000 unspent
                allocation(.investments, allocated: 40_000, used: 30_000),  // 10.000 unspent, 30.000 funded
            ],
            unallocatedHeadroom: 5_000,
            tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 48_000)
        XCTAssertEqual(projection.unallocatedHeadroom, 5_000)
        XCTAssertEqual(
            projection.totalSaved, 53_000,
            "only the unspent side plus untouched headroom - funded savings are excluded")
    }

    func testSavedIsWhatCameInUnderPlanAndOverspentIsEveryOverrun() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [
                allocation(.meals, allocated: 90_000, used: 52_000),      // 38.000 under
                allocation(.utilities, allocated: 60_000, used: 63_060),  // 3.060 over
                allocation(.donations, allocated: 44_000, used: 36_500),  // 7.500 under
            ],
            tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 45_500)
        XCTAssertEqual(projection.overspent, 3_060)
        XCTAssertEqual(projection.totalSaved, 45_500, "no savings categories, no headroom here")
        XCTAssertEqual(projection.netSaved, 42_440)
        assertSharesNormalised(projection)
    }

    /// Money spent in a category with no allocation had no plan behind it, so it counts as
    /// overspending. This is the only place on the card that surfaces off-plan spending.
    func testOffPlanSpendingCountsAsOverspent() {
        let allocations = [allocation(.meals, allocated: 90_000, used: 52_000)]

        let withoutOffPlan = AllocationBalanceProjection(
            base: 400_000, allocations: allocations, tense: .projected)
        let withOffPlan = AllocationBalanceProjection(
            base: 400_000, allocations: allocations,
            unallocatedSpending: 18_000, tense: .projected)

        XCTAssertEqual(withoutOffPlan.overspent, 0)
        XCTAssertEqual(withOffPlan.overspent, 18_000)
        // It must not disturb the projection - that money is already inside `base`.
        XCTAssertEqual(withOffPlan.projected, withoutOffPlan.projected)
        XCTAssertEqual(withOffPlan.netSaved, withoutOffPlan.netSaved - 18_000)
    }

    func testOverrunsAndOffPlanSpendingBothLandInOverspent() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 50_000, used: 70_000)],  // 20.000 over
            unallocatedSpending: 5_000,
            tense: .projected)

        XCTAssertEqual(projection.overspent, 25_000)
    }

    func testNetGoesNegativeWhenOverspendingDominates() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 50_000, used: 52_000)],  // 2.000 over
            unallocatedSpending: 40_000,
            tense: .projected)

        XCTAssertEqual(projection.unspentAllocations, 0)
        XCTAssertEqual(projection.overspent, 42_000)
        XCTAssertEqual(projection.netSaved, -42_000)
    }

    func testNegativeOffPlanSpendingIsIgnored() {
        // Defensive: a refund-heavy category could in principle net below zero upstream.
        let projection = AllocationBalanceProjection(
            base: 400_000, allocations: [], unallocatedSpending: -5_000, tense: .projected)

        XCTAssertEqual(projection.overspent, 0)
    }

    // MARK: - Bar

    /// The bar compares *spent* money, not saved money: an open month cannot have saved anything,
    /// so a bar built from `totalSaved` would erode as the month filled in.
    func testBarComparesSpendingInsideThePlanAgainstSpendingOutsideIt() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 100_000, used: 75_000)],
            unallocatedSpending: 25_000,
            tense: .projected)

        XCTAssertEqual(projection.usedWithinAllocations, 75_000)
        XCTAssertEqual(projection.overspent, 25_000)
        XCTAssertEqual(projection.barShares.withinPlan, 0.75, accuracy: 0.0001)
        XCTAssertEqual(projection.barShares.beyondPlan, 0.25, accuracy: 0.0001)
        assertSharesNormalised(projection)
    }

    func testBarIsAllGreenWhenEverySpendStayedInsideItsAllocation() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 100_000, used: 60_000)],
            tense: .projected)

        XCTAssertEqual(projection.barShares.withinPlan, 1.0, accuracy: 0.0001)
        XCTAssertEqual(projection.barShares.beyondPlan, 0)
    }

    func testBarIsEmptyBeforeAnythingIsSpent() {
        // A future month with allocations but no transactions yet: nothing to compare.
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 100_000, used: 0)],
            unallocatedHeadroom: 73_500,
            tense: .projected)

        XCTAssertEqual(projection.barShares.withinPlan, 0)
        XCTAssertEqual(projection.barShares.beyondPlan, 0)
        assertSharesNormalised(projection)
    }

    /// Regression for the real complaint: a future month's unspent allocations must not inflate the
    /// bar, because that money is earmarked for spending, not kept.
    func testUnspentAllocationsDoNotInflateTheBar() {
        // R$3.5k of allocations untouched, R$735 unallocated - nothing spent at all.
        let untouched = AllocationBalanceProjection(
            base: 4_290_000,
            allocations: [allocation(.market, allocated: 350_000, used: 0)],
            unallocatedHeadroom: 73_500,
            tense: .projected)

        XCTAssertEqual(
            untouched.barShares.withinPlan, 0,
            "a plan nobody has spent against yet says nothing about adherence")
        XCTAssertGreaterThan(
            untouched.totalSaved, 0,
            "totalSaved still tracks it - the card just does not surface it while the month is open")
    }

    func testBarIsTenseIndependent() {
        let allocations = [
            allocation(.meals, allocated: 100_000, used: 25_000),
            allocation(.utilities, allocated: 40_000, used: 65_000),
        ]

        let projected = AllocationBalanceProjection(
            base: 400_000, allocations: allocations, tense: .projected)
        let actual = AllocationBalanceProjection(
            base: 400_000, allocations: allocations, tense: .actual)

        XCTAssertEqual(projected.barShares.withinPlan, actual.barShares.withinPlan, accuracy: 0.0001)
        XCTAssertEqual(projected.barShares.beyondPlan, actual.barShares.beyondPlan, accuracy: 0.0001)
    }

    // MARK: - Closed-month headline

    func testClosedMonthReportsWhatTheAllocationsConsumed() {
        let actual = AllocationBalanceProjection(
            base: 300_000,
            allocations: [
                allocation(.meals, allocated: 60_000, used: 45_000),
                allocation(.savings, allocated: 40_000, used: 40_000),
            ],
            tense: .actual)

        XCTAssertEqual(actual.usedWithinAllocations, 85_000)
        XCTAssertEqual(
            actual.headlineAmount, 85_000,
            "a closed month leads with what the allocations consumed")
    }

    func testOpenMonthLeadsWithTheProjection() {
        let projection = AllocationBalanceProjection(
            base: 300_000,
            allocations: [allocation(.meals, allocated: 60_000, used: 45_000)],
            tense: .projected)

        XCTAssertEqual(projection.headlineAmount, projection.projected)
    }

    func testUsedAmountIsCappedAtAllocatedForTheClosedMonthHeadline() {
        // Overspent 70.000 against 50.000; the excess belongs in `overspent`, not the headline.
        let actual = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.meals, allocated: 50_000, used: 70_000)],
            tense: .actual)

        XCTAssertEqual(actual.usedWithinAllocations, 50_000)
        XCTAssertEqual(actual.headlineAmount, 50_000)
        XCTAssertEqual(actual.overspent, 20_000)
    }
}
