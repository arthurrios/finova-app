//
//  BalanceHistoryStartTests.swift
//  FinovaTests
//

import XCTest

@testable import Finova

/// Pins where the running balance starts counting (`BalanceHistoryStart`).
final class BalanceHistoryStartTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suiteName = "BalanceHistoryStartTests"
  private let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    return cal
  }()

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  private func tx(
    _ amount: Int, _ date: Date, _ type: TransactionType = .expense,
    card: Int? = nil, statement: Bool? = nil
  ) -> Transaction {
    Transaction(
      data: UITransactionData(
        id: nil, title: "t", amount: amount,
        dateTimestamp: Int(date.timeIntervalSince1970), budgetMonthDate: date.monthAnchor,
        isRecurring: nil, hasInstallments: nil, parentTransactionId: nil,
        installmentNumber: nil, totalInstallments: nil, originalAmount: nil,
        creditCardId: card, isCreditCardStatement: statement,
        category: .groceries, type: type))
  }

  func testAnAccountThatNeverAdjustedItsBalanceCountsTheWholeHistory() {
    let start = BalanceHistoryStart.anchor(
      uid: "u1", offset: 0, now: date(2026, 9, 25), defaults: defaults)
    XCTAssertNil(start)
  }

  func testAnAdjustedAccountStartsAtTheOldWindowAndTheStartNeverMovesAgain() {
    let now = date(2026, 9, 25)
    let expected = now.monthAnchor(offsetByMonths: SeriesMonths.carouselRange.lowerBound)

    let first = BalanceHistoryStart.anchor(uid: "u1", offset: 12_345, now: now, defaults: defaults)
    XCTAssertEqual(first, expected)

    // A year later, and after the offset changed, the start is still the one decided first.
    let later = BalanceHistoryStart.anchor(
      uid: "u1", offset: 99, now: date(2027, 9, 25), defaults: defaults)
    XCTAssertEqual(later, expected)
  }

  func testTheDecisionIsPerAccount() {
    let now = date(2026, 9, 25)
    _ = BalanceHistoryStart.anchor(uid: "adjusted", offset: 500, now: now, defaults: defaults)
    XCTAssertNil(BalanceHistoryStart.anchor(uid: "fresh", offset: 0, now: now, defaults: defaults))
  }

  func testNoSignedInUserCountsEverythingAndStoresNothing() {
    XCTAssertNil(BalanceHistoryStart.anchor(uid: nil, offset: 500, defaults: defaults))
    XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("balanceHistoryStart") }.isEmpty)
  }

  func testTransactionsOlderThanTheRangeStillCarryIntoIt() {
    let rows = [
      tx(1_000_00, date(2024, 3, 5), .income),
      tx(300_00, date(2025, 1, 10)),
      tx(50_00, date(2026, 9, 1)),  // inside the range: not part of the carry
    ]
    let firstAnchor = date(2025, 9, 1).monthAnchor
    XCTAssertEqual(
      BalanceHistoryStart.netBefore(anchor: firstAnchor, start: nil, transactions: rows), 700_00)
  }

  func testTheCarrySkipsCardPurchasesButCountsStatements() {
    let rows = [
      tx(80_00, date(2025, 2, 5), card: 1),
      tx(80_00, date(2025, 3, 10), card: 1, statement: true),
    ]
    let firstAnchor = date(2025, 9, 1).monthAnchor
    XCTAssertEqual(
      BalanceHistoryStart.netBefore(anchor: firstAnchor, start: nil, transactions: rows), -80_00)
  }

  func testTheCarryIgnoresRowsBeforeAFixedStart() {
    let rows = [
      tx(1_000_00, date(2024, 3, 5), .income),  // before the start: already in the offset
      tx(300_00, date(2025, 1, 10)),
    ]
    let start = date(2024, 9, 1).monthAnchor
    let firstAnchor = date(2025, 9, 1).monthAnchor
    XCTAssertEqual(
      BalanceHistoryStart.netBefore(anchor: firstAnchor, start: start, transactions: rows), -300_00)
  }
}
