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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.spacing4) {
                        // Grouped so a hidden back button leaves no gap above the controls.
                        VStack(alignment: .leading, spacing: Metrics.spacing3) {
                            backButton
                            controls
                        }
                        .id(Self.topID)
                        chartCard
                        savingsCard
                        contributorsCard
                            .id(Self.whyID)
                        insights
                    }
                    .padding(.vertical, Metrics.spacing4)
                }
                .scrollIndicators(.hidden)
                // Drilling in shows the chart of what was opened; going back returns to the card it was
                // opened from.
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                FilterPickerSheet(viewModel: viewModel) { filter in
                    selectionFeedback.selectionChanged()
                    isPickerPresented = false
                    withAnimation(.snappy(duration: 0.3)) { viewModel.choose(filter: filter) }
                }
            }
        }
    }

    private var hidden: Bool { viewModel.isValuesHidden }

    private static let topID = "budgetHistory.top"
    private static let whyID = "budgetHistory.why"
    @State private var scrollTarget: String?

    /// Opens a part of the "Why" card as its own view, remembering where it came from.
    private func drill(into filter: BudgetHistoryFilter) {
        selectionFeedback.selectionChanged()
        withAnimation(.snappy(duration: 0.3)) { viewModel.drill(into: filter) }
        scrollTarget = Self.topID
    }

    /// "‹ Back to Whole month": shown only after drilling in, so the summary is one tap away.
    @ViewBuilder
    private var backButton: some View {
        if let previous = viewModel.filterTrail.last {
            SwiftUI.Button {
                selectionFeedback.selectionChanged()
                withAnimation(.snappy(duration: 0.3)) { viewModel.goBack() }
                scrollTarget = Self.whyID
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(format: "budgetHistory.back.format".localized,
                        BudgetHistoryViewModel.title(for: previous)))
                        .font(Font(Fonts.textSMBold.font))
                }
                .foregroundStyle(Color(Colors.mainMagenta))
                .padding(.horizontal, Metrics.spacing3)
                .frame(height: 32)
                .background(Capsule().fill(Color(Colors.mainMagenta).opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Metrics.spacing4)
        }
    }

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
        SectionCard(title: "budgetHistory.section.chart".localized) {
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
        }
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

            // Names the big number, which otherwise reads as a total of something unknown.
            Text(spentLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(Colors.gray500))
                .padding(.top, Metrics.spacing1)
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spentLabel: String {
        switch viewModel.filter {
        case .wholeMonth: return "budgetHistory.readout.spent.whole".localized
        case .category(let category):
            return String(format: "budgetHistory.readout.spent.category.format".localized, category.displayName)
        case .outsideAllocations: return "budgetHistory.readout.spent.outside".localized
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
        guard month.hasPlan else {
            // Outside allocations has no plan when the categories took the whole budget - say so, with
            // by how much, instead of a bare "nothing planned".
            if viewModel.filter == .outsideAllocations {
                let split = viewModel.budgetSplit(month.monthAnchor)
                if split.budget == 0 { return "budgetHistory.readout.noBudget".localized }
                let over = split.inCategories - split.budget
                return over > 0 && !hidden
                    ? String(format: "budgetHistory.readout.categoriesOver.format".localized, over.currencyString)
                    : "budgetHistory.readout.categoriesFull".localized
            }
            return "budgetHistory.hero.noPlan".localized
        }
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

        return SectionCard(title: "budgetHistory.section.insights".localized) {
            HStack(spacing: 0) {
            InsightTile(
                icon: "checkmark.seal.fill",
                tint: Color(Colors.mainGreen),
                title: "budgetHistory.insight.onPlan.title".localized,
                value: onPlanValue,
                caption: "budgetHistory.insight.onPlan.caption".localized)
            VerticalSeparator()
            InsightTile(
                icon: "arrow.left.and.right",
                tint: Color(Colors.mainMagenta),
                title: "budgetHistory.insight.range.title".localized,
                value: rangeValue,
                caption: "budgetHistory.insight.range.caption".localized)
            VerticalSeparator()
            InsightTile(
                icon: "flame.fill",
                tint: streak > 0 ? Color(Colors.warningAmber) : Color(Colors.gray400),
                title: "budgetHistory.insight.streak.title".localized,
                value: streakValue,
                caption: "budgetHistory.insight.streak.caption".localized)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Metrics.spacing4)
    }

    // MARK: - Savings

    /// What the chosen filter saved in closed months, from a start month the user picks.
    private var savingsCard: some View {
        let savings = viewModel.savings
        return SectionCard(title: "budgetHistory.savings.title".localized, accessory: { savingsStartMenu }) {
          VStack(alignment: .leading, spacing: Metrics.spacing2) {
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
          }
          .padding(Metrics.spacing5)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    /// A short name that fits one row, and the detail for the grey line under it - the transaction
    /// rows' title-and-subtitle shape, so a long reason never gets cut.
    private func differenceLabel(_ difference: BudgetHistory.OutsideDifference) -> (title: String, subtitle: String) {
        let months = BudgetHistoryViewModel.monthList(difference.months)
        switch difference.reason {
        case .categoriesAboveBudget:
            return ("budgetHistory.outside.diff.aboveBudget.title".localized,
                    String(format: "budgetHistory.outside.diff.aboveBudget.format".localized, months))
        case .spentOutsideWithNoRoom:
            return ("budgetHistory.outside.diff.spentNoRoom.title".localized,
                    String(format: "budgetHistory.outside.diff.spentNoRoom.format".localized, months))
        case .noMonthBudget:
            return ("budgetHistory.outside.diff.noBudget.title".localized,
                    String(format: "budgetHistory.outside.diff.noBudget.format".localized, months))
        case .otherMonth:
            return ("budgetHistory.outside.diff.otherMonth.title".localized,
                    "budgetHistory.outside.timing".localized)
        }
    }

    // MARK: - What made Saved

    @State private var expandedPart: SavingsContributors.Part?
    @State private var showsOthers = false

    /// What made the Saved figure: the few parts that moved it most, then everything else in one line,
    /// then the total - which is the Saved figure. Categories for the whole month, months otherwise.
    @ViewBuilder
    private var contributorsCard: some View {
        if let contributors = viewModel.contributors {
            SectionCard(
                title: hidden
                    ? "budgetHistory.explain.header.hidden".localized
                    : String(format: "budgetHistory.explain.header.format".localized,
                        contributors.total.maskedSignedCurrencyString(hidden: false))
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    if !contributors.savers.isEmpty {
                        GroupLabel(text: "budgetHistory.contrib.saved".localized, tint: Colors.mainGreen)
                        ForEach(contributors.savers, id: \.part) { item in
                            Separator()
                            contributorRow(item)
                        }
                    }
                    if !contributors.overspenders.isEmpty {
                        if !contributors.savers.isEmpty { Separator() }
                        GroupLabel(text: "budgetHistory.contrib.over".localized, tint: Colors.mainRed)
                        ForEach(contributors.overspenders, id: \.part) { item in
                            Separator()
                            contributorRow(item)
                        }
                    }
                    if contributors.othersCount > 0 {
                        Separator()
                        // Opens to the parts it sums, biggest effect first, so nothing stays hidden.
                        ContributorRow(
                            icon: Image(systemName: "ellipsis"),
                            title: String(format: "budgetHistory.contrib.others.format".localized,
                                contributors.othersCount),
                            amount: contributors.others.maskedSignedCurrencyString(hidden: hidden),
                            // Coloured by direction like every named line, so it is clear which way
                            // the remainder moved Saved.
                            tint: hidden ? Colors.gray700
                                : (contributors.others >= 0 ? Colors.mainGreen : Colors.mainRed),
                            accessory: showsOthers ? "chevron.up" : "chevron.down"
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) { showsOthers.toggle() }
                        }
                        if showsOthers {
                            ForEach(contributors.rest, id: \.part) { item in
                                Separator()
                                contributorRow(item)
                            }
                        }
                    }
                    CardFooter(
                        label: "budgetHistory.contrib.total".localized,
                        caption: contributors.firstMonth.flatMap { first in
                            contributors.lastMonth.map { BudgetHistoryViewModel.periodTitle(first, $0) }
                        },
                        value: contributors.total.maskedSignedCurrencyString(hidden: hidden),
                        tint: hidden ? nil : (contributors.total >= 0 ? Colors.mainGreen : Colors.mainRed))
                }
            }
            .padding(.horizontal, Metrics.spacing4)
            .onChange(of: viewModel.filter) { _, _ in
                expandedPart = nil
                showsOthers = false
            }
        }
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
                drill(into: .category(category))
            }
        case .outsideAllocations:
            ContributorRow(icon: FilterIcon(filter: .outsideAllocations),
                title: "budgetHistory.outside.title".localized, amount: amount,
                tint: hidden ? Colors.gray700 : tint, accessory: "chevron.right") {
                selectionFeedback.selectionChanged()
                drill(into: .outsideAllocations)
            }
        case .difference(let reason):
            let isOpen = expandedPart == item.part
            let difference = viewModel.outsideDifferences.first { $0.reason == reason }
            ContributorRow(icon: Image(systemName: "square.dashed"),
                title: difference.map { differenceLabel($0).title } ?? "",
                subtitle: difference.map { differenceLabel($0).subtitle }, amount: amount,
                tint: hidden ? Colors.gray700 : tint, accessory: isOpen ? "chevron.up" : "chevron.down") {
                withAnimation(.easeInOut(duration: 0.2)) { expandedPart = isOpen ? nil : item.part }
            }
            if isOpen, let difference {
                differenceDetail(difference)
            }
        case .month(let anchor):
            let isOpen = expandedPart == item.part
            ContributorRow(icon: Image(systemName: "calendar"),
                title: BudgetHistoryViewModel.longMonth(anchor), amount: amount,
                tint: hidden ? Colors.gray700 : tint, accessory: isOpen ? "chevron.up" : "chevron.down") {
                withAnimation(.easeInOut(duration: 0.2)) { expandedPart = isOpen ? nil : item.part }
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
                        note("budgetHistory.explain.outside.unspent".localized)
                    }
                }
                .modifier(DetailBand())

                if !detail.biggest.isEmpty {
                    Separator()
                    GroupLabel(text: "budgetHistory.contrib.topExpenses".localized, tint: Colors.gray500)
                    ForEach(Array(detail.biggest.enumerated()), id: \.offset) { _, transaction in
                        Separator()
                        ExpenseRow(transaction: transaction, hidden: hidden) {
                            viewModel.onOpenTransaction?(transaction)
                        }
                    }
                }
            }
        }
    }

    /// What a named difference is made of: the subtraction for months whose categories took the budget,
    /// the very expenses for spending outside categories, a sentence for month timing.
    @ViewBuilder
    private func differenceDetail(_ difference: BudgetHistory.OutsideDifference) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch difference.reason {
            case .categoriesAboveBudget, .noMonthBudget:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(difference.months, id: \.self) { anchor in
                        let split = viewModel.budgetSplit(anchor)
                        detailLine(BudgetHistoryViewModel.longMonth(anchor), "", bold: true)
                        detailLine("budgetHistory.explain.plan.wholeMonth".localized,
                            split.budget.maskedCurrencyString(hidden: hidden))
                        detailLine("budgetHistory.explain.inCategories".localized,
                            (-split.inCategories).maskedSignedCurrencyString(hidden: hidden))
                        detailLine("=", (split.budget - split.inCategories).maskedSignedCurrencyString(hidden: hidden),
                            tint: hidden ? nil : Colors.mainRed, bold: true)
                    }
                    note("budgetHistory.diff.note.aboveBudget".localized)
                }
                .modifier(DetailBand())
            case .spentOutsideWithNoRoom:
                VStack(alignment: .leading, spacing: 0) {
                    note("budgetHistory.diff.note.spentNoRoom".localized)
                }
                .modifier(DetailBand())
                ForEach(Array(viewModel.outsideExpenses(in: difference.months).enumerated()), id: \.offset) {
                    _, transaction in
                    Separator()
                    ExpenseRow(transaction: transaction, hidden: hidden) {
                        viewModel.onOpenTransaction?(transaction)
                    }
                }
            case .otherMonth:
                VStack(alignment: .leading, spacing: 0) {
                    note("budgetHistory.diff.note.otherMonth".localized)
                }
                .modifier(DetailBand())
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Font(Fonts.textXS.font))
            .foregroundStyle(Color(Colors.gray500))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Metrics.spacing1)
    }

    private func detailLine(_ label: String, _ value: String, tint: UIColor? = nil, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(Font(bold ? Fonts.textSMBold.font : Fonts.textSM.font))
                .foregroundStyle(Color(Colors.gray700))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Metrics.spacing2)
            Text(value)
                .font(Font(bold ? Fonts.textSMBold.font : Fonts.textSM.font))
                .foregroundStyle(Color(tint ?? Colors.gray600))
                .fixedSize()
        }
        .padding(.vertical, Metrics.spacing1)
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
        .padding(.horizontal, Metrics.spacing4)
        .padding(.vertical, Metrics.spacing3)
        .accessibilityElement(children: .combine)
    }
}

