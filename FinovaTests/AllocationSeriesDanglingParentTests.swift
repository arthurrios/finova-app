//
//  AllocationSeriesDanglingParentTests.swift
//  FinovaTests
//
//  `parentAllocationId` is a LOCAL id that CloudKit carries between devices verbatim, so an
//  occurrence that arrived from another device can point at an id that is not a live row here.
//
//  Reported symptom: "edit this and all future" from Jan/27 changed January and March and nothing
//  else. Those two were exactly the rows carrying the dangling pointer — a scoped edit selects
//  siblings by parent pointer, so it reached only the rows sharing that same dangling value and
//  every correctly-linked month stayed outdated.
//

import Foundation
import XCTest

@testable import Finova

final class AllocationSeriesDanglingParentTests: XCTestCase {
  private var allocationRepo: BudgetAllocationRepository!
  private var service: BudgetAllocationService!
  private var uid: String!

  /// Far enough out that every month in play is in the future, and inside the window lazy
  /// generation covers.
  private let firstOffset = 1
  private let lastOffset = 9

  override func setUp() {
    super.setUp()
    uid = "test_alloc_dangling_\(UUID().uuidString)"
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
    allocationRepo = BudgetAllocationRepository()
    service = BudgetAllocationService(allocationRepo: allocationRepo)
    for allocation in allocationRepo.fetchAllAllocations() {
      if let id = allocation.dbId { try? allocationRepo.deleteAllocation(id: id) }
    }
  }

  override func tearDown() {
    for allocation in allocationRepo.fetchAllAllocations() {
      if let id = allocation.dbId { try? allocationRepo.deleteAllocation(id: id) }
    }
    super.tearDown()
  }

  private func anchor(_ offset: Int) -> Int { Date().monthAnchor(offsetByMonths: offset) }

  /// A recurring series whose occurrences exist for `firstOffset...lastOffset`, with the rows at
  /// `+5` and `+7` re-pointed at an id no allocation answers to.
  private func makeSeriesWithDanglingOrphans() throws -> (parentId: Int, editAnchor: Int) {
    let parentId = try service.createAllocation(
      category: .education, amount: 40_000, monthAnchor: anchor(firstOffset), isRecurring: true)

    // Generation is lazy on this release — reading a month is what creates it.
    for offset in firstOffset...lastOffset {
      _ = service.getAllocationsWithUsage(forMonth: anchor(offset))
    }

    let danglingParentId = 9_999_999
    for offset in [5, 7] {
      let row = try XCTUnwrap(
        allocationRepo.fetchAllAllocations().first {
          $0.monthDate == anchor(offset)
            && $0.category.key == TransactionCategory.education.key
        }, "Month \(offset) should have been generated")
      try allocationRepo.updateParentAllocationId(
        id: try XCTUnwrap(row.dbId), parentId: danglingParentId)
    }

    return (parentId, anchor(5))
  }

  func testEditFutureFromARowWithADanglingParentPointerReachesTheWholeSeries() throws {
    let (parentId, editAnchor) = try makeSeriesWithDanglingOrphans()

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
      }
    }

    XCTAssertNotNil(
      allocationRepo.fetchAllAllocations().first { $0.dbId == parentId },
      "The original series parent must still exist")
  }

  func testDeleteFutureFromARowWithADanglingParentPointerReachesTheWholeSeries() throws {
    let (_, cutoffAnchor) = try makeSeriesWithDanglingOrphans()

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

  /// The healthy path must be untouched: a series with intact pointers still edits forward only.
  func testEditFutureOnlyStillLeavesEarlierMonthsAlone() throws {
    _ = try service.createAllocation(
      category: .utilities, amount: 40_000, monthAnchor: anchor(firstOffset), isRecurring: true)
    for offset in firstOffset...lastOffset {
      _ = service.getAllocationsWithUsage(forMonth: anchor(offset))
    }

    let editAnchor = anchor(4)
    let editRow = try XCTUnwrap(
      allocationRepo.fetchAllAllocations().first {
        $0.monthDate == editAnchor && $0.category.key == TransactionCategory.utilities.key
      })
    try service.updateAllocationWithOption(
      id: try XCTUnwrap(editRow.dbId), newAmount: 77_000, option: .futureOnly)

    for allocation in allocationRepo.fetchAllAllocations()
    where allocation.category.key == TransactionCategory.utilities.key
      && allocation.monthDate < editAnchor && allocation.monthDate > anchor(firstOffset)
    {
      XCTAssertEqual(
        allocation.allocatedAmount, 40_000,
        "Month \(allocation.monthDate) is before the edit and must keep its old amount")
    }
  }
}
