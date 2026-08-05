//
//  AllocationTagBreakdownTests.swift
//  FinovaTests
//
//  Per-tag subtotals and the donut's segment order, on the allocations card.
//

import Foundation
import XCTest

@testable import Finova

final class AllocationTagBreakdownTests: XCTestCase {

    private let anchor = 1_767_225_600  // arbitrary; the type never reads a date

    // MARK: - Fixtures

    private func allocation(
        _ category: TransactionCategory,
        allocated: Int,
        used: Int = 0
    ) -> BudgetAllocation {
        BudgetAllocation(
            dbId: nil,
            monthDate: anchor,
            category: category,
            allocatedAmount: allocated,
            usedAmount: used)
    }

    private func spending(
        _ category: TransactionCategory,
        spent: Int
    ) -> UnallocatedCategorySpending {
        UnallocatedCategorySpending(category: category, spentAmount: spent, monthDate: anchor)
    }

    private func tag(_ id: String, _ name: String, order: Int) -> AllocationTag {
        AllocationTag(id: id, name: name, colorIndex: order, sortOrder: order)
    }

    private let essentials = AllocationTag(
        id: "t-essentials", name: "Essentials", colorIndex: 0, sortOrder: 0)
    private let wealth = AllocationTag(id: "t-wealth", name: "Wealth", colorIndex: 1, sortOrder: 1)

    /// The scenario from the design discussion: investments dominate the plan, and the living costs
    /// worth tracking sit inside what is left.
    private func makeStandardBreakdown() -> AllocationTagBreakdown {
        AllocationTagBreakdown(
            allocations: [
                allocation(.investments, allocated: 560_000, used: 560_000),
                allocation(.homeMaintenance, allocated: 200_000, used: 200_000),
                allocation(.groceries, allocated: 60_000, used: 48_000),
                allocation(.transportation, allocated: 40_000, used: 31_000),
                allocation(.utilities, allocated: 30_000, used: 27_500),
            ],
            unallocatedSpending: [],
            unallocatedHeadroom: 110_000,
            totalBudget: 1_000_000,
            tags: [essentials, wealth],
            categoryTagIds: [
                TransactionCategory.investments.key: wealth.id,
                TransactionCategory.homeMaintenance.key: essentials.id,
                TransactionCategory.groceries.key: essentials.id,
                TransactionCategory.transportation.key: essentials.id,
                TransactionCategory.utilities.key: essentials.id,
            ])
    }

    // MARK: - Subtotals

