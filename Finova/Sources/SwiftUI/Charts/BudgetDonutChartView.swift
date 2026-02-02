//
//  BudgetDonutChartView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import SwiftUI
import Charts

@available(iOS 17.0, *)
struct BudgetDonutChartView: View {
    let allocations: [BudgetAllocation]
    let unallocatedAmount: Int
    var onSegmentTapped: ((TransactionCategory) -> Void)?

    @State private var rawSelectedValue: Int?
    @State private var selectedIndex: Int?

    private var totalAmount: Int {
        allocations.reduce(0) { $0 + $1.allocatedAmount } + unallocatedAmount
    }

    private func findSelectedIndex(for value: Int) -> Int? {
        var cumulative = 0
        for (index, allocation) in allocations.enumerated() {
            cumulative += allocation.allocatedAmount
            if value <= cumulative {
                return index
            }
        }
        // Check if it's the unallocated section
        if unallocatedAmount > 0 && value <= cumulative + unallocatedAmount {
            return -1 // -1 represents unallocated
        }
        return nil
    }

    /// Formats currency with compact notation for large values (e.g., R$ 1,5 mi)
    private func compactCurrency(_ amount: Int) -> String {
        let absAmount = abs(amount)
        let prefix = amount < 0 ? "-" : ""

        if absAmount >= 1_000_000_00 { // 1 million (in cents)
            let millions = Double(absAmount) / 1_000_000_00
            return "\(prefix)R$ \(String(format: "%.1f", millions)) mi"
        } else if absAmount >= 100_000_00 { // 100k+ (in cents)
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$ \(String(format: "%.0f", thousands)) mil"
        } else {
            return amount.currencyString
        }
    }

    var body: some View {
        Chart {
            ForEach(Array(allocations.enumerated()), id: \.element.id) { index, allocation in
                SectorMark(
                    angle: .value("Amount", allocation.allocatedAmount),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(Color(allocation.category.color))
                .cornerRadius(4)
                .opacity(selectedIndex == nil || selectedIndex == index ? 1.0 : 0.35)
            }

            if unallocatedAmount > 0 {
                SectorMark(
                    angle: .value("Unallocated", unallocatedAmount),
                    innerRadius: .ratio(0.7),
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
                let centerSize = frame.width * 0.6 // 60% of chart width for center content
                VStack(spacing: 4) {
                    if let index = selectedIndex, index >= 0, index < allocations.count {
                        let allocation = allocations[index]
                        if let icon = UIImage(named: allocation.category.iconName) {
                            Image(uiImage: icon)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(Color(allocation.category.color))
                                .frame(width: 28, height: 28)
                        }
                        Text(allocation.category.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(Colors.gray300))
                            .lineLimit(1)
                        Text(compactCurrency(allocation.allocatedAmount))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    } else if selectedIndex == -1 {
                        // Unallocated selected
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(Color(Colors.gray400))
                        Text("budget.unallocated".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(Colors.gray300))
                            .lineLimit(1)
                        Text(compactCurrency(unallocatedAmount))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    } else {
                        // Show total
                        Text(compactCurrency(totalAmount))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(Colors.gray100))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("chart.total.label".localized)
                            .font(.system(size: 12))
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
