//
//  BudgetDonutChartView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import Charts
import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct BudgetDonutChartView: View {
    let allocations: [BudgetAllocation]
    let totalBudget: Int
    let unallocatedAmount: Int
    let unallocatedSpending: [UnallocatedCategorySpending]
    /// Slice order and, when tags exist, the inner ring. Always built by the caller from the same
    /// values as the properties above, so it is never out of step with them.
    var breakdown: AllocationTagBreakdown = .empty
    var isValuesHidden: Bool = false
    var onSegmentTapped: ((TransactionCategory) -> Void)?
    var onUnallocatedSpendingTapped: ((UnallocatedCategorySpending) -> Void)?

    @State private var rawSelectedValue: Int?
    /// The selected slice's `AllocationTagBreakdown.Segment.id`, or nil.
    ///
    /// Replaced the old integer index, which walked `allocations` in array order and used -1 as a
    /// sentinel for the headroom slice. Once slices are drawn in tag-grouped order rather than array
    /// order, an index into `allocations` no longer identifies the slice under the finger.
    @State private var selectedSegmentID: String?

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

    /// Check if we have any content to display
    private var hasContent: Bool {
        !allocations.isEmpty || !unallocatedSpending.isEmpty
    }

    /// Whether the inner tag ring is drawn. When false every radius and colour below is exactly what
    /// the card rendered before tags existed.
    private var hasTags: Bool { breakdown.hasTags }

    // MARK: - Lookups

    private var allocationsByCategoryKey: [String: BudgetAllocation] {
        Dictionary(allocations.map { ($0.category.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var spendingByCategoryKey: [String: UnallocatedCategorySpending] {
        Dictionary(
            unallocatedSpending.map { ($0.category.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The slices to draw, in draw order.
    ///
    /// Falls back to the pre-tag order when no breakdown was supplied, so a caller that passes none -
    /// the layout tests, and any code path not yet updated - renders exactly as before.
    private var segments: [AllocationTagBreakdown.Segment] {
        if !breakdown.segments.isEmpty { return breakdown.segments }
        return AllocationTagBreakdown(
            allocations: allocations,
            unallocatedSpending: unallocatedSpending,
            unallocatedHeadroom: unallocatedAmount,
            totalBudget: totalBudget,
            tags: [],
            categoryTagIds: [:]
        ).segments
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

    private func color(for segment: AllocationTagBreakdown.Segment) -> Color {
        switch segment.kind {
        case .allocated(let key):
            guard let allocation = allocationsByCategoryKey[key] else { return Color(Colors.gray600) }
            return colorForAllocation(allocation)
        case .offPlan:
            return Color(Colors.gray500)
        case .headroom:
            return Color(Colors.gray600)
        }
    }

    /// Base opacity when nothing is selected. Kept as separate literals per kind rather than a single
    /// multiplier: the values are not proportional to each other, they are three independent choices.
    private func baseOpacity(for segment: AllocationTagBreakdown.Segment) -> Double {
        switch segment.kind {
        case .allocated: return 1.0
        case .offPlan: return 0.8
        case .headroom: return 0.5
        }
    }

    private func opacity(for segment: AllocationTagBreakdown.Segment) -> Double {
        guard let selectedSegmentID else { return baseOpacity(for: segment) }
        if segment.id == selectedSegmentID {
            // Headroom brightens on selection; the other kinds are already at their base.
            return segment.kind == .headroom ? 1.0 : baseOpacity(for: segment)
        }
        return 0.35
    }

    /// Geometry of the category ring.
    ///
    /// Without tags this stays the single three-argument `SectorMark` call the card has always used -
    /// no `outerRadius`, `innerRadius: .ratio(0.65)` - so a user who never makes a tag keeps the exact
    /// donut they had. With tags it shrinks to 85...66pt to free a band for the tag ring.
    private var categoryInnerRatio: CGFloat { hasTags ? Self.categoryRingInnerRatio : 0.65 }

    /// 66pt of the 85pt plot radius.
    static let categoryRingInnerRatio: CGFloat = 0.7765
    /// The tag ring occupies 62...55pt, drawn as a 7pt band centred on 58.5pt.
    static let tagRingOuterRadius: CGFloat = 62
    static let tagRingInnerRadius: CGFloat = 55

    var body: some View {
        Chart {
            if hasContent {
                ForEach(segments) { segment in
                    if hasTags {
                        SectorMark(
                            angle: .value("Amount", segment.amount),
                            innerRadius: .ratio(categoryInnerRatio),
                            outerRadius: .ratio(1.0),
                            angularInset: 2
                        )
                        .foregroundStyle(color(for: segment))
                        .cornerRadius(4)
                        .opacity(opacity(for: segment))
                    } else {
                        SectorMark(
                            angle: .value("Amount", segment.amount),
                            innerRadius: .ratio(0.65),
                            angularInset: 2
                        )
                        .foregroundStyle(color(for: segment))
                        .cornerRadius(4)
                        .opacity(opacity(for: segment))
                    }
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
                ZStack {
                    // The tag ring is drawn rather than charted. Every SectorMark in one Chart shares a
                    // single angular scale whose domain is the sum of ALL mark values, so a second set
                    // of marks summing to the same total collapses both rings to half a circle each -
                    // verified, not assumed. `.chartBackground`'s GeometryReader hands us the plot rect,
                    // so a hand-drawn ring shares the marks' coordinate space exactly.
                    if hasTags {
                        tagRing(in: frame)
                    }
                    centerContent
                        .frame(width: centerSize, height: centerSize)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .onChange(of: rawSelectedValue) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                guard let value = newValue else {
                    selectedSegmentID = nil
                    return
                }
                guard let segment = segment(atAngularValue: value) else {
                    selectedSegmentID = nil
                    return
                }
                selectedSegmentID = segment.id
                switch segment.kind {
                case .allocated(let key):
                    if let allocation = allocationsByCategoryKey[key] {
                        onSegmentTapped?(allocation.category)
                    }
                case .offPlan, .headroom:
                    // Off-plan and headroom slices only update the centre readout, as before.
                    break
                }
            }
        }
    }

    // MARK: - Tag ring

    /// One filled annular sector per tag arc.
    ///
    /// Filled with hard radial edges, not stroked: `StrokeStyle(lineCap: .round)` on a 7pt band turns
    /// every arc into a pill, which reads as a different visual language from the category slices
    /// 4pt outside it. The marks' own `cornerRadius(4)` is not mimicked for the same reason - at 7pt a
    /// 4pt corner radius is a pill again.
    @available(iOS 17.0, *)
    private func tagRing(in frame: CGRect) -> some View {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let plotRadius = min(frame.width, frame.height) / 2
        // The ring's radii are expressed against the 85pt design radius, so they hold if the container
        // is ever sized differently.
        let scale = plotRadius / 85.0
        let outer = Self.tagRingOuterRadius * scale
        let inner = Self.tagRingInnerRadius * scale

        return ZStack {
            ForEach(breakdown.tagArcs) { arc in
                let start = -Double.pi / 2 + arc.startFraction * 2 * Double.pi
                let end = -Double.pi / 2 + arc.endFraction * 2 * Double.pi
                // The marks' 2pt angularInset converted to radians at this ring's own radius, so the
                // gaps line up with the outer band's radially instead of just numerically.
                let inset = min(2.0 / Double(outer), max(0, (end - start) / 2 - 0.001))
                Path { path in
                    path.addArc(
                        center: centre, radius: outer,
                        startAngle: .radians(start + inset), endAngle: .radians(end - inset),
                        clockwise: false)
                    path.addArc(
                        center: centre, radius: inner,
                        startAngle: .radians(end - inset), endAngle: .radians(start + inset),
                        clockwise: true)
                    path.closeSubpath()
                }
                .fill(Color(arc.tag.color.arc))
            }
        }
    }

    // MARK: - Centre readout

    @ViewBuilder
    private var centerContent: some View {
        VStack(spacing: 2) {
            if let selected = selectedSegment {
                switch selected.kind {
                case .allocated(let key):
                    if let allocation = allocationsByCategoryKey[key] {
                        if let icon = UIImage(named: allocation.category.iconName) {
                            Image(uiImage: icon)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(colorForAllocation(allocation))
                                .frame(width: 24, height: 24)
                        }
                        centerLabel(allocation.category.displayName)
                        centerValue(allocation.allocatedAmount)
                    }
                case .offPlan(let key):
                    if let spending = spendingByCategoryKey[key] {
                        if let icon = UIImage(named: spending.category.iconName(for: .expense)) {
                            Image(uiImage: icon)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(Color(Colors.gray400))
                                .frame(width: 24, height: 24)
                        }
                        centerLabel(spending.category.displayName)
                        centerValue(spending.spentAmount)
                    }
                case .headroom:
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24))
                        .foregroundColor(Color(Colors.gray400))
                    centerLabel("budget.unallocated".localized)
                    centerValue(effectiveUnallocatedAmount)
                }
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
                // Show total budget
                Text(isValuesHidden ? "••••••" : totalBudget.compactCurrencyString)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(Colors.gray100))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("budget.total.label".localized)
                    .font(.system(size: 11))
                    .foregroundColor(Color(Colors.gray400))
            }
        }
    }

    private func centerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color(Colors.gray300))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func centerValue(_ amount: Int) -> some View {
        Text(isValuesHidden ? "••••••" : amount.compactCurrencyString)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(Color(Colors.gray100))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: - Hit testing

    private var selectedSegment: AllocationTagBreakdown.Segment? {
        guard let selectedSegmentID else { return nil }
        return segments.first { $0.id == selectedSegmentID }
    }

    /// Walks the drawn order accumulating amounts, so the slice returned is the one under the finger
    /// even though that order is no longer the order of the `allocations` array.
    private func segment(atAngularValue value: Int) -> AllocationTagBreakdown.Segment? {
        var cumulative = 0
        for segment in segments {
            cumulative += segment.amount
            if value <= cumulative { return segment }
        }
        return nil
    }
}
