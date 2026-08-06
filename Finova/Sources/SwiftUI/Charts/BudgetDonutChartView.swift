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
    var selectedTagId: String?
    var isValuesHidden: Bool = false
    var onSegmentTapped: ((TransactionCategory) -> Void)?
    var onUnallocatedSpendingTapped: ((UnallocatedCategorySpending) -> Void)?
    /// `nil` clears the tag filter.
    var onTagSelected: ((String?) -> Void)?

    @State private var rawSelectedValue: Int?
    /// The plot rect, captured so a tap's radius can be measured. `chartAngleSelection` yields only a
    /// scalar on the angular axis and so cannot tell the two rings apart; the radius is what does.
    @State private var plotRect: CGRect = .zero
    @State private var lastTapLocation: CGPoint?
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
        // A drilled-in slice takes precedence over a selected tag, so tapping a member of the selected
        // tag still reads as a selection rather than being flattened by it.
        if let selectedSegmentID {
            if segment.id == selectedSegmentID {
                // Headroom brightens on selection; the other kinds are already at their base.
                return segment.kind == .headroom ? 1.0 : baseOpacity(for: segment)
            }
            return 0.35
        }
        if let selectedTagId {
            // Headroom belongs to no tag, so it is always dimmed while one is selected.
            guard segment.kind != .headroom else { return 0.35 }
            return segment.tagId == selectedTagId ? baseOpacity(for: segment) : 0.28
        }
        return baseOpacity(for: segment)
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
                .onAppear { plotRect = frame }
                .onChange(of: frame) { _, newValue in plotRect = newValue }
            }
        }
        // `simultaneousGesture`, so this coexists with Charts' own selection recogniser rather than
        // replacing it: the angle comes from Charts and only the radius comes from here.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { event in lastTapLocation = event.location }
        )
        .onChange(of: rawSelectedValue) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                guard let value = newValue else {
                    selectedSegmentID = nil
                    return
                }
                handleSelection(angularValue: value)
            }
        }
    }

    private func handleSelection(angularValue: Int) {
        // Without a tap location there is no radius, so fall back to the outer ring - which is what the
        // chart did before the tag ring existed.
        let hit: Hit
        if let tap = lastTapLocation, plotRect != .zero, hasTags {
            hit = Self.resolve(
                tap: tap, plot: plotRect, rawAngleValue: angularValue,
                breakdown: breakdownForHitTesting)
        } else if let segment = segment(atAngularValue: angularValue) {
            hit = .segment(segment.id)
        } else {
            hit = .none
        }

        switch hit {
        case .tag(let tagId):
            // Tap-again clears, matching the chip strip.
            selectedSegmentID = nil
            onTagSelected?(selectedTagId == tagId ? nil : tagId)

        case .segment(let segmentID):
            guard let segment = segments.first(where: { $0.id == segmentID }) else { return }
            // While a tag is selected its non-members are dimmed and out of scope, so a tap on one is
            // ignored rather than silently drilling into something the user cannot see.
            if let selectedTagId, segment.tagId != selectedTagId { return }
            selectedSegmentID = segment.id
            if case .allocated(let key) = segment.kind,
                let allocation = allocationsByCategoryKey[key]
            {
                onSegmentTapped?(allocation.category)
            }

        case .none:
            selectedSegmentID = nil
        }
    }

    /// The breakdown `resolve` should walk. Uses the caller's when it has segments, and otherwise the
    /// tagless one built here, so hit-testing can never disagree with what was drawn.
    private var breakdownForHitTesting: AllocationTagBreakdown {
        breakdown.segments.isEmpty ? .empty : breakdown
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
                .opacity(selectedTagId == nil || selectedTagId == arc.id ? 1.0 : 0.35)
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
                                // Full-strength magenta, NOT `colorForAllocation`. That ramp scales
                                // brightness from 0.35 to 1.0 by slice size, which is meaningful on the
                                // ring - bigger reads brighter - but in the centre it only makes a small
                                // category's icon nearly invisible against the dark card. Here the icon
                                // just names the category; its brightness carries no information.
                                .foregroundColor(Color(Colors.mainMagenta))
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
            } else if let arc = selectedArc {
                if let icon = arc.tag.icon.image {
                    Image(uiImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(arc.tag.color.arc))
                        .frame(width: 24, height: 24)
                }
                centerLabel(arc.tag.name)
                centerValue(arc.bucket.allocated)
                // The share is a proportion, not an amount, so it survives value-hiding - the same rule
                // the projection bar follows. Omitted entirely when there is no budget to be a share of,
                // rather than printing a meaningless 0%.
                if totalBudget > 0 {
                    Text(
                        String(
                            format: "budget.tag.shareOfBudget".localized,
                            Int((arc.bucket.share * 100).rounded()))
                    )
                    .font(.system(size: 9))
                    .foregroundColor(Color(Colors.gray400))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                Text(isValuesHidden ? ValueMask.placeholder : totalBudget.compactCurrencyString)
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
        Text(isValuesHidden ? ValueMask.placeholder : amount.compactCurrencyString)
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

    private var selectedArc: AllocationTagBreakdown.TagArc? {
        guard let selectedTagId else { return nil }
        return breakdown.arc(id: selectedTagId)
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

    /// What a tap landed on.
    enum Hit: Equatable {
        case tag(String)
        case segment(String)
        case none
    }

    /// Radius band a tap must fall in to count as the tag ring: the drawn 55...62pt band widened 4pt
    /// each way for fingers, still strictly inside the category ring's 66pt inner edge.
    static let tagBandInnerRadius: CGFloat = 51
    static let tagBandOuterRadius: CGFloat = 66

    /// Resolves a tap into a ring and a slice. Static and pure so it is testable without SwiftUI.
    ///
    /// - Parameters:
    ///   - tap: point in the plot's coordinate space.
    ///   - plot: the plot rect, as `.chartBackground` reports it.
    ///   - rawAngleValue: the value `chartAngleSelection` produced for the same tap.
    static func resolve(
        tap: CGPoint,
        plot: CGRect,
        rawAngleValue: Int,
        breakdown: AllocationTagBreakdown
    ) -> Hit {
        guard plot.width > 0, plot.height > 0 else { return .none }

        let plotRadius = min(plot.width, plot.height) / 2
        let scale = plotRadius / 85.0
        let radius = hypot(tap.x - plot.midX, tap.y - plot.midY)

        // The centre hole. Today a tap here still selects whichever slice shares its angle, which is a
        // small pre-existing wart; ignoring it is deliberate, not a regression.
        if radius < tagBandInnerRadius * scale { return .none }

        if radius <= tagBandOuterRadius * scale {
            guard breakdown.angularTotal > 0 else { return .none }
            let fraction = Double(rawAngleValue) / Double(breakdown.angularTotal)
            let arc = breakdown.tagArcs.first {
                $0.startFraction <= fraction && fraction < $0.endFraction
            }
            return arc.map { .tag($0.id) } ?? .none
        }

        var cumulative = 0
        for segment in breakdown.segments {
            cumulative += segment.amount
            if rawAngleValue <= cumulative { return .segment(segment.id) }
        }
        return .none
    }
}
