//
//  AllocationTagBreakdown.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import CoreGraphics
import Foundation

/// What each tag costs in one month, and the order the donut has to draw its slices in.
///
/// Like `AllocationBalanceProjection`, this type *consumes* values and computes nothing it could
/// fetch: no repository, no service, no `Date()`. That is what makes it scope-correct for free - the
/// caller hands it the arrays `BudgetAllocationService` already filtered by `LedgerScope`, with
/// `usedAmount` already keyed on by category, so a per-tag subtotal cannot disagree with the card it
/// sits on. Reaching for a repository from in here would silently break group scoping.
struct AllocationTagBreakdown: Equatable {

    // MARK: - Segment

    /// One drawable slice of the donut, in draw order.
    struct Segment: Equatable, Identifiable {

        enum Kind: Equatable {
            /// A category with a budget allocation.
            case allocated(categoryKey: String)
            /// A category that was spent in without an allocation - the card's grey slices.
            case offPlan(categoryKey: String)
            /// Budget cap never earmarked to any category.
            case headroom
        }

        let id: String
        let kind: Kind
        /// The slice's share of the angular domain, in minor units.
        let amount: Int
        /// `nil` for untagged categories, and always `nil` for `.headroom`.
        let tagId: String?

        var categoryKey: String? {
            switch kind {
            case .allocated(let key), .offPlan(let key): return key
            case .headroom: return nil
            }
        }
    }

    // MARK: - Bucket

    /// The money figures for one group of categories. Shared shape between a real tag and the
    /// untagged remainder so the chip strip can render both from one type.
    struct Bucket: Equatable {
        /// Σ allocated over member categories. **This is the sub-budget figure** the chip leads with.
        let allocated: Int
        /// Everything spent in member categories, planned or not. Deliberately uncapped, so
        /// `allocated - used` is an honest "left in this group" and may go negative.
        let used: Int
        /// Allocated but not yet spent, clamped per category.
        let unspent: Int
        /// Category overruns plus everything spent in member categories with no allocation.
        let overspent: Int
        /// Spend in member categories that had no allocation at all.
        let offPlan: Int
        /// The bucket's share of the donut's angular domain.
        let angularAmount: Int
        /// Fraction of the month's total budget this group plans to consume, 0...1.
        let share: Double

        var remaining: Int { allocated - used }
        var isOverspent: Bool { remaining < 0 }
    }

    /// A `Bucket` that owns a contiguous arc of the ring.
    struct TagArc: Equatable, Identifiable {
        let tag: AllocationTag
        let bucket: Bucket
        /// Segment ids belonging to this tag, for dimming non-members.
        let memberSegmentIDs: Set<String>
        /// Arc boundaries as fractions of the full circle, 0...1.
        let startFraction: Double
        let endFraction: Double

        var id: String { tag.id }
    }

    // MARK: - Stored

    let segments: [Segment]
    let tagArcs: [TagArc]
    /// Categories with money this month that belong to no tag. Absent when there is nothing untagged.
    let untagged: Bucket?
    /// Budget cap never earmarked, clamped at zero.
    let headroom: Int
    /// The denominator the donut normalises by. Must equal what the chart sums, or the ring and the
    /// slices drift apart.
    let angularTotal: Int
    let totalBudget: Int

    /// True when at least one tag has an arc this month. The card keys its whole appearance off this:
    /// false means render exactly as the app did before tags existed.
    var hasTags: Bool { !tagArcs.isEmpty }

    static let empty = AllocationTagBreakdown(
        segments: [], tagArcs: [], untagged: nil, headroom: 0, angularTotal: 0, totalBudget: 0)

    private init(
        segments: [Segment],
        tagArcs: [TagArc],
        untagged: Bucket?,
        headroom: Int,
        angularTotal: Int,
        totalBudget: Int
    ) {
        self.segments = segments
        self.tagArcs = tagArcs
        self.untagged = untagged
        self.headroom = headroom
        self.angularTotal = angularTotal
        self.totalBudget = totalBudget
    }

    // MARK: - Building