/// One named contributor: an icon, a name, and how much it saved (green) or overspent (red).
private struct ContributorRow<Icon: View>: View {
    /// The transaction list's row height, so these rows read as the same kind of table.
    static var rowHeight: CGFloat { 60 }

    let icon: Icon
    let title: String
    var subtitle: String? = nil
    let amount: String
    let tint: UIColor
    let accessory: String
    let onTap: () -> Void

    var body: some View {
        SwiftUI.Button(action: onTap) {
            HStack(spacing: Metrics.spacing3) {
                IconBox { icon }
                VStack(alignment: .leading, spacing: Metrics.spacing1) {
                    Text(title)
                        .font(Font(Fonts.textSMBold.font))
                        .foregroundStyle(Color(Colors.gray700))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(Font(Fonts.textXS.font))
                            .foregroundStyle(Color(Colors.gray500))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: Metrics.spacing2)
                Text(amount)
                    .font(Font(Fonts.textSMBold.font))
                    .foregroundStyle(Color(tint))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: accessory)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(Colors.gray400))
            }
            .padding(.horizontal, Metrics.spacing5)
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A card in the app's table style: the `CardHeader` band - 44pt, small uppercase grey title, optional
/// count badge - over a body, all inside one bordered card with a separator under the header.
private struct SectionCard<Accessory: View, Content: View>: View {
    let title: String
    var count: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metrics.spacing2) {
                Text(title)
                    .font(Font(Fonts.title2XS.font))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(Colors.gray500))
                    .lineLimit(1)
                Spacer(minLength: Metrics.spacing2)
                if let count {
                    Text(count)
                        .font(Font(Fonts.titleXS.font))
                        .foregroundStyle(Color(Colors.gray600))
                        .padding(.horizontal, Metrics.spacing2)
                        .frame(height: 18)
                        .background(Capsule().fill(Color(Colors.gray300)))
                }
                accessory()
            }
            .padding(.leading, Metrics.spacing5)
            .padding(.trailing, Metrics.spacing4)
            .frame(height: Metrics.cardHeaderHeight)
            Separator()
            content()
        }
        .cardBackground()
    }
}

