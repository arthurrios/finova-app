//
//  RecurringMaterializationTests.swift
//  FinovaTests
//
//  A recurring series must materialize EVERY month from its own start through the horizon, eagerly,
//  with no gaps — and nothing may materialize in response to a read.
//

import Foundation
import XCTest

@testable import Finova

final class RecurringMaterializationTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var addViewModel: AddTransactionModalViewModel!
  private var recurringManager: RecurringTransactionManager!

  override func setUp() {
    super.setUp()
    UIDUserDefaultsManager.shared.currentUserUID = "test_materialize_\(UUID().uuidString)"
    transactionRepo = TransactionRepository()
    addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
    recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    transactionRepo.clearAllTransactionsForTesting()
    UIDUserDefaultsManager.shared.signOut()
    super.tearDown()
  }

  // MARK: - Helpers

  @discardableResult
  private func createSeries(
    title: String,
    amount: Int = 100_000,
    startingMonthsFromNow offset: Int,
    day: Int = 10,
    category: String = "utilities",
    rule: BusinessDayRule = .exact
  ) throws -> Transaction {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let anchor = Date().monthAnchor(offsetByMonths: offset)
    var parts = cal.dateComponents([.year, .month], from: Date.fromMonthAnchor(anchor))
    parts.day = day
    parts.hour = 12
    let start = try XCTUnwrap(cal.date(from: parts))

    let result = addViewModel.addTransaction(
      title: title,
      amount: amount,
      dateString: DateFormatter.fullDateFormatter.string(from: start),
      categoryKey: category,
      typeRaw: "expense",
      isRecurring: true,
      businessDayRule: rule)
    guard case .success = result else {
      throw XCTSkip("Could not create the recurring fixture: \(result)")
    }
    TransactionRepository.invalidateCache()

    return try XCTUnwrap(
      transactionRepo.fetchAllTransactions().first {
        $0.title == title && $0.isRecurring == true
      }, "Recurring parent should exist")
  }

  /// Every slot the series occupies, ascending.
  private func slots(ofSeries parentId: Int) -> [Int] {
    TransactionRepository.invalidateCache()
    return transactionRepo.fetchAllTransactions()
      .filter { $0.id == parentId || $0.parentTransactionId == parentId }
      .map { $0.seriesPeriod }
      .sorted()
  }

  private func assertContiguous(
    _ slots: [Int], from start: Int, through end: Int, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let expected = SeriesMonths.anchors(from: start, through: end)
    XCTAssertEqual(
      slots, expected,
      "Series should hold exactly one occurrence per month from \(start) through \(end), with no gaps",
      file: file, line: line)
  }

  // MARK: - Gap-free materialization

  /// The headline bug: a series created while scrolled back to a past month left every month
  /// between its start and today empty, because the horizon was anchored on `now` rather than on
  /// `max(now, start)`.
  func testSeriesStartedInThePastFillsEveryMonthFromItsStart() throws {
    let parent = try createSeries(title: "Past Rent", startingMonthsFromNow: -6)
    let parentId = try XCTUnwrap(parent.id)

    assertContiguous(
      slots(ofSeries: parentId),
      from: parent.seriesPeriod,
      through: SeriesMonths.horizonAnchor(start: parent.seriesPeriod))
  }

  func testSeriesStartedInAFutureMonthFillsFromThatMonth() throws {
    let parent = try createSeries(title: "Future Rent", startingMonthsFromNow: 5)
    let parentId = try XCTUnwrap(parent.id)

    assertContiguous(
      slots(ofSeries: parentId),
      from: parent.seriesPeriod,
      through: SeriesMonths.horizonAnchor(start: parent.seriesPeriod))
  }

  /// The carousel renders -12…+24, so every one of those months must exist for a series that starts
  /// today. The horizon runs further (+36) on purpose, as slack.
  func testEveryCarouselMonthIsMaterializedAfterCreation() throws {
    let parent = try createSeries(title: "Carousel Rent", startingMonthsFromNow: 0)
    let parentId = try XCTUnwrap(parent.id)
    let held = Set(slots(ofSeries: parentId))

    for offset in 0...SeriesMonths.carouselRange.upperBound {
      let anchor = Date().monthAnchor(offsetByMonths: offset)
      XCTAssertTrue(held.contains(anchor), "Carousel month at offset \(offset) should exist")
    }
  }

  /// An unrelated one-off that happens to share a title and a day must not punch a hole in a series.
  /// The old duplicate guard keyed on `title | month | day` across EVERY row in the ledger.
  func testAnUnrelatedOneOffOnTheSameDayDoesNotBlockAMonth() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let conflictAnchor = Date().monthAnchor(offsetByMonths: 3)
    var parts = cal.dateComponents([.year, .month], from: Date.fromMonthAnchor(conflictAnchor))
    parts.day = 10
    parts.hour = 12
    let conflictDate = try XCTUnwrap(cal.date(from: parts))

    // A NON-recurring transaction, same title and same day, three months out.
    let oneOff = addViewModel.addTransaction(
      title: "Shared Name",
      amount: 100_000,
      dateString: DateFormatter.fullDateFormatter.string(from: conflictDate),
      categoryKey: "utilities",
      typeRaw: "expense",
      isRecurring: false)
    guard case .success = oneOff else { throw XCTSkip("Could not create the one-off fixture") }
    TransactionRepository.invalidateCache()

    let parent = try createSeries(title: "Shared Name", startingMonthsFromNow: 0)
    let parentId = try XCTUnwrap(parent.id)

    XCTAssertTrue(
      Set(slots(ofSeries: parentId)).contains(conflictAnchor),
      "A one-off sharing the title and day must not block the series' own month")
  }

  /// Two genuinely distinct series that differ only by day of month must both fill completely.
  func testASameTitleSeriesOnADifferentDayStillGeneratesItsOwnHorizon() throws {
    let first = try createSeries(title: "Twin", startingMonthsFromNow: 0, day: 5)
    let second = try createSeries(title: "Twin", startingMonthsFromNow: 0, day: 20)

    let firstId = try XCTUnwrap(first.id)
    let secondId = try XCTUnwrap(second.id)
    XCTAssertNotEqual(firstId, secondId, "Different anchor days must not be linked into one series")

    assertContiguous(
      slots(ofSeries: firstId), from: first.seriesPeriod,
      through: SeriesMonths.horizonAnchor(start: first.seriesPeriod))
    assertContiguous(
      slots(ofSeries: secondId), from: second.seriesPeriod,
      through: SeriesMonths.horizonAnchor(start: second.seriesPeriod))
  }

  func testMaterializationIsIdempotent() throws {
    let parent = try createSeries(title: "Idempotent", startingMonthsFromNow: -2)
    let parentId = try XCTUnwrap(parent.id)
    let before = slots(ofSeries: parentId)

    XCTAssertEqual(
      recurringManager.materializeSeries(parentId: parentId), 0,
      "A second pass over a complete series must create nothing")
    XCTAssertEqual(slots(ofSeries: parentId), before)
  }

  func testDeletedMonthIsNotResurrected() throws {
    let parent = try createSeries(title: "Tombstoned", startingMonthsFromNow: 0)
    let parentId = try XCTUnwrap(parent.id)

    let victimAnchor = Date().monthAnchor(offsetByMonths: 4)
    let victim = try XCTUnwrap(
      transactionRepo.fetchAllTransactions().first {
        $0.parentTransactionId == parentId && $0.seriesPeriod == victimAnchor
      })
    try transactionRepo.deleteTransactionWithOption(
      id: try XCTUnwrap(victim.id), option: .currentSelection)
    TransactionRepository.invalidateCache()

    _ = recurringManager.materializeSeries(parentId: parentId)

    XCTAssertFalse(
      Set(slots(ofSeries: parentId)).contains(victimAnchor),
      "An intentionally deleted month must not be recreated by materialization")
  }

  // MARK: - Cleanup

  /// Cleanup must use the RETENTION range. Passing the carousel range deleted the twelve months
  /// creation had just generated.
  func testCleanupDoesNotDeleteMonthsCreationJustGenerated() throws {
    let parent = try createSeries(title: "Retained", startingMonthsFromNow: 0)
    let parentId = try XCTUnwrap(parent.id)
    let before = slots(ofSeries: parentId)

    recurringManager.cleanupRecurringInstancesOutsideRange(
      SeriesMonths.retentionRange, referenceDate: Date(), cleanupOption: .futureOnly)

    XCTAssertEqual(
      slots(ofSeries: parentId), before,
      "Cleanup over the retention range must not remove anything creation just materialized")
  }

  // MARK: - Business-day rules

  /// Under `.previous`/`.next` an occurrence's date can land in an adjacent month, so its
  /// accounting month and its slot diverge. The series must still hold exactly one occurrence per
  /// slot — no gaps, no doubles.
  func testBusinessDayRuleDoesNotCreateGapsOrDuplicateSlots() throws {
    for rule in [BusinessDayRule.previousBusinessDay, .nextBusinessDay] {
      let title = "Payday \(rule.rawValue)"
      // Day 1 with `.previous` is the case that pushes an occurrence into the PREVIOUS month.
      let parent = try createSeries(
        title: title, startingMonthsFromNow: -3, day: 1, rule: rule)
      let parentId = try XCTUnwrap(parent.id)

      let held = slots(ofSeries: parentId)
      assertContiguous(
        held, from: parent.seriesPeriod,
        through: SeriesMonths.horizonAnchor(start: parent.seriesPeriod))
      XCTAssertEqual(
        held.count, Set(held).count,
        "\(rule): every slot must be held exactly once, even when dates shift across months")
    }
  }

  /// The anchor day is read from the UNADJUSTED date, so a rule that shifts dates must not split a
  /// series into two by making its occurrences look like different series.
  func testRuleShiftedOccurrencesKeepOneSeriesIdentity() throws {
    let parent = try createSeries(
      title: "Rule Anchored", startingMonthsFromNow: 0, day: 1, rule: .previousBusinessDay)
    let parentId = try XCTUnwrap(parent.id)

    let members = transactionRepo.fetchAllTransactions()
      .filter { $0.id == parentId || $0.parentTransactionId == parentId }
    let anchorDays = Set(members.map { SeriesDay.anchorDay(of: $0) })

    XCTAssertEqual(
      anchorDays, [1],
      "Every occurrence's unadjusted anchor day must stay the series' day, whatever the rule did to its date")
  }
}
