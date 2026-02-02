//
//  BudgetDonutChartView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import SwiftUI
import Charts
import UIKit

@available(iOS 17.0, *)
struct BudgetDonutChartView: View {
    let allocations: [BudgetAllocation]
    let unallocatedAmount: Int
    var onSegmentTapped: ((TransactionCategory) -> Void)?

    @State private var rawSelectedValue: Int?
    @State private var selectedIndex: Int?

    // Minimum percentage a sector should occupy for visibility/tappability
    private let minimumSectorPercent: Double = 0.05 // 5% minimum

    private var totalAmount: Int {
        allocations.reduce(0) { $0 + $1.allocatedAmount } + unallocatedAmount
    }

    /// Adjusted values that ensure minimum sector size for tappability
    private var adjustedAllocations: [(allocation: BudgetAllocation, displayValue: Int)] {
        guard totalAmount > 0 else { return allocations.map { ($0, $0.allocatedAmount) } }

        let minValue = Int(Double(totalAmount) * minimumSectorPercent)

        return allocations.map { allocation in
            let adjustedValue = max(allocation.allocatedAmount, minValue)
            return (allocation, adjustedValue)
        }
    }

    private var adjustedUnallocated: Int {
        guard totalAmount > 0, unallocatedAmount > 0 else { return unallocatedAmount }
        let minValue = Int(Double(totalAmount) * minimumSectorPercent)
        return max(unallocatedAmount, minValue)
    }

    private var adjustedTotal: Int {
        adjustedAllocations.reduce(0) { $0 + $1.displayValue } + (unallocatedAmount > 0 ? adjustedUnallocated : 0)
    }

    private func findSelectedIndex(for value: Int) -> Int? {
        var cumulative = 0
        for (index, item) in adjustedAllocations.enumerated() {
            cumulative += item.displayValue
            if value <= cumulative {
                return index
            }
        }
        // Check if it's the unallocated section
        if unallocatedAmount > 0 && value <= cumulative + adjustedUnallocated {
            return -1 // -1 represents unallocated
        }
        return nil
    }

    /// Maximum allocated amount among all allocations (for relative brightness calculation)
    private var maxAllocatedAmount: Int {
        allocations.map { $0.allocatedAmount }.max() ?? 1
    }

    /// Creates a color based on relative size - bigger portions are brighter, smaller are darker
    /// - Parameter allocation: The budget allocation
    /// - Returns: Magenta color with brightness based on relative size
    private func colorForAllocation(_ allocation: BudgetAllocation) -> Color {
        // Calculate relative size (0 to 1) compared to the largest allocation
        let relativeSize = Double(allocation.allocatedAmount) / Double(maxAllocatedAmount)

        // Brightness: 0.35 (dark) to 1.0 (bright) - bigger = brighter
        let minBrightness: CGFloat = 0.35
        let maxBrightness: CGFloat = 1.0
        let brightness = minBrightness + (maxBrightness - minBrightness) * CGFloat(relativeSize)

        // Get magenta's HSB values and adjust brightness
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var baseBrightness: CGFloat = 0
        var alpha: CGFloat = 0

        Colors.mainMagenta.getHue(&hue, saturation: &saturation, brightness: &baseBrightness, alpha: &alpha)

        // Create new color with adjusted brightness, full opacity
        let adjustedColor = UIColor(hue: hue, saturation: saturation, brightness: baseBrightness * brightness, alpha: 1.0)
        return Color(adjustedColor)
    }

    /// Formats currency with ultra-compact notation for chart center
    private func compactCurrency(_ amount: Int) -> String {
        let absAmount = abs(amount)
        let prefix = amount < 0 ? "-" : ""

        if absAmount >= 1_000_000_00 { // 1 million (in cents)
            let millions = Double(absAmount) / 1_000_000_00
            if millions >= 10 {
                return "\(prefix)R$\(String(format: "%.0f", millions))mi"
            }
            return "\(prefix)R$\(String(format: "%.1f", millions))mi"
        } else if absAmount >= 100_000_00 { // 100k+ (in cents)
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$\(String(format: "%.0f", thousands))k"
        } else if absAmount >= 10_000_00 { // 10k+ (in cents)
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$\(String(format: "%.1f", thousands))k"
        } else if absAmount >= 1_000_00 { // 1k+ (in cents)
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$\(String(format: "%.1f", thousands))k"
        } else {
            // For smaller values, show without cents
            let reais = absAmount / 100
            return "\(prefix)R$\(reais)"
        }
    }

    var body: some View {
        Chart {
            ForEach(Array(adjustedAllocations.enumerated()), id: \.1.allocation.id) { (index: Int, item: (allocation: BudgetAllocation, displayValue: Int)) in
                SectorMark(
                    angle: .value("Amount", item.displayValue),
                    innerRadius: .ratio(0.65),
                    angularInset: 2
                )
                .foregroundStyle(colorForAllocation(item.allocation))
                .cornerRadius(4)
                .opacity(selectedIndex == nil || selectedIndex == index ? 1.0 : 0.35)
            }

            if unallocatedAmount > 0 {
                SectorMark(
                    angle: .value("Unallocated", adjustedUnallocated),
                    innerRadius: .ratio(0.65),
                    angularInset: 2
                )
                .foregroundStyle(Color(Colors.gray600))
                .cornerRadius(4)
                .opacity(selectedIndex == nil ? 0.5 : (selectedIndex == -1 ? 1.0 : 0.35))
            }
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $rawSelectedValue)
        .chartBackground { _ in
            GeometryReader { geometry in
                let frame = geometry.frame(in: .local)
                let centerSize = frame.width * 0.5 // 50% of chart width for center content
                VStack(spacing: 2) {
                    if let index = selectedIndex, index >= 0, index < allocations.count {
                        let allocation = allocations[index]
                        if let icon = UIImage(named: allocation.category.iconName) {
                            Image(uiImage: icon)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(colorForAllocation(allocation))
                                .frame(width: 24, height: 24)
                        }
                        Text(allocation.category.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(Colors.gray300))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(compactCurrency(allocation.allocatedAmount))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else if selectedIndex == -1 {
                        // Unallocated selected
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(Color(Colors.gray400))
                        Text("budget.unallocated".localized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(Colors.gray300))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(compactCurrency(unallocatedAmount))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        // Show total
                        Text(compactCurrency(totalAmount))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("chart.total.label".localized)
                            .font(.system(size: 11))
                            .foregroundColor(Color(Colors.gray400))
                    }
                }
                .frame(width: centerSize, height: centerSize)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .onChange(of: rawSelectedValue) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                if let value = newValue {
                    selectedIndex = findSelectedIndex(for: value)
                    if let index = selectedIndex, index >= 0, index < allocations.count {
                        onSegmentTapped?(allocations[index].category)
                    }
                } else {
                    selectedIndex = nil
                }
            }
        }
    }
}
