//
//  BudgetHistoryForecast.swift
//  Finova
//
//  Created by Arthur Rios on 01/11/26.
//

import Foundation

/// One month ahead, read from what the dashboard's budget card is given for that month.
///
/// Kept apart from `BudgetHistoryMonth` on purpose. Every score, streak and savings total walks
/// `BudgetHistorySeries.months`, so a projected month that is never in that array cannot reach them.
struct BudgetForecastMonth: Equatable, Identifiable {

    /// One allocated category. Same-category rows in a month are summed, as `BudgetHistory` does.
    struct Allocation: Equatable {
        let category: TransactionCategory
        let planned: Int
        /// Rows already dated in the month: the card's `usedAmount`.
        let scheduled: Int

        /// The projection assumes the whole plan gets spent, and more when the rows already pass it.
        var expected: Int { max(planned, scheduled) }
    }

    let monthAnchor: Int
    /// Zero means no budget was set.
    let budget: Int
    let allocations: [Allocation]
    /// Rows dated in the month, in categories with no allocation then.
    let outsideByCategory: [TransactionCategory: Int]
    /// The card's `totalUsedInUnallocatedCategories`.
    let outside: Int
    /// Statements falling due in the month. They move the balance but not the budget: their purchases
    /// count in the month they were made, which is how the card's "Used" reads them.
    let statementsDue: Int
    /// The card's own projection. Nil when the ledger has no row for the month, as on the card.
    let projection: AllocationBalanceProjection?

    var id: Int { monthAnchor }

    var inside: Int { allocations.reduce(0) { $0 + $1.expected } }
    var allocated: Int { allocations.reduce(0) { $0 + $1.planned } }

    /// Nothing to project: no budget, no allocation and no row.
    var isEmpty: Bool { budget == 0 && allocations.isEmpty && outside == 0 }

    /// - Parameters: the values `BudgetCard.configure` is handed for the month, so the two can only
    ///   differ if someone changes one side.
    init(
        monthAnchor: Int,
        allocations: [BudgetAllocation],
        summary: UnallocatedBudgetSummary,
        unallocatedSpending: [UnallocatedCategorySpending],
        closingBalance: Int?,
        deferredCardSpending: Int,
        statementsDue: Int,
        reservedPlan: Int? = nil
    ) {
        self.monthAnchor = monthAnchor
        self.budget = max(0, summary.totalBudget)

        var planned: [TransactionCategory: Int] = [:]
        var scheduled: [TransactionCategory: Int] = [:]
        for allocation in allocations {
            planned[allocation.category, default: 0] += allocation.allocatedAmount
            scheduled[allocation.category] = allocation.usedAmount
        }
        self.allocations = planned
            .map { Allocation(category: $0.key, planned: $0.value, scheduled: scheduled[$0.key] ?? 0) }
            .sorted { $0.planned != $1.planned ? $0.planned > $1.planned : $0.category.key < $1.category.key }

        self.outsideByCategory = unallocatedSpending.reduce(into: [:]) {
            $0[$1.category, default: 0] += $1.spentAmount
        }
        self.outside = max(0, summary.totalUsedInUnallocatedCategories)
        self.statementsDue = statementsDue
        self.projection = closingBalance.map {
            AllocationBalanceProjection(
                base: $0,
                allocations: allocations,
                unallocatedSpending: summary.totalUsedInUnallocatedCategories,
                unallocatedHeadroom: summary.unallocatedAmount,
                deferredCardSpending: deferredCardSpending,
                reservedPlan: reservedPlan,
                tense: .projected)
        }
    }
}

/// One projected month through one filter: the same plan the past months of that filter are read
/// against, and what is expected to land on it.
struct BudgetForecastFigures: Equatable, Identifiable {

    enum Status: Equatable {
        case fits
        case short
        /// Costs are expected, but nothing was planned. Never a plan of zero.
        case noPlan
        /// Nothing planned and nothing expected.
        case empty
    }

    let monthAnchor: Int
    let filter: BudgetHistoryFilter
    /// Zero means nothing was planned: no budget for the month, or no allocation for the category.
    let planned: Int
    /// For the whole month, the plan assumed spent in full. For a category, its rows already dated.
    let inside: Int
    /// Rows already dated in the month in categories with no allocation then.
    let outside: Int

    var id: Int { monthAnchor }

