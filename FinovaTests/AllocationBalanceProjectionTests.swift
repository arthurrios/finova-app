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

    /// The three bar segments must always describe a whole, or nothing at all - the bar fills the
    /// width whenever there is something to divide, so the comparison stays readable.
    private func assertSharesNormalised(
        _ projection: AllocationBalanceProjection,
        line: UInt = #line
    ) {
        let shares = projection.barShares
        let sum = shares.projected + shares.saved + shares.overspent
        if sum == 0 {
            XCTAssertEqual(shares.projected, 0, line: line)
            XCTAssertEqual(shares.saved, 0, line: line)
            XCTAssertEqual(shares.overspent, 0, line: line)
        } else {
            XCTAssertEqual(sum, 1.0, accuracy: 0.0001, line: line)
        }
        XCTAssertGreaterThanOrEqual(shares.projected, 0, line: line)
        XCTAssertGreaterThanOrEqual(shares.saved, 0, line: line)
        XCTAssertGreaterThanOrEqual(shares.overspent, 0, line: line)
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

    // MARK: - Deferred card spending

    /// The regression this term exists for. A card purchase consumes the month's plan but leaves the
    /// account on a later statement, so `base` does not move - and the projection used to climb by the
    /// amount of a spend.
    func testCardPurchaseDoesNotRaiseTheProjection() {
        // Market allocated 50.000 with 10.000 already spent, on a 100.000 balance.
        let before = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.market, allocated: 50_000, used: 10_000)],
            tense: .projected)

        // A 15.000 card purchase in Market, settling next month: usage rises, `base` cannot move
        // because the balance is cash-only.
        let after = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.market, allocated: 50_000, used: 25_000)],
            deferredCardSpending: 15_000,
            tense: .projected)

        XCTAssertEqual(before.projected, 60_000)
        XCTAssertEqual(
            after.projected, before.projected,
            "spending against the plan on a card must not change what the month is projected to keep")
    }

    /// Without the subtraction the same purchase inflates the projection - kept as the explicit
    /// statement of the bug, so nobody "simplifies" the term away.
    func testOmittingDeferredCardSpendingInflatesTheProjection() {
        let unsubtracted = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.market, allocated: 50_000, used: 25_000)],
            tense: .projected)

        XCTAssertEqual(unsubtracted.projected, 75_000, "the pre-fix behaviour: up by the 15.000 spent")
    }

    func testDeferredCardSpendingComesOffTheProjectionOnly() {
        let allocations = [allocation(.meals, allocated: 90_000, used: 52_000)]

        let withoutCard = AllocationBalanceProjection(
            base: 400_000, allocations: allocations,
            unallocatedSpending: 8_000, unallocatedHeadroom: 20_000, tense: .projected)
        let withCard = AllocationBalanceProjection(
            base: 400_000, allocations: allocations,
            unallocatedSpending: 8_000, unallocatedHeadroom: 20_000,
            deferredCardSpending: 30_000, tense: .projected)

        XCTAssertEqual(withCard.projected, withoutCard.projected - 30_000)
        // Money spent is neither kept nor off-plan, so no other quantity may move.
        XCTAssertEqual(withCard.unspentAllocations, withoutCard.unspentAllocations)
        XCTAssertEqual(withCard.totalSaved, withoutCard.totalSaved)
        XCTAssertEqual(withCard.overspent, withoutCard.overspent)
        XCTAssertEqual(withCard.netSaved, withoutCard.netSaved)
        XCTAssertEqual(withCard.usedWithinAllocations, withoutCard.usedWithinAllocations)
    }

    func testDeferredCardSpendingDefaultsToZero() {
        let projection = AllocationBalanceProjection(
            base: 100_000,
            allocations: [allocation(.meals, allocated: 40_000, used: 0)],
            tense: .projected)

        XCTAssertEqual(projection.deferredCardSpending, 0)
        XCTAssertEqual(projection.projected, 60_000)
    }

    func testNegativeDeferredCardSpendingIsIgnored() {
        // Defensive: the service counts expenses only, so a negative means the caller measured
        // something else - it must never invent money.
        let projection = AllocationBalanceProjection(
            base: 100_000, allocations: [], deferredCardSpending: -25_000, tense: .projected)

        XCTAssertEqual(projection.deferredCardSpending, 0)
        XCTAssertEqual(projection.projected, 100_000)
    }

    /// Card debt already run up is a real claim on the balance, so it can tip a month over on its own.
    func testCardDebtCanOverCommitAMonthTheAllocationsAloneWouldNot() {
        let allocations = [allocation(.meals, allocated: 30_000, used: 0)]

        let cashOnly = AllocationBalanceProjection(
            base: 40_000, allocations: allocations, tense: .projected)
        let withCard = AllocationBalanceProjection(
            base: 40_000, allocations: allocations,
            deferredCardSpending: 25_000, tense: .projected)

        XCTAssertFalse(cashOnly.isOverCommitted)
        XCTAssertTrue(withCard.isOverCommitted)
        XCTAssertEqual(withCard.projected, -15_000)
        XCTAssertEqual(withCard.shortfall, 15_000)
        assertSharesNormalised(withCard)
    }

    func testDeferredCardSpendingShrinksTheSurvivingBarSegment() {
        let allocations = [allocation(.meals, allocated: 100_000, used: 40_000)]

        let withoutCard = AllocationBalanceProjection(
            base: 400_000, allocations: allocations, tense: .projected)
        let withCard = AllocationBalanceProjection(
            base: 400_000, allocations: allocations,
            deferredCardSpending: 100_000, tense: .projected)

        XCTAssertLessThan(withCard.barShares.projected, withoutCard.barShares.projected)
        assertSharesNormalised(withCard)
        assertSharesNormalised(withoutCard)
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

    /// The bar compares the block's three quantities: what the balance ends up with, what is being
    /// saved, and what broke out of the plan.
    func testBarComparesProjectedAgainstSavedAndOverspent() {
        // R$4k balance, R$1k allocated with R$400 of it spent: R$600 unspent, so R$3.4k survives.
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.meals, allocated: 100_000, used: 40_000)],
            unallocatedHeadroom: 20_000,
            tense: .projected)

        XCTAssertEqual(projection.projected, 340_000)
        XCTAssertEqual(projection.totalSaved, 80_000)  // 60_000 unspent + 20_000 headroom
        XCTAssertEqual(projection.overspent, 0)

        let shares = projection.barShares
        XCTAssertEqual(shares.projected, 340_000 / 420_000, accuracy: 0.0001)
        XCTAssertEqual(shares.saved, 80_000 / 420_000, accuracy: 0.0001)
        XCTAssertEqual(shares.overspent, 0)
        assertSharesNormalised(projection)
    }

    /// The regression that prompted the three-segment bar: `projected` is what is left *after* savings
    /// come out, so it must never wear the colour that means "saved". Here the projection dwarfs the
    /// saved figure, and if the two were merged - or if projected took the green - the bar would claim
    /// almost everything is being kept.
    func testProjectedIsNotTheSavedAmount() {
        let projection = AllocationBalanceProjection(
            base: 400_000,
            allocations: [allocation(.savings, allocated: 50_000, used: 50_000)],
            tense: .projected)

        XCTAssertEqual(projection.projected, 400_000, "a fully funded allocation is already out")
        XCTAssertEqual(
            projection.totalSaved, 0,
            "money paid into a savings category left the account; it is not held")
        XCTAssertEqual(projection.barShares.projected, 1.0, accuracy: 0.0001)
        XCTAssertEqual(projection.barShares.saved, 0)
    }

    func testOverspendingGetsItsOwnSegment() {
        let projection = AllocationBalanceProjection(
            base: 300_000,
            allocations: [allocation(.meals, allocated: 100_000, used: 130_000)],
            unallocatedSpending: 20_000,
            tense: .projected)

        XCTAssertEqual(projection.overspent, 50_000)  // 30_000 overrun + 20_000 off-plan
        XCTAssertGreaterThan(projection.barShares.overspent, 0)
        assertSharesNormalised(projection)
    }

    /// An over-committed month cannot draw a negative width. The shortfall is named in the block's
    /// caption instead, so the bar shows only the quantities that do have a size.
    func testOverCommittedBarDropsTheProjectedSegment() {
        let projection = AllocationBalanceProjection(
            base: 50_000,
            allocations: [allocation(.meals, allocated: 200_000, used: 0)],
            tense: .projected)

        XCTAssertTrue(projection.isOverCommitted)
        XCTAssertEqual(projection.barShares.projected, 0)
        XCTAssertEqual(projection.barShares.saved, 1.0, accuracy: 0.0001)
        assertSharesNormalised(projection)
    }

    func testBarIsEmptyWhenThereIsNothingToCompare() {
        let projection = AllocationBalanceProjection(base: 0, allocations: [], tense: .projected)

        XCTAssertEqual(projection.barShares.projected, 0)
        XCTAssertEqual(projection.barShares.saved, 0)
        XCTAssertEqual(projection.barShares.overspent, 0)
        assertSharesNormalised(projection)
    }

    /// Both tenses read the same three quantities, so "saved" means one thing across the whole card.
    func testBarIsTenseIndependent() {
        let allocations = [
            allocation(.meals, allocated: 100_000, used: 25_000),
            allocation(.utilities, allocated: 40_000, used: 65_000),
        ]

        let projected = AllocationBalanceProjection(
            base: 400_000, allocations: allocations, tense: .projected)
        let actual = AllocationBalanceProjection(
            base: 400_000, allocations: allocations, tense: .actual)

        XCTAssertEqual(projected.barShares.projected, actual.barShares.projected, accuracy: 0.0001)
        XCTAssertEqual(projected.barShares.saved, actual.barShares.saved, accuracy: 0.0001)
        XCTAssertEqual(projected.barShares.overspent, actual.barShares.overspent, accuracy: 0.0001)
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
            actual.headlineAmount, actual.netSaved,
            "a closed month leads with its verdict, not a capped spend figure")
        XCTAssertNotEqual(
            actual.headlineAmount, actual.usedWithinAllocations,
            "the old headline was capped per category and disagreed with the footer's Used")
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
        XCTAssertEqual(actual.overspent, 20_000)
        XCTAssertEqual(actual.headlineAmount, actual.netSaved)
    }
}