    func testTagAllocatedIsTheSumOfItsMemberAllocations() {
        let breakdown = makeStandardBreakdown()

        // 200_000 + 60_000 + 40_000 + 30_000
        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.allocated, 330_000)
        XCTAssertEqual(breakdown.arc(id: wealth.id)?.bucket.allocated, 560_000)
    }

    func testTagUsedIncludesEveryMemberSpend() {
        let breakdown = makeStandardBreakdown()

        // 200_000 + 48_000 + 31_000 + 27_500
        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.used, 306_500)
        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.remaining, 23_500)
    }

    func testShareIsMeasuredAgainstTheMonthsBudget() {
        let breakdown = makeStandardBreakdown()

        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.share ?? 0, 0.33, accuracy: 0.0001)
        XCTAssertEqual(breakdown.arc(id: wealth.id)?.bucket.share ?? 0, 0.56, accuracy: 0.0001)
    }

    /// Off-plan spend has no plan behind it, so it must not inflate a sub-budget - it lands in `used`
    /// and `offPlan`, widens the arc, and leaves `allocated` and `share` alone.
    func testOffPlanSpendWidensTheArcButNotTheSubBudget() {
        let breakdown = AllocationTagBreakdown(
            allocations: [allocation(.groceries, allocated: 60_000, used: 48_000)],
            unallocatedSpending: [spending(.transportation, spent: 25_000)],
            unallocatedHeadroom: 0,
            totalBudget: 100_000,
            tags: [essentials],
            categoryTagIds: [
                TransactionCategory.groceries.key: essentials.id,
                TransactionCategory.transportation.key: essentials.id,
            ])

        let bucket = breakdown.arc(id: essentials.id)?.bucket
        XCTAssertEqual(bucket?.allocated, 60_000)
        XCTAssertEqual(bucket?.offPlan, 25_000)
        XCTAssertEqual(bucket?.used, 73_000)
        XCTAssertEqual(bucket?.angularAmount, 85_000)
        XCTAssertEqual(bucket?.share ?? 0, 0.6, accuracy: 0.0001)
    }

    /// The figures a tag reports must be the same ones the card computes, or the chip and the
    /// projection block will disagree about the same month.
    func testUnspentAndOverspentMatchTheCardsOwnHelpers() {
        let members = [
            allocation(.groceries, allocated: 60_000, used: 48_000),
            allocation(.meals, allocated: 30_000, used: 44_000),
        ]
        let breakdown = AllocationTagBreakdown(
            allocations: members,
            unallocatedSpending: [],
            unallocatedHeadroom: 0,
            totalBudget: 100_000,
            tags: [essentials],
            categoryTagIds: [
                TransactionCategory.groceries.key: essentials.id,
                TransactionCategory.meals.key: essentials.id,
            ])

        let bucket = breakdown.arc(id: essentials.id)?.bucket
        XCTAssertEqual(bucket?.unspent, AllocationBalanceProjection.unspent(allocations: members))
        XCTAssertEqual(
            bucket?.overspent,
            AllocationBalanceProjection.overspent(allocations: members, unallocatedSpending: 0))
        XCTAssertEqual(bucket?.overspent, 14_000)
        XCTAssertTrue(bucket?.isOverspent ?? false)
    }

    // MARK: - Segment order

    /// Arc order follows the user's arrangement, not the amounts.
    ///
    /// `wealth` holds the far bigger slice (investments, 560k) and still comes second, because
    /// `essentials` sits above it on the tags screen. This used to be total-descending with `sortOrder`
    /// only as a tiebreaker, which meant dragging a tag had no visible effect on the donut whenever the
    /// two differed in size — i.e. almost always.
    func testTagsFollowTheUserOrderAndMembersStayContiguous() {
        let breakdown = makeStandardBreakdown()

        XCTAssertEqual(breakdown.tagArcs.map { $0.id }, [essentials.id, wealth.id])

        // Every member of a tag must sit in one unbroken run, or the ring cannot span them.
        for arc in breakdown.tagArcs {
            let positions = breakdown.segments.enumerated()
                .filter { arc.memberSegmentIDs.contains($0.element.id) }
                .map { $0.offset }
            XCTAssertEqual(
                positions, Array(positions.first!...positions.last!),
                "\(arc.tag.name) members are not contiguous")
        }
    }

    /// Reordering on the tags screen has to move the arcs, whatever the relative sizes are.
    func testReorderingTagsReordersTheArcs() {
        let promotedWealth = AllocationTag(
            id: wealth.id, name: wealth.name, colorIndex: 1, sortOrder: 0)
        let demotedEssentials = AllocationTag(
            id: essentials.id, name: essentials.name, colorIndex: 0, sortOrder: 1)

        let breakdown = AllocationTagBreakdown(
            allocations: [
                allocation(.investments, allocated: 560_000, used: 560_000),
                allocation(.groceries, allocated: 60_000, used: 48_000),
            ],
            unallocatedSpending: [],
            unallocatedHeadroom: 0,
            totalBudget: 620_000,
            tags: [demotedEssentials, promotedWealth],
            categoryTagIds: [
                TransactionCategory.investments.key: wealth.id,
                TransactionCategory.groceries.key: essentials.id,
            ])

        XCTAssertEqual(breakdown.tagArcs.map { $0.id }, [wealth.id, essentials.id])
    }

    /// `id` still breaks ties, so two tags that somehow share a `sortOrder` cannot swap between
    /// launches and make the donut visibly reshuffle for no reason.
    func testEqualSortOrdersFallBackToAStableOrder() {
        let a = AllocationTag(id: "t-aaa", name: "A", colorIndex: 0, sortOrder: 0)
        let b = AllocationTag(id: "t-bbb", name: "B", colorIndex: 1, sortOrder: 0)

        let breakdown = AllocationTagBreakdown(
            allocations: [
                allocation(.groceries, allocated: 10_000, used: 0),
                allocation(.investments, allocated: 90_000, used: 0),
            ],
            unallocatedSpending: [],
            unallocatedHeadroom: 0,
            totalBudget: 100_000,
            tags: [b, a],
            categoryTagIds: [
                TransactionCategory.groceries.key: a.id,
                TransactionCategory.investments.key: b.id,
            ])

        XCTAssertEqual(breakdown.tagArcs.map { $0.id }, ["t-aaa", "t-bbb"])
    }

    func testHeadroomIsAlwaysTheLastSegment() {
        let breakdown = makeStandardBreakdown()

        XCTAssertEqual(breakdown.segments.last?.kind, .headroom)
        XCTAssertEqual(breakdown.segments.last?.amount, 110_000)
        XCTAssertNil(breakdown.segments.last?.tagId)
    }

    /// With no tags the donut must draw exactly what it drew before this feature existed: allocations
    /// by amount descending, then off-plan spend by amount descending, then headroom.
    func testWithoutTagsTheSegmentOrderMatchesTheLegacyOrder() {
        let breakdown = AllocationTagBreakdown(
            allocations: [
                allocation(.groceries, allocated: 60_000),
                allocation(.investments, allocated: 560_000),
                allocation(.utilities, allocated: 30_000),
            ],
            unallocatedSpending: [spending(.meals, spent: 12_000), spending(.travel, spent: 40_000)],
            unallocatedHeadroom: 50_000,
            totalBudget: 1_000_000,
            tags: [],
            categoryTagIds: [:])

        XCTAssertFalse(breakdown.hasTags)
        XCTAssertTrue(breakdown.tagArcs.isEmpty)
        XCTAssertNil(breakdown.untagged)
        XCTAssertEqual(
            breakdown.segments.map { $0.id },
            [
                "alloc-investments", "alloc-groceries", "alloc-utilities",
                "offplan-travel", "offplan-meals",
                "headroom",
            ])
    }

    /// Same requirement as above, reached the other way: a user who made tags but has not linked any
    /// category yet must still see the untouched card.
    func testTagsThatMatchNothingThisMonthChangeNothing() {
        let breakdown = AllocationTagBreakdown(
            allocations: [allocation(.groceries, allocated: 60_000)],
            unallocatedSpending: [],
            unallocatedHeadroom: 0,
            totalBudget: 100_000,
            tags: [essentials, wealth],
            categoryTagIds: [TransactionCategory.travel.key: essentials.id])

        XCTAssertFalse(breakdown.hasTags)
        XCTAssertTrue(breakdown.tagArcs.isEmpty)
        XCTAssertNil(breakdown.untagged, "a lone Untagged chip covering everything is noise")
        XCTAssertEqual(breakdown.segments.map { $0.id }, ["alloc-groceries"])
    }

    func testAnIdleTagGetsNoArcAndNoChip() {
        let breakdown = makeStandardBreakdown()

        let idle = tag("t-idle", "Idle", order: 5)
        let withIdle = AllocationTagBreakdown(
            allocations: [allocation(.groceries, allocated: 60_000)],
            unallocatedSpending: [],
            unallocatedHeadroom: 0,
            totalBudget: 100_000,
            tags: [essentials, idle],
            categoryTagIds: [TransactionCategory.groceries.key: essentials.id])

        XCTAssertEqual(breakdown.tagArcs.count, 2)
        XCTAssertEqual(withIdle.tagArcs.map { $0.id }, [essentials.id])
        XCTAssertNil(withIdle.arc(id: idle.id))
    }

    // MARK: - Untagged and headroom

    func testUntaggedIsItsOwnBucketOnceSomethingIsTagged() {
        let breakdown = AllocationTagBreakdown(
            allocations: [
                allocation(.groceries, allocated: 60_000, used: 48_000),
                allocation(.travel, allocated: 25_000, used: 10_000),
            ],
            unallocatedSpending: [],
            unallocatedHeadroom: 15_000,
            totalBudget: 100_000,
            tags: [essentials],
            categoryTagIds: [TransactionCategory.groceries.key: essentials.id])

        XCTAssertEqual(breakdown.untagged?.allocated, 25_000)
        XCTAssertEqual(breakdown.untagged?.used, 10_000)
    }

    /// Headroom belongs to no tag *and* to no untagged bucket. Folding it into untagged would make the
    /// chip disagree with the footer's own "Unallocated" figure.
    func testHeadroomIsExcludedFromEveryBucket() {
        let breakdown = AllocationTagBreakdown(
            allocations: [
                allocation(.groceries, allocated: 60_000),
                allocation(.travel, allocated: 25_000),
            ],
            unallocatedSpending: [],
            unallocatedHeadroom: 15_000,
            totalBudget: 100_000,
            tags: [essentials],
            categoryTagIds: [TransactionCategory.groceries.key: essentials.id])

        XCTAssertEqual(breakdown.headroom, 15_000)
        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.allocated, 60_000)
        XCTAssertEqual(breakdown.untagged?.allocated, 25_000)
        XCTAssertEqual(
            breakdown.tagArcs.reduce(0) { $0 + $1.bucket.allocated } + (breakdown.untagged?.allocated ?? 0),
            85_000,
            "headroom must not appear in any bucket's allocated total")
    }

    func testNegativeHeadroomClampsToZeroAndLeavesTheDomain() {
        let breakdown = AllocationTagBreakdown(
            allocations: [allocation(.groceries, allocated: 60_000)],
            unallocatedSpending: [],
            unallocatedHeadroom: -20_000,
            totalBudget: 40_000,
            tags: [essentials],
            categoryTagIds: [TransactionCategory.groceries.key: essentials.id])

        XCTAssertEqual(breakdown.headroom, 0)
        XCTAssertEqual(breakdown.angularTotal, 60_000)
        XCTAssertFalse(breakdown.segments.contains { $0.kind == .headroom })
    }

    func testZeroBudgetYieldsNoShareRatherThanADivideByZero() {
        let breakdown = AllocationTagBreakdown(
            allocations: [allocation(.groceries, allocated: 60_000)],
            unallocatedSpending: [],
            unallocatedHeadroom: 0,
            totalBudget: 0,
            tags: [essentials],
            categoryTagIds: [TransactionCategory.groceries.key: essentials.id])

        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.share, 0)
        XCTAssertEqual(breakdown.arc(id: essentials.id)?.bucket.allocated, 60_000)
    }

    func testATagWithOnlyOffPlanSpendStillGetsAnArc() {
        let breakdown = AllocationTagBreakdown(
            allocations: [],
            unallocatedSpending: [spending(.transportation, spent: 25_000)],
            unallocatedHeadroom: 0,
            totalBudget: 100_000,
            tags: [essentials],
            categoryTagIds: [TransactionCategory.transportation.key: essentials.id])

        let bucket = breakdown.arc(id: essentials.id)?.bucket
        XCTAssertNotNil(bucket, "the ring geometry needs an arc wherever the donut has slices")
        XCTAssertEqual(bucket?.allocated, 0)
        XCTAssertEqual(bucket?.share, 0)
        XCTAssertEqual(bucket?.angularAmount, 25_000)
    }

    // MARK: - Invariants

    /// The donut normalises by the sum of every slice, so the ring's fractions are only correct while
    /// `angularTotal` equals that sum. Drift here shows up as arcs that no longer cap their members.
    func testAngularTotalIsTheSumOfEverySegment() {
        for breakdown in [makeStandardBreakdown(), makeMixedBreakdown()] {
            XCTAssertEqual(
                breakdown.angularTotal,
                breakdown.segments.reduce(0) { $0 + $1.amount })
        }
    }

    func testBucketAngularAmountsPlusHeadroomAccountForTheWholeDomain() {
        let breakdown = makeMixedBreakdown()

        let sum =
            breakdown.tagArcs.reduce(0) { $0 + $1.bucket.angularAmount }
            + (breakdown.untagged?.angularAmount ?? 0)
            + breakdown.headroom
        XCTAssertEqual(sum, breakdown.angularTotal)
    }

    func testArcFractionsAreMonotoneAndStartAtZero() {
        let breakdown = makeStandardBreakdown()

        XCTAssertEqual(breakdown.tagArcs.first?.startFraction ?? -1, 0, accuracy: 0.0001)
        var previousEnd = 0.0
        for arc in breakdown.tagArcs {
            XCTAssertEqual(arc.startFraction, previousEnd, accuracy: 0.0001)
            XCTAssertGreaterThan(arc.endFraction, arc.startFraction)
            previousEnd = arc.endFraction
        }
        XCTAssertLessThanOrEqual(previousEnd, 1.0)
    }

    func testEverySegmentBelongsToAtMostOneTag() {
        let breakdown = makeMixedBreakdown()

        for segment in breakdown.segments {
            let owners = breakdown.tagArcs.filter { $0.memberSegmentIDs.contains(segment.id) }
            XCTAssertLessThanOrEqual(owners.count, 1, "\(segment.id) is claimed by \(owners.count) tags")
            XCTAssertEqual(owners.first?.id, segment.tagId)
        }
    }

    func testSegmentMembershipLookupAgreesWithTheArcs() {
        let breakdown = makeStandardBreakdown()

        XCTAssertTrue(breakdown.segment("alloc-groceries", belongsTo: essentials.id))
        XCTAssertFalse(breakdown.segment("alloc-groceries", belongsTo: wealth.id))
        XCTAssertFalse(breakdown.segment("headroom", belongsTo: essentials.id))
    }

    func testEmptyBreakdownIsInert() {
        let breakdown = AllocationTagBreakdown.empty

        XCTAssertFalse(breakdown.hasTags)
        XCTAssertTrue(breakdown.segments.isEmpty)
        XCTAssertNil(breakdown.untagged)
        XCTAssertEqual(breakdown.angularTotal, 0)
    }

    /// Everything at once: two tags, an untagged category, off-plan spend on both sides, and headroom.
    private func makeMixedBreakdown() -> AllocationTagBreakdown {
        AllocationTagBreakdown(
            allocations: [
                allocation(.investments, allocated: 560_000, used: 560_000),
                allocation(.homeMaintenance, allocated: 200_000, used: 210_000),
                allocation(.groceries, allocated: 60_000, used: 48_000),
                allocation(.travel, allocated: 25_000, used: 5_000),
            ],
            unallocatedSpending: [
                spending(.transportation, spent: 31_000),
                spending(.entertainment, spent: 12_000),
            ],
            unallocatedHeadroom: 40_000,
            totalBudget: 1_000_000,
            tags: [essentials, wealth],
            categoryTagIds: [
                TransactionCategory.investments.key: wealth.id,
                TransactionCategory.homeMaintenance.key: essentials.id,
                TransactionCategory.groceries.key: essentials.id,
                TransactionCategory.transportation.key: essentials.id,
            ])
    }
}
