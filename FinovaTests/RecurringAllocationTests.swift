//
//  RecurringAllocationTests.swift
//  FinovaTests
//
//  Recurring allocations had no coverage at all, and were the side that genuinely generated on
//  render — a month existed only if the user had scrolled to it.
//

import Foundation
import XCTest

@testable import Finova

final class RecurringAllocationTests: XCTestCase {
  private var allocationRepo: BudgetAllocationRepository!
  private var service: BudgetAllocationService!

  override func setUp() {
    super.setUp()
    UIDUserDefaultsManager.shared.currentUserUID = "test_alloc_recurring_\(UUID().uuidString)"
    allocationRepo = BudgetAllocationRepository()
    service = BudgetAllocationService(allocationRepo: allocationRepo)
  }

  override func tearDown() {
    for allocation in allocationRepo.fetchAllAllocations() {
      if let id = allocation.dbId { try? allocationRepo.deleteAllocation(id: id) }
    }
    UIDUserDefaultsManager.shared.signOut()
    super.tearDown()
  }

  // MARK: - Helpers

  @discardableResult
  private func createRecurring(
    category: TransactionCategory = .utilities,
    amount: Int = 40_000,
    startingMonthsFromNow offset: Int,
    endMonth: Int? = nil
  ) throws -> Int {
    try service.createAllocation(
      category: category, amount: amount,
      monthAnchor: Date().monthAnchor(offsetByMonths: offset),
      isRecurring: true, recurrenceEndMonth: endMonth)
  }

  private func months(ofSeries parentId: Int) -> [Int] {
    allocationRepo.fetchAllAllocations()
      .filter { $0.dbId == parentId || $0.parentAllocationId == parentId }
      .map { $0.monthDate }
      .sorted()
  }

