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
        var unspent = 0
        var overrun = 0
        var used = 0

        for allocation in allocations {
            let remaining = allocation.remainingAmount
            unspent += max(0, remaining)
            overrun += max(0, -remaining)
            // Capped so an overspent category cannot report more used than it ever allocated; the
            // excess is already counted in `overrun`.
            used += max(0, min(allocation.usedAmount, allocation.allocatedAmount))
        }

        self.base = base
        self.unspentAllocations = unspent
        self.unallocatedHeadroom = max(0, unallocatedHeadroom)
        self.overspent = overrun + max(0, unallocatedSpending)
        self.usedWithinAllocations = used
        self.projected = base - unspent
        self.tense = tense
    }

    /// Money the month held on to: budget earmarked but not spent, plus cap never earmarked.
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
    /// - `.projected`: what survives once the plan is honoured.
    /// - `.actual`: what the allocations actually consumed. The closing balance is already the
    ///   leading block, so repeating it here would say nothing.
    var headlineAmount: Int {
        switch tense {
        case .projected: return projected
        case .actual: return usedWithinAllocations
        }
    }

    /// How far the allocations exceed the balance, or zero when they don't.
    var shortfall: Int { isOverCommitted ? abs(projected) : 0 }

    /// Normalised widths for the two-segment bar: `totalSaved` against `overspent`. Sums to 1, or
    /// is all-zero when neither has happened.
    ///
    /// Tense-independent on purpose - "came in under" versus "went over" reads the same whether the
    /// month is still running or already closed. Normalised over the two together rather than over
    /// `base`, because both are usually a small fraction of a balance: dividing by the balance
    /// renders a sliver that says nothing either way.
    var barShares: (saved: CGFloat, overspent: CGFloat) {
        let total = totalSaved + overspent
        guard total > 0 else { return (0, 0) }
        let divisor = CGFloat(total)
        return (
            saved: CGFloat(totalSaved) / divisor,
            overspent: CGFloat(overspent) / divisor
        )
    }
}
