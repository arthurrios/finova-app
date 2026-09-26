//
//  RecurringAllocationConflictTests.swift
//  FinovaTests
//
//  Creating a bounded recurring allocation ("6 months") reported, and on "Overwrite" deleted,
//  same-category allocations in every later month, including months after its end that the series
//  never reaches.
//

import Foundation
import XCTest

@testable import Finova

final class RecurringAllocationConflictTests: XCTestCase {

    private func anchor(monthsFromStart offset: Int) -> Int {
        let start = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 1))!
        return Calendar.current.date(byAdding: .month, value: offset, to: start)!.monthAnchor
    }

    private var allocations: [BudgetAllocation] {
        [
            BudgetAllocation(dbId: 1, monthDate: anchor(monthsFromStart: 1), category: .market, allocatedAmount: 100),
            BudgetAllocation(dbId: 2, monthDate: anchor(monthsFromStart: 3), category: .market, allocatedAmount: 100),
            BudgetAllocation(dbId: 3, monthDate: anchor(monthsFromStart: 7), category: .market, allocatedAmount: 100),
            BudgetAllocation(dbId: 4, monthDate: anchor(monthsFromStart: 2), category: .meals, allocatedAmount: 100),
            BudgetAllocation(dbId: 5, monthDate: anchor(monthsFromStart: 0), category: .market, allocatedAmount: 100),
        ]
    }

    func testABoundedSeriesOnlyConflictsWithMonthsItReaches() {
        let conflicts = BudgetAllocationService.recurringConflicts(
            category: .market, from: anchor(monthsFromStart: 0), through: anchor(monthsFromStart: 6),
            in: allocations)

        XCTAssertEqual(
            conflicts.compactMap(\.dbId).sorted(), [1, 2],
            "Month 7 is after the series ends, so it is neither reported nor deleted")
    }

    func testTheEndMonthItselfIsReached() {
        let conflicts = BudgetAllocationService.recurringConflicts(
            category: .market, from: anchor(monthsFromStart: 0), through: anchor(monthsFromStart: 3),
            in: allocations)

        XCTAssertEqual(conflicts.compactMap(\.dbId).sorted(), [1, 2])
    }

    func testAnOngoingSeriesConflictsWithEveryLaterMonth() {
        let conflicts = BudgetAllocationService.recurringConflicts(
            category: .market, from: anchor(monthsFromStart: 0), through: nil, in: allocations)

        XCTAssertEqual(conflicts.compactMap(\.dbId).sorted(), [1, 2, 3])
    }
}