  private func assertContiguous(
    _ months: [Int], from start: Int, through end: Int, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      months, SeriesMonths.anchors(from: start, through: end),
      "Series should hold exactly one allocation per month from \(start) through \(end)",
      file: file, line: line)
  }

  // MARK: - Gap-free materialization

  /// The primary allocation bug: the horizon walked `1...36` from `Date()` and discarded anything at
  /// or before the parent's month, so a series created on a past month never filled the gap between
  /// its start and today.
  func testRecurringAllocationCreatedInAPastMonthFillsEveryMonth() throws {
    let start = Date().monthAnchor(offsetByMonths: -6)
    let parentId = try createRecurring(startingMonthsFromNow: -6)

    assertContiguous(
      months(ofSeries: parentId), from: start,
      through: SeriesMonths.horizonAnchor(start: start))
  }

  func testRecurringAllocationCreatedInAFutureMonthFillsFromThatMonth() throws {
    let start = Date().monthAnchor(offsetByMonths: 4)
    let parentId = try createRecurring(startingMonthsFromNow: 4)

    assertContiguous(
      months(ofSeries: parentId), from: start,
      through: SeriesMonths.horizonAnchor(start: start))
  }

  func testBoundedSeriesStopsAtItsEndMonthAndClearsRecurrence() throws {
    let start = Date().monthAnchor(offsetByMonths: 0)
    let end = Date().monthAnchor(offsetByMonths: 5)
    let parentId = try createRecurring(startingMonthsFromNow: 0, endMonth: end)

    assertContiguous(months(ofSeries: parentId), from: start, through: end)

    let parent = allocationRepo.fetchAllAllocations().first { $0.dbId == parentId }
    XCTAssertEqual(
      parent?.isRecurring, false,
      "A bounded series must stop recurring so the rolling top-up never extends it")
  }

  /// An unrelated allocation in the same category must not punch a hole in a series. The old dedup
  /// treated every same-category row, from any series, as "already covered".
  func testAnUnrelatedAllocationForTheSameCategoryDoesNotBlockTheSeries() throws {
    // A one-off allocation for the same category, three months out.
    let conflictAnchor = Date().monthAnchor(offsetByMonths: 3)
    _ = try service.createAllocation(
      category: .utilities, amount: 99_000, monthAnchor: conflictAnchor,
      isRecurring: false, recurrenceEndMonth: nil)

    // The series cannot own that month (one live allocation per month+category), but every OTHER
    // month must still be materialized — that is the regression.
    let start = Date().monthAnchor(offsetByMonths: 0)
    let parentId = try createRecurring(startingMonthsFromNow: 0)
    let held = Set(months(ofSeries: parentId))

    for anchor in SeriesMonths.anchors(from: start, through: SeriesMonths.horizonAnchor(start: start))
    where anchor != conflictAnchor {
      XCTAssertTrue(held.contains(anchor), "Month \(anchor) should not have been skipped")
    }
  }

  // MARK: - Delete

  /// Deleting ONE occurrence used to clear the PARENT's `is_recurring`, silently stopping the whole
  /// series — and, via the create-conflict flow, several unrelated ones.
  func testDeletingOneOccurrenceDoesNotStopTheSeries() throws {
    let parentId = try createRecurring(startingMonthsFromNow: 0)
    let victimAnchor = Date().monthAnchor(offsetByMonths: 3)
    let victim = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.parentAllocationId == parentId && $0.monthDate == victimAnchor
      })

    try allocationRepo.deleteAllocation(id: try XCTUnwrap(victim.dbId))

    let parent = allocationRepo.fetchAllAllocations().first { $0.dbId == parentId }
    XCTAssertEqual(
      parent?.isRecurring, true,
      "Removing one month must not stop the series from recurring")

    let remaining = Set(months(ofSeries: parentId))
    XCTAssertFalse(remaining.contains(victimAnchor), "The deleted month should be gone")
    XCTAssertTrue(
      remaining.contains(Date().monthAnchor(offsetByMonths: 4)),
      "Later months must survive a single-occurrence delete")
  }

  /// The permanent-hole bug: tombstones used to be keyed on `"<month>|<category>"` with no series
  /// component, so a month deleted once could never be filled again — by ANY later series for that
  /// category. A brand-new series came out missing exactly those months, silently.
  func testANewSeriesIsNotBlockedByAnEarlierSeriesDeletedMonths() throws {
    let oldParentId = try createRecurring(startingMonthsFromNow: 0)
    let holeA = Date().monthAnchor(offsetByMonths: 6)
    let holeB = Date().monthAnchor(offsetByMonths: 7)

    for hole in [holeA, holeB] {
      let row = try XCTUnwrap(
        allocationRepo.fetchAllAllocations().first {
          $0.parentAllocationId == oldParentId && $0.monthDate == hole
        })
      try allocationRepo.deleteAllocation(id: try XCTUnwrap(row.dbId))
    }

    // Remove the old series entirely, then start a fresh one for the same category.
    try allocationRepo.deleteAllRecurringAllocations(id: oldParentId)

    let start = Date().monthAnchor(offsetByMonths: 0)
    let newParentId = try createRecurring(startingMonthsFromNow: 0)
    let held = Set(months(ofSeries: newParentId))

    XCTAssertTrue(
      held.contains(holeA) && held.contains(holeB),
      "A new series must materialize months that an EARLIER series had deleted")
    assertContiguous(
      months(ofSeries: newParentId), from: start,
      through: SeriesMonths.horizonAnchor(start: start))
  }

  func testDeletingOneOccurrenceDoesNotResurrectThatMonth() throws {
    let parentId = try createRecurring(startingMonthsFromNow: 0)
    let victimAnchor = Date().monthAnchor(offsetByMonths: 3)
    let victim = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.parentAllocationId == parentId && $0.monthDate == victimAnchor
      })
    try allocationRepo.deleteAllocation(id: try XCTUnwrap(victim.dbId))

    _ = allocationRepo.materializeSeries(parentId: parentId, endMonth: nil)

    XCTAssertFalse(
      Set(months(ofSeries: parentId)).contains(victimAnchor),
      "The tombstone must keep a deleted month deleted across materialization")
  }

  func testDeleteFutureStopsTheSeriesAndKeepsEarlierMonths() throws {
    let start = Date().monthAnchor(offsetByMonths: -3)
    let parentId = try createRecurring(startingMonthsFromNow: -3)

    let cutoffAnchor = Date().monthAnchor(offsetByMonths: 1)
    let cutoffRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.parentAllocationId == parentId && $0.monthDate == cutoffAnchor
      })
    try allocationRepo.deleteRecurringAllocationAndFuture(id: try XCTUnwrap(cutoffRow.dbId))

    let remaining = months(ofSeries: parentId)
    assertContiguous(
      remaining, from: start,
      through: Date().monthAnchor(offsetByMonths: 0))
  }

  // MARK: - Edit

  func testEditFutureOnlyUpdatesEveryLaterOccurrence() throws {
    let parentId = try createRecurring(startingMonthsFromNow: 0, endMonth: nil)
    let editAnchor = Date().monthAnchor(offsetByMonths: 2)
    let editRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.parentAllocationId == parentId && $0.monthDate == editAnchor
      })

    try service.updateAllocationWithOption(
      id: try XCTUnwrap(editRow.dbId), newAmount: 77_000, option: .futureOnly)

    for allocation in allocationRepo.fetchAllAllocations()
    where allocation.dbId == parentId || allocation.parentAllocationId == parentId {
      if allocation.monthDate >= editAnchor {
        XCTAssertEqual(
          allocation.allocatedAmount, 77_000,
          "Month \(allocation.monthDate) is at/after the edit and should carry the new amount")
      } else {
        XCTAssertEqual(allocation.allocatedAmount, 40_000)
      }
    }
  }

  // MARK: - Split series (the "skips two months in the middle" bug)

  /// Reported symptom: editing/deleting a series from Jan 2027 forward applied to every future month
  /// EXCEPT two in the middle, which kept their old value.
  ///
  /// Cause: those months' rows were created by an EARLIER series for the same category. Creation
  /// refuses a month that is already taken, so the newer series was born with holes exactly there,
  /// and a scope filter keyed on the parent pointer never saw the older rows. Category + scope is
  /// the series identity for an allocation, so the two parents describe one timeline and must be
  /// merged before any scoped write.
  private func makeSplitSeries() throws -> (parentId: Int, strandedMonths: [Int]) {
    // An older "series": two consecutive months owned by their own parent.
    let strandedA = Date().monthAnchor(offsetByMonths: 6)
    let strandedB = Date().monthAnchor(offsetByMonths: 7)
    let oldParentId = try service.createAllocation(
      category: .utilities, amount: 40_000, monthAnchor: strandedA,
      isRecurring: true, recurrenceEndMonth: strandedB)

    // The current series, created earlier in the timeline. Its horizon runs straight through
    // strandedA/strandedB, which are already occupied.
    let parentId = try createRecurring(startingMonthsFromNow: 0)
    XCTAssertNotEqual(parentId, oldParentId)

    return (parentId, [strandedA, strandedB])
  }

  func testScopedEditReachesMonthsOwnedByAnEarlierSeriesForTheSameCategory() throws {
    let (parentId, stranded) = try makeSplitSeries()

    let editAnchor = Date().monthAnchor(offsetByMonths: 2)
    let editRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        ($0.dbId == parentId || $0.parentAllocationId == parentId) && $0.monthDate == editAnchor
      })
    try service.updateAllocationWithOption(
      id: try XCTUnwrap(editRow.dbId), newAmount: 88_000, option: .futureOnly)

    for month in stranded {
      let row = try XCTUnwrap(
        allocationRepo.fetchAllAllocations().first {
          $0.monthDate == month && $0.category.key == TransactionCategory.utilities.key
        }, "Month \(month) should still exist")
      XCTAssertEqual(
        row.allocatedAmount, 88_000,
        "Month \(month) is after the edit and must not be skipped just because an earlier series owned it")
    }
  }

  func testScopedDeleteReachesMonthsOwnedByAnEarlierSeriesForTheSameCategory() throws {
    let (parentId, stranded) = try makeSplitSeries()

    let cutoffAnchor = Date().monthAnchor(offsetByMonths: 2)
    let cutoffRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        ($0.dbId == parentId || $0.parentAllocationId == parentId) && $0.monthDate == cutoffAnchor
      })
    try service.deleteAllocation(id: try XCTUnwrap(cutoffRow.dbId), deleteAllFuture: true)

    for month in stranded {
      XCTAssertNil(
        allocationRepo.fetchAllAllocations().first {
          $0.monthDate == month && $0.category.key == TransactionCategory.utilities.key
        },
        "Month \(month) is after the cutoff and must be deleted, not skipped")
    }
  }

  /// The bound that keeps the merge honest: a genuine one-off allocation the user created for a
  /// single month is not part of anyone's series and must survive a scoped delete.
  func testAOneOffAllocationIsNotSweptIntoTheSeries() throws {
    let oneOffAnchor = Date().monthAnchor(offsetByMonths: 6)
    _ = try service.createAllocation(
      category: .utilities, amount: 12_345, monthAnchor: oneOffAnchor,
      isRecurring: false, recurrenceEndMonth: nil)

    let parentId = try createRecurring(startingMonthsFromNow: 0)
    let cutoffAnchor = Date().monthAnchor(offsetByMonths: 2)
    let cutoffRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        ($0.dbId == parentId || $0.parentAllocationId == parentId) && $0.monthDate == cutoffAnchor
      })
    try service.deleteAllocation(id: try XCTUnwrap(cutoffRow.dbId), deleteAllFuture: true)

    let survivor = allocationRepo.fetchAllAllocations().first { $0.monthDate == oneOffAnchor }
    XCTAssertEqual(
      survivor?.allocatedAmount, 12_345,
      "A standalone one-off must not be adopted into a series and deleted with it")
  }

  // MARK: - Dangling parent pointer (the "only January and March changed" bug)

  /// `parent_allocation_id` is a LOCAL autoincrement id that CloudKit carries between devices
  /// verbatim (`CKBudgetAllocationAdapter`), so a row that arrived from another device can point at
  /// an id that is not a live row here — until `parent_allocation_uuid` resolves, or forever if the
  /// sender predates the uuid columns.
  ///
  /// Reported symptom: "edit this and all future" from Jan/27 changed January and March and nothing
  /// else. Those two were exactly the rows carrying the dangling pointer: anchoring the pre-edit
  /// repair on a non-existent parent makes `repairAllocationSeries` and `materializeSeries` bail on
  /// their `first(where:)` guard, and the pointer filter downstream then reaches only the rows that
  /// happen to share the same dangling value.
  private func makeSeriesWithDanglingOrphans() throws -> (
    parentId: Int, editAnchor: Int, orphanAnchors: [Int]
  ) {
    let parentId = try createRecurring(category: .education, startingMonthsFromNow: 0)

    let editAnchor = Date().monthAnchor(offsetByMonths: 5)
    let strayAnchor = Date().monthAnchor(offsetByMonths: 7)
    let danglingParentId = 9_999_999

    for anchor in [editAnchor, strayAnchor] {
      let row = try XCTUnwrap(
        allocationRepo.fetchAllAllocations().first {
          $0.parentAllocationId == parentId && $0.monthDate == anchor
        })
      try allocationRepo.updateParentAllocationId(
        id: try XCTUnwrap(row.dbId), parentId: danglingParentId)
    }

    return (parentId, editAnchor, [editAnchor, strayAnchor])
  }

  func testEditFutureFromARowWithADanglingParentPointerReachesTheWholeSeries() throws {
    let (parentId, editAnchor, _) = try makeSeriesWithDanglingOrphans()

    let editRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.monthDate == editAnchor && $0.category.key == TransactionCategory.education.key
      })
    try service.updateAllocationWithOption(
      id: try XCTUnwrap(editRow.dbId), newAmount: 88_000, option: .futureOnly)

    for allocation in allocationRepo.fetchAllAllocations()
    where allocation.category.key == TransactionCategory.education.key {
      if allocation.monthDate >= editAnchor {
        XCTAssertEqual(
          allocation.allocatedAmount, 88_000,
          "Month \(allocation.monthDate) is at/after the edit and must not be skipped because the edited row's parent pointer dangles"
        )
      } else {
        XCTAssertEqual(allocation.allocatedAmount, 40_000)
      }
    }

    XCTAssertNotNil(
      allocationRepo.fetchAllAllocations().first { $0.dbId == parentId },
      "The original series parent must still exist")
  }

  func testDeleteFutureFromARowWithADanglingParentPointerReachesTheWholeSeries() throws {
    let (_, cutoffAnchor, _) = try makeSeriesWithDanglingOrphans()

    let cutoffRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.monthDate == cutoffAnchor && $0.category.key == TransactionCategory.education.key
      })
    try service.deleteAllocation(id: try XCTUnwrap(cutoffRow.dbId), deleteAllFuture: true)

    let survivors = allocationRepo.fetchAllAllocations()
      .filter { $0.category.key == TransactionCategory.education.key }
      .map { $0.monthDate }
    XCTAssertTrue(
      survivors.allSatisfy { $0 < cutoffAnchor },
      "Every month at/after the cutoff must be deleted, including the ones whose parent pointer dangles"
    )
  }

  // MARK: - No lazy generation

  /// The load-bearing test for the eager-generation decision: reading a month must never create a
  /// row. `getAllocationsWithUsage` used to materialize this month's occurrences first.
  func testReadingAMonthNeverCreatesRows() throws {
    _ = try createRecurring(startingMonthsFromNow: 0)
    let before = allocationRepo.fetchAllAllocations().count

    for offset in SeriesMonths.carouselRange {
      _ = service.getAllocationsWithUsage(
        forMonth: Date().monthAnchor(offsetByMonths: offset), in: .personal)
    }

    XCTAssertEqual(
      allocationRepo.fetchAllAllocations().count, before,
      "Reading every month in the carousel must not write a single row")
  }
}
