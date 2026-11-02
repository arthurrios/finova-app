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
    /// The months ahead of the open one, read with the history.
    @Published private(set) var forecast: BudgetForecast = .empty
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

    /// Which months the Saved and "Why" cards count, both ending at the selected month.
    enum SavingsScope: CaseIterable {
        /// From `savingsStart` up to the selected month: the running total.
        case upTo
        /// The selected month alone, so its own savers and overspenders can be read.
        case only
    }

    /// Not remembered: "only" is a closer look at one month, and the screen opens on the running total.
    @Published private(set) var savingsScope: SavingsScope = .upTo
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
        forecast = service.forecast(in: ledgerScope, asOf: reference())
        if history.series(for: filter) == nil && !isForecastOnly(filter) {
            filter = .wholeMonth
        }
        // An entry month older than six months opens the longer range, so it is on screen.
        if let index = history.monthAnchors.firstIndex(of: selectedAnchor),
            history.monthAnchors.count - index > Span.sixMonths.rawValue
        {
            range = .twelveMonths
        }
        if !history.monthAnchors.contains(selectedAnchor) && selectedForecast == nil {
            selectedAnchor = history.currentAnchor
        }
        keepSelectionVisible()
    }

    // MARK: - Derived

    /// A category first planned in a month ahead: it has no past to read, only a forecast.
    private func isForecastOnly(_ filter: BudgetHistoryFilter) -> Bool {
        guard case .category(let category) = filter, history.series(for: filter) == nil else { return false }
        return forecast.plannedCategories.contains(category)
    }

    /// Every past month of the chosen filter.
    private var fullSeries: BudgetHistorySeries {
        history.series(for: filter)
            ?? (isForecastOnly(filter) ? BudgetHistorySeries(filter: filter, months: []) : history.wholeMonth)
    }

    /// The bars on screen: the chosen range, minus leading months with nothing in them.
    var series: BudgetHistorySeries {
        fullSeries
            .suffix(range.rawValue)
            .trimmingLeadingEmptyMonths()
    }

    var selectedMonth: BudgetHistoryMonth? {
        series.month(selectedAnchor) ?? series.months.last
    }

    /// The projected bars after the past ones, for the chosen filter. Never part of `series`, so they
    /// reach no score, streak or savings figure.
    /// Empty when no month ahead has anything for this filter: six blank columns would only squeeze
    /// the past bars.
    var forecastMonths: [BudgetForecastFigures] {
        let months = forecast.figures(for: filter)
        return months.allSatisfy { $0.status == .empty } ? [] : months
    }

    /// The selected month when it lies ahead. While it does, `selectedMonth` stays on the open month
    /// and the Saved figures are not on screen.
    var selectedForecast: BudgetForecastFigures? {
        forecastMonths.first { $0.monthAnchor == selectedAnchor }
    }

    /// The month highlighted on the chart, past or projected.
    var displayedAnchor: Int? { selectedForecast?.monthAnchor ?? selectedMonth?.monthAnchor }

    var filters: [BudgetHistoryFilter] {
        history.filters + forecast.plannedCategories.map(BudgetHistoryFilter.category).filter(isForecastOnly)
    }

    /// The 12-month option only when it would show more than the 6-month one. A ledger with five months
    /// of history draws the same bars under both, and a toggle that changes nothing reads as broken.
    var offersLongerRange: Bool {
        fullSeries
            .suffix(Span.twelveMonths.rawValue)
            .trimmingLeadingEmptyMonths()
            .months.count > Span.sixMonths.rawValue
    }

    var isEmpty: Bool { history.isEmpty && forecast.isEmpty }

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

    /// The first month Saved counts: the chosen start, or the selected month itself under `.only`.
    var countedStart: Int? {
        savingsScope == .only ? savingsEnd : savingsStart
    }

    /// "Only" is on and the selected month is still open. Its figures are what it has left, or is
    /// over, up to today - not saved yet - so the screen labels them "so far" and keeps what is left grey.
    var isSoFar: Bool {
        savingsScope == .only && selectedMonth?.isCurrent == true
    }

    /// The history the Saved and "Why" figures read: the open month counted so far under `isSoFar`,
    /// left out everywhere else.
    private var countedHistory: BudgetHistory {
        isSoFar ? history.countingOpenMonthSoFar(in: expenses, asOf: reference()) : history
    }

    /// What made the Saved figure, over the same months it counts.
    var contributors: SavingsContributors? {
        countedHistory.contributors(for: filter, from: countedStart, through: savingsEnd)
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

    /// One projected month as its card shows it: the figures, the rows already dated in it and the
    /// three biggest of them, and the month's balance figures.
    func forecastDetail(_ figures: BudgetForecastFigures) -> ForecastDetail? {
        guard let month = forecast.month(figures.monthAnchor) else { return nil }
        let listed = forecast.transactions(for: filter, month: figures.monthAnchor, in: expenses)
            .filter { $0.amount > 0 }
        return ForecastDetail(
            figures: figures, month: month, scheduledCount: listed.count, biggest: Array(listed.prefix(3)))
    }

    struct ForecastDetail {
        let figures: BudgetForecastFigures
        let month: BudgetForecastMonth
        let scheduledCount: Int
        let biggest: [Transaction]
    }

    /// The named parts of the outside remainder, shown under the Saved card while that filter is on.
    var outsideDifferences: [BudgetHistory.OutsideDifference] {
        guard outsideTiming != nil else { return [] }
        return countedHistory.outsideDifferences(from: countedStart, through: savingsEnd)
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
        // Outside allocations counts its named differences too, so its Saved figure is the same
        // number its row shows in the list and in the whole month's "Why" card.
        if filter == .outsideAllocations {
            return countedHistory.outsideSavings(from: countedStart, through: savingsEnd) ?? .none
        }
        return countedHistory.series(for: filter)?.savings(from: countedStart, through: savingsEnd) ?? .none
    }

    /// A month's budget and what its categories were given - the subtraction behind outside figures.
    func budgetSplit(_ anchor: Int) -> (budget: Int, inCategories: Int) {
        (history.wholeMonth.month(anchor)?.planned ?? 0,
         history.categories.reduce(0) { $0 + ($1.month(anchor)?.planned ?? 0) })
    }

    /// The expenses outside every category in `months`, biggest first - what a "spent outside
    /// categories" difference is made of.
    func outsideExpenses(in months: [Int]) -> [Transaction] {
        months.flatMap { history.transactions(for: .outsideAllocations, month: $0, in: expenses) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    /// Filters left by drilling into a part of the "Why" card, most recent last. The screen shows a
    /// way back to the last one; choosing from the picker starts over.
    @Published private(set) var filterTrail: [BudgetHistoryFilter] = []

    func drill(into newFilter: BudgetHistoryFilter) {
        guard newFilter != filter else { return }
        filterTrail.append(filter)
        select(filter: newFilter)
    }

    func goBack() {
        guard let previous = filterTrail.popLast() else { return }
        select(filter: previous)
    }

    func choose(filter newFilter: BudgetHistoryFilter) {
        filterTrail.removeAll()
        select(filter: newFilter)
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
        return countedHistory.outsideAllocations(from: countedStart, through: savingsEnd)
    }

    /// What the outside series does not explain, since `savingsStart`. Shown under the Saved card while
    /// the outside filter is chosen, so that card plus this line equal its row in the list.
    var outsideTiming: Int? {
        guard filter == .outsideAllocations else { return nil }
        return countedHistory.outsideTiming(from: countedStart, through: savingsEnd)
    }

    /// The month the arrows step to, or nil at either end of the bars on screen.
    func neighbour(by offset: Int) -> Int? {
        let months = series.months.map(\.monthAnchor) + forecastMonths.map(\.monthAnchor)
        guard let index = months.firstIndex(where: { $0 == displayedAnchor }) else { return nil }
        let target = index + offset
        return months.indices.contains(target) ? months[target] : nil
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

    func select(savingsScope scope: SavingsScope) {
        savingsScope = scope
        CoachMarkCenter.shared.post(.historySavingsChanged)
    }

    func select(filter newFilter: BudgetHistoryFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        keepSelectionVisible()
        CoachMarkCenter.shared.post(.historyFilterChanged)
    }

    func select(range newRange: Span) {
        guard newRange != range else { return }
        range = newRange
        keepSelectionVisible()
        CoachMarkCenter.shared.post(.historyRangeChanged)
    }

    func select(month anchor: Int) {
        guard series.month(anchor) != nil || forecastMonths.contains(where: { $0.monthAnchor == anchor })
        else { return }
        selectedAnchor = anchor
        CoachMarkCenter.shared.post(.historyMonthPicked)
        if selectedForecast != nil { CoachMarkCenter.shared.post(.historyProjectedMonthPicked) }
    }

    /// A shorter range or a trimmed series can drop the selected month off the chart. Move the
    /// selection to the open month rather than leaving the readout on a month with no bar.
    private func keepSelectionVisible() {
        guard series.month(selectedAnchor) == nil, selectedForecast == nil else { return }
        if let month = series.months.last?.monthAnchor ?? forecastMonths.first?.monthAnchor {
            selectedAnchor = month
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

    /// "Up to Sep" or "Only Sep" - short, so both fit side by side in the switch.
    static func savingsScopeTitle(_ scope: SavingsScope, month anchor: Int) -> String {
        let key = scope == .upTo ? "budgetHistory.savings.through.format" : "budgetHistory.savings.only.format"
        return String(format: key.localized, shortMonth(anchor))
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

    /// The status a projected month carries: an amount when values are visible, a word when not.
    /// The words never say "saved" or "on plan": nothing here has happened yet.
    static func forecastStatusText(for month: BudgetForecastFigures, hidden: Bool) -> String {
        switch month.status {
        case .fits:
            return hidden
                ? "budgetHistory.forecast.status.fits".localized
                : String(format: "budgetHistory.status.left.format".localized, month.difference.currencyString)
        case .short:
            return hidden
                ? "budgetHistory.forecast.status.short".localized
                : String(
                    format: "budgetHistory.forecast.status.short.format".localized,
                    abs(month.difference).currencyString)
        case .noPlan, .empty:
            return noPlanText(for: month.filter)
        }
    }

    /// A month with no plan says so in words, so it never reads as a plan of zero.
    static func noPlanText(for filter: BudgetHistoryFilter) -> String {
        switch filter {
        case .category: return "budgetHistory.forecast.noAllocation".localized
        case .wholeMonth, .outsideAllocations: return "budgetHistory.forecast.noBudget".localized
        }
    }

    /// What VoiceOver reads for a projected month. Opens by saying it is projected, so the amounts
    /// that follow are never taken for a result.
    static func forecastAccessibilityValue(for month: BudgetForecastFigures, hidden: Bool) -> String {
        var parts = ["budgetHistory.forecast.badge".localized]
        if !hidden {
            parts.append(
                month.hasPlan
                    ? String(
                        format: "budgetHistory.forecast.a11y.expectedOf.format".localized,
                        month.expected.currencyString, month.planned.currencyString)
                    : String(
                        format: "budgetHistory.forecast.a11y.expected.format".localized,
                        month.expected.currencyString))
        }
        parts.append(forecastStatusText(for: month, hidden: hidden))
        return parts.joined(separator: ", ")
    }
}
