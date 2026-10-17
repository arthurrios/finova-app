//
//  BudgetHistoryChartView.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import Charts
import SwiftUI
import UIKit

/// One bar per month: what was spent, drawn over what was planned.
///
/// Each column is up to four marks on one x value, all with explicit `yStart`/`yEnd` so Charts does
/// not stack them:
/// - a grey bar to the plan - the room the month had;
/// - a red bar to what was spent, only when the month went over;
/// - a magenta bar to the smaller of spent and plan, drawn over the red one, so the red that is left
///   showing is exactly the overspend;
/// - a dark tick at the plan, so the line the month was measured against stays visible on a bar that
///   ran past it. It also covers the seam where the magenta bar ends inside the red one.
struct BudgetHistoryChartView: View {
    let months: [BudgetHistoryMonth]
    let selectedAnchor: Int?
    let isValuesHidden: Bool
    /// The chart in the allocation details preview: no amount axis, no percent labels and no touch.
    /// The selected month is still named in magenta on the month axis.
    var isCompact: Bool = false
    var onSelect: ((Int) -> Void)?

    @State private var rawSelection: String?
    /// The plot area, captured so a tap can be turned into a column. Columns on a categorical axis are
    /// equal bands, so the column under a finger is plain arithmetic.
    @State private var plotRect: CGRect = .zero

    /// Percent labels over the bars only while they have room. Twelve columns on a phone leave about
    /// 26pt each - narrower than "112%".
    private var showsPercentLabels: Bool { !isCompact && months.count <= 6 }

    private var barRatio: CGFloat { months.count <= 6 ? 0.5 : 0.62 }

    private var maxValue: Int {
        max(months.map { max($0.planned, $0.spent) }.max() ?? 0, 1)
    }

    /// Head room for the percent labels, which are drawn above the tallest bar.
    private var yTop: Double {
        Double(maxValue) * (showsPercentLabels ? 1.2 : 1.06)
    }

    private static func key(_ month: BudgetHistoryMonth) -> String { String(month.monthAnchor) }

    /// A scale label, in `compactCurrencyString`'s own shape - symbol, no space, number - so "R$0" and
    /// "R$15.0k" read as one scale. Below a thousand that function falls back to the full amount with
    /// cents, which only widens the axis: gridlines sit on round numbers anyway.
    private static func axisLabel(_ amountMinor: Int) -> String {
        let code = AppConfig.currencyCode
        let major = Double(amountMinor) / pow(10, Double(CurrencyUtils.fractionDigits(for: code)))
        guard major < 1000 else { return amountMinor.compactCurrencyString }
        return currencySymbol(for: code) + String(Int(major.rounded()))
    }

    private static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    private func select(_ anchor: Int) {
        guard anchor != selectedAnchor else { return }
        onSelect?(anchor)
    }

    /// The month whose column contains `x`, in the chart's own coordinates.
    private func anchor(atX x: CGFloat) -> Int? {
        guard plotRect.width > 0, !months.isEmpty else { return nil }
        let band = plotRect.width / CGFloat(months.count)
        let index = Int(((x - plotRect.minX) / band).rounded(.down))
        guard months.indices.contains(index) else { return nil }
        return months[index].monthAnchor
    }

    private func spentColor(for month: BudgetHistoryMonth) -> Color {
        guard month.hasPlan else { return Color(Colors.gray400) }
        // The open month is lighter: it is still filling, and a full-strength bar reads as final.
        return Color(Colors.mainMagenta).opacity(month.isCurrent ? 0.6 : 1)
    }

