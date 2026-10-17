//
//  BudgetHistoryContentView.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import SwiftUI
import UIKit

/// Everything under the header: what is shown and over how long, the selected month with the chart,
/// what the selection saved, and three insight tiles.
///
/// Every control that changes the readout sits in or above the card it changes. An earlier version had
/// a month list far below the chart that also selected months, and selecting in one place moved
/// something out of sight in the other.
struct BudgetHistoryContentView: View {
    @ObservedObject var viewModel: BudgetHistoryViewModel

    @State private var isPickerPresented = false
    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.spacing4) {
                    controls
                    chartCard
                    savingsCard
                    contributorsCard
                    insights
                }
                .padding(.vertical, Metrics.spacing4)
            }
            .scrollIndicators(.hidden)
            .sheet(isPresented: $isPickerPresented) {
                FilterPickerSheet(viewModel: viewModel) { filter in
                    selectionFeedback.selectionChanged()
                    isPickerPresented = false
                    withAnimation(.snappy(duration: 0.3)) { viewModel.select(filter: filter) }
                }
            }
        }
    }

    private var hidden: Bool { viewModel.isValuesHidden }

    private func select(month anchor: Int) {
        guard anchor != viewModel.selectedAnchor else { return }
        selectionFeedback.selectionChanged()
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.select(month: anchor)
        }
    }

    // MARK: - Controls

    /// What is shown, and over how long. One button opens the full list, so reaching the last of 26
    /// categories is a tap and a glance rather than a long sideways scroll.
    private var controls: some View {
        HStack(spacing: Metrics.spacing3) {
            SwiftUI.Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: Metrics.spacing2) {
                    FilterIcon(filter: viewModel.filter)
                        .frame(width: 16, height: 16)
                    Text(BudgetHistoryViewModel.title(for: viewModel.filter))
                        .font(Font(Fonts.textSMBold.font))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color(Colors.gray700))
                .padding(.horizontal, Metrics.spacing4)
                .frame(height: 36)
                .background(Capsule().fill(Color(Colors.gray100)))
                .overlay(Capsule().stroke(Color(Colors.gray300), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("budgetHistory.a11y.chooseFilter".localized)
            .accessibilityValue(BudgetHistoryViewModel.title(for: viewModel.filter))

            Spacer(minLength: 0)

            if viewModel.offersLongerRange {
                rangePicker
            }
        }
        .padding(.horizontal, Metrics.spacing4)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing4) {
            if let month = viewModel.selectedMonth {
                readout(for: month)
            }

            BudgetHistoryChartView(
                months: viewModel.series.months,
                selectedAnchor: viewModel.selectedMonth?.monthAnchor,
                isValuesHidden: hidden,
                onSelect: select(month:)
            )
            .frame(height: 210)

            legend
        }
        .padding(Metrics.spacing5)
        .cardBackground()
        .padding(.horizontal, Metrics.spacing4)
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(BudgetHistoryViewModel.Span.allCases) { range in
                let isSelected = range == viewModel.range
                SwiftUI.Button {
                    selectionFeedback.selectionChanged()
                    withAnimation(.snappy(duration: 0.3)) { viewModel.select(range: range) }
                } label: {
                    Text(range.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : Color(Colors.gray500))
                        .frame(width: 40, height: 28)
                        .background(Capsule().fill(isSelected ? Color(Colors.mainMagenta) : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(Colors.gray100)))
        .overlay(Capsule().stroke(Color(Colors.gray300), lineWidth: 1))
    }

    /// The selected month in words and figures. Updates as a finger scrubs the chart - the pattern
    /// the donut's centre readout uses for a selected slice.
    private func readout(for month: BudgetHistoryMonth) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacing1) {
            HStack(spacing: Metrics.spacing1) {
                stepButton(by: -1)
                Text(BudgetHistoryViewModel.longMonth(month.monthAnchor))
                    .font(Font(Fonts.textSMBold.font))
                    .foregroundStyle(Color(Colors.gray600))
                    .contentTransition(.numericText())
                stepButton(by: 1)
                Spacer(minLength: Metrics.spacing2)
                // Right-aligned, in the same column as the status pill under it.
                if month.isCurrent {
                    Text("budgetHistory.status.inProgress".localized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(Colors.mainMagenta))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(Colors.mainMagenta).opacity(0.1)))
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(month.spent.maskedCurrencyString(hidden: hidden))
                    .font(.custom(Fonts.titleLG.font.fontName, size: 24))
                    .foregroundStyle(Color(Colors.gray700))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Spacer(minLength: Metrics.spacing2)
                StatusPill(month: month, hidden: hidden)
            }

            Text(planLine(for: month))
                .font(Font(Fonts.textXS.font))
                .foregroundStyle(Color(Colors.gray500))
        }
    }

    /// One month back or forward, within the bars on screen. Next to the month name so the month being
    /// read and the way to change it are in one place.
    private func stepButton(by offset: Int) -> some View {
        let target = viewModel.neighbour(by: offset)
        return SwiftUI.Button {
            if let target { select(month: target) }
        } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(target == nil ? Color(Colors.gray300) : Color(Colors.mainMagenta))
                // The back arrow's glyph sits on the card's left edge, in line with the amount
                // under it; the tap area still extends 28pt to the right of it.
                .frame(width: offset < 0 ? 20 : 28, height: 28, alignment: offset < 0 ? .leading : .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityLabel(
            (offset < 0 ? "budgetHistory.a11y.previousMonth" : "budgetHistory.a11y.nextMonth").localized)
    }

    private func planLine(for month: BudgetHistoryMonth) -> String {
        guard month.hasPlan else { return "budgetHistory.hero.noPlan".localized }
        var line = String(
            format: "budgetHistory.hero.of.format".localized,
            month.planned.maskedCurrencyString(hidden: hidden))
        if let percent = month.percentUsed {
            line += " · " + String(format: "budgetHistory.percent.format".localized, percent)
        }
        return line
    }

    private var legend: some View {
        HStack(spacing: Metrics.spacing4) {
            legendItem(color: Color(Colors.mainMagenta), label: "budgetHistory.legend.spent".localized)
            legendItem(color: Color(Colors.mainRed), label: "budgetHistory.legend.over".localized)
            HStack(spacing: Metrics.spacing1 + 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color(Colors.gray300))
                        .frame(width: 10, height: 10)
                    Rectangle().fill(Color(Colors.gray600)).frame(width: 12, height: 2)
                        .offset(y: -4)
                }
                .frame(width: 12, height: 10)
                Text("budgetHistory.legend.plan".localized)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(Color(Colors.gray500))
        .accessibilityHidden(true)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: Metrics.spacing1 + 2) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    // MARK: - Insights

    private var insights: some View {
        let series = viewModel.series
        let scored = series.scoredMonths.count
        let none = "budgetHistory.insight.none".localized

        let onPlanValue = scored > 0
            ? String(format: "budgetHistory.insight.onPlan.value.format".localized, series.monthsOnPlan, scored)
            : none
        let rangeValue: String = series.usageRange.map { range in
            range.low == range.high ? "\(range.low)%" : "\(range.low)–\(range.high)%"
        } ?? none
        let streak = series.streak
        let streakValue = scored == 0
            ? none
            : streak == 1
                ? "budgetHistory.insight.streak.value.one".localized
                : String(format: "budgetHistory.insight.streak.value.format".localized, streak)

        return HStack(spacing: Metrics.spacing2) {
            InsightTile(
                icon: "checkmark.seal.fill",
                tint: Color(Colors.mainGreen),
                title: "budgetHistory.insight.onPlan.title".localized,
                value: onPlanValue,
                caption: "budgetHistory.insight.onPlan.caption".localized)
            InsightTile(
                icon: "arrow.left.and.right",
                tint: Color(Colors.mainMagenta),
                title: "budgetHistory.insight.range.title".localized,
                value: rangeValue,
                caption: "budgetHistory.insight.range.caption".localized)
            InsightTile(
                icon: "flame.fill",
                tint: streak > 0 ? Color(Colors.warningAmber) : Color(Colors.gray400),
                title: "budgetHistory.insight.streak.title".localized,
                value: streakValue,
                caption: "budgetHistory.insight.streak.caption".localized)
        }
        .padding(.horizontal, Metrics.spacing4)
    }

    // MARK: - Savings

    /// What the chosen filter saved in closed months, from a start month the user picks.
    private var savingsCard: some View {
        let savings = viewModel.savings
        return VStack(alignment: .leading, spacing: Metrics.spacing2) {
            HStack(alignment: .center) {
                Text("budgetHistory.savings.title".localized)
                    .font(Font(Fonts.title2XS.font))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(Colors.gray500))
                Spacer(minLength: Metrics.spacing2)
                savingsStartMenu
            }

            if savings.months == 0 {
                Text("budgetHistory.savings.none".localized)
                    .font(Font(Fonts.textSM.font))
                    .foregroundStyle(Color(Colors.gray500))
            } else {
                Text(savings.net.maskedSignedCurrencyString(hidden: hidden))
                    .font(.custom(Fonts.titleLG.font.fontName, size: 24))
                    .foregroundStyle(
                        hidden ? Color(Colors.gray700)
                            : savings.net >= 0 ? Color(Colors.mainGreen) : Color(Colors.mainRed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 2) {
                    if let split = savingsSplit(savings) {
                        Text(split)
                    }
                    Text(savingsPeriod(savings))
                }
                .font(Font(Fonts.textXS.font))
                .foregroundStyle(Color(Colors.gray500))
            }

            // What the chart does not explain, each part with its reason, so the card plus these lines
            // equal the Outside allocations row in the list.
            let differences = viewModel.outsideDifferences
            if !differences.isEmpty {
                Divider().overlay(Color(Colors.gray300)).padding(.vertical, Metrics.spacing1)
                ForEach(Array(differences.enumerated()), id: \.offset) { _, difference in
                    HStack(alignment: .firstTextBaseline) {
                        Text(differenceLabel(difference))
                            .font(Font(Fonts.textXS.font))
                            .foregroundStyle(Color(Colors.gray500))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Metrics.spacing2)
                        Text(difference.amount.maskedSignedCurrencyString(hidden: hidden))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(Colors.gray600))
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Metrics.spacing5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .padding(.horizontal, Metrics.spacing4)
        .accessibilityElement(children: .contain)
    }

    /// "R$ 5.119,06 saved · R$ 1.350,09 over", leaving out a side that is zero. Nil while values are
    /// hidden, or when only one side has anything - the net above already says it.
    private func savingsSplit(_ savings: BudgetHistorySeries.Savings) -> String? {
        guard !hidden, savings.saved > 0, savings.overspent > 0 else { return nil }
        return String(
            format: "budgetHistory.savings.detail.format".localized,
            savings.saved.currencyString, savings.overspent.currencyString)
    }

    private var savingsStartMenu: some View {
        Menu {
            startOption(nil)
            Divider()
            ForEach(viewModel.savingsStartOptions.reversed(), id: \.self) { anchor in
                startOption(anchor)
            }
        } label: {
            HStack(spacing: 4) {
                Text(BudgetHistoryViewModel.savingsStartTitle(viewModel.savingsStart))
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color(Colors.mainMagenta))
        }
    }

    @ViewBuilder
    private func startOption(_ anchor: Int?) -> some View {
        let title = anchor.map(BudgetHistoryViewModel.longMonth)
            ?? "budgetHistory.savings.since.start".localized
        SwiftUI.Button {
            selectionFeedback.selectionChanged()
            withAnimation(.snappy(duration: 0.3)) { viewModel.select(savingsStart: anchor) }
        } label: {
            if viewModel.savingsStart == anchor {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// "Up to September 2026 · 5 closed months": which months the figure above adds up, so it is clear
    /// that it moves with the month selected on the chart.
    private func savingsPeriod(_ savings: BudgetHistorySeries.Savings) -> String {
        let months = savings.months == 1
            ? "budgetHistory.savings.months.one".localized
            : String(format: "budgetHistory.savings.months.format".localized, savings.months)
        guard let end = viewModel.savingsEndMonth else { return months }
        return BudgetHistoryViewModel.savingsEndTitle(end) + " · " + months
    }

    private func differenceLabel(_ difference: BudgetHistory.OutsideDifference) -> String {
        let months = BudgetHistoryViewModel.monthList(difference.months)
        switch difference.reason {
        case .categoriesAboveBudget:
            return String(format: "budgetHistory.outside.diff.aboveBudget.format".localized, months)
        case .spentOutsideWithNoRoom:
            return String(format: "budgetHistory.outside.diff.spentNoRoom.format".localized, months)
        case .noMonthBudget:
            return String(format: "budgetHistory.outside.diff.noBudget.format".localized, months)
        case .otherMonth:
            return "budgetHistory.outside.timing".localized
        }
    }

    // MARK: - What made Saved

    @State private var expandedMonth: Int?
    @State private var showsOthers = false

    /// What made the Saved figure: the few parts that moved it most, then everything else in one line,
    /// then the total - which is the Saved figure. Categories for the whole month, months otherwise.
    @ViewBuilder
    private var contributorsCard: some View {
        if let contributors = viewModel.contributors {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hidden
                        ? "budgetHistory.explain.header.hidden".localized
                        : String(format: "budgetHistory.explain.header.format".localized,
                            contributors.total.maskedSignedCurrencyString(hidden: false)))
                        .font(Font(Fonts.title2XS.font))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(Colors.gray500))
                    if let first = contributors.firstMonth, let last = contributors.lastMonth {
                        Text(BudgetHistoryViewModel.periodTitle(first, last))
                            .font(Font(Fonts.textXS.font))
                            .foregroundStyle(Color(Colors.gray500))
                    }
                }
                .padding(.horizontal, Metrics.spacing5)
                .padding(.top, Metrics.spacing4)
                .padding(.bottom, Metrics.spacing2)

                if !contributors.savers.isEmpty {
                    sectionLabel("budgetHistory.contrib.saved".localized, tint: Colors.mainGreen)
                    ForEach(contributors.savers, id: \.part) { contributorRow($0) }
                }
                if !contributors.overspenders.isEmpty {
                    sectionLabel("budgetHistory.contrib.over".localized, tint: Colors.mainRed)
                    ForEach(contributors.overspenders, id: \.part) { contributorRow($0) }
                }
                if contributors.othersCount > 0 {
                    Divider().overlay(Color(Colors.gray300)).padding(.top, Metrics.spacing2)
                    // Opens to the parts it sums, biggest effect first, so nothing stays hidden.
                    SwiftUI.Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsOthers.toggle() }
                    } label: {
                        HStack(spacing: Metrics.spacing2) {
                            ExplanationLine(
                                label: String(format: "budgetHistory.contrib.others.format".localized,
                                    contributors.othersCount),
                                value: contributors.others.maskedSignedCurrencyString(hidden: hidden),
                                // Coloured by direction like every named line, so it is clear which
                                // way the remainder moved Saved.
                                tint: hidden ? nil
                                    : (contributors.others >= 0 ? Colors.mainGreen : Colors.mainRed))
                                .padding(.trailing, -Metrics.spacing5)
                            Image(systemName: showsOthers ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(Colors.gray400))
                                .padding(.trailing, Metrics.spacing5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showsOthers {
                        ForEach(contributors.rest, id: \.part) { contributorRow($0) }
                    }
                }
                Divider().overlay(Color(Colors.gray300))
                ExplanationLine(
                    label: "budgetHistory.contrib.total".localized,
                    value: contributors.total.maskedSignedCurrencyString(hidden: hidden),
                    tint: hidden ? nil : (contributors.total >= 0 ? Colors.mainGreen : Colors.mainRed),
                    weight: .bold)
                    .padding(.vertical, Metrics.spacing2)
                    .background(Color(Colors.gray200).opacity(0.5))
            }
            .cardBackground()
            .padding(.horizontal, Metrics.spacing4)
            .onChange(of: viewModel.filter) { _, _ in
                expandedMonth = nil
                showsOthers = false
            }
        }
    }

    private func sectionLabel(_ text: String, tint: UIColor) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(tint))
            .padding(.horizontal, Metrics.spacing5)
            .padding(.top, Metrics.spacing3)
            .padding(.bottom, Metrics.spacing1)
    }

    /// A category opens that category; a month opens its three biggest expenses in place.
    @ViewBuilder
    private func contributorRow(_ item: SavingsContributors.Item) -> some View {
        let tint = item.net >= 0 ? Colors.mainGreen : Colors.mainRed
        let amount = item.net.maskedSignedCurrencyString(hidden: hidden)
        switch item.part {
        case .category(let category):
            ContributorRow(icon: FilterIcon(filter: .category(category)),
                title: category.displayName, amount: amount, tint: hidden ? Colors.gray700 : tint,
                accessory: "chevron.right") {
                selectionFeedback.selectionChanged()
                withAnimation(.snappy(duration: 0.3)) { viewModel.select(filter: .category(category)) }
            }
        case .outsideAllocations:
            ContributorRow(icon: FilterIcon(filter: .outsideAllocations),
                title: "budgetHistory.outside.title".localized, amount: amount,
                tint: hidden ? Colors.gray700 : tint, accessory: "chevron.right") {
                selectionFeedback.selectionChanged()
                withAnimation(.snappy(duration: 0.3)) { viewModel.select(filter: .outsideAllocations) }
            }
        case .month(let anchor):
            let isOpen = expandedMonth == anchor
            ContributorRow(icon: Image(systemName: "calendar"),
                title: BudgetHistoryViewModel.longMonth(anchor), amount: amount,
                tint: hidden ? Colors.gray700 : tint, accessory: isOpen ? "chevron.up" : "chevron.down") {
                withAnimation(.easeInOut(duration: 0.2)) { expandedMonth = isOpen ? nil : anchor }
            }
            if isOpen {
                monthDetail(anchor)
            }
        }
    }

    private var planLabel: String {
        switch viewModel.filter {
        case .wholeMonth: return "budgetHistory.explain.plan.wholeMonth".localized
        case .category(let category):
            return String(format: "budgetHistory.explain.plan.category.format".localized, category.displayName)
        case .outsideAllocations: return "budgetHistory.explain.plan.outside".localized
        }
    }

    /// The month's own sum first - plan, spent, result - so its number adds up on the spot, then only
    /// the three biggest expenses: enough to see what drove it, without repeating the dashboard list.
    @ViewBuilder
    private func monthDetail(_ anchor: Int) -> some View {
        if let detail = viewModel.monthDetail(anchor) {
            VStack(alignment: .leading, spacing: 0) {
                if let split = detail.budgetSplit {
                    detailLine(
                        "budgetHistory.explain.plan.wholeMonth".localized,
                        split.budget.maskedCurrencyString(hidden: hidden))
                    detailLine(
                        "budgetHistory.explain.inCategories".localized,
                        (-split.inCategories).maskedSignedCurrencyString(hidden: hidden))
                    detailLine(
                        "= " + planLabel, detail.month.planned.maskedCurrencyString(hidden: hidden),
                        bold: true)
                } else {
                    detailLine(planLabel, detail.month.planned.maskedCurrencyString(hidden: hidden))
                }
                detailLine(
                    String(format: "budgetHistory.explain.spent.format".localized, detail.expenseCount),
                    (-detail.month.spent).maskedSignedCurrencyString(hidden: hidden))
                detailLine(
                    "= " + BudgetHistoryViewModel.longMonth(anchor),
                    detail.month.difference.maskedSignedCurrencyString(hidden: hidden),
                    tint: hidden ? nil : (detail.month.difference >= 0 ? Colors.mainGreen : Colors.mainRed),
                    bold: true)
                if detail.budgetSplit != nil && detail.month.difference > 0 {
                    // The question this answers: which expense made this number? None did.
                    Text("budgetHistory.explain.outside.unspent".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Colors.gray500))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Metrics.spacing1)
                }
                if !detail.biggest.isEmpty {
                    Text("budgetHistory.contrib.topExpenses".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Colors.gray500))
                        .padding(.top, Metrics.spacing2)
                        .padding(.bottom, Metrics.spacing1)
                }
                ForEach(Array(detail.biggest.enumerated()), id: \.offset) { _, transaction in
                    SwiftUI.Button {
                        viewModel.onOpenTransaction?(transaction)
                    } label: {
                        HStack {
                            Text(transaction.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(Colors.gray700))
                                .lineLimit(1)
                            Spacer(minLength: Metrics.spacing2)
                            Text((-transaction.amount).maskedSignedCurrencyString(hidden: hidden))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(Colors.gray600))
                                .fixedSize()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(Colors.gray400))
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 56 + Metrics.spacing5)
            .padding(.trailing, Metrics.spacing5)
            .padding(.bottom, Metrics.spacing2)
        }
    }

    private func detailLine(_ label: String, _ value: String, tint: UIColor? = nil, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: bold ? .semibold : .regular))
                .foregroundStyle(Color(Colors.gray700))
            Spacer(minLength: Metrics.spacing2)
            Text(value)
                .font(.system(size: 12, weight: bold ? .semibold : .medium))
                .foregroundStyle(Color(tint ?? Colors.gray600))
                .fixedSize()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: Metrics.spacing3) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Color(Colors.gray400))
            Text("budgetHistory.empty.title".localized)
                .font(Font(Fonts.titleMD.font))
                .foregroundStyle(Color(Colors.gray700))
            Text("budgetHistory.empty.message".localized)
                .font(Font(Fonts.textSM.font))
                .foregroundStyle(Color(Colors.gray500))
                .multilineTextAlignment(.center)
        }
        .padding(Metrics.spacing8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pieces

/// The amount left or over, coloured by outcome. Words instead of amounts while values are hidden.
private struct StatusPill: View {
    let month: BudgetHistoryMonth
    let hidden: Bool

    private var tint: Color {
        switch month.status {
        case .within, .inProgress: return Color(Colors.mainGreen)
        case .over: return Color(Colors.mainRed)
        case .noPlan, .empty: return Color(Colors.gray500)
        }
    }

    private var icon: String {
        switch month.status {
        case .within: return "checkmark"
        case .inProgress: return "clock"
        case .over: return "arrow.up.right"
        case .noPlan, .empty: return "minus"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(BudgetHistoryViewModel.statusText(for: month, hidden: hidden))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Metrics.spacing2)
        .frame(height: 22)
        .background(Capsule().fill(tint.opacity(0.1)))
        .fixedSize()
    }
}

private struct InsightTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing1) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(Colors.gray500))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(Font(Fonts.titleMD.font))
                .foregroundStyle(Color(Colors.gray700))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(Color(Colors.gray400))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.spacing3)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

