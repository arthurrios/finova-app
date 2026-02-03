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
    let unallocatedSpending: [UnallocatedCategorySpending]
    var onSegmentTapped: ((TransactionCategory) -> Void)?
    var onUnallocatedSpendingTapped: ((UnallocatedCategorySpending) -> Void)?

    @State private var rawSelectedValue: Int?
    @State private var selectedIndex: Int?

    /// Sum of all allocation amounts
    private var allocatedTotal: Int {
        allocations.reduce(0) { $0 + $1.allocatedAmount }
    }

    /// Sum of all unallocated spending amounts
    private var unallocatedSpendingTotal: Int {
        unallocatedSpending.reduce(0) { $0 + $1.spentAmount }
    }

    /// Effective unallocated amount (never negative for display purposes)
    private var effectiveUnallocatedAmount: Int {
        max(0, unallocatedAmount)
    }

    /// Total amount for chart display (includes unallocated spending)
    private var totalAmount: Int {
        allocatedTotal + effectiveUnallocatedAmount + unallocatedSpendingTotal
    }

    private var hasAllocations: Bool {
        !allocations.isEmpty
    }

    private var allocatedPercentage: Int {
        guard totalAmount > 0 else { return 0 }
        return Int((Double(allocatedTotal) / Double(totalAmount)) * 100)
    }

    private func findSelectedIndex(for value: Int) -> Int? {
        var cumulative = 0

        // Check allocations first
        for (index, allocation) in allocations.enumerated() {
            cumulative += allocation.allocatedAmount
            if value <= cumulative {
                return index
            }
        }

        // Check unallocated spending segments
        // Index will be: allocations.count + spending index
        for (index, spending) in unallocatedSpending.enumerated() {
            cumulative += spending.spentAmount
            if value <= cumulative {
                return allocations.count + index // Offset by allocations count
            }
        }

        // Check if it's the remaining unallocated section
        if effectiveUnallocatedAmount > 0 && value <= cumulative + effectiveUnallocatedAmount {
            return -1 // -1 represents remaining unallocated budget
        }
        return nil
    }

    /// Check if index is an unallocated spending index
    private func isUnallocatedSpendingIndex(_ index: Int) -> Bool {
        return index >= allocations.count && index < allocations.count + unallocatedSpending.count
    }

    /// Get unallocated spending for a given index
    private func getUnallocatedSpending(for index: Int) -> UnallocatedCategorySpending? {
        let spendingIndex = index - allocations.count
        guard spendingIndex >= 0 && spendingIndex < unallocatedSpending.count else { return nil }
        return unallocatedSpending[spendingIndex]
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

    /// Check if we have any content to display
    private var hasContent: Bool {
        !allocations.isEmpty || !unallocatedSpending.isEmpty
    }

    var body: some View {
        Chart {
            if hasContent {
                // Allocated categories (magenta shades)
                ForEach(Array(allocations.enumerated()), id: \.1.id) { (index: Int, allocation: BudgetAllocation) in
                    SectorMark(
                        angle: .value("Amount", allocation.allocatedAmount),
                        innerRadius: .ratio(0.65),
                        angularInset: 2
                    )
                    .foregroundStyle(colorForAllocation(allocation))
                    .cornerRadius(4)
                    .opacity(selectedIndex == nil || selectedIndex == index ? 1.0 : 0.35)
                }

                // Unallocated spending categories (slightly brighter gray)
                ForEach(Array(unallocatedSpending.enumerated()), id: \.1.category.key) { (index: Int, spending: UnallocatedCategorySpending) in
                    let chartIndex = allocations.count + index
                    SectorMark(
                        angle: .value("Unallocated Spending", spending.spentAmount),
                        innerRadius: .ratio(0.65),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(Colors.gray500)) // Brighter than unallocated budget
                    .cornerRadius(4)
                    .opacity(selectedIndex == nil || selectedIndex == chartIndex ? 0.8 : 0.35)
                }

                // Remaining unallocated budget (darkest gray)
                if effectiveUnallocatedAmount > 0 {
                    SectorMark(
                        angle: .value("Unallocated", effectiveUnallocatedAmount),
                        innerRadius: .ratio(0.65),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(Colors.gray600))
                    .cornerRadius(4)
                    .opacity(selectedIndex == nil ? 0.5 : (selectedIndex == -1 ? 1.0 : 0.35))
                }
            } else {
                // No allocations or spending - show full gray circle
                SectorMark(
                    angle: .value("Empty", 1),
                    innerRadius: .ratio(0.65)
                )
                .foregroundStyle(Color(Colors.gray600))
                .opacity(0.5)
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
                        // Allocated category selected
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
                    } else if let index = selectedIndex, let spending = getUnallocatedSpending(for: index) {
                        // Unallocated spending category selected
                        if let icon = UIImage(named: spending.category.iconName(for: .expense)) {
                            Image(uiImage: icon)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(Color(Colors.gray400))
                                .frame(width: 24, height: 24)
                        }
                        Text(spending.category.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(Colors.gray300))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(compactCurrency(spending.spentAmount))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else if selectedIndex == -1 {
                        // Remaining unallocated budget selected
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(Color(Colors.gray400))
                        Text("budget.unallocated".localized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(Colors.gray300))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(compactCurrency(effectiveUnallocatedAmount))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else if !hasContent {
                        // No allocations or spending - show 0% allocated
                        Text("0%")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(Colors.gray400))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("budget.allocated.label".localized)
                            .font(.system(size: 11))
                            .foregroundColor(Color(Colors.gray500))
                    } else {
                        // Show total
                        Text(compactCurrency(totalAmount))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("budget.total.label".localized)
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
                    if let index = selectedIndex {
                        if index >= 0 && index < allocations.count {
                            // Allocated category tapped
                            onSegmentTapped?(allocations[index].category)
                        } else if let spending = getUnallocatedSpending(for: index) {
                            // Unallocated spending category tapped
                            onUnallocatedSpendingTapped?(spending)
                        }
                    }
                } else {
                    selectedIndex = nil
                }
            }
        }
    }
}