    var body: some View {
        Chart {
            ForEach(months) { month in
                let x = Self.key(month)

                if !isCompact && month.monthAnchor == selectedAnchor {
                    RectangleMark(
                        x: .value("Month", x),
                        yStart: .value("Amount", 0),
                        yEnd: .value("Amount", yTop),
                        width: .ratio(0.94)
                    )
                    .foregroundStyle(Color(Colors.gray200))
                    .cornerRadius(8)
                    .accessibilityHidden(true)
                }

                if month.hasPlan {
                    BarMark(
                        x: .value("Month", x),
                        yStart: .value("Amount", 0),
                        yEnd: .value("Amount", month.planned),
                        width: .ratio(barRatio)
                    )
                    .foregroundStyle(Color(Colors.gray300))
                    .cornerRadius(4)
                    .accessibilityHidden(true)
                }

                if month.spentOverPlan > 0 {
                    BarMark(
                        x: .value("Month", x),
                        yStart: .value("Amount", 0),
                        yEnd: .value("Amount", month.spent),
                        width: .ratio(barRatio)
                    )
                    .foregroundStyle(Color(Colors.mainRed))
                    .cornerRadius(4)
                    .accessibilityHidden(true)
                }

                BarMark(
                    x: .value("Month", x),
                    yStart: .value("Amount", 0),
                    yEnd: .value("Amount", month.spentWithinPlan),
                    width: .ratio(barRatio)
                )
                .foregroundStyle(spentColor(for: month))
                .cornerRadius(4)
                .accessibilityLabel(BudgetHistoryViewModel.longMonth(month.monthAnchor))
                .accessibilityValue(
                    BudgetHistoryViewModel.accessibilityValue(for: month, hidden: isValuesHidden))

                if month.hasPlan {
                    RectangleMark(
                        x: .value("Month", x),
                        y: .value("Amount", month.planned),
                        width: .ratio(min(barRatio + 0.16, 0.9)),
                        height: 2
                    )
                    .foregroundStyle(Color(Colors.gray600))
                    .accessibilityHidden(true)
                }

                if showsPercentLabels, let percent = month.percentUsed {
                    PointMark(
                        x: .value("Month", x),
                        y: .value("Amount", max(month.planned, month.spent))
                    )
                    .opacity(0)
                    .annotation(position: .top, spacing: 4) {
                        Text(verbatim: "\(percent)%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                month.status == .over ? Color(Colors.mainRed) : Color(Colors.gray500))
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .chartYScale(domain: 0...yTop)
        .chartXAxis {
            AxisMarks(values: months.map(Self.key)) { value in
                AxisValueLabel {
                    if let key = value.as(String.self), let anchor = Int(key) {
                        let isSelected = anchor == selectedAnchor
                        VStack(spacing: 0) {
                            // Three letters at twelve columns: "Maio" beside "Abr" and "Jun" leaves
                            // no gap between labels.
                            Text(months.count > 6
                                ? String(BudgetHistoryViewModel.shortMonth(anchor).prefix(3))
                                : BudgetHistoryViewModel.shortMonth(anchor))
                                .font(.system(
                                    size: isCompact ? 9 : 11, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(
                                    isSelected ? Color(Colors.mainMagenta) : Color(Colors.gray500))
                            if !isCompact, let year = BudgetHistoryViewModel.yearMark(anchor) {
                                Text(year)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color(Colors.gray400))
                            }
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color(Colors.gray300))
                    AxisValueLabel {
                        // A scale is an amount, so it hides with the rest of them. The gridlines
                        // stay: proportions are not what the user asked to hide.
                        if !isValuesHidden, let amount = value.as(Double.self) {
                            Text(Self.axisLabel(Int(amount)))
                                .font(.system(size: 10))
                                .foregroundStyle(Color(Colors.gray400))
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                // Clear and without a content shape, so it takes no touches of its own.
                Color.clear
                    .onAppear { plotRect = proxy.plotFrame.map { geometry[$0] } ?? .zero }
                    .onChange(of: geometry.size) { _, _ in
                        plotRect = proxy.plotFrame.map { geometry[$0] } ?? .zero
                    }
            }
        }
        // Press-and-drag scrubs across months - Charts' own selection gesture.
        .chartXSelection(value: isCompact ? .constant(nil) : $rawSelection)
        // A plain tap selects too, the way a tap selects a slice on the dashboard donut. Simultaneous,
        // so it neither replaces the scrub nor stops the screen from scrolling.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .local).onEnded { event in
                guard !isCompact, let anchor = anchor(atX: event.location.x) else { return }
                select(anchor)
            }
        )
        // Charts clears its selection when the finger lifts. The screen keeps the last month touched.
        .onChange(of: rawSelection) { _, newValue in
            guard let newValue, let anchor = Int(newValue) else { return }
            select(anchor)
        }
        .animation(.snappy(duration: 0.3), value: months)
    }
}
