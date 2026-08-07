//
//  ProjectionExplainerViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 07/08/26.
//

import Foundation

/// One line of the itemised formula. Ordered as the sheet reads it, top to bottom.
struct ProjectionExplainerLine: Equatable {
    enum Kind: Equatable {
        /// The starting balance.
        case base
        /// Something taken off it. Rendered with a leading minus.
        case subtraction
        /// The figure the card shows, after a rule.
        case result
    }

    let kind: Kind
    let label: String
    /// Minor units, unsigned. `kind` decides how it reads; the view adds the sign.
    let amount: Int
}

/// One category's row in the history table.
struct ProjectionExplainerHistoryRow: Equatable {
    let categoryName: String
    /// `nil` when this category has no usable history, in which case `detail` says so.
    let range: String?
    /// What stands behind the range: a month count, or why there is no range.
    let detail: String
}

/// Explains the allocations card's projected balance: the arithmetic, itemised, plus what the user's
/// own closed months say about the assumption the arithmetic makes.
///
/// Reads a projection rather than computing one. `AllocationBalanceProjection` is the single site of
/// that formula and this sheet only relabels its terms - if the two disagreed, the explanation would
/// be worse than nothing.
final class ProjectionExplainerViewModel {

    private let projection: AllocationBalanceProjection
    private let balanceDay: Int
    private let allocations: [BudgetAllocation]
    private let monthAnchor: Int
    private let ledgerScope: LedgerScope
    private let allocationService: BudgetAllocationService

    init(
        projection: AllocationBalanceProjection,
        balanceDay: Int,
        allocations: [BudgetAllocation],
        monthAnchor: Int,
        ledgerScope: LedgerScope,
        allocationService: BudgetAllocationService = BudgetAllocationService()
    ) {
        self.projection = projection
        self.balanceDay = balanceDay
        self.allocations = allocations
        self.monthAnchor = monthAnchor
        self.ledgerScope = ledgerScope
        self.allocationService = allocationService
    }

    // MARK: - Formula

    var title: String { "projection.explainer.title".localized }

    var formulaHeader: String { "projection.explainer.formula.header".localized }

    /// The itemised arithmetic.
    ///
    /// A term worth zero is dropped rather than shown as `- R$ 0,00`: a line that changes nothing is
    /// noise in an explanation, and on a month with no card spending the card term is exactly that.
    /// `base` and the result always appear, even at zero, because their absence would leave the
    /// subtractions hanging off nothing.
    var formulaLines: [ProjectionExplainerLine] {
        var lines: [ProjectionExplainerLine] = [
            ProjectionExplainerLine(
                kind: .base,
                label: "projection.explainer.formula.balance.format".localized(
                    balanceDay.localizedDayOfMonth),
                amount: projection.base)
        ]

        if projection.deferredCardSpending > 0 {
            lines.append(
                ProjectionExplainerLine(
                    kind: .subtraction,
                    label: "projection.explainer.formula.card".localized,
                    amount: projection.deferredCardSpending))
        }
        if projection.unspentAllocations > 0 {
            lines.append(
                ProjectionExplainerLine(
                    kind: .subtraction,
                    label: "projection.explainer.formula.unspent".localized,
                    amount: projection.unspentAllocations))
        }

        lines.append(
            ProjectionExplainerLine(
                kind: .result,
                label: "projection.explainer.formula.result".localized,
                amount: projection.projected))
        return lines
    }

    /// Why the figure is usually beaten. Stated plainly because the caption on the card has 72pt and
    /// cannot say it, which is the whole reason this sheet exists.
    var formulaNote: String { "projection.explainer.formula.note".localized }

    // MARK: - History

    var historyHeader: String { "projection.explainer.history.header".localized }

    /// One row per allocated category, in the order the card lists them.
    ///
    /// Computed once, on demand: `spendHistories` makes one pass per table rather than one per
    /// category, so this is two reads regardless of how many categories there are.
    lazy var historyRows: [ProjectionExplainerHistoryRow] = {
        guard !allocations.isEmpty else { return [] }

        let histories = allocationService.spendHistories(
            for: allocations.map(\.category), before: monthAnchor, in: ledgerScope)

        return allocations.map { allocation in
            let history = histories[allocation.category.key] ?? .none
            switch history.verdict {
            case .notEnoughHistory:
                return ProjectionExplainerHistoryRow(
                    categoryName: allocation.category.displayName,
                    range: nil,
                    detail: "projection.explainer.history.none".localized)

            case .consistent(_, _, let months):
                return ProjectionExplainerHistoryRow(
                    categoryName: allocation.category.displayName,
                    range: Self.rangeText(for: history),
                    detail: Self.monthsText(months))

            case .varied:
                // Named rather than summarised. A category whose months disagree this much has no
                // usable typical figure, and saying so is more use than a midpoint nobody should plan
                // against - the range is still shown so the reader can see how wide it is.
                return ProjectionExplainerHistoryRow(
                    categoryName: allocation.category.displayName,
                    range: Self.rangeText(for: history),
                    detail: "projection.explainer.history.varied".localized)
            }
        }
    }()

    /// Shown instead of the table when there is nothing in it yet.
    var historyEmptyText: String? {
        historyRows.contains { $0.range != nil }
            ? nil
            : "projection.explainer.history.empty".localized
    }

    // MARK: - Formatting

    /// Collapses to one value when both ends round to the same percent - `56-56%` reads as a bug.
    private static func rangeText(for history: CategorySpendHistory) -> String {
        let range = history.percentRange
        if range.low == range.high {
            return "projection.explainer.history.single.format".localized(range.low)
        }
        return "projection.explainer.history.range.format".localized(range.low, range.high)
    }

    private static func monthsText(_ months: Int) -> String {
        months == 1
            ? "projection.explainer.history.month".localized
            : "projection.explainer.history.months.format".localized(months)
    }
}
