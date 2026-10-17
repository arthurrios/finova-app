//
//  BudgetHistoryViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import Combine
import Foundation

/// State for the budget history screen. The SwiftUI content observes it; the view controller owns it.
final class BudgetHistoryViewModel: ObservableObject {

    /// How many months the chart shows, ending at the open month.
    enum Span: Int, CaseIterable, Identifiable {
        case sixMonths = 6
        case twelveMonths = 12

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .sixMonths: return "budgetHistory.range.6m".localized
            case .twelveMonths: return "budgetHistory.range.12m".localized
            }
        }
    }

    @Published private(set) var history: BudgetHistory = .empty
    @Published var filter: BudgetHistoryFilter
    @Published var range: Span = .sixMonths
    @Published var selectedAnchor: Int
    @Published private(set) var isValuesHidden: Bool = ValueMask.isActive

    let ledgerScope: LedgerScope
    private let service: BudgetHistoryService
    private let reference: () -> Date
    private var visibilityObservation: ValueVisibilityObservation?

    /// - Parameters:
    ///   - filter: what the screen opens on. A category with no plan in the window falls back to the
    ///     whole month rather than opening on a chip that is not there.
    ///   - monthAnchor: the month to select first. A month outside the window selects the open month.
    init(
        ledgerScope: LedgerScope,
        filter: BudgetHistoryFilter = .wholeMonth,
        monthAnchor: Int? = nil,
        service: BudgetHistoryService = BudgetHistoryService(),
        reference: @escaping () -> Date = Date.init
    ) {
        self.ledgerScope = ledgerScope
        self.filter = filter
        self.service = service
        self.reference = reference
        self.selectedAnchor = monthAnchor ?? reference().monthAnchor
        visibilityObservation = ValueVisibilityStore.shared.observe { [weak self] hidden in
            self?.isValuesHidden = hidden
        }
    }

    /// Reads the ledger again. Called on appear, so an edit made from a pushed screen shows on return.
    func load() {
        history = service.history(in: ledgerScope, asOf: reference())
        if history.series(for: filter) == nil {
            filter = .wholeMonth
        }
        // An entry month older than six months opens the longer range, so it is on screen.
        if let index = history.monthAnchors.firstIndex(of: selectedAnchor),
            history.monthAnchors.count - index > Span.sixMonths.rawValue
        {
            range = .twelveMonths
        }
        if !history.monthAnchors.contains(selectedAnchor) {
            selectedAnchor = history.currentAnchor
        }
        keepSelectionVisible()
    }

    // MARK: - Derived

    /// The bars on screen: the chosen range, minus leading months with nothing in them.
    var series: BudgetHistorySeries {
        (history.series(for: filter) ?? history.wholeMonth)
            .suffix(range.rawValue)
            .trimmingLeadingEmptyMonths()
    }

    var selectedMonth: BudgetHistoryMonth? {
        series.month(selectedAnchor) ?? series.months.last
    }

    var filters: [BudgetHistoryFilter] { history.filters }

    /// The 12-month option only when it would show more than the 6-month one. A ledger with five months
    /// of history draws the same bars under both, and a toggle that changes nothing reads as broken.
    var offersLongerRange: Bool {
        (history.series(for: filter) ?? history.wholeMonth)
            .suffix(Span.twelveMonths.rawValue)
            .trimmingLeadingEmptyMonths()
            .months.count > Span.sixMonths.rawValue
    }

    var isEmpty: Bool { history.isEmpty }

    // MARK: - Intents

    func select(filter newFilter: BudgetHistoryFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        keepSelectionVisible()
    }

    func select(range newRange: Span) {
        guard newRange != range else { return }
        range = newRange
        keepSelectionVisible()
    }

    func select(month anchor: Int) {
        guard series.month(anchor) != nil else { return }
        selectedAnchor = anchor
    }

    /// A shorter range or a trimmed series can drop the selected month off the chart. Move the
    /// selection to the open month rather than leaving the readout on a month with no bar.
    private func keepSelectionVisible() {
        if series.month(selectedAnchor) == nil, let last = series.months.last {
            selectedAnchor = last.monthAnchor
        }
    }
}

// MARK: - Text

extension BudgetHistoryViewModel {

    static func title(for filter: BudgetHistoryFilter) -> String {
        switch filter {
        case .wholeMonth: return "budgetHistory.filter.wholeMonth".localized
        case .category(let category): return category.displayName
        }
    }

    private static let monthKeys = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ]

    private static func monthIndex(_ anchor: Int) -> (month: Int, year: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month], from: Date.fromMonthAnchor(anchor))
        return (parts.month ?? 1, parts.year ?? 0)
    }

    /// "Oct" - the app's own month strings, so the axis follows the app language like the carousel.
    static func shortMonth(_ anchor: Int) -> String {
        let index = monthIndex(anchor).month - 1
        return "month.\(monthKeys[index])".localized
    }

    /// "'26" under a January, so a run of months that crosses a year says where. Nil for other months.
    static func yearMark(_ anchor: Int) -> String? {
        let parts = monthIndex(anchor)
        guard parts.month == 1 else { return nil }
        return "’" + String(format: "%02d", parts.year % 100)
    }

    /// "October 2026".
    static func longMonth(_ anchor: Int) -> String {
        let parts = monthIndex(anchor)
        return "month.\(monthKeys[parts.month - 1]).ext".localized + " \(parts.year)"
    }

    /// The short status line a month carries: an amount when values are visible, a word when not.
    static func statusText(for month: BudgetHistoryMonth, hidden: Bool) -> String {
        switch month.status {
        case .within, .inProgress:
            return hidden
                ? (month.status == .inProgress
                    ? "budgetHistory.status.inProgress".localized
                    : "budgetHistory.status.within".localized)
                : String(
                    format: "budgetHistory.status.left.format".localized,
                    month.difference.currencyString)
        case .over:
            return hidden
                ? "budgetHistory.status.overPlain".localized
                : String(
                    format: "budgetHistory.status.over.format".localized,
                    abs(month.difference).currencyString)
        case .noPlan:
            return "budgetHistory.status.noPlan".localized
        case .empty:
            return "budgetHistory.status.empty".localized
        }
    }

    /// What VoiceOver reads for a month, on the chart and in the list.
    static func accessibilityValue(for month: BudgetHistoryMonth, hidden: Bool) -> String {
        var parts: [String] = []
        if !hidden {
            parts.append(
                month.hasPlan
                    ? String(
                        format: "budgetHistory.a11y.spentOf.format".localized,
                        month.spent.currencyString, month.planned.currencyString)
                    : month.spent.currencyString)
        }
        if let percent = month.percentUsed {
            parts.append(String(format: "budgetHistory.percent.format".localized, percent))
        }
        parts.append(statusText(for: month, hidden: hidden))
        // Hidden, an open month's status already reads "In progress".
        if month.isCurrent && !(hidden && month.status == .inProgress) {
            parts.append("budgetHistory.status.inProgress".localized)
        }
        return parts.joined(separator: ", ")
    }
}
