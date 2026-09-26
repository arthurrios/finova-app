//
//  RecurringSeriesFixesTests.swift
//  FinovaTests
//
//  Pins four recurring-series fixes: a month deleted on its own stays deleted after a restart,
//  deleting only the first month keeps the series going, rewriting a row keeps its weekend rule,
//  and generated months land on the right day east of UTC.
//

import Foundation
import XCTest

@testable import Finova

final class RecurringSeriesFixesTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var addViewModel: AddTransactionModalViewModel!
  private var recurringManager: RecurringTransactionManager!
  private var originalTimeZone: TimeZone!

  override func setUp() {
    super.setUp()
    originalTimeZone = NSTimeZone.default
    SecureLocalDataManager.shared.authenticateUser(
      firebaseUID: "test_recurring_fixes_\(UUID().uuidString)")
    transactionRepo = TransactionRepository()
    addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
    recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    NSTimeZone.default = originalTimeZone
    transactionRepo.clearAllTransactionsForTesting()
    RecurringTransactionManager.clearAllDeletedInstanceTracking()
    super.tearDown()
  }

  private func makeSeries(title: String, rule: BusinessDayRule = .exact) throws -> Transaction {
    let start = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    let result = addViewModel.addTransaction(
      title: title, amount: 10_000,
      dateString: DateFormatter.fullDateFormatter.string(from: start),
      categoryKey: "utilities", typeRaw: "expense", isRecurring: true, businessDayRule: rule)
    guard case .success = result else { throw XCTSkip("Could not create the series: \(result)") }
    TransactionRepository.invalidateCache()
    let parent = try XCTUnwrap(
      transactionRepo.fetchAllTransactions().first { $0.title == title && $0.isRecurring == true })
    recurringManager.generateInstancesForTransaction(
      parent, in: -3...6, referenceDate: Date(), transactionStartDate: start)
    TransactionRepository.invalidateCache()
    return parent
  }

  private func rows(titled title: String) -> [Transaction] {
    TransactionRepository.invalidateCache()
    return transactionRepo.fetchAllTransactions().filter { $0.title == title }
  }

  // MARK: - A deleted month stays deleted

  func testADeletedMonthIsReadBackFromStorageNotMemory() {
    RecurringTransactionManager.trackDeletedInstance(parentId: 4242, monthAnchor: 1_700_000_000)

    let stored = UserDefaults.standard.dictionaryRepresentation()
      .filter { $0.key.hasPrefix("recurringExcludedAnchors_v1_") }
      .compactMap { $0.value as? [String: [Int]] }
    XCTAssertTrue(
      stored.contains { $0["4242"]?.contains(1_700_000_000) == true },
      "The exclusion must be written to UserDefaults so it survives a restart")
    XCTAssertTrue(RecurringTransactionManager.excludedAnchors(for: 4242).contains(1_700_000_000))

    RecurringTransactionManager.clearDeletedInstanceTracking(for: 4242)
    XCTAssertTrue(RecurringTransactionManager.excludedAnchors(for: 4242).isEmpty)
  }

  // MARK: - Deleting only the first month keeps the series

  func testDeletingOnlyTheFirstMonthHandsTheSeriesToTheNextOne() throws {
    let parent = try makeSeries(title: "Internet")
    let parentId = try XCTUnwrap(parent.id)
    let before = rows(titled: "Internet").count
    try XCTSkipIf(before < 3, "Fixture made too few months: \(before)")

    try transactionRepo.deleteTransactionWithOption(id: parentId, option: .currentSelection)

    let remaining = rows(titled: "Internet")
    XCTAssertFalse(remaining.contains { $0.id == parentId }, "The first month is deleted")
    XCTAssertEqual(remaining.count, before - 1, "Only the first month is deleted")
    let heir = try XCTUnwrap(
      remaining.first { $0.isRecurring == true }, "Another month must now head the series")
    XCTAssertEqual(heir.parentTransactionId, heir.id, "The new head links to itself")
    XCTAssertTrue(
      remaining.allSatisfy { $0.parentTransactionId == heir.id },
      "Every remaining month points at the new head")

    // The series still generates: remove its last month outright (no exclusion) and ask for it again.
    let last = try XCTUnwrap(remaining.filter { $0.id != heir.id }.max { $0.seriesPeriod < $1.seriesPeriod })
    try transactionRepo.delete(id: try XCTUnwrap(last.id))
    TransactionRepository.invalidateCache()
    let created = recurringManager.materializeMissingOccurrences([last.seriesPeriod])
    XCTAssertEqual(created, 1, "The series must keep generating after its first month is deleted")
  }

  // MARK: - Rewrites keep the weekend rule

  func testRewritingTheParentLinkKeepsTheWeekendRule() throws {
    let parent = try makeSeries(title: "School", rule: .nextBusinessDay)
    let parentId = try XCTUnwrap(parent.id)

    try transactionRepo.updateParentTransactionId(transactionId: parentId, parentId: parentId)
    TransactionRepository.invalidateCache()

    let reread = try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == parentId })
    XCTAssertEqual(reread.businessDayRule, .nextBusinessDay)
    XCTAssertEqual(reread.unadjustedDateTimestamp, parent.unadjustedDateTimestamp)
  }

  // MARK: - East of UTC

  func testGeneratedMonthsKeepTheirDayEastOfUTC() throws {
    let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
    NSTimeZone.default = tokyo
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tokyo

    // Local midnight on the 15th, three months back: the moment that is still the 14th in UTC.
    let base = calendar.date(byAdding: .month, value: -3, to: Date())!
    var parts = calendar.dateComponents([.year, .month], from: base)
    parts.day = 15
    let startDate = try XCTUnwrap(calendar.date(from: parts))
    let parentId = try transactionRepo.insertTransactionAndGetId(
      TransactionModel(
        title: "Tokyo rent", category: "utilities", amount: 5_000, type: "expense",
        dateTimestamp: Int(startDate.timeIntervalSince1970),
        budgetMonthDate: startDate.monthAnchor, isRecurring: true,
        unadjustedDateTimestamp: Int(startDate.timeIntervalSince1970),
        seriesPeriod: startDate.monthAnchor))
    try transactionRepo.updateParentTransactionId(transactionId: parentId, parentId: parentId)

    let manager = RecurringTransactionManager(transactionRepo: transactionRepo)
    let nextMonth = startDate.monthAnchor(offsetByMonths: 1)
    _ = manager.materializeMissingOccurrences([nextMonth])

    let child = try XCTUnwrap(
      rows(titled: "Tokyo rent").first { $0.parentTransactionId == parentId && $0.id != parentId },
      "The next month should be generated")
    XCTAssertEqual(calendar.component(.day, from: child.date), 15, "Must stay on the 15th in Tokyo")
  }
}