    var hasPlan: Bool { planned > 0 }
    var expected: Int { inside + outside }

    /// Positive is what is left, negative is the shortfall.
    var difference: Int { planned - expected }

    var percentExpected: Int? {
        guard hasPlan else { return nil }
        return Int((Double(expected) / Double(planned) * 100).rounded())
    }

    var status: Status {
        guard hasPlan else { return expected > 0 ? .noPlan : .empty }
        return expected > planned ? .short : .fits
    }

    /// The three pieces the chart stacks, adding up to `expected`. The part past the plan is its own
    /// piece, so it never hides inside the two below it.
    var insideWithinPlan: Int { hasPlan ? min(inside, planned) : inside }
    var outsideWithinPlan: Int { hasPlan ? min(outside, planned - insideWithinPlan) : outside }
    var overPlan: Int { hasPlan ? max(0, expected - planned) : 0 }
}

/// The months ahead of the open one, nearest first. Pure: no repository, no `Date()`.
struct BudgetForecast: Equatable {

    /// How far ahead the history screen reads.
    static let monthsAhead = 6

    let months: [BudgetForecastMonth]

    static let empty = BudgetForecast(months: [])

    var isEmpty: Bool { months.allSatisfy(\.isEmpty) }

    func month(_ anchor: Int) -> BudgetForecastMonth? {
        months.first { $0.monthAnchor == anchor }
    }

    /// Categories with an allocation in a month ahead, biggest plan first.
    var plannedCategories: [TransactionCategory] {
        var totals: [TransactionCategory: Int] = [:]
        for allocation in months.flatMap(\.allocations) {
            totals[allocation.category, default: 0] += allocation.planned
        }
        return totals
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.key < $1.key.key }
            .map(\.key)
    }

    /// Every month read through `filter`.
    func figures(for filter: BudgetHistoryFilter) -> [BudgetForecastFigures] {
        months.map { Self.figures(for: $0, filter: filter) }
    }

    private static func figures(
        for month: BudgetForecastMonth, filter: BudgetHistoryFilter
    ) -> BudgetForecastFigures {
        switch filter {
        case .wholeMonth:
            return BudgetForecastFigures(
                monthAnchor: month.monthAnchor, filter: filter, planned: month.budget,
                inside: month.inside, outside: month.outside)
        case .category(let category):
            // One category has no full plan to assume: its allocation is the plan, and the rows already
            // dated are what can be said about it. With no allocation those rows are outside costs.
            if let allocation = month.allocations.first(where: { $0.category == category }) {
                return BudgetForecastFigures(
                    monthAnchor: month.monthAnchor, filter: filter, planned: allocation.planned,
                    inside: allocation.scheduled, outside: 0)
            }
            return BudgetForecastFigures(
                monthAnchor: month.monthAnchor, filter: filter, planned: 0,
                inside: 0, outside: month.outsideByCategory[category] ?? 0)
        case .outsideAllocations:
            // The rule `BudgetHistory` uses for the past: no budget, or a budget the categories took
            // whole, leaves no outside plan.
            return BudgetForecastFigures(
                monthAnchor: month.monthAnchor, filter: filter,
                planned: month.budget > 0 ? max(0, month.budget - month.allocated) : 0,
                inside: 0, outside: month.outside)
        }
    }

    /// The rows behind one month's figures, biggest first. On the allocation clock (`budgetMonthDate`)
    /// for every filter, because these figures have no date-clock total to match.
    ///
    /// - Parameter expenses: the set `BudgetHistory.transactions(for:month:in:)` takes.
    func transactions(
        for filter: BudgetHistoryFilter, month anchor: Int, in expenses: [Transaction]
    ) -> [Transaction] {
        let inMonth = expenses.filter { $0.budgetMonthDate == anchor }
        let matching: [Transaction]
        switch filter {
        case .wholeMonth:
            matching = inMonth
        case .category(let category):
            matching = inMonth.filter { $0.category == category }
        case .outsideAllocations:
            let planned = Set(month(anchor)?.allocations.map(\.category) ?? [])
            matching = inMonth.filter { !planned.contains($0.category) }
        }
        return matching
            .filter { $0.type == .expense && !($0.hasInstallments == true && $0.parentTransactionId == nil) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.dateTimestamp > $1.dateTimestamp }
    }
}
