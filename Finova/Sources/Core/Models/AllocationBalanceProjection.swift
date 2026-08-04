//
//  AllocationBalanceProjection.swift
//  Finova
//
//  Created by Arthur Rios on 03/08/26.
//

import CoreGraphics
import Foundation

/// The balance a month is expected to close with once every budget allocation plays out.
///
/// This type *consumes* a balance and never computes one. It holds no repository, no service and
/// no `Date()`, so it cannot read a ledger even by accident - which is deliberate: the app already
/// has several drifting balance implementations, and this must not become another one. The caller
/// supplies `base`, a cumulative, scope-correct `finalBalance`.
///
/// Built for any month, but it reports different quantities depending on `tense`: for a closed
/// month `base - unspentAllocations` would answer "what if the leftover budget *had* been spent",
/// which never happened, so a closed month reports what the allocations actually consumed instead.
struct AllocationBalanceProjection: Equatable {

    /// Whether the month still lies ahead (a forecast) or has closed (a record).
    enum Tense {
        case projected
        case actual
    }

    /// Money spent beyond the plan, for callers that need the figure without a balance to project
    /// from - the allocations header shows it next to the row count.
    ///
    /// Shared with `init` so the header and the card can never disagree about what "overspent"
    /// means. Both terms are visible in the list: category overruns are its red arrows, and
    /// unallocated spending is its greyed rows.
    static func overspent(
        allocations: [BudgetAllocation],
        unallocatedSpending: Int
    ) -> Int {
        let overruns = allocations.reduce(0) { $0 + max(0, -$1.remainingAmount) }
        return overruns + max(0, unallocatedSpending)
    }

    /// Budget earmarked but not yet spent, clamped per category.
    ///
    /// Shared with `init` so the allocations header and the card agree. Like `overspent`, it is a
    /// total of what the list already shows: the green arrows on its rows.
    static func unspent(allocations: [BudgetAllocation]) -> Int {
        allocations.reduce(0) { $0 + max(0, $1.remainingAmount) }
    }

    /// Ledger closing balance for the month, in minor units.
    let base: Int

    /// Budget earmarked to categories but not yet spent, clamped per category.
    let unspentAllocations: Int

    /// Budget cap that was never earmarked to any category, clamped at zero.
    ///
    /// Counts as saved: money the user neither planned to spend nor spent. Over-allocation (a
    /// negative headroom) clamps to zero here - planning beyond the cap is not overspending, and the
    /// footer's amber `Unallocated` already warns about it.
    let unallocatedHeadroom: Int

    /// Money spent beyond the plan: every category's overrun, plus everything spent in categories
    /// that had no allocation at all. The second term is why this surfaces off-plan spending, which
    /// no other element on the card names.
    let overspent: Int

    /// Allocation money already spent, capped per category at what was allocated.
    ///
    /// Savings and investment categories get no special treatment: funding them debits the account
    /// exactly like any other spend, so they are not counted as money kept.
    let usedWithinAllocations: Int

    /// What survives once every allocation is honoured. May be negative.
    let projected: Int

    let tense: Tense

    /// - Parameters:
    ///   - unallocatedSpending: spending in categories with no allocation, which counts toward
    ///     `overspent` - money spent with no plan behind it is money spent beyond the plan.
    ///   - unallocatedHeadroom: budget cap never earmarked to a category, which counts toward
    ///     `totalSaved`. Clamped at zero, so over-allocation does not read as negative saving.
    init(
        base: Int,
        allocations: [BudgetAllocation],
        unallocatedSpending: Int = 0,
        unallocatedHeadroom: Int = 0,
        tense: Tense
    ) {
        // Only the *unspent* remainder is a future outflow. Money already spent is inside `base`,
        // so charging the full allocated amount would subtract it twice. A negative remainder means
        // the category is overspent - it clamps to zero here and is counted in `overspent` instead.
        // Capped so an overspent category cannot report more used than it ever allocated; the
        // excess is counted in `overspent` instead.
        let used = allocations.reduce(0) {
            $0 + max(0, min($1.usedAmount, $1.allocatedAmount))
        }
        let unspent = Self.unspent(allocations: allocations)

        self.base = base
        self.unspentAllocations = unspent
        self.unallocatedHeadroom = max(0, unallocatedHeadroom)
        self.overspent = Self.overspent(
            allocations: allocations, unallocatedSpending: unallocatedSpending)
        self.usedWithinAllocations = used
        self.projected = base - unspent
        self.tense = tense
    }

    /// Money the month held on to: budget earmarked but not spent, plus cap never earmarked.
    ///
    /// A *realised* figure, so the card only surfaces it once the month has closed. Mid-month an
    /// unspent allocation is money still earmarked for spending, not money kept.
    ///
    /// Deliberately excludes savings and investment allocations that were funded - that money was
    /// debited to a fund, so it left the account and is not "saved" in this card's sense.
    var totalSaved: Int { unspentAllocations + unallocatedHeadroom }

    /// Saved minus overspent. Positive means the month held on to more than it let slip.
    var netSaved: Int { totalSaved - overspent }

    /// True when the allocations promise more than the balance can cover.
    /// Only meaningful while the month is open; a closed month cannot be over-committed.
    var isOverCommitted: Bool { tense == .projected && projected < 0 }

    /// The figure the trailing block leads with.
    ///
    /// - `.projected`: what survives if the whole plan is spent.
    /// - `.actual`: the month's verdict. It used to be `usedWithinAllocations`, captioned "Budget
    ///   used" - untrue twice over, because that figure is capped per category and so excluded both
    ///   overruns and off-plan spending, and it disagreed with the card's own `Used` footer.
    var headlineAmount: Int {
        switch tense {
        case .projected: return projected
        case .actual: return netSaved
        }
    }

    /// How far the allocations exceed the balance, or zero when they don't.
    var shortfall: Int { isOverCommitted ? abs(projected) : 0 }

    /// Normalised widths for the two-segment bar: of the money actually spent, how much stayed
    /// inside its allocation against how much broke out of it. Sums to 1, or is all-zero before
    /// anything has been spent.
    ///
    /// Tense-independent, and deliberately built from *spent* money rather than from `totalSaved`.
    /// An open month cannot have saved anything yet - an unspent allocation is money the user plans
    /// to spend, so counting it as kept would show a figure that erodes as the month fills in.
    /// Plan adherence is true at every point in the month, and stays true once it closes.
    var barShares: (withinPlan: CGFloat, beyondPlan: CGFloat) {
        let total = usedWithinAllocations + overspent
        guard total > 0 else { return (0, 0) }
        let divisor = CGFloat(total)
        return (
            withinPlan: CGFloat(usedWithinAllocations) / divisor,
            beyondPlan: CGFloat(overspent) / divisor
        )
    }
}
