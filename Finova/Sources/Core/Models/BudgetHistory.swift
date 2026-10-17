//
//  BudgetHistory.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import Foundation

/// What a budget history is read for: the whole month's budget, or one category's allocation.
enum BudgetHistoryFilter: Hashable {
    case wholeMonth
    case category(TransactionCategory)

    var id: String {
        switch self {
        case .wholeMonth: return "wholeMonth"
        case .category(let category): return category.key
        }
    }
}

/// One month of one filter: what was planned, and what was spent against it.
struct BudgetHistoryMonth: Equatable, Identifiable {

    /// Where the month landed. `.inProgress` is the open month while it is still under its plan - it
    /// can still go over, so it is never counted as a month "on plan". An open month that is already
    /// over is `.over`: that cannot be undone by the days left.
    enum Status: Equatable {
        case within
        case over
        case inProgress
        /// Spending with nothing planned. "Fraction of plan" has no meaning here, so it is neither a
        /// hit nor a miss - the same rule `CategorySpendHistory` applies to its samples.
        case noPlan
        /// Nothing planned and nothing spent.
        case empty
    }

    let monthAnchor: Int
    /// Minor units. Zero means nothing was planned.
    let planned: Int
    /// Minor units.
    let spent: Int
    let isCurrent: Bool

    var id: Int { monthAnchor }

    var hasPlan: Bool { planned > 0 }

    /// Positive is what is left, negative is how far past the plan the month went.
    var difference: Int { planned - spent }

    /// `spent / planned`, unclamped so an overspend reads as more than 100%. Nil with no plan.
    var ratio: Double? {
        guard hasPlan else { return nil }
        return Double(spent) / Double(planned)
    }

    /// Whole percent of the plan used. Rounded here so every surface prints the same figure.
    var percentUsed: Int? {
        ratio.map { Int(($0 * 100).rounded()) }
    }

    var status: Status {
        guard hasPlan else { return spent > 0 ? .noPlan : .empty }
        if spent > planned { return .over }
        return isCurrent ? .inProgress : .within
    }

    /// The spent part that fits inside the plan, and the part past it. Drawn as two stacked bars.
    var spentWithinPlan: Int { hasPlan ? min(spent, planned) : spent }
    var spentOverPlan: Int { hasPlan ? max(0, spent - planned) : 0 }
}

/// A run of months for one filter, oldest first, ending at the current month.
struct BudgetHistorySeries: Equatable {
    let filter: BudgetHistoryFilter
    let months: [BudgetHistoryMonth]

    /// Closed months that had a plan. The open month is left out of every score below: it can still
    /// change, and counting it would make the score move day by day.
    var scoredMonths: [BudgetHistoryMonth] {
        months.filter { !$0.isCurrent && $0.hasPlan }
    }

    var monthsOnPlan: Int {
        scoredMonths.filter { $0.status == .within }.count
    }

    /// Closed months on plan in a row, counted back from the latest closed month. A closed month with
    /// no plan ends the streak: the user was not following a plan then.
    var streak: Int {
        var count = 0
        for month in months.reversed() where !month.isCurrent {
            guard month.status == .within else { break }
            count += 1
        }
        return count
    }

    /// Lowest and highest share of the plan used across the scored months - a range and not an
    /// average, for the reason `CategorySpendHistory` gives: an average hides months that disagree.
    var usageRange: (low: Int, high: Int)? {
        let percents = scoredMonths.compactMap(\.percentUsed)
        guard let low = percents.min(), let high = percents.max() else { return nil }
        return (low, high)
    }

    /// What closed months left over against their plan, netted: a month under its plan adds what it did
    /// not spend, a month over it takes the overspend back off.
    struct Savings: Equatable {
        /// Sum of what months under their plan left unspent.
        let saved: Int
        /// Sum of how far months over their plan went. Positive.
        let overspent: Int
        /// Closed months with a plan that were counted.
        let months: Int

        var net: Int { saved - overspent }

        static let none = Savings(saved: 0, overspent: 0, months: 0)
    }

    /// Savings over the closed months with a plan, from `start` (inclusive) on, or over all of them
    /// when `start` is nil. The open month is never counted: what it has left is not saved yet, and
    /// counting it would show a figure that shrinks as the month goes on.
    func savings(from start: Int? = nil) -> Savings {
        let counted = scoredMonths.filter { start == nil || $0.monthAnchor >= start! }
        return Savings(
            saved: counted.reduce(0) { $0 + max(0, $1.difference) },
            overspent: counted.reduce(0) { $0 + max(0, -$1.difference) },
            months: counted.count)
    }

    /// Nothing planned and nothing spent in any month of the series.
    var isEmpty: Bool {
        months.allSatisfy { $0.status == .empty }
    }

    /// The last `count` months, keeping the current one.
    func suffix(_ count: Int) -> BudgetHistorySeries {
        BudgetHistorySeries(filter: filter, months: Array(months.suffix(count)))
    }

    /// Drops leading months that have nothing in them, so a ledger that started three months ago
    /// shows three bars and not nine empty slots first. The current month always stays.
    func trimmingLeadingEmptyMonths() -> BudgetHistorySeries {
        let firstUsed = months.firstIndex { $0.status != .empty || $0.isCurrent } ?? months.endIndex
        return BudgetHistorySeries(filter: filter, months: Array(months[firstUsed...]))
    }