/// One line of the Why card: a label and an amount, with an optional note under it.
private struct ExplanationLine: View {
    let label: String
    let value: String
    var tint: UIColor? = nil
    var note: String? = nil
    var weight: Font.Weight = .regular

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 13, weight: weight))
                    .foregroundStyle(Color(Colors.gray700))
                Spacer(minLength: Metrics.spacing2)
                Text(value)
                    .font(.system(size: 13, weight: weight == .regular ? .medium : weight))
                    .foregroundStyle(Color(tint ?? Colors.gray700))
                    .lineLimit(1)
                    .fixedSize()
            }
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Colors.gray500))
            }
        }
        .padding(.horizontal, Metrics.spacing5)
        .padding(.vertical, Metrics.spacing2)
        .accessibilityElement(children: .combine)
    }
}

/// One named contributor: an icon, a name, and how much it saved (green) or overspent (red).
private struct ContributorRow<Icon: View>: View {
    let icon: Icon
    let title: String
    let amount: String
    let tint: UIColor
    let accessory: String
    let onTap: () -> Void

    var body: some View {
        SwiftUI.Button(action: onTap) {
            HStack(spacing: Metrics.spacing3) {
                icon
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color(Colors.gray600))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: CornerRadius.medium).fill(Color(Colors.gray200)))
                Text(title)
                    .font(Font(Fonts.textSM.font))
                    .foregroundStyle(Color(Colors.gray700))
                    .lineLimit(1)
                Spacer(minLength: Metrics.spacing2)
                Text(amount)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(tint))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: accessory)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(Colors.gray400))
            }
            .padding(.horizontal, Metrics.spacing5)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The icon a filter is shown with: a calendar for the whole month, the category's own otherwise.
