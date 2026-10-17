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
    /// Every expense behind the bars, read with the history. Filtered in memory per month and filter.
    @Published private(set) var expenses: [Transaction] = []
    /// Opens a transaction's details. Set by the view controller, which owns navigation.
    var onOpenTransaction: ((Transaction) -> Void)?
    @Published var filter: BudgetHistoryFilter
    @Published var range: Span = .sixMonths
    @Published var selectedAnchor: Int
    /// First closed month counted in "saved". Nil counts from the first month that had a plan.
    ///
    /// Remembered per ledger and changed only by the user picking another one - a running total whose
    /// start moved by itself would stop being comparable from one visit to the next.
    @Published private(set) var savingsStart: Int?
    @Published private(set) var isValuesHidden: Bool = ValueMask.isActive

    let ledgerScope: LedgerScope
    private let service: BudgetHistoryReading
    private let reference: () -> Date
    private var visibilityObservation: ValueVisibilityObservation?
    private let defaults: UserDefaults

    /// One remembered start per ledger: a group's plan started on its own date, not the user's.
    /// Personal is keyed by the signed-in user, so two accounts on one phone keep their own.
    private var savingsStartKey: String {
        "budgetHistory.savingsStart." + (ledgerScope.groupId ?? "personal.\(ledgerScope.localUid ?? "")")
    }

    /// - Parameters:
    ///   - filter: what the screen opens on. A category with no plan in the window falls back to the
    ///     whole month rather than opening on a chip that is not there.
    ///   - monthAnchor: the month to select first. A month outside the window selects the open month.
    init(
        ledgerScope: LedgerScope,
        filter: BudgetHistoryFilter = .wholeMonth,
        monthAnchor: Int? = nil,
        service: BudgetHistoryReading = BudgetHistoryService(),
        reference: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard
    ) {
        self.ledgerScope = ledgerScope
        self.filter = filter
        self.service = service
        self.reference = reference
        self.defaults = defaults
        self.selectedAnchor = monthAnchor ?? reference().monthAnchor
        self.savingsStart = defaults.object(forKey: savingsStartKey) as? Int
        visibilityObservation = ValueVisibilityStore.shared.observe { [weak self] hidden in
            self?.isValuesHidden = hidden
        }
    }

    /// Reads the ledger again. Called on appear, so an edit made from a pushed screen shows on return.
    func load() {
        history = service.history(in: ledgerScope, includeWholeMonth: true, asOf: reference())
        expenses = service.expenses(in: ledgerScope)
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

    /// What the chosen filter saved since `savingsStart`.
    /// Saved counts up to the month being read, so moving through the chart shows the running total.
    /// The open month never counts, so selecting it counts up to the month before.
    var savingsEnd: Int? { selectedMonth?.monthAnchor }

    /// The last month the Saved figure includes: the selected month, or the closed month before it
    /// when the selected one is still open. Nil when no closed month is at or before it.
    var savingsEndMonth: Int? {
        guard let end = savingsEnd else { return nil }
        return history.closedMonthAnchors.last { $0 <= end }
    }

    /// What made the Saved figure, over the same months it counts.
    var contributors: SavingsContributors? {
        history.contributors(for: filter, from: savingsStart, through: savingsEnd)
    }

    /// One month of the chosen filter, as the detail under a month row: its plan, what was spent and
    /// across how many expenses, and the three biggest of them. Zero-amount rows never count.
    func monthDetail(_ anchor: Int) -> MonthDetail? {
        guard let month = history.series(for: filter)?.month(anchor) else { return nil }
        let listed = history.transactions(for: filter, month: anchor, in: expenses).filter { $0.amount > 0 }
        // For Outside allocations the plan is itself a subtraction - the month budget minus what the
        // categories were given - and showing it is what explains a large number with no expense.
        var budgetSplit: (budget: Int, inCategories: Int)?
        if filter == .outsideAllocations, let budget = history.wholeMonth.month(anchor)?.planned, budget > 0 {
            let inCategories = history.categories.reduce(0) { $0 + ($1.month(anchor)?.planned ?? 0) }
            budgetSplit = (budget, inCategories)
        }
        return MonthDetail(
            month: month, expenseCount: listed.count, biggest: Array(listed.prefix(3)),
            budgetSplit: budgetSplit)
    }

    struct MonthDetail {
        let month: BudgetHistoryMonth
        let expenseCount: Int
        let biggest: [Transaction]
        let budgetSplit: (budget: Int, inCategories: Int)?
    }

    /// The named parts of the outside remainder, shown under the Saved card while that filter is on.
    var outsideDifferences: [BudgetHistory.OutsideDifference] {
        guard outsideTiming != nil else { return [] }
        return history.outsideDifferences(from: savingsStart, through: savingsEnd)
    }

    /// "Aug, Sep".
    static func monthList(_ anchors: [Int]) -> String {
        anchors.map(shortMonth).joined(separator: ", ")
    }

    /// "May to Sep 2026", or one month's name: the months a Saved figure covers.
    static func periodTitle(_ first: Int, _ last: Int) -> String {
        guard first != last else { return longMonth(first) }
        return String(format: "budgetHistory.explain.earlier.format".localized, shortMonth(first), longMonth(last))
    }

    var savings: BudgetHistorySeries.Savings {
        savings(for: filter)
    }

    func savings(for filter: BudgetHistoryFilter) -> BudgetHistorySeries.Savings {
        history.series(for: filter)?.savings(from: savingsStart, through: savingsEnd) ?? .none
    }

    /// Closed months a savings start can be set to: from the first month any filter had a plan. A
    /// start before that counts nothing more than "since the start" does.
    var savingsStartOptions: [Int] {
        let firstPlanned = ([history.wholeMonth] + history.categories)
            .compactMap { $0.scoredMonths.first?.monthAnchor }
            .min()
        guard let firstPlanned else { return [] }
        return history.closedMonthAnchors.filter { $0 >= firstPlanned }
    }

    /// The remainder row under the categories, since `savingsStart`. Nil with no categories: then the
    /// whole month is the only row and there is nothing to reconcile.
    var outsideAllocations: Int? {
        guard !history.categories.isEmpty else { return nil }
        return history.outsideAllocations(from: savingsStart, through: savingsEnd)
    }

    /// What the outside series does not explain, since `savingsStart`. Shown under the Saved card while
    /// the outside filter is chosen, so that card plus this line equal its row in the list.
    var outsideTiming: Int? {
        guard filter == .outsideAllocations else { return nil }
        return history.outsideTiming(from: savingsStart, through: savingsEnd)
    }

    /// The month the arrows step to, or nil at either end of the bars on screen.
    func neighbour(by offset: Int) -> Int? {
        let months = series.months
        guard let index = months.firstIndex(where: { $0.monthAnchor == selectedMonth?.monthAnchor })
        else { return nil }
        let target = index + offset
        return months.indices.contains(target) ? months[target].monthAnchor : nil
    }

    // MARK: - Intents

    func select(savingsStart start: Int?) {
        savingsStart = start
        if let start {
            defaults.set(start, forKey: savingsStartKey)
        } else {
            defaults.removeObject(forKey: savingsStartKey)
        }
    }

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
        case .outsideAllocations: return "budgetHistory.outside.title".localized
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

    /// "Since the start" or "Since March 2026".
    /// "Up to September 2026".
    static func savingsEndTitle(_ end: Int) -> String {
        String(format: "budgetHistory.savings.through.format".localized, longMonth(end))
    }

    static func savingsStartTitle(_ start: Int?) -> String {
        guard let start else { return "budgetHistory.savings.since.start".localized }
        return String(format: "budgetHistory.savings.since.format".localized, longMonth(start))
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
            // Hidden, an open month still reads "On plan" so far: the readout already carries an
            // "In progress" badge beside it, and saying it twice tells the reader nothing.
            return hidden
                ? "budgetHistory.status.within".localized
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
        if month.isCurrent {
            parts.append("budgetHistory.status.inProgress".localized)
        }
        return parts.joined(separator: ", ")
    }
}