    /// - Parameters:
    ///   - allocations: the month's allocations, already scope-filtered with `usedAmount` populated.
    ///   - unallocatedSpending: spend in categories with no allocation, already scope-filtered.
    ///   - unallocatedHeadroom: `UnallocatedBudgetSummary.unallocatedAmount`. Clamped at zero here -
    ///     over-allocating is not overspending, and the footer already warns about it in amber.
    ///   - totalBudget: the month's cap, used only as the denominator for `share`.
    init(
        allocations: [BudgetAllocation],
        unallocatedSpending: [UnallocatedCategorySpending],
        unallocatedHeadroom: Int,
        totalBudget: Int,
        tags: [AllocationTag],
        categoryTagIds: [String: String]
    ) {
        let effectiveHeadroom = max(0, unallocatedHeadroom)

        // Only tags that actually have money this month get an arc. A tag whose categories are all
        // idle would otherwise draw a zero-width band and show a 0-value chip, which reads as a bug.
        var allocationsByTag: [String: [BudgetAllocation]] = [:]
        var spendingByTag: [String: [UnallocatedCategorySpending]] = [:]
        var untaggedAllocations: [BudgetAllocation] = []
        var untaggedSpending: [UnallocatedCategorySpending] = []

        for allocation in allocations {
            if let tagId = categoryTagIds[allocation.category.key], tags.contains(where: { $0.id == tagId }) {
                allocationsByTag[tagId, default: []].append(allocation)
            } else {
                untaggedAllocations.append(allocation)
            }
        }
        for spending in unallocatedSpending {
            if let tagId = categoryTagIds[spending.category.key], tags.contains(where: { $0.id == tagId }) {
                spendingByTag[tagId, default: []].append(spending)
            } else {
                untaggedSpending.append(spending)
            }
        }

        // Split across three statements rather than one chained sum: the single expression tipped the
        // type checker into an exponential solve ("unable to type-check in reasonable time").
        let allocatedTotal: Int = allocations.reduce(0) { $0 + $1.allocatedAmount }
        let offPlanTotal: Int = unallocatedSpending.reduce(0) { $0 + $1.spentAmount }
        let total: Int = allocatedTotal + offPlanTotal + effectiveHeadroom

        // Tag order is the user's own, then id.
        //
        // This used to be total desc with `sortOrder` only as a tiebreaker, so the biggest slice read
        // first. That is a reasonable default but it overrode the order the user set by dragging on the
        // tags screen — two tags of different sizes would ignore the arrangement entirely, which made
        // reordering look broken. An explicitly chosen order beats a derived one.
        //
        // `id` still breaks ties, so this remains a *total* order and the donut cannot reshuffle
        // between launches. Categories WITHIN a tag stay amount desc (see `sortedSegments`) — those are
        // enum cases with no user-defined order to respect.
        let liveTags = tags.filter { tag in
            !(allocationsByTag[tag.id] ?? []).isEmpty || !(spendingByTag[tag.id] ?? []).isEmpty
        }
        let orderedTags = liveTags.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
        }

        var builtSegments: [Segment] = []
        var builtArcs: [TagArc] = []
        var cumulative = 0

        for tag in orderedTags {
            let members = Self.sortedSegments(
                allocations: allocationsByTag[tag.id] ?? [],
                spending: spendingByTag[tag.id] ?? [],
                tagId: tag.id)
            guard !members.isEmpty else { continue }

            let start = cumulative
            builtSegments.append(contentsOf: members)
            cumulative += members.reduce(0) { $0 + $1.amount }

            builtArcs.append(
                TagArc(
                    tag: tag,
                    bucket: Self.bucket(
                        allocations: allocationsByTag[tag.id] ?? [],
                        spending: spendingByTag[tag.id] ?? [],
                        totalBudget: totalBudget),
                    memberSegmentIDs: Set(members.map { $0.id }),
                    startFraction: total > 0 ? Double(start) / Double(total) : 0,
                    endFraction: total > 0 ? Double(cumulative) / Double(total) : 0))
        }

        // Untagged next, then headroom last, so the tag arcs stay contiguous from 12 o'clock.
        builtSegments.append(contentsOf: Self.sortedSegments(
            allocations: untaggedAllocations, spending: untaggedSpending, tagId: nil))

        if effectiveHeadroom > 0 {
            builtSegments.append(
                Segment(id: "headroom", kind: .headroom, amount: effectiveHeadroom, tagId: nil))
        }

