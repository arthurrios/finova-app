//
//  BudgetHistoryContentView.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import SwiftUI
import UIKit

/// Everything under the header: filter chips, the selected month's readout, the chart, three
/// insight tiles and the month list. The list repeats the chart as text, so nothing on the chart is
/// reachable only by touch.
struct BudgetHistoryContentView: View {
    @ObservedObject var viewModel: BudgetHistoryViewModel

    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.spacing4) {
                        filterChips
                            .id(Self.topID)
                        chartCard
                        insights
                        monthList(proxy: proxy)
                    }
                    .padding(.vertical, Metrics.spacing4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private static let topID = "budgetHistory.top"

    private var hidden: Bool { viewModel.isValuesHidden }

    private func select(month anchor: Int) {
        guard anchor != viewModel.selectedAnchor else { return }
        selectionFeedback.selectionChanged()
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.select(month: anchor)
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Metrics.spacing2) {
                    ForEach(viewModel.filters, id: \.self) { filter in
                        chip(for: filter).id(filter.id)
                    }
                }
                .padding(.horizontal, Metrics.spacing4)
            }
            .scrollIndicators(.hidden)
            // Opened from a category's details, its chip may sit past the edge.
            .onAppear { proxy.scrollTo(viewModel.filter.id, anchor: .center) }
        }
    }

    private func chip(for filter: BudgetHistoryFilter) -> some View {
        let isSelected = filter == viewModel.filter
        return SwiftUI.Button {
            selectionFeedback.selectionChanged()
            withAnimation(.snappy(duration: 0.3)) { viewModel.select(filter: filter) }
        } label: {
            HStack(spacing: Metrics.spacing1 + 2) {
                chipIcon(for: filter)
                    .frame(width: 14, height: 14)
                Text(BudgetHistoryViewModel.title(for: filter))
                    .font(Font(Fonts.textXS.font))
                    .fontWeight(isSelected ? .bold : .regular)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color(Colors.gray600))
            .padding(.horizontal, Metrics.spacing3)
            .frame(height: 32)
            .background(
                Capsule().fill(isSelected ? Color(Colors.mainMagenta) : Color(Colors.gray100))
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : Color(Colors.gray300), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func chipIcon(for filter: BudgetHistoryFilter) -> some View {
        switch filter {
        case .wholeMonth:
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
        case .category(let category):
            if let icon = UIImage(named: category.iconName) {
                Image(uiImage: icon).resizable().renderingMode(.template).scaledToFit()
            }
        }
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing4) {
            HStack(alignment: .center) {
                Text(BudgetHistoryViewModel.title(for: viewModel.filter))
                    .font(Font(Fonts.title2XS.font))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(Colors.gray500))
                    .lineLimit(1)
                Spacer(minLength: Metrics.spacing3)
                if viewModel.offersLongerRange {
                    rangePicker
                }
            }
            // Holds the row at the picker's height whether or not it shows, so the card does not jump
            // when a chip with less history is chosen.
            .frame(minHeight: 28)

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
                        .foregroundStyle(isSelected ? Color(Colors.gray700) : Color(Colors.gray500))
                        .frame(width: 40, height: 24)
                        .background(
                            Capsule().fill(isSelected ? Color(Colors.gray100) : Color.clear)
                                .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(Colors.gray200)))
    }

    /// The selected month in words and figures. Updates as a finger scrubs the chart - the pattern
    /// the donut's centre readout uses for a selected slice.
    private func readout(for month: BudgetHistoryMonth) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacing1) {
            HStack(spacing: Metrics.spacing2) {
                Text(BudgetHistoryViewModel.longMonth(month.monthAnchor))
                    .font(Font(Fonts.textXS.font))
                    .foregroundStyle(Color(Colors.gray500))
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
        .accessibilityElement(children: .combine)
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

    // MARK: - Month list

    private func monthList(proxy: ScrollViewProxy) -> some View {
        let months = Array(viewModel.series.months.reversed())
        return VStack(alignment: .leading, spacing: 0) {
            Text("budgetHistory.months.header".localized)
                .font(Font(Fonts.title2XS.font))
                .textCase(.uppercase)
                .foregroundStyle(Color(Colors.gray500))
                .padding(.horizontal, Metrics.spacing5)
                .frame(height: 40)

            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                Divider().overlay(Color(Colors.gray300))
                MonthRow(
                    month: month,
                    isSelected: month.monthAnchor == viewModel.selectedMonth?.monthAnchor,
                    hidden: hidden
                ) {
                    select(month: month.monthAnchor)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(Self.topID, anchor: .top)
                    }
                }
            }
        }
        .cardBackground()
        .padding(.horizontal, Metrics.spacing4)
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

private struct MonthRow: View {
    let month: BudgetHistoryMonth
    let isSelected: Bool
    let hidden: Bool
    let onTap: () -> Void

    private var barColor: Color {
        switch month.status {
        case .over: return Color(Colors.mainRed)
        case .noPlan, .empty: return Color(Colors.gray400)
        case .within, .inProgress: return Color(Colors.mainMagenta)
        }
    }

    private var amounts: String {
        let spent = month.spent.maskedCurrencyString(hidden: hidden)
        guard month.hasPlan else { return spent }
        return spent + " / " + month.planned.maskedCurrencyString(hidden: hidden)
    }

    var body: some View {
        SwiftUI.Button(action: onTap) {
            VStack(alignment: .leading, spacing: Metrics.spacing2) {
                HStack(alignment: .center) {
                    Text(BudgetHistoryViewModel.longMonth(month.monthAnchor))
                        .font(Font(isSelected ? Fonts.textSMBold.font : Fonts.textSM.font))
                        .foregroundStyle(Color(Colors.gray700))
                    Spacer(minLength: Metrics.spacing2)
                    StatusPill(month: month, hidden: hidden)
                }
                HStack(spacing: Metrics.spacing3) {
                    GeometryReader { geometry in
                        let fraction = min(month.ratio ?? (month.spent > 0 ? 1 : 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(Colors.gray200))
                            Capsule().fill(barColor.opacity(month.isCurrent ? 0.6 : 1))
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                    Text(amounts)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Colors.gray500))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, Metrics.spacing5)
            .padding(.vertical, Metrics.spacing3)
            .background(isSelected ? Color(Colors.mainMagenta).opacity(0.06) : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(Color(Colors.mainMagenta)).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BudgetHistoryViewModel.longMonth(month.monthAnchor))
        .accessibilityValue(BudgetHistoryViewModel.accessibilityValue(for: month, hidden: hidden))
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
