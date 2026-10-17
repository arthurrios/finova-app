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
                    explanationCard
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

            if let timing = viewModel.outsideTiming, timing != 0 {
                Divider().overlay(Color(Colors.gray300)).padding(.vertical, Metrics.spacing1)
                HStack(alignment: .firstTextBaseline) {
                    Text("budgetHistory.outside.timing".localized)
                        .font(Font(Fonts.textXS.font))
                        .foregroundStyle(Color(Colors.gray500))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Metrics.spacing2)
                    Text(timing.maskedSignedCurrencyString(hidden: hidden))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(Colors.gray600))
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
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

    // MARK: - Explanation

    @State private var showsAllRows = false
    private static let collapsedRowCount = 5

    /// Why Saved shows what it shows: the selected month's plan run down by each expense in date
    /// order, the month's result, and the earlier months that make up the rest. The last line is the
    /// Saved figure itself, so the card always ends on the number it explains.
    @ViewBuilder
    private var explanationCard: some View {
        if let explanation = viewModel.explanation {
            let rows = showsAllRows
                ? explanation.rows : Array(explanation.rows.prefix(Self.collapsedRowCount))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hidden
                        ? "budgetHistory.explain.header.hidden".localized
                        : String(format: "budgetHistory.explain.header.format".localized,
                            explanation.total.maskedSignedCurrencyString(hidden: false)))
                        .font(Font(Fonts.title2XS.font))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(Colors.gray500))
                    Text(BudgetHistoryViewModel.longMonth(explanation.month.monthAnchor))
                        .font(Font(Fonts.textXS.font))
                        .foregroundStyle(Color(Colors.gray500))
                }
                .padding(.horizontal, Metrics.spacing5)
                .padding(.vertical, Metrics.spacing4)

                Divider().overlay(Color(Colors.gray300))
                ExplanationLine(
                    label: planLabel,
                    value: explanation.month.hasPlan
                        ? explanation.month.planned.maskedCurrencyString(hidden: hidden)
                        : "budgetHistory.explain.noPlan".localized,
                    weight: .semibold)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().overlay(Color(Colors.gray300)).padding(.leading, Metrics.spacing5)
                    ExplanationRow(
                        row: row, showsLeft: explanation.month.hasPlan, hidden: hidden
                    ) {
                        viewModel.onOpenTransaction?(row.transaction)
                    }
                }

                if explanation.rows.count > Self.collapsedRowCount {
                    Divider().overlay(Color(Colors.gray300))
                    SwiftUI.Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllRows.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showsAllRows
                                ? "budgetHistory.transactions.showLess".localized
                                : String(format: "budgetHistory.transactions.showAll.format".localized,
                                    explanation.rows.count))
                            Image(systemName: showsAllRows ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(Font(Fonts.textSMBold.font))
                        .foregroundStyle(Color(Colors.mainMagenta))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(Color(Colors.gray300))
                summary(explanation)
            }
            .cardBackground()
            .padding(.horizontal, Metrics.spacing4)
            // A new month or filter starts collapsed again.
            .onChange(of: viewModel.selectedAnchor) { _, _ in showsAllRows = false }
            .onChange(of: viewModel.filter) { _, _ in showsAllRows = false }
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

    /// The arithmetic from the month's spending to the Saved figure, one line per step.
    private func summary(_ explanation: SavingsExplanation) -> some View {
        let month = explanation.month
        let monthName = BudgetHistoryViewModel.longMonth(month.monthAnchor)
        return VStack(spacing: 0) {
            ExplanationLine(
                label: String(format: "budgetHistory.explain.spent.format".localized, explanation.rows.count),
                value: (-explanation.listedSpent).maskedSignedCurrencyString(hidden: hidden))
            if explanation.adjustment != 0 {
                ExplanationLine(
                    label: "budgetHistory.explain.adjustment".localized,
                    value: (-explanation.adjustment).maskedSignedCurrencyString(hidden: hidden))
            }
            if month.hasPlan {
                ExplanationLine(
                    label: "= " + monthName,
                    value: month.difference.maskedSignedCurrencyString(hidden: hidden),
                    tint: hidden ? nil : (month.difference >= 0 ? Colors.mainGreen : Colors.mainRed),
                    note: countingNote(explanation.counting),
                    weight: .semibold)
            } else if let note = countingNote(explanation.counting) {
                ExplanationLine(label: "= " + monthName, value: "", note: note)
            }
            if explanation.earlier.months > 0, let first = explanation.earlierFirst,
                let last = explanation.earlierLast
            {
                ExplanationLine(
                    label: "+ " + (first == last
                        ? BudgetHistoryViewModel.longMonth(first)
                        : String(format: "budgetHistory.explain.earlier.format".localized,
                            BudgetHistoryViewModel.shortMonth(first), BudgetHistoryViewModel.shortMonth(last))),
                    value: explanation.earlier.net.maskedSignedCurrencyString(hidden: hidden),
                    tint: hidden ? nil : (explanation.earlier.net >= 0 ? Colors.mainGreen : Colors.mainRed))
            }
            ExplanationLine(
                label: "= " + (viewModel.savingsEndMonth.map(BudgetHistoryViewModel.savingsEndTitle)
                    .map { "budgetHistory.savings.title".localized + " · " + $0 }
                    ?? "budgetHistory.savings.title".localized),
                value: explanation.total.maskedSignedCurrencyString(hidden: hidden),
                tint: hidden ? nil : (explanation.total >= 0 ? Colors.mainGreen : Colors.mainRed),
                weight: .bold)
        }
        .padding(.vertical, Metrics.spacing2)
        .background(Color(Colors.gray200).opacity(0.5))
    }

    private func countingNote(_ counting: SavingsExplanation.Counting) -> String? {
        switch counting {
        case .counted: return nil
        case .inProgress: return "budgetHistory.explain.inProgress".localized
        case .noPlan: return "budgetHistory.explain.notCounted.noPlan".localized
        case .beforeStart: return "budgetHistory.explain.notCounted.beforeStart".localized
        }
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

/// One line of the explanation's arithmetic: a label and an amount, with an optional note under it.
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

/// One expense, with what is left of the month's plan after it: green while the plan holds, red from
/// the expense that takes it past zero. A tap opens the transaction's details.
private struct ExplanationRow: View {
    let row: SavingsExplanation.Row
    let showsLeft: Bool
    let hidden: Bool
    let onTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    private var isOver: Bool { showsLeft && row.leftAfter < 0 }

    private var leftText: String {
        if hidden {
            return (isOver ? "budgetHistory.status.overPlain" : "budgetHistory.status.within").localized
        }
        return String(
            format: (isOver ? "budgetHistory.status.over.format" : "budgetHistory.status.left.format").localized,
            abs(row.leftAfter).currencyString)
    }

    var body: some View {
        let transaction = row.transaction
        SwiftUI.Button(action: onTap) {
            HStack(spacing: Metrics.spacing3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(showsLeft ? Color(isOver ? Colors.mainRed : Colors.mainGreen) : Color(Colors.gray300))
                    .frame(width: 3, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.title)
                        .font(Font(Fonts.textSM.font))
                        .foregroundStyle(Color(Colors.gray700))
                        .lineLimit(1)
                    Text(Self.dateFormatter.string(from: transaction.date) + " · " + transaction.category.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Colors.gray500))
                        .lineLimit(1)
                }
                Spacer(minLength: Metrics.spacing2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text((-transaction.amount).maskedSignedCurrencyString(hidden: hidden))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(Colors.gray700))
                    if showsLeft {
                        Text(leftText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(isOver ? Colors.mainRed : Colors.mainGreen))
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
            .padding(.horizontal, Metrics.spacing5)
            .padding(.vertical, Metrics.spacing2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private extension Transaction {
    /// A list identity that never collides: the database id, or for an unsaved row its title, date and
    /// amount. Transaction is not Identifiable and its id is optional.
    var historyRowID: String {
        id.map(String.init) ?? "\(title)-\(dateTimestamp)-\(amount)"
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
