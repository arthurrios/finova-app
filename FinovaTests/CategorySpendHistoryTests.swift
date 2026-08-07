//
//  CategorySpendHistoryTests.swift
//  FinovaTests
//
//  The range a category's closed months describe, and when it is worth reporting.
//
//  A range rather than an average, because an average hides divergence: months of 20/90/15/85 percent
//  average to about half with a confident-looking sample behind them, and half is precisely the figure
//  not to plan against. These pin that divergent history reads as divergent instead.
//

import Foundation
import XCTest

@testable import Finova

final class CategorySpendHistoryTests: XCTestCase {

    /// Arbitrary anchors; the type never reads a date, it only keys by one.
    private func history(_ ratios: [Double]) -> CategorySpendHistory {
        var byMonth: [Int: Double] = [:]
        for (index, ratio) in ratios.enumerated() {
            byMonth[1_767_225_600 + index * 2_678_400] = ratio
        }
        return CategorySpendHistory(ratiosByMonth: byMonth)
    }

    // MARK: - Shape

    func testEmptyHistoryIsNoneAndReportsNothing() {
        let empty = CategorySpendHistory.none

        XCTAssertEqual(empty.sampleCount, 0)
        XCTAssertEqual(empty.verdict, .notEnoughHistory)
        XCTAssertEqual(empty, history([]))
    }

    func testSampleCountIsTheNumberOfMonths() {
        XCTAssertEqual(history([0.5, 0.6, 0.7]).sampleCount, 3)
    }

    /// Keyed by month so one month cannot contribute twice - which would inflate the sample count and
    /// with it the reader's confidence in the range.
    func testOneMonthCannotBeSampledTwice() {
        let duplicated = CategorySpendHistory(ratiosByMonth: [1_767_225_600: 0.9])

        XCTAssertEqual(duplicated.sampleCount, 1)
    }

    func testLowestAndHighestBoundTheSamples() {
        let result = history([0.42, 0.91, 0.55, 0.63])

        XCTAssertEqual(result.lowestRatio, 0.42, accuracy: 0.0001)
        XCTAssertEqual(result.highestRatio, 0.91, accuracy: 0.0001)
        XCTAssertEqual(result.spread, 0.49, accuracy: 0.0001)
    }

    func testIdenticalMonthsHaveNoSpread() {
        let result = history([0.6, 0.6, 0.6, 0.6])

        XCTAssertEqual(result.spread, 0, accuracy: 0.0001)
        XCTAssertEqual(result.verdict, .consistent(low: 0.6, high: 0.6, months: 4))
    }

    /// A month that was budgeted and never spent is a real observation, and the strongest signal this
    /// type exists to carry. It must reach `lowestRatio`, not be treated as a gap.
    func testAZeroPercentMonthIsIncludedInTheRange() {
        let result = history([0.0, 0.55, 0.60, 0.58])

        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(result.lowestRatio, 0, accuracy: 0.0001)
    }

    /// The clamp that used to bound this at 1.0 protected a money figure. It no longer feeds one, so
    /// "you usually go past this budget" survives to the screen.
    func testRatiosAboveOneSurviveUnclamped() {
        let result = history([0.95, 1.40, 1.10, 1.05])

        XCTAssertEqual(result.highestRatio, 1.40, accuracy: 0.0001)
        XCTAssertEqual(result.percentRange.high, 140)
    }

    // MARK: - Verdict: enough history

    func testFewerThanFourSamplesIsNotEnoughHistory() {
        for count in 0..<CategorySpendHistory.minimumSamples {
            let result = history(Array(repeating: 0.6, count: count))
            XCTAssertEqual(
                result.verdict, .notEnoughHistory,
                "\(count) samples should not be characterised")
        }
    }

    func testExactlyFourSamplesEarnsAVerdict() {
        let result = history([0.55, 0.58, 0.61, 0.64])

        XCTAssertEqual(result.verdict, .consistent(low: 0.55, high: 0.64, months: 4))
    }

    func testTheVerdictCarriesTheSampleCount() {
        let result = history([0.5, 0.52, 0.54, 0.56, 0.58, 0.6, 0.55, 0.53])

        guard case .consistent(_, _, let months) = result.verdict else {
            return XCTFail("eight tight samples should be consistent")
        }
        XCTAssertEqual(months, 8)
    }

    // MARK: - Verdict: consistent vs varied

    /// The threshold is inclusive, so a spread sitting exactly on it still reports a range.
    func testASpreadExactlyAtTheThresholdIsConsistent() {
        let result = history([0.30, 0.70, 0.50, 0.60])

        XCTAssertEqual(result.spread, CategorySpendHistory.maximumSpread, accuracy: 0.0001)
        guard case .consistent = result.verdict else {
            return XCTFail("a spread exactly at the threshold must not be called varied")
        }
    }

    func testASpreadJustOverTheThresholdIsVaried() {
        let result = history([0.30, 0.71, 0.50, 0.60])

        XCTAssertGreaterThan(result.spread, CategorySpendHistory.maximumSpread)
        guard case .varied = result.verdict else {
            return XCTFail("a spread past the threshold must be reported as varied")
        }
    }

    /// The case the whole design exists for: months that disagree wildly average to a plausible-looking
    /// figure. The verdict must say so rather than hand back a confident midpoint.
    func testWildlyDivergentMonthsAreReportedAsVariedNotAveraged() {
        let result = history([0.20, 0.90, 0.15, 0.85, 0.30, 0.95, 0.25, 0.80])

        XCTAssertEqual(result.verdict, .varied(low: 0.15, high: 0.95, months: 8))
    }

    /// A varied verdict still carries its bounds - nothing is withheld for being inconsistent, because
    /// being inconsistent is the finding.
    func testAVariedVerdictStillReportsItsRange() {
        guard case .varied(let low, let high, _) = history([0.05, 1.40, 0.60, 0.20]).verdict else {
            return XCTFail("expected varied")
        }
        XCTAssertEqual(low, 0.05, accuracy: 0.0001)
        XCTAssertEqual(high, 1.40, accuracy: 0.0001)
    }

    // MARK: - Percent rounding

    func testPercentRangeRoundsToWholePercents() {
        let result = history([0.5549, 0.6451, 0.60, 0.58])

        XCTAssertEqual(result.percentRange.low, 55)
        XCTAssertEqual(result.percentRange.high, 65)
    }

    /// Both ends can round to the same whole percent. Rounding lives on the type so a caller can spot
    /// that and render one value, instead of "56-56%" reaching the screen and reading as a bug.
    func testBothEndsCanRoundToTheSamePercent() {
        let result = history([0.5551, 0.5559, 0.5555, 0.5557])

        XCTAssertEqual(result.percentRange.low, result.percentRange.high)
        XCTAssertEqual(result.percentRange.low, 56)
    }

    func testAZeroPercentLowEndRoundsToZeroNotAway() {
        let result = history([0.0, 0.004, 0.60, 0.58])

        XCTAssertEqual(result.percentRange.low, 0)
    }
}