        let untaggedBucket: Bucket?
        if builtArcs.isEmpty || (untaggedAllocations.isEmpty && untaggedSpending.isEmpty) {
            // No chip when nothing is tagged: a lone "Untagged" covering the whole budget is noise.
            untaggedBucket = nil
        } else {
            untaggedBucket = Self.bucket(
                allocations: untaggedAllocations, spending: untaggedSpending, totalBudget: totalBudget)
        }

        self.segments = builtSegments
        self.tagArcs = builtArcs
        self.untagged = untaggedBucket
        self.headroom = effectiveHeadroom
        self.angularTotal = total
        self.totalBudget = totalBudget
    }

    // MARK: - Lookup

    func arc(id tagId: String) -> TagArc? {
        tagArcs.first { $0.id == tagId }
    }

    /// Whether a segment belongs to the given tag - the question the donut asks to decide dimming.
    func segment(_ segmentId: String, belongsTo tagId: String) -> Bool {
        arc(id: tagId)?.memberSegmentIDs.contains(segmentId) ?? false
    }

    // MARK: - Helpers

    private static func angularAmount(
        _ allocations: [BudgetAllocation]?,
        _ spending: [UnallocatedCategorySpending]?
    ) -> Int {
        (allocations ?? []).reduce(0) { $0 + $1.allocatedAmount }
            + (spending ?? []).reduce(0) { $0 + $1.spentAmount }
    }

    /// Allocated members first by amount desc, then off-plan members by amount desc. Category key
    /// breaks ties so the order is stable across launches.
    ///
    /// Note this *sorts* rather than preserving caller order, which changes the donut even for a user
    /// with no tags: `MonthCarouselCell` sorts its allocations amount-desc for the list but hands the
    /// card the unsorted array, so slices were previously drawn in whatever order the service returned
    /// - roughly creation order - and disagreed with the list directly beneath them. Sorting here makes
    /// the two agree. Deliberate, and the only visible change for someone who never makes a tag.
    private static func sortedSegments(
        allocations: [BudgetAllocation],
        spending: [UnallocatedCategorySpending],
        tagId: String?
    ) -> [Segment] {
        let allocated = allocations
            .sorted { lhs, rhs in
                lhs.allocatedAmount == rhs.allocatedAmount
                    ? lhs.category.key < rhs.category.key
                    : lhs.allocatedAmount > rhs.allocatedAmount
            }
            .map {
                Segment(
                    id: "alloc-\($0.category.key)",
                    kind: .allocated(categoryKey: $0.category.key),
                    amount: $0.allocatedAmount,
                    tagId: tagId)
            }

        let offPlan = spending
            .sorted { lhs, rhs in
                lhs.spentAmount == rhs.spentAmount
                    ? lhs.category.key < rhs.category.key
                    : lhs.spentAmount > rhs.spentAmount
            }
            .map {
                Segment(
                    id: "offplan-\($0.category.key)",
                    kind: .offPlan(categoryKey: $0.category.key),
                    amount: $0.spentAmount,
                    tagId: tagId)
            }

        return allocated + offPlan
    }

    private static func bucket(
        allocations: [BudgetAllocation],
        spending: [UnallocatedCategorySpending],
        totalBudget: Int
    ) -> Bucket {
        let allocated = allocations.reduce(0) { $0 + $1.allocatedAmount }
        let offPlan = spending.reduce(0) { $0 + $1.spentAmount }
        let usedInAllocations = allocations.reduce(0) { $0 + $1.usedAmount }

        return Bucket(
            allocated: allocated,
            used: usedInAllocations + offPlan,
            // Borrowed rather than recomputed, so a tag's figures can never drift from the card's.
            unspent: AllocationBalanceProjection.unspent(allocations: allocations),
            overspent: AllocationBalanceProjection.overspent(
                allocations: allocations, unallocatedSpending: offPlan),
            offPlan: offPlan,
            angularAmount: allocated + offPlan,
            // `allocated`, not `angularAmount`: "% of budget" means how much of the cap this group
            // *plans* to consume. Off-plan spend has no plan behind it and must not inflate that.
            share: totalBudget > 0 ? Double(allocated) / Double(totalBudget) : 0)
    }
}
