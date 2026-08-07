//
//  MonthAnchorArithmeticTests.swift
//  FinovaTests
//
//  Stepping between month anchors.
//
//  Every call site in the app used to roll this by hand, and several stepped in a UTC calendar before
//  reading `.monthAnchor`, which uses `TimeZone.current` - two conventions inside one expression. These
//  pin the shared helpers so the next caller has something to trust.
//

import Foundation
import XCTest

@testable import Finova

final class MonthAnchorArithmeticTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: 0, second: 0)
        )!
    }

    private func yearMonth(of anchor: Int) -> (year: Int, month: Int) {
        let comps = calendar.dateComponents(
            [.year, .month], from: Date.fromMonthAnchor(anchor))
        return (comps.year!, comps.month!)
    }

    // MARK: - monthAnchor(offsetByMonths:)

    func testZeroOffsetIsTheReceiversOwnMonthAnchor() {
        let reference = date(2026, 8, 17)

        XCTAssertEqual(reference.monthAnchor(offsetByMonths: 0), reference.monthAnchor)
    }

    func testSteppingForwardAndBackwardLandsOnTheExpectedMonths() {
        let reference = date(2026, 8, 17)

        XCTAssertEqual(yearMonth(of: reference.monthAnchor(offsetByMonths: -1)).month, 7)
        XCTAssertEqual(yearMonth(of: reference.monthAnchor(offsetByMonths: 1)).month, 9)
        XCTAssertEqual(yearMonth(of: reference.monthAnchor(offsetByMonths: -8)).month, 12)
        XCTAssertEqual(yearMonth(of: reference.monthAnchor(offsetByMonths: -8)).year, 2025)
    }

    func testSteppingCrossesTheYearBoundaryBackwards() {
        let january = date(2026, 1, 15)
        let previous = yearMonth(of: january.monthAnchor(offsetByMonths: -1))

        XCTAssertEqual(previous.year, 2025)
        XCTAssertEqual(previous.month, 12)
    }

    func testSteppingCrossesTheYearBoundaryForwards() {
        let december = date(2026, 12, 15)
        let next = yearMonth(of: december.monthAnchor(offsetByMonths: 1))

        XCTAssertEqual(next.year, 2027)
        XCTAssertEqual(next.month, 1)
    }

    func testAFullYearBackIsTheSameMonthOfTheYearBefore() {
        let reference = date(2026, 8, 17)
        let back = yearMonth(of: reference.monthAnchor(offsetByMonths: -12))

        XCTAssertEqual(back.year, 2025)
        XCTAssertEqual(back.month, 8)
    }

    /// A month-end receiver is the case worth stating explicitly, because it is the one people expect
    /// to break. It does not: `date(byAdding: .month)` clamps the *day* and keeps the month, so 31
    /// January plus a month is 28 February and February is still the answer. Anchoring before stepping
    /// is about being canonical, not about dodging this. Pinned so the behaviour cannot regress.
    func testAMonthEndReceiverStillLandsInTheRightMonths() {
        for (year, month, day) in [(2026, 1, 31), (2026, 3, 31), (2026, 5, 31), (2026, 12, 31)] {
            let reference = date(year, month, day)

            let back = yearMonth(of: reference.monthAnchor(offsetByMonths: -1))
            let expectedBack = month == 1 ? (year - 1, 12) : (year, month - 1)
            XCTAssertEqual(back.year, expectedBack.0, "\(year)-\(month)-\(day) stepping back")
            XCTAssertEqual(back.month, expectedBack.1, "\(year)-\(month)-\(day) stepping back")

            let forward = yearMonth(of: reference.monthAnchor(offsetByMonths: 1))
            let expectedForward = month == 12 ? (year + 1, 1) : (year, month + 1)
            XCTAssertEqual(forward.year, expectedForward.0, "\(year)-\(month)-\(day) stepping forward")
            XCTAssertEqual(forward.month, expectedForward.1, "\(year)-\(month)-\(day) stepping forward")
        }
    }

    /// The receiver's time of day must not reach the result - that is what anchoring first buys.
    func testTheResultIsIndependentOfTheReceiversTimeOfDay() {
        let earlyInTheDay = date(2026, 3, 31, 0)
        let lateInTheDay = date(2026, 3, 31, 23)

        XCTAssertEqual(
            earlyInTheDay.monthAnchor(offsetByMonths: -1),
            lateInTheDay.monthAnchor(offsetByMonths: -1))
    }

    /// The helper must agree with the property every stored `month_date` was written through, or
    /// anchors computed here would address different rows than anchors written elsewhere.
    func testStepsAgreeWithDateMonthAnchor() {
        let reference = date(2026, 8, 17)

        for offset in -14...14 {
            let stepped = reference.monthAnchor(offsetByMonths: offset)
            let ym = yearMonth(of: stepped)
            XCTAssertEqual(
                stepped, date(ym.year, ym.month, 1).monthAnchor,
                "offset \(offset) disagrees with Date.monthAnchor")
        }
    }

    // MARK: - closedMonthAnchors

    func testClosedMonthAnchorsAreOldestFirstAndTheRequestedLength() {
        let anchors = DateUtils.closedMonthAnchors(count: 12, asOf: date(2026, 8, 17))

        XCTAssertEqual(anchors.count, 12)
        XCTAssertEqual(anchors, anchors.sorted(), "oldest first")
        XCTAssertEqual(Set(anchors).count, 12, "no month may appear twice")
    }

    func testClosedMonthAnchorsAreContiguous() {
        let reference = date(2026, 8, 17)
        let anchors = DateUtils.closedMonthAnchors(count: 12, asOf: reference)

        // -12 through -1, in order.
        let expected = (1...12).reversed().map { reference.monthAnchor(offsetByMonths: -$0) }
        XCTAssertEqual(anchors, expected)
    }

    func testTheCurrentMonthIsNeverIncluded() {
        let reference = date(2026, 8, 17)
        let anchors = DateUtils.closedMonthAnchors(count: 12, asOf: reference)

        XCTAssertFalse(anchors.contains(reference.monthAnchor))
    }

    /// The agreement the helper's doc comment promises: it derives closedness from offsets rather than
    /// calling `isPastMonth`, so the two must be checked against each other here instead.
    func testEveryReturnedAnchorIsAPastMonth() {
        for anchor in DateUtils.closedMonthAnchors(count: 12) {
            XCTAssertTrue(
                DateUtils.isPastMonth(date: Date.fromMonthAnchor(anchor)),
                "\(anchor) is not a closed month")
        }
    }

    func testTheWindowCrossesTheYearBoundary() {
        let anchors = DateUtils.closedMonthAnchors(count: 3, asOf: date(2026, 2, 10))
        let months = anchors.map { yearMonth(of: $0) }

        XCTAssertEqual(months.map(\.month), [11, 12, 1])
        XCTAssertEqual(months.map(\.year), [2025, 2025, 2026])
    }

    func testZeroOrNegativeCountIsEmptyRatherThanACrash() {
        XCTAssertTrue(DateUtils.closedMonthAnchors(count: 0).isEmpty)
        XCTAssertTrue(DateUtils.closedMonthAnchors(count: -5).isEmpty)
    }

    func testASingleMonthWindowIsTheMonthBeforeTheReference() {
        let anchors = DateUtils.closedMonthAnchors(count: 1, asOf: date(2026, 8, 17))

        XCTAssertEqual(anchors.count, 1)
        XCTAssertEqual(yearMonth(of: anchors[0]).month, 7)
    }
}
