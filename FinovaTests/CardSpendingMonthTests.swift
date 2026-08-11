//
//  CardSpendingMonthTests.swift
//  FinovaTests
//
//  A card expense belongs to the month it was SPENT in, not the month the card bills it.
//
//  Moving a transaction onto another statement used to stamp that statement's DUE month onto
//  `budget_month_date`. A due date almost always falls in the month after the purchase, so the
//  expense was charged to the following month's category allocation.
//

import Foundation
import XCTest

@testable import Finova

final class CardSpendingMonthTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var cardRepo: CreditCardRepository!
  private var service: CreditCardService!
  private var uid: String!

  override func setUp() {
    super.setUp()
    uid = "test_card_month_\(UUID().uuidString)"
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
    transactionRepo = TransactionRepository()
    cardRepo = CreditCardRepository()
    service = CreditCardService()
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    transactionRepo.clearAllTransactionsForTesting()
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

  private func attachedPurchase(
    title: String, on statementId: Int, card: CreditCard, at date: Date
  ) throws -> Int {
    let id = try transactionRepo.insertTransactionAndGetId(
      TransactionModel(
        title: title,
        category: "meals",
        amount: 4_500,
        type: "expense",
        dateTimestamp: Int(date.timeIntervalSince1970),
        budgetMonthDate: date.monthAnchor))
    try transactionRepo.updateCreditCardFields(
      transactionId: id, creditCardId: try XCTUnwrap(card.id),
      statementId: statementId, isCreditCardStatement: false)
    return id
  }

  private func transaction(id: Int) throws -> Transaction {
    try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == id })
  }

  // MARK: - Moving a transaction between statements

  func testMovingATransactionToAnotherStatementKeepsItsSpendingMonth() throws {
    let card = try makeCard()
    let purchaseDate = Date()
    let purchaseMonth = purchaseDate.monthAnchor

    let firstStatement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: purchaseDate, userId: uid))
    let txId = try attachedPurchase(
      title: "Lunch", on: try XCTUnwrap(firstStatement.id), card: card, at: purchaseDate)

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

  // MARK: - Repair of already-stamped rows

  func testRepairMovesAlreadyStampedRowsBackToTheirSpendingMonth() throws {
    let card = try makeCard()
    let purchaseDate = Date()
    let purchaseMonth = purchaseDate.monthAnchor
    let statement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: purchaseDate, userId: uid))
    let txId = try attachedPurchase(
      title: "Dinner", on: try XCTUnwrap(statement.id), card: card, at: purchaseDate)

    // Reproduce the damage the old move path left behind.
    DBHelper.shared.setStatementOverridden(transactionId: txId, overridden: true)
    let dueMonth = statement.dueDate.monthAnchor
    transactionRepo.updateBudgetMonthDate(transactionId: txId, newBudgetMonthDate: dueMonth)
    XCTAssertNotEqual(dueMonth, purchaseMonth, "Fixture is only meaningful if the months differ")

    let fixed = service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo)

    XCTAssertEqual(fixed, 1, "The stamped row should be the one row repaired")
    XCTAssertEqual(
      try transaction(id: txId).budgetMonthDate, purchaseMonth,
      "The repair puts the expense back in the month it was spent")
    XCTAssertEqual(
      service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo), 0,
      "A second pass has nothing left to move")
  }

  /// The bound that keeps the repair honest: a purchase nobody moved was never damaged.
  func testRepairLeavesAnUnmovedCardPurchaseAlone() throws {
    let card = try makeCard()
    let statement = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: Date(), userId: uid))
    let txId = try attachedPurchase(
      title: "Groceries", on: try XCTUnwrap(statement.id), card: card, at: Date())
    let before = try transaction(id: txId).budgetMonthDate

    XCTAssertEqual(
      service.repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo), 0,
      "A plain, never-moved card purchase is not part of the damaged population")
    XCTAssertEqual(try transaction(id: txId).budgetMonthDate, before)
  }
}
