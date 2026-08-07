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

    /// Money already charged against this month's allocations that `base` has not absorbed yet:
    /// credit card spending made this month whose statement settles in a later one.
    ///
    /// Without this term the projection *rises* when a card purchase is added, which is what it used to
    /// do. `base` is cash-only - `TransactionLedgerService` keeps card purchases out of the balance
    /// entirely and represents them by the statement synthetic, dated to the statement's due date -
    /// while allocation usage counts the purchase in the month it was made. So the purchase consumed
    /// the plan here (`unspentAllocations` fell) with nothing coming off the balance, and
    /// `base - unspent` climbed by the amount of a *spend*.
    ///
    /// Subtracting it makes this answer "what is left once the plan is honoured, counting the card debt
    /// this month has already run up". The money is committed either way; only the date it leaves the
    /// account differs.
    let deferredCardSpending: Int

    /// What survives once every allocation is honoured and this month's card debt is paid. May be
    /// negative.
    let projected: Int

    let tense: Tense

    /// - Parameters:
    ///   - unallocatedSpending: spending in categories with no allocation, which counts toward
    ///     `overspent` - money spent with no plan behind it is money spent beyond the plan.
    ///   - unallocatedHeadroom: budget cap never earmarked to a category, which counts toward
    ///     `totalSaved`. Clamped at zero, so over-allocation does not read as negative saving.
    ///   - deferredCardSpending: card spending counted against these allocations whose statement
    ///     settles after this month, so `base` does not reflect it yet. Comes off the projection and
    ///     nothing else - it is money spent, so it is neither saved nor overspending. Clamped at zero;
    ///     `BudgetAllocationService.deferredCardSpending` counts only expenses, so a negative can only
    ///     mean the caller measured something else.
    init(
        base: Int,
        allocations: [BudgetAllocation],
        unallocatedSpending: Int = 0,
        unallocatedHeadroom: Int = 0,
        deferredCardSpending: Int = 0,
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
        let deferred = max(0, deferredCardSpending)

        self.base = base
        self.unspentAllocations = unspent
        self.unallocatedHeadroom = max(0, unallocatedHeadroom)
        self.overspent = Self.overspent(
            allocations: allocations, unallocatedSpending: unallocatedSpending)
        self.usedWithinAllocations = used
        self.deferredCardSpending = deferred
        // Both subtrahends are outflows `base` has yet to see: `unspent` because the plan has not been
        // drawn on yet, `deferred` because the card statement carrying it lands in a later month.
        self.projected = base - deferred - unspent
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

    /// Normalised widths for the three-segment bar, comparing the block's three quantities against each
    /// other. Sums to 1 whenever any of them is non-zero, and is all-zero otherwise so the bare track
    /// shows through.
    ///
    /// - `projected`: what the balance is left with once the plan plays out. **Not** the saved amount -
    ///   savings have already come out of it - which is why it takes the outgoing colour and not green.
    /// - `saved`: `totalSaved`, money still sitting in the account: budget earmarked but not spent, plus
    ///   the cap never earmarked at all.
    /// - `overspent`: what broke out of the plan - category overruns plus spending with no plan behind it.
    ///
    /// Two earlier versions of this bar got the question wrong, so both are worth naming. It first
    /// plotted plan *adherence* - of money spent, how much stayed inside its allocation - which came out
    /// almost entirely green on any well-behaved month and so read as "all of this is saved". It then
    /// plotted `projected` in green against the outgoing remainder, which put the biggest slice in the
    /// colour meaning "saved" while the actual saved figure went unshown.
    ///
    /// A comparison, not a partition: `projected` and `saved` both derive from `unspentAllocations`, so
    /// they do not add up to `base` and are not meant to.
    var barShares: (projected: CGFloat, saved: CGFloat, overspent: CGFloat) {
        // A negative projection has no width. The shortfall is named in the block's caption instead.
        let survives = max(0, projected)
        let total = survives + totalSaved + overspent
        guard total > 0 else { return (0, 0, 0) }

        let divisor = CGFloat(total)
        return (
            projected: CGFloat(survives) / divisor,
            saved: CGFloat(totalSaved) / divisor,
            overspent: CGFloat(overspent) / divisor
        )
    }
}
