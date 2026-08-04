//
//  AllocationTagSelectionTests.swift
//  FinovaTests
//
//  Which ring a tap on the donut landed on. `chartAngleSelection` yields only an angle, so the radius
//  is the only thing separating the tag ring from the category ring - this is where that arithmetic is
//  checked, without SwiftUI in the way.
//

import CoreGraphics
import Foundation
import XCTest

@testable import Finova

@available(iOS 17.0, *)
final class AllocationTagSelectionTests: XCTestCase {

    /// The real container: 170x170, so a plot radius of 85pt and scale 1.
    private let plot = CGRect(x: 0, y: 0, width: 170, height: 170)
    private var centre: CGPoint { CGPoint(x: plot.midX, y: plot.midY) }

    private let essentials = AllocationTag(
        id: "t-essentials", name: "Essentials", colorIndex: 5, sortOrder: 0)
    private let wealth = AllocationTag(id: "t-wealth", name: "Wealth", colorIndex: 2, sortOrder: 1)

    /// Essentials 150k (0...0.5), Wealth 100k (0.5...0.833), untagged 30k, headroom 20k. Total 300k.
    private func breakdown() -> AllocationTagBreakdown {
        AllocationTagBreakdown(
            allocations: [
                BudgetAllocation(
                    dbId: 1, monthDate: 0, category: .homeMaintenance,
                    allocatedAmount: 150_000, usedAmount: 0),
                BudgetAllocation(
                    dbId: 2, monthDate: 0, category: .investments,
                    allocatedAmount: 100_000, usedAmount: 0),
                BudgetAllocation(
                    dbId: 3, monthDate: 0, category: .travel,
                    allocatedAmount: 30_000, usedAmount: 0),
            ],
            unallocatedSpending: [],
            unallocatedHeadroom: 20_000,
            totalBudget: 300_000,
            tags: [essentials, wealth],
            categoryTagIds: [
                TransactionCategory.homeMaintenance.key: essentials.id,
                TransactionCategory.investments.key: wealth.id,
            ])
    }

    /// A point at `radius` from the centre, `fraction` of the way clockwise from 12 o'clock.
    private func point(radius: CGFloat, fraction: Double) -> CGPoint {
        let radians = fraction * 2 * .pi - .pi / 2
        return CGPoint(
            x: centre.x + radius * CGFloat(cos(radians)),
            y: centre.y + radius * CGFloat(sin(radians)))
    }

    /// The angular value Charts would report for a tap at `fraction` around the circle.
    private func angularValue(_ fraction: Double, in breakdown: AllocationTagBreakdown) -> Int {
        Int((Double(breakdown.angularTotal) * fraction).rounded())
    }

    private func resolve(radius: CGFloat, fraction: Double) -> BudgetDonutChartView.Hit {
        let model = breakdown()
        return BudgetDonutChartView.resolve(
            tap: point(radius: radius, fraction: fraction),
            plot: plot,
            rawAngleValue: angularValue(fraction, in: model),
            breakdown: model)
    }

    // MARK: - Bands

    /// The centre hole. Today a tap here still selects whichever slice shares its angle; ignoring it is
    /// deliberate, so this test exists to stop someone "restoring" that.
    func testTapInTheCentreHoleSelectsNothing() {
        for radius in [CGFloat(0), 20, 40, 50] {
            XCTAssertEqual(resolve(radius: radius, fraction: 0.25), .none, "r=\(radius)")
        }
    }

    func testTapOnTheTagBandSelectsATag() {
        // 51...66pt is the tag band: the drawn 55...62 widened for fingers.
        for radius in [CGFloat(52), 55, 58, 62, 65] {
            XCTAssertEqual(
                resolve(radius: radius, fraction: 0.25), .tag(essentials.id), "r=\(radius)")
        }
    }

    func testTapOnTheCategoryRingSelectsASlice() {
        for radius in [CGFloat(68), 75, 84] {
            XCTAssertEqual(
                resolve(radius: radius, fraction: 0.25),
                .segment("alloc-homeMaintenance"), "r=\(radius)")
        }
    }

    /// The band must stop strictly inside the category ring's 66pt inner edge, or a tap meant for the
    /// innermost sliver of a slice selects a tag instead.
    func testTheTwoBandsDoNotOverlap() {
        XCTAssertEqual(
            BudgetDonutChartView.tagBandOuterRadius,
            BudgetDonutChartView.categoryRingInnerRatio * 85,
            accuracy: 0.5)
    }

    // MARK: - Angles

    func testEachTagOwnsItsOwnSweep() {
        // Essentials spans 0...0.5, Wealth 0.5...0.8333.
        XCTAssertEqual(resolve(radius: 58, fraction: 0.10), .tag(essentials.id))
        XCTAssertEqual(resolve(radius: 58, fraction: 0.49), .tag(essentials.id))
        XCTAssertEqual(resolve(radius: 58, fraction: 0.55), .tag(wealth.id))
        XCTAssertEqual(resolve(radius: 58, fraction: 0.80), .tag(wealth.id))
    }

    /// The untagged slice and the headroom slice have no arc, so the band is bare there.
    func testTheBandIsEmptyWhereNoTagReaches() {
        XCTAssertEqual(resolve(radius: 58, fraction: 0.90), .none)
        XCTAssertEqual(resolve(radius: 58, fraction: 0.97), .none)
    }

    func testCategoryRingStillResolvesUntaggedAndHeadroomSlices() {
        XCTAssertEqual(resolve(radius: 75, fraction: 0.90), .segment("alloc-travel"))
        XCTAssertEqual(resolve(radius: 75, fraction: 0.97), .segment("headroom"))
    }

    // MARK: - Degenerate input

    func testAnEmptyBreakdownNeverResolvesToATag() {
        for radius in [CGFloat(0), 40, 58, 75, 84] {
            let hit = BudgetDonutChartView.resolve(
                tap: point(radius: radius, fraction: 0.25),
                plot: plot, rawAngleValue: 100, breakdown: .empty)
            if case .tag = hit { XCTFail("empty breakdown resolved to a tag at r=\(radius)") }
        }
    }

    func testAZeroSizedPlotResolvesToNothing() {
        XCTAssertEqual(
            BudgetDonutChartView.resolve(
                tap: .zero, plot: .zero, rawAngleValue: 100, breakdown: breakdown()),
            .none)
    }

    /// A container sized differently must still hit the right bands - the radii are expressed against
    /// the 85pt design radius and scaled, not hardcoded in points.
    func testBandsScaleWithThePlotSize() {
        let doubled = CGRect(x: 0, y: 0, width: 340, height: 340)
        let model = breakdown()
        let centre = CGPoint(x: doubled.midX, y: doubled.midY)

        func hit(radius: CGFloat) -> BudgetDonutChartView.Hit {
            let radians = 0.25 * 2 * Double.pi - Double.pi / 2
            let tap = CGPoint(
                x: centre.x + radius * CGFloat(cos(radians)),
                y: centre.y + radius * CGFloat(sin(radians)))
            return BudgetDonutChartView.resolve(
                tap: tap, plot: doubled,
                rawAngleValue: angularValue(0.25, in: model), breakdown: model)
        }

        XCTAssertEqual(hit(radius: 80), .none, "the hole is twice as wide too")
        XCTAssertEqual(hit(radius: 116), .tag(essentials.id))
        XCTAssertEqual(hit(radius: 150), .segment("alloc-homeMaintenance"))
    }
}