private struct FilterIcon: View {
    let filter: BudgetHistoryFilter

    var body: some View {
        switch filter {
        case .wholeMonth:
            Image(systemName: "calendar")
                .resizable()
                .scaledToFit()
        case .outsideAllocations:
            Image(systemName: "square.dashed")
                .resizable()
                .scaledToFit()
        case .category(let category):
            if let icon = UIImage(named: category.iconName) {
                Image(uiImage: icon).resizable().renderingMode(.template).scaledToFit()
            }
        }
    }
}

/// Every filter in one vertical list, each with what it saved since the chosen start month - so the
/// list that picks a category also compares them.
private struct FilterPickerSheet: View {
    @ObservedObject var viewModel: BudgetHistoryViewModel
    let onPick: (BudgetHistoryFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Metrics.spacing1) {
                Text("budgetHistory.picker.title".localized)
                    .font(Font(Fonts.titleMD.font))
                    .foregroundStyle(Color(Colors.gray700))
                Text("budgetHistory.savings.title".localized + " · "
                    + BudgetHistoryViewModel.savingsStartTitle(viewModel.savingsStart)
                    + (viewModel.savingsEndMonth.map { " · " + BudgetHistoryViewModel.savingsEndTitle($0) } ?? ""))
                    .font(Font(Fonts.textXS.font))
                    .foregroundStyle(Color(Colors.gray500))
            }
            .padding(.horizontal, Metrics.spacing5)
            .padding(.top, Metrics.spacing6)
            .padding(.bottom, Metrics.spacing3)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filters, id: \.self) { filter in
                        row(for: filter)
                        Divider().overlay(Color(Colors.gray300)).padding(.leading, 64)
                    }
                    if let outside = viewModel.outsideAllocations {
                        outsideRow(outside)
                    }
                }
            }
        }
        .background(Color(Colors.gray100))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(CornerRadius.bottomSheet)
    }

    /// The remainder, so the category rows plus this one add up to the whole month. Tapping it shows
    /// it like a category: unallocated budget as the plan, unplanned spending as what was spent.
    private func outsideRow(_ amount: Int) -> some View {
        let hidden = viewModel.isValuesHidden
        let isSelected = viewModel.filter == .outsideAllocations
        return SwiftUI.Button {
            onPick(.outsideAllocations)
        } label: {
            HStack(spacing: Metrics.spacing3) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isSelected ? Color(Colors.mainMagenta) : Color(Colors.gray500))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(
                                isSelected ? Color(Colors.mainMagenta) : Color(Colors.gray300),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                VStack(alignment: .leading, spacing: 2) {
                    Text("budgetHistory.outside.title".localized)
                        .font(Font(isSelected ? Fonts.textSMBold.font : Fonts.textSM.font))
                        .foregroundStyle(Color(Colors.gray700))
                    Text("budgetHistory.outside.caption".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Colors.gray500))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.spacing2)
                Text(amount.maskedSignedCurrencyString(hidden: hidden))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        hidden ? Color(Colors.gray500)
                            : amount >= 0 ? Color(Colors.mainGreen) : Color(Colors.mainRed))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(Colors.mainMagenta))
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, Metrics.spacing5)
            .padding(.vertical, Metrics.spacing3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func row(for filter: BudgetHistoryFilter) -> some View {
        let isSelected = filter == viewModel.filter
        let savings = viewModel.savings(for: filter)
        let hidden = viewModel.isValuesHidden
        return SwiftUI.Button {
            onPick(filter)
        } label: {
            HStack(spacing: Metrics.spacing3) {
                FilterIcon(filter: filter)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? Color(Colors.mainMagenta) : Color(Colors.gray600))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .fill(isSelected ? Color(Colors.mainMagenta).opacity(0.1) : Color(Colors.gray200)))
                Text(BudgetHistoryViewModel.title(for: filter))
                    .font(Font(isSelected ? Fonts.textSMBold.font : Fonts.textSM.font))
                    .foregroundStyle(Color(Colors.gray700))
                    .lineLimit(1)
                Spacer(minLength: Metrics.spacing2)
                Text(savings.months == 0
                    ? "budgetHistory.insight.none".localized
                    : savings.net.maskedSignedCurrencyString(hidden: hidden))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        savings.months == 0 || hidden ? Color(Colors.gray500)
                            : savings.net >= 0 ? Color(Colors.mainGreen) : Color(Colors.mainRed))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(Colors.mainMagenta))
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, Metrics.spacing5)
            .padding(.vertical, Metrics.spacing3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension View {
    /// The white, bordered card every section on the light screens uses.
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: CornerRadius.extraLarge, style: .continuous)
                .fill(Color(Colors.gray100))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.extraLarge, style: .continuous)
                .stroke(Color(Colors.gray300), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.extraLarge, style: .continuous))
    }
}
