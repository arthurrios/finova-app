//
//  CardSpendingMonthTests.swift
//  FinovaTests
//
//  A card expense belongs to the month it was SPENT in, not the month the card bills it.
//
//  `date` and `budget_month_date` answer different questions — when the money leaves, and which
//  month's category allocation the purchase consumes — and every statement remap used to write both.
//  Since a due date almost always falls in the month after the purchase, that pushed each affected
//  expense, in every category, into the following month's budget.
//

import Foundation
import XCTest

@testable import Finova

final class CardSpendingMonthTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var addViewModel: AddTransactionModalViewModel!
  private var cardRepo: CreditCardRepository!
  private var service: CreditCardService!
  private var uid: String!

  override func setUp() {
    super.setUp()
    uid = "test_card_month_\(UUID().uuidString)"
    UIDUserDefaultsManager.shared.currentUserUID = uid
    transactionRepo = TransactionRepository()
    addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
    cardRepo = CreditCardRepository()
    service = CreditCardService()
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    transactionRepo.clearAllTransactionsForTesting()
    UIDUserDefaultsManager.shared.signOut()
    super.tearDown()
  }

  // MARK: - Helpers

  /// A card that closes on the 28th and falls due on the 5th — so a purchase is billed in the
  /// FOLLOWING month, which is the whole point of these tests.
  private func makeCard() throws -> CreditCard {
    let cardId = try XCTUnwrap(
      cardRepo.insertCard(
        CreditCard(
          name: "TestCard", lastFourDigits: "4242", cardBrand: .visa,
          closingDay: 28, dueDay: 5, creditLimit: 5_000_000,
          cardColor: .blue, userId: uid,
          isDeleted: false, isDefault: true, createdAt: Date(), updatedAt: Date())))
    return try XCTUnwrap(cardRepo.fetchCard(byId: cardId))
  }

  private func transaction(id: Int) throws -> Transaction {
    TransactionRepository.invalidateCache()
    return try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == id })
  }

  // MARK: - Moving a transaction between statements

  /// `moveTransactionToStatement` used to stamp the target statement's due month onto
  /// `budget_month_date`. Moving a meal to next month's invoice is a statement of when the CARD
  /// bills it — it does not change the month the meal was eaten in.
  func testMovingATransactionToAnotherStatementKeepsItsSpendingMonth() throws {
    let card = try makeCard()
    let purchaseDate = Date()
    let purchaseMonth = purchaseDate.monthAnchor

    let firstStatement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: purchaseDate, userId: uid))
    let txId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "Lunch", category: "meals", amount: 4_500, type: "expense",
        dateTimestamp: Int(purchaseDate.timeIntervalSince1970),
        budgetMonthDate: purchaseMonth))
    try transactionRepo.updateCreditCardFields(
      transactionId: txId, creditCardId: try XCTUnwrap(card.id),
      statementId: try XCTUnwrap(firstStatement.id), isCreditCardStatement: false)

    // Push it onto a later invoice, the way the transaction-details screen does.
    let laterDate = Calendar.current.date(byAdding: .month, value: 2, to: purchaseDate)!
    let laterStatement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: laterDate, userId: uid))
    service.moveTransactionToStatement(
      transactionId: txId,
      creditCardId: try XCTUnwrap(card.id),
      toStatementId: try XCTUnwrap(laterStatement.id),
      fromStatementId: firstStatement.id,
      transactionRepo: transactionRepo)

    let moved = try transaction(id: txId)
    XCTAssertEqual(moved.statementId, laterStatement.id, "The move itself must still happen")
    XCTAssertEqual(
      moved.budgetMonthDate, purchaseMonth,
      "The meal still consumed the allocation of the month it was bought in")
  }

  // MARK: - Installments

  /// Each installment's ledger date is moved onto its statement's due date — that is when the money
  /// leaves — while its budget month stays on its own occurrence month.
  ///
  /// The remap is exercised through `updateStatementDueDate`, which is the single writer every
  /// production path now uses. Creating the series with a `creditCardId` would not do: statement
  /// assignment there is gated on `AuthenticationManager.shared.currentUser`, which no unit test has,
  /// so the children would come back with no card at all and the test would prove nothing.
  func testInstallmentsAreBudgetedInTheirOwnMonthNotTheDueMonth() throws {
    let card = try makeCard()
    // The 20th: after it, this card's cycle closes on the 28th and falls due on the 5th of the
    // NEXT month, so due-month and purchase-month genuinely differ.
    let start = try XCTUnwrap(
      Calendar.current.date(
        from: DateComponents(
          year: Calendar.current.component(.year, from: Date()),
          month: Calendar.current.component(.month, from: Date()),
          day: 20)))

    let result = addViewModel.addTransactionWithInstallments(
      InstallmentTransactionData(
        title: "Headphones",
        totalAmount: 60_000,
        date: DateFormatter.fullDateFormatter.string(from: start),
        category: "meals",
        transactionType: "expense",
        installments: 3))
    guard case .success = result else {
      return XCTFail("Could not create the installment fixture: \(result)")
    }

    TransactionRepository.invalidateCache()
    let children = transactionRepo.fetchAllTransactions()
      .filter { $0.installmentNumber != nil }
      .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    XCTAssertEqual(children.count, 3, "Three installments should exist")

    for child in children {
      let number = try XCTUnwrap(child.installmentNumber)
      let childId = try XCTUnwrap(child.id)
      let occurrence = Calendar.current.date(byAdding: .month, value: number - 1, to: start)!
      let statement = try XCTUnwrap(
        service.getOrCreateStatement(for: card, transactionDate: occurrence, userId: uid))

      try transactionRepo.updateCreditCardFields(
        transactionId: childId, creditCardId: try XCTUnwrap(card.id),
        statementId: try XCTUnwrap(statement.id), isCreditCardStatement: false)
      transactionRepo.updateStatementDueDate(
        transactionId: childId,
        newDateTimestamp: Int(statement.dueDate.timeIntervalSince1970))

      let remapped = try transaction(id: childId)
      XCTAssertEqual(
        remapped.dateTimestamp, Int(statement.dueDate.timeIntervalSince1970),
        "Installment #\(number) leaves the account when its invoice falls due")
      XCTAssertEqual(
        remapped.budgetMonthDate, start.monthAnchor(offsetByMonths: number - 1),
        "Installment #\(number) is spent in its own month, not the month its invoice falls due")
      XCTAssertNotEqual(
        statement.dueDate.monthAnchor, remapped.budgetMonthDate,
        "Fixture is only meaningful while the due month and the spending month differ")
    }
  }

  // MARK: - Repair of already-stamped rows

  func testRepairMovesAlreadyStampedRowsBackToTheirSpendingMonth() throws {
    let card = try makeCard()
    let purchaseDate = Date()
    let purchaseMonth = purchaseDate.monthAnchor
    let statement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: purchaseDate, userId: uid))

    let txId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "Dinner", category: "meals", amount: 7_000, type: "expense",
        dateTimestamp: Int(purchaseDate.timeIntervalSince1970),
        budgetMonthDate: purchaseMonth))
    try transactionRepo.updateCreditCardFields(
      transactionId: txId, creditCardId: try XCTUnwrap(card.id),
      statementId: try XCTUnwrap(statement.id), isCreditCardStatement: false)

    // Reproduce the damage the old write paths left behind: a row moved between statements is
    // flagged overridden, and the old code then stamped the statement's due month on it.
    DBHelper.shared.setStatementOverridden(transactionId: txId, overridden: true)
    let dueMonth = statement.dueDate.monthAnchor
    transactionRepo.updateBudgetMonthDate(transactionId: txId, newBudgetMonthDate: dueMonth)
    XCTAssertNotEqual(dueMonth, purchaseMonth, "Fixture is only meaningful if the months differ")

    let fixed = service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo)

    XCTAssertEqual(fixed, 1, "The stamped row should be the one row repaired")
    XCTAssertEqual(
      try transaction(id: txId).budgetMonthDate, purchaseMonth,
      "The repair puts the expense back in the month it was spent")
  }

  /// The repair reads only columns the remap never wrote, so running it twice changes nothing.
  func testRepairIsIdempotent() throws {
    let card = try makeCard()
    let statement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: Date(), userId: uid))
    let txId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "Coffee", category: "meals", amount: 900, type: "expense"))
    try transactionRepo.updateCreditCardFields(
      transactionId: txId, creditCardId: try XCTUnwrap(card.id),
      statementId: try XCTUnwrap(statement.id), isCreditCardStatement: false)
    DBHelper.shared.setStatementOverridden(transactionId: txId, overridden: true)
    transactionRepo.updateBudgetMonthDate(
      transactionId: txId, newBudgetMonthDate: statement.dueDate.monthAnchor)

    _ = service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo)
    let after = try transaction(id: txId).budgetMonthDate

    XCTAssertEqual(
      service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo), 0,
      "A second pass has nothing left to move")
    XCTAssertEqual(try transaction(id: txId).budgetMonthDate, after)
  }

  /// The bound that keeps the repair honest: a plain card purchase was never damaged, so nothing
  /// may recompute its month — least of all a business-day-adjusted one, whose correct month is the
  /// ADJUSTED one and would be dragged backwards by the unadjusted date.
  func testRepairLeavesAnUndamagedCardPurchaseAlone() throws {
    let card = try makeCard()
    let statement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: Date(), userId: uid))
    let txId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "Groceries", category: "market", amount: 12_000, type: "expense"))
    try transactionRepo.updateCreditCardFields(
      transactionId: txId, creditCardId: try XCTUnwrap(card.id),
      statementId: try XCTUnwrap(statement.id), isCreditCardStatement: false)
    let before = try transaction(id: txId).budgetMonthDate

    XCTAssertEqual(
      service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo), 0,
      "A plain, never-moved card purchase is not part of the damaged population")
    XCTAssertEqual(try transaction(id: txId).budgetMonthDate, before)
  }
}