    func month(_ anchor: Int) -> BudgetHistoryMonth? {
        months.first { $0.monthAnchor == anchor }
    }
}

/// Every series a history screen can show, for one ledger. Pure: no repository, no `Date()`.
struct BudgetHistory: Equatable {

    /// Twelve closed months plus the open one - the most the chart shows. A ledger with older plans
    /// gets a longer window, so "saved since the start" counts every month that had a plan.
    static let minimumWindowMonths = 13

    /// Ten years. Only a bound against a corrupt month date stretching the read without limit.
    static let maximumWindowMonths = 120

    /// Closed months, oldest first: what the savings start can be set to.
    var closedMonthAnchors: [Int] {
        monthAnchors.filter { $0 != currentAnchor }
    }

    /// The month totals the dashboard card shows: the budget row and the "used" figure.
    struct MonthTotal: Equatable {
        let budget: Int?
        let used: Int
    }

    let monthAnchors: [Int]
    let currentAnchor: Int
    let wholeMonth: BudgetHistorySeries
    /// Every category with an allocation somewhere in the window, biggest plan first.
    let categories: [BudgetHistorySeries]

    var filters: [BudgetHistoryFilter] {
        [.wholeMonth] + categories.map(\.filter)
    }

    func series(for filter: BudgetHistoryFilter) -> BudgetHistorySeries? {
        switch filter {
        case .wholeMonth: return wholeMonth
        case .category: return categories.first { $0.filter == filter }
        }
    }

    var isEmpty: Bool {
        wholeMonth.isEmpty && categories.isEmpty
    }

    static let empty = BudgetHistory(
        monthAnchors: [], currentAnchor: 0,
        wholeMonth: BudgetHistorySeries(filter: .wholeMonth, months: []), categories: [])

    init(
        monthAnchors: [Int], currentAnchor: Int, wholeMonth: BudgetHistorySeries,
        categories: [BudgetHistorySeries]
    ) {
        self.monthAnchors = monthAnchors
        self.currentAnchor = currentAnchor
        self.wholeMonth = wholeMonth
        self.categories = categories
    }

    /// - Parameters:
    ///   - monthAnchors: the window, oldest first. Anything outside it is ignored.
    ///   - currentAnchor: the open month.
    ///   - allocations: the ledger's allocations, any months. Same-category rows in one month are
    ///     summed, for the reason `BudgetAllocationService.spendHistories` gives.
    ///   - spentByCategory: `categoryKey -> monthAnchor -> spent`, already built with the predicate
    ///     the allocation card uses, so a bar here matches the card for the same month.
    ///   - monthTotals: per month, the figures the dashboard's month card shows.
    init(
        monthAnchors: [Int],
        currentAnchor: Int,
        allocations: [BudgetAllocation],
        spentByCategory: [String: [Int: Int]],
        monthTotals: [Int: MonthTotal]
    ) {
        let window = Set(monthAnchors)

        var plannedByCategory: [String: [Int: Int]] = [:]
        var categoriesByKey: [String: TransactionCategory] = [:]
        for allocation in allocations
        where window.contains(allocation.monthDate) && allocation.allocatedAmount > 0 {
            plannedByCategory[allocation.category.key, default: [:]][
                allocation.monthDate, default: 0] += allocation.allocatedAmount
            categoriesByKey[allocation.category.key] = allocation.category
        }

        func months(planned: (Int) -> Int, spent: (Int) -> Int) -> [BudgetHistoryMonth] {
            monthAnchors.map { anchor in
                BudgetHistoryMonth(
                    monthAnchor: anchor, planned: max(0, planned(anchor)), spent: max(0, spent(anchor)),
                    isCurrent: anchor == currentAnchor)
            }
        }

        let wholeMonth = BudgetHistorySeries(
            filter: .wholeMonth,
            months: months(
                planned: { monthTotals[$0]?.budget ?? 0 },
                spent: { monthTotals[$0]?.used ?? 0 }))

        // Biggest plan in the open month first - the order the user sees on the card today - then
        // the biggest plan across the window for categories no longer planned. Key last, so the order
        // never depends on dictionary order.
        let ordered = plannedByCategory.keys.sorted { lhs, rhs in
            let lhsNow = plannedByCategory[lhs]?[currentAnchor] ?? 0
            let rhsNow = plannedByCategory[rhs]?[currentAnchor] ?? 0
            if lhsNow != rhsNow { return lhsNow > rhsNow }
            let lhsTotal = plannedByCategory[lhs]?.values.reduce(0, +) ?? 0
            let rhsTotal = plannedByCategory[rhs]?.values.reduce(0, +) ?? 0
            if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }
            return lhs < rhs
        }

        let categories: [BudgetHistorySeries] = ordered.compactMap { key in
            guard let category = categoriesByKey[key] else { return nil }
            let planned = plannedByCategory[key] ?? [:]
            let spent = spentByCategory[key] ?? [:]
            return BudgetHistorySeries(
                filter: .category(category),
                months: months(planned: { planned[$0] ?? 0 }, spent: { spent[$0] ?? 0 }))
        }

        self.init(
            monthAnchors: monthAnchors, currentAnchor: currentAnchor, wholeMonth: wholeMonth,
            categories: categories)
    }
}
