//
//  RecurringSeriesLinkerTests.swift
//  FinovaTests
//
//  Orphaned occurrences must be re-attached so scoped edits reach them — and nothing else may be.
//

import Foundation
import XCTest

@testable import Finova

final class RecurringSeriesLinkerTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var addViewModel: AddTransactionModalViewModel!
  private var recurringManager: RecurringTransactionManager!
  private var linker: RecurringSeriesLinker!

  override func setUp() {
    super.setUp()
    UIDUserDefaultsManager.shared.currentUserUID = "test_linker_\(UUID().uuidString)"
    transactionRepo = TransactionRepository()
    addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
    recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    linker = RecurringSeriesLinker(transactionRepo: transactionRepo)
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    transactionRepo.clearAllTransactionsForTesting()
    UIDUserDefaultsManager.shared.signOut()
    super.tearDown()
  }

  // MARK: - Helpers

  private func makeSeries(
    title: String, amount: Int = 100_000, day: Int = 10, category: String = "utilities",
    startingMonthsFromNow offset: Int = 0
  ) throws -> Transaction {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    var parts = cal.dateComponents(
      [.year, .month], from: Date.fromMonthAnchor(Date().monthAnchor(offsetByMonths: offset)))
    parts.day = day
    parts.hour = 12
    let start = try XCTUnwrap(cal.date(from: parts))

    let result = addViewModel.addTransaction(
      title: title, amount: amount,
      dateString: DateFormatter.fullDateFormatter.string(from: start),
      categoryKey: category, typeRaw: "expense", isRecurring: true)
    guard case .success = result else { throw XCTSkip("Could not create fixture: \(result)") }
    TransactionRepository.invalidateCache()

    return try XCTUnwrap(
      transactionRepo.fetchAllTransactions().first { $0.title == title && $0.isRecurring == true })
  }

  /// Breaks one occurrence's parent pointer the way a cross-device id mismatch does: it points at
  /// an id that does not exist locally.
  private func orphan(_ transaction: Transaction) throws {
    try transactionRepo.updateParentTransactionId(
      transactionId: try XCTUnwrap(transaction.id), parentId: 999_999)
    TransactionRepository.invalidateCache()
  }

  private func members(of parentId: Int) -> [Transaction] {
    TransactionRepository.invalidateCache()
    return transactionRepo.fetchAllTransactions()
      .filter { $0.id == parentId || $0.parentTransactionId == parentId }
  }

  // MARK: - Adoption

  func testOrphanedOccurrenceIsReattachedToItsSeries() throws {
    let parent = try makeSeries(title: "Orphan Test")
    let parentId = try XCTUnwrap(parent.id)

    let victimAnchor = Date().monthAnchor(offsetByMonths: 4)
    let victim = try XCTUnwrap(
      members(of: parentId).first { $0.seriesPeriod == victimAnchor })
    try orphan(victim)
    XCTAssertFalse(members(of: parentId).contains { $0.id == victim.id })

    XCTAssertEqual(linker.repairTransactionSeries(around: parentId), 1)
    XCTAssertTrue(
      members(of: parentId).contains { $0.id == victim.id },
      "The orphan should be back in its series")
  }

  /// The whole point of relinking: an orphan must actually receive a scoped edit.
  func testEditAllFutureUpdatesReattachedOccurrences() throws {
    let parent = try makeSeries(title: "Edit Reaches Orphan")
    let parentId = try XCTUnwrap(parent.id)

    let victimAnchor = Date().monthAnchor(offsetByMonths: 6)
    let victim = try XCTUnwrap(members(of: parentId).first { $0.seriesPeriod == victimAnchor })
    try orphan(victim)

    let editAnchor = Date().monthAnchor(offsetByMonths: 2)
    let editRow = try XCTUnwrap(members(of: parentId).first { $0.seriesPeriod == editAnchor })
    let editDate = editRow.unadjustedDate

    let newData = TransactionModel(
      id: editRow.id, title: "Edit Reaches Orphan", category: "utilities", amount: 175_000,
      type: "expense", dateTimestamp: Int(editDate.timeIntervalSince1970),
      budgetMonthDate: editAnchor, isRecurring: true, hasInstallments: false,
      parentTransactionId: parentId, originalAmount: 175_000)

    try recurringManager.editRecurringTransactionsFromDate(
      parentTransactionId: parentId, selectedTransactionDate: editDate,
      editOption: .futureOnly, newData: newData)
    TransactionRepository.invalidateCache()

    let reattached = try XCTUnwrap(
      transactionRepo.fetchAllTransactions().first { $0.id == victim.id })
    XCTAssertEqual(
      reattached.amount, 175_000,
      "An occurrence whose parent pointer was broken must still receive 'this and future'")
  }

  // MARK: - Bounds on over-matching

  func testDoesNotMergeTwoSeriesThatDifferByDay() throws {
    let first = try makeSeries(title: "Day Split", day: 5)
    let second = try makeSeries(title: "Day Split", day: 20)
    let firstId = try XCTUnwrap(first.id)
    let secondId = try XCTUnwrap(second.id)

    let before = members(of: firstId).count
    XCTAssertEqual(
      linker.repairTransactionSeries(around: firstId), 0,
      "A series anchored on a different day is a different series")
    XCTAssertEqual(members(of: firstId).count, before)
    XCTAssertFalse(members(of: firstId).contains { $0.id == secondId })
  }

  func testDoesNotMergeTwoSeriesThatDifferByCategory() throws {
    let first = try makeSeries(title: "Category Split", category: "utilities")
    _ = try makeSeries(title: "Category Split", category: "food")
    let firstId = try XCTUnwrap(first.id)

    let before = members(of: firstId).count
    XCTAssertEqual(linker.repairTransactionSeries(around: firstId), 0)
    XCTAssertEqual(members(of: firstId).count, before)
  }

  /// A row that already has a live, matching parent belongs to that parent — never steal it.
  func testDoesNotClaimARowThatHasALiveParent() throws {
    let keeper = try makeSeries(title: "Keeper", day: 5)
    let other = try makeSeries(title: "Other", day: 20)
    let keeperId = try XCTUnwrap(keeper.id)
    let otherId = try XCTUnwrap(other.id)

    let otherBefore = members(of: otherId).count
    _ = linker.repairTransactionSeries(around: keeperId)
    XCTAssertEqual(
      members(of: otherId).count, otherBefore,
      "Repairing one series must not take rows from another that is intact")
  }

  /// Two rows in one slot is the duplicate the whole design prevents.
  func testDoesNotRelinkIntoAnOccupiedSlot() throws {
    let parent = try makeSeries(title: "Occupied Slot")
    let parentId = try XCTUnwrap(parent.id)

    // A second, identical series occupies the same slots. Orphan one of ITS rows: the target series
    // already holds that slot, so the orphan must be left alone rather than doubled up.
    let anchor = Date().monthAnchor(offsetByMonths: 3)
    let duplicate = try XCTUnwrap(members(of: parentId).first { $0.seriesPeriod == anchor })
    let clone = TransactionModel(
      title: duplicate.title, category: duplicate.category.key, amount: duplicate.amount,
      type: duplicate.type.key, dateTimestamp: duplicate.dateTimestamp,
      budgetMonthDate: duplicate.budgetMonthDate, parentTransactionId: 999_999,
      unadjustedDateTimestamp: duplicate.unadjustedDateTimestamp, seriesPeriod: anchor)
    let cloneId = try transactionRepo.insertTransactionAndGetId(clone)
    TransactionRepository.invalidateCache()

    XCTAssertEqual(
      linker.repairTransactionSeries(around: parentId), 0,
      "An orphan whose slot is already held must not be adopted")
    let after = try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == cloneId })
    XCTAssertNotEqual(after.parentTransactionId, parentId)
  }

  /// Amount is checked against the set of amounts the series has HELD, not the parent's current
  /// one. A stale orphan carries a previous amount — that is what makes it stale — so a stricter
  /// check would reject exactly the rows this exists to adopt.
  func testAmountComparisonUsesTheSeriesAmountHistory() throws {
    let parent = try makeSeries(title: "In Effect", amount: 100_000)
    let parentId = try XCTUnwrap(parent.id)

    // Raise everything from month +2 onward to 200_000; months before keep 100_000.
    let editAnchor = Date().monthAnchor(offsetByMonths: 2)
    let editRow = try XCTUnwrap(members(of: parentId).first { $0.seriesPeriod == editAnchor })
    let newData = TransactionModel(
      id: editRow.id, title: "In Effect", category: "utilities", amount: 200_000, type: "expense",
      dateTimestamp: editRow.dateTimestamp, budgetMonthDate: editAnchor, isRecurring: true,
      hasInstallments: false, parentTransactionId: parentId, originalAmount: 200_000)
    try recurringManager.editRecurringTransactionsFromDate(
      parentTransactionId: parentId, selectedTransactionDate: editRow.unadjustedDate,
      editOption: .futureOnly, newData: newData)
    TransactionRepository.invalidateCache()

    // Orphan a LATER month, which now holds 200_000 while the parent still holds 100_000.
    let laterAnchor = Date().monthAnchor(offsetByMonths: 8)
    let later = try XCTUnwrap(members(of: parentId).first { $0.seriesPeriod == laterAnchor })
    XCTAssertEqual(later.amount, 200_000, "Precondition: the later month took the edit")
    try orphan(later)

    XCTAssertEqual(
      linker.repairTransactionSeries(around: parentId), 1,
      "Comparing against the parent's stale amount would refuse exactly the rows that need adopting")
  }

  /// Relinking must not disturb sync identity — it writes one integer column and nothing else.
  func testRelinkPreservesCKRecordIdAndUuid() throws {
    let parent = try makeSeries(title: "Identity Safe")
    let parentId = try XCTUnwrap(parent.id)

    let anchor = Date().monthAnchor(offsetByMonths: 5)
    let victim = try XCTUnwrap(members(of: parentId).first { $0.seriesPeriod == anchor })
    let victimId = try XCTUnwrap(victim.id)

    let ckBefore = transactionRepo.fetchCKRecordName(for: victimId)
    let uuidBefore = DBHelper.shared.uuidIdentity(table: "Transactions", localId: victimId)?.uuid

    try orphan(victim)
    _ = linker.repairTransactionSeries(around: parentId)

    XCTAssertEqual(transactionRepo.fetchCKRecordName(for: victimId), ckBefore)
    XCTAssertEqual(
      DBHelper.shared.uuidIdentity(table: "Transactions", localId: victimId)?.uuid, uuidBefore,
      "A relink must never re-key a row — that would read as delete+create on other devices")
  }
}