extension SectionCard where Accessory == EmptyView {
    init(title: String, count: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, count: count, accessory: { EmptyView() }, content: content)
    }
}

/// The app's table separator: full width, 1pt, gray300.
private struct Separator: View {
    var body: some View {
        Rectangle().fill(Color(Colors.gray300)).frame(height: 1)
    }
}

private struct VerticalSeparator: View {
    var body: some View {
        Rectangle().fill(Color(Colors.gray300)).frame(width: 1)
    }
}

/// The transaction cell's icon container: 32pt, gray200, gray300 border, magenta glyph.
private struct IconBox<Icon: View>: View {
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        icon()
            .frame(width: 16, height: 16)
            .foregroundStyle(Color(Colors.mainMagenta))
            .frame(width: Metrics.spacing8, height: Metrics.spacing8)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium).fill(Color(Colors.gray200)))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium).stroke(Color(Colors.gray300), lineWidth: 1))
    }
}

/// The tinted band an opened row shows its arithmetic in, indented to the row title.
private struct DetailBand: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, Metrics.spacing5 + Metrics.spacing8 + Metrics.spacing3)
            .padding(.trailing, Metrics.spacing5)
            .padding(.vertical, Metrics.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(Colors.gray200).opacity(0.5))
    }
}

/// One expense in the transaction cell's style: category icon box, bold title, date and category,
/// bold amount. A tap opens its details.
private struct ExpenseRow: View {
    let transaction: Transaction
    let hidden: Bool
    let onTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    var body: some View {
        SwiftUI.Button(action: onTap) {
            HStack(spacing: Metrics.spacing3) {
                IconBox {
                    if let icon = UIImage(named: transaction.category.iconName(for: transaction.type)) {
                        Image(uiImage: icon).resizable().renderingMode(.template).scaledToFit()
                    }
                }
                VStack(alignment: .leading, spacing: Metrics.spacing1) {
                    Text(transaction.title)
                        .font(Font(Fonts.textSMBold.font))
                        .foregroundStyle(Color(Colors.gray700))
                        .lineLimit(1)
                    Text(Self.dateFormatter.string(from: transaction.date) + " · " + transaction.category.displayName)
                        .font(Font(Fonts.textXS.font))
                        .foregroundStyle(Color(Colors.gray500))
                        .lineLimit(1)
                }
                Spacer(minLength: Metrics.spacing2)
                Text((-transaction.amount).maskedSignedCurrencyString(hidden: hidden))
                    .font(Font(Fonts.textSMBold.font))
                    .foregroundStyle(Color(Colors.gray700))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(Colors.gray400))
            }
            .padding(.horizontal, Metrics.spacing5)
            .frame(minHeight: ContributorRow<EmptyView>.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A small band naming a group of rows, like a table section header.
private struct GroupLabel: View {
    let text: String
    let tint: UIColor

    var body: some View {
        Text(text)
            .font(Font(Fonts.title2XS.font))
            .textCase(.uppercase)
            .foregroundStyle(Color(tint))
            .padding(.horizontal, Metrics.spacing5)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(Color(Colors.gray200).opacity(0.5))
    }
}

/// The card's closing total, set off from the rows above like the details screens' footer.
private struct CardFooter: View {
    let label: String
    var caption: String? = nil
    let value: String
    var tint: UIColor? = nil

    var body: some View {
        VStack(spacing: 0) {
            Separator()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Font(Fonts.textSMBold.font))
                        .foregroundStyle(Color(Colors.gray700))
                    if let caption {
                        Text(caption)
                            .font(Font(Fonts.textXS.font))
                            .foregroundStyle(Color(Colors.gray500))
                    }
                }
                Spacer(minLength: Metrics.spacing2)
                Text(value)
                    .font(Font(Fonts.textSMBold.font))
                    .foregroundStyle(Color(tint ?? Colors.gray700))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Metrics.spacing5)
            .frame(minHeight: ContributorRow<EmptyView>.rowHeight)
            .background(Color(Colors.gray200).opacity(0.5))
            .accessibilityElement(children: .combine)
        }
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
                    Separator()
                    ForEach(viewModel.filters, id: \.self) { filter in
                        row(for: filter)
                        Separator()
                    }
                    if let outside = viewModel.outsideAllocations {
                        outsideRow(outside)
                        Separator()
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
                IconBox { FilterIcon(filter: .outsideAllocations) }
                VStack(alignment: .leading, spacing: Metrics.spacing1) {
                    Text("budgetHistory.outside.title".localized)
                        .font(Font(Fonts.textSMBold.font))
                        .foregroundStyle(Color(Colors.gray700))
                    Text("budgetHistory.outside.caption".localized)
                        .font(Font(Fonts.textXS.font))
                        .foregroundStyle(Color(Colors.gray500))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.spacing2)
                Text(amount.maskedSignedCurrencyString(hidden: hidden))
                    .font(Font(Fonts.textSMBold.font))
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
            .frame(minHeight: ContributorRow<EmptyView>.rowHeight)
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
                IconBox { FilterIcon(filter: filter) }
                Text(BudgetHistoryViewModel.title(for: filter))
                    .font(Font(Fonts.textSMBold.font))
                    .foregroundStyle(Color(Colors.gray700))
                    .lineLimit(1)
                Spacer(minLength: Metrics.spacing2)
                Text(savings.months == 0
                    ? "budgetHistory.insight.none".localized
                    : savings.net.maskedSignedCurrencyString(hidden: hidden))
                    .font(Font(Fonts.textSMBold.font))
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
            .frame(minHeight: ContributorRow<EmptyView>.rowHeight)
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
