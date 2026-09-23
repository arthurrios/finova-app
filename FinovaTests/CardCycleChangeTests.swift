//
//  CardCycleChangeTests.swift
//  FinovaTests
//
//  Two bugs reported on a real card:
//
//  1. Editing only the category of one installment made the series vanish from the statement: the
//     edit sheet pre-filled that installment's own date (its due date) as the series start, and the
//     save rebuilt all installments from there.
//  2. After changing a card's closing/due day, an installment stayed on a "ghost" statement with the
//     old dates, and installments on the surviving statement kept the old due date.
//

import Foundation
import XCTest

@testable import Finova

final class CardCycleChangeTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var addViewModel: AddTransactionModalViewModel!
  private var cardRepo: CreditCardRepository!
  private var stmtRepo: StatementRepository!
  private var service: CreditCardService!
  private var uid: String!
  private let calendar = Calendar.current

  override func setUp() {
    super.setUp()
    uid = "test_card_cycle_\(UUID().uuidString)"
    UIDUserDefaultsManager.shared.currentUserUID = uid
    transactionRepo = TransactionRepository()
    addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
    cardRepo = CreditCardRepository()
    stmtRepo = StatementRepository()
    service = CreditCardService()
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    transactionRepo.clearAllTransactionsForTesting()
    UIDUserDefaultsManager.shared.signOut()
    super.tearDown()
  }

  // MARK: - Helpers

  private func makeCard(closingDay: Int, dueDay: Int) throws -> CreditCard {
    let cardId = try XCTUnwrap(
      cardRepo.insertCard(
        CreditCard(
          name: "BTG", lastFourDigits: "1652", cardBrand: .visa,
          closingDay: closingDay, dueDay: dueDay, creditLimit: 5_000_000,
          cardColor: .blue, userId: uid,
          isDeleted: false, isDefault: true, createdAt: Date(), updatedAt: Date())))
    return try XCTUnwrap(cardRepo.fetchCard(byId: cardId))
  }

  private func transaction(id: Int) throws -> Transaction {
    TransactionRepository.invalidateCache()
    return try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == id })
  }

  private func children() -> [Transaction] {
    TransactionRepository.invalidateCache()
    return transactionRepo.fetchAllTransactions()
      .filter { $0.installmentNumber != nil }
      .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
  }

  /// A statement inserted directly, the way a ghost left over from the old card rules looks.
  private func insertStatement(cardId: Int, closing: Date, due: Date) throws -> CreditCardStatement {
    let stmt = CreditCardStatement(
      id: nil, creditCardId: cardId, closingDate: closing, dueDate: due,
      totalAmount: 0, isPaid: false, paidDate: nil, paidAmount: nil,
      isDatesOverridden: false, userId: uid, createdAt: Date(), updatedAt: Date())
    let id = try XCTUnwrap(stmtRepo.insertStatement(stmt))
    return try XCTUnwrap(stmtRepo.fetchStatements(forCardId: cardId).first { $0.id == id })
  }

  /// Links an installment to a statement and puts it on that statement's due date — what every
  /// production path does. (Creating the series with a card cannot do it in a unit test: statement
  /// assignment there needs `AuthenticationManager.shared.currentUser`.)
  private func link(_ txId: Int, to stmt: CreditCardStatement, cardId: Int) throws {
    try transactionRepo.updateCreditCardFields(
      transactionId: txId, creditCardId: cardId,
      statementId: try XCTUnwrap(stmt.id), isCreditCardStatement: false)
    transactionRepo.updateDateAndBudgetMonth(
      transactionId: txId,
      newDateTimestamp: Int(stmt.dueDate.timeIntervalSince1970),
      newBudgetMonthDate: stmt.dueDate.monthAnchor)
  }

  private func day(_ day: Int, monthsFromNow offset: Int) -> Date {
    let base = calendar.date(byAdding: .month, value: offset, to: Date())!
    return calendar.date(
      from: DateComponents(
        year: calendar.component(.year, from: base),
        month: calendar.component(.month, from: base),
        day: day))!
  }

  // MARK: - Bug 1: category edit

  func testEditingOnlyTheCategoryLeavesEveryInstallmentWhereItWas() throws {
    let card = try makeCard(closingDay: 1, dueDay: 5)
    let cardId = try XCTUnwrap(card.id)
    let start = day(10, monthsFromNow: -2)
    let startString = DateFormatter.fullDateFormatter.string(from: start)

    guard
      case .success = addViewModel.addTransactionWithInstallments(
        InstallmentTransactionData(
          title: "Seguro", totalAmount: 30_000, date: startString,
          category: "meals", transactionType: "expense", installments: 3))
    else { return XCTFail("Could not create the installment fixture") }

    for child in children() {
      let number = try XCTUnwrap(child.installmentNumber)
      let occurrence = calendar.date(byAdding: .month, value: number - 1, to: start)!
      let stmt = try XCTUnwrap(
        service.getOrCreateStatement(for: card, transactionDate: occurrence, userId: uid))
      try link(try XCTUnwrap(child.id), to: stmt, cardId: cardId)
    }
    let before = children()
    XCTAssertEqual(before.count, 3)

    // Edit installment #2 — the one the user sees on this month's invoice — and change only the
    // category. The sheet sends the series start date, the total and the count back unchanged.
    let edited = try XCTUnwrap(before[1].id)
    let result = addViewModel.updateTransactionWithInstallments(
      id: edited,
      InstallmentTransactionData(
        title: "Seguro", totalAmount: 30_000, date: startString,
        category: "gifts", transactionType: "expense", installments: 3,
        creditCardId: cardId))
    guard case .success = result else { return XCTFail("Edit failed: \(result)") }

    let after = children()
    XCTAssertEqual(after.map(\.id), before.map(\.id), "No installment may be deleted or recreated")
    XCTAssertEqual(after.map(\.statementId), before.map(\.statementId), "Every installment stays on its invoice")
    XCTAssertEqual(after.map(\.dateTimestamp), before.map(\.dateTimestamp), "Every installment keeps its date")
    XCTAssertEqual(after.map(\.budgetMonthDate), before.map(\.budgetMonthDate))
    XCTAssertTrue(after.allSatisfy { $0.category.key == "gifts" }, "The category change applies to the series")
  }

  /// Same edit on a synced series whose children point at a parent id this device does not hold —
  /// 23 such series were on the reporter's phone, HBO Max among them.
  func testEditingOnlyTheCategoryOfAnOrphanedSeriesLeavesItInPlace() throws {
    let card = try makeCard(closingDay: 1, dueDay: 5)
    let cardId = try XCTUnwrap(card.id)
    let start = day(10, monthsFromNow: -2)

    guard
      case .success = addViewModel.addTransactionWithInstallments(
        InstallmentTransactionData(
          title: "HBO Max", totalAmount: 41_880, date: DateFormatter.fullDateFormatter.string(from: start),
          category: "meals", transactionType: "expense", installments: 12))
    else { return XCTFail("Could not create the installment fixture") }

    var previous: CreditCardStatement?
    for child in children() {
      let stmt = try XCTUnwrap(
        previous.flatMap { service.nextStatement(after: $0, for: card, userId: uid) }
          ?? service.getOrCreateStatement(for: card, transactionDate: start, userId: uid))
      try link(try XCTUnwrap(child.id), to: stmt, cardId: cardId)
      previous = stmt
    }
    let parentId = try XCTUnwrap(children().first?.parentTransactionId)
    try DBHelper.shared.deleteTransaction(id: parentId)
    TransactionRepository.invalidateCache()

    let before = children()
    let edited = try XCTUnwrap(before[4].id)
    let seriesStart = try XCTUnwrap(
      AddTransactionModalViewModel.installmentSeriesStartDate(groupId: parentId, related: before))

    let result = addViewModel.updateTransactionWithInstallments(
      id: edited,
      InstallmentTransactionData(
        title: "HBO Max", totalAmount: 41_880,
        date: DateFormatter.fullDateFormatter.string(from: seriesStart),
        category: "gifts", transactionType: "expense", installments: 12,
        creditCardId: cardId))
    guard case .success = result else { return XCTFail("Edit failed: \(result)") }

    let after = children()
    XCTAssertEqual(after.map(\.id), before.map(\.id), "No installment may be deleted or recreated")
    XCTAssertEqual(after.map(\.statementId), before.map(\.statementId))
    XCTAssertEqual(after.map(\.dateTimestamp), before.map(\.dateTimestamp))
    XCTAssertTrue(after.allSatisfy { $0.category.key == "gifts" })
  }

  // MARK: - Bug 2: closing / due day change

  /// The user's state: the card is already on closing 1 / due 5, one statement for next month is
  /// on those dates, and a ghost for the SAME month is still on closing 6 / due 13 holding one
  /// installment. Installments on the surviving statement still carry the old due date.
  func testGhostStatementIsMergedAndInstallmentsMoveToTheNewDueDate() throws {
    let card = try makeCard(closingDay: 1, dueDay: 5)
    let cardId = try XCTUnwrap(card.id)

    let ghost = try insertStatement(
      cardId: cardId, closing: day(6, monthsFromNow: 1), due: day(13, monthsFromNow: 1))
    let current = try insertStatement(
      cardId: cardId, closing: day(1, monthsFromNow: 1), due: day(5, monthsFromNow: 1))

    let strandedId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "HBO Max", category: "meals", amount: 3_490, type: "expense",
        dateTimestamp: Int(ghost.dueDate.timeIntervalSince1970),
        budgetMonthDate: ghost.dueDate.monthAnchor,
        installmentNumber: 5, totalInstallments: 12))
    try link(strandedId, to: ghost, cardId: cardId)

    // On the surviving statement, but still dated on the OLD due day.
    let staleId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "Seguro Song", category: "meals", amount: 51_443, type: "expense",
        dateTimestamp: Int(ghost.dueDate.timeIntervalSince1970),
        budgetMonthDate: ghost.dueDate.monthAnchor,
        installmentNumber: 7, totalInstallments: 10))
    try transactionRepo.updateCreditCardFields(
      transactionId: staleId, creditCardId: cardId,
      statementId: try XCTUnwrap(current.id), isCreditCardStatement: false)

    let removed = service.mergeSameMonthOpenStatements(for: card, transactionRepo: transactionRepo)
    service.remapOpenInstallmentsToDueDate(cardId: cardId, transactionRepo: transactionRepo)

    XCTAssertEqual(removed, 1, "The ghost is the one statement removed")
    let remaining = stmtRepo.fetchStatements(forCardId: cardId)
    XCTAssertEqual(remaining.map(\.id), [current.id], "The statement on the current closing day survives")

    let stranded = try transaction(id: strandedId)
    XCTAssertEqual(stranded.statementId, current.id, "The stranded installment joins the real invoice")
    XCTAssertEqual(stranded.dateTimestamp, Int(current.dueDate.timeIntervalSince1970))

    let stale = try transaction(id: staleId)
    XCTAssertEqual(
      stale.dateTimestamp, Int(current.dueDate.timeIntervalSince1970),
      "An installment shows its invoice's due date, not the old one")
  }

  /// The reporter's exact shape: the ghost is OLDER (lower id) than the real invoice, and the card
  /// edit pass first moves both onto the same day — so the keeper must be the one with the rows.
  func testCardEditPassKeepsTheRealInvoiceWhenTheGhostIsOlder() throws {
    let card = try makeCard(closingDay: 1, dueDay: 5)
    let cardId = try XCTUnwrap(card.id)
    let ghost = try insertStatement(
      cardId: cardId, closing: day(6, monthsFromNow: 1), due: day(13, monthsFromNow: 1))
    let real = try insertStatement(
      cardId: cardId, closing: day(1, monthsFromNow: 1), due: day(5, monthsFromNow: 1))

    var realRows: [Int] = []
    for n in 1...3 {
      let id = try transactionRepo.insertTransactionAndGetId(
        CloudKitSyncTestHelpers.makeTransactionModel(
          title: "Seguro \(n)", category: "meals", amount: 1_000, type: "expense",
          dateTimestamp: 0, budgetMonthDate: 0, installmentNumber: n, totalInstallments: 10))
      try link(id, to: real, cardId: cardId)
      realRows.append(id)
    }
    let hboId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "HBO Max", category: "meals", amount: 3_490, type: "expense",
        dateTimestamp: 0, budgetMonthDate: 0, installmentNumber: 5, totalInstallments: 12))
    try link(hboId, to: ghost, cardId: cardId)

    service.recalculateStatementDatesForCard(
      card, userId: uid, transactionRepo: transactionRepo, respectingDateOverrides: true)

    XCTAssertEqual(stmtRepo.fetchStatements(forCardId: cardId).map(\.id), [real.id])
    for id in realRows + [hboId] {
      let tx = try transaction(id: id)
      XCTAssertEqual(tx.statementId, real.id)
      XCTAssertEqual(tx.dateTimestamp, Int(real.dueDate.timeIntervalSince1970))
    }
  }

  /// A ghost due on the OLD day 13 with no day-5 statement in its month: there is nothing to merge
  /// it into, so the launch pass must move the statement itself onto the current days.
  func testLoneGhostOnTheOldDueDayMovesToTheNewDays() throws {
    let card = try makeCard(closingDay: 1, dueDay: 5)
    let cardId = try XCTUnwrap(card.id)
    let ghost = try insertStatement(
      cardId: cardId, closing: day(6, monthsFromNow: 2), due: day(13, monthsFromNow: 2))

    let txId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "HBO Max", category: "meals", amount: 3_490, type: "expense",
        dateTimestamp: 0, budgetMonthDate: 0,
        installmentNumber: 6, totalInstallments: 12))
    try link(txId, to: ghost, cardId: cardId)

    service.recalculateStatementDatesForCard(
      card, userId: uid, transactionRepo: transactionRepo, respectingDateOverrides: true)

    let fixed = try XCTUnwrap(stmtRepo.fetchStatements(forCardId: cardId).first { $0.id == ghost.id })
    XCTAssertEqual(calendar.component(.day, from: fixed.closingDate), 1)
    XCTAssertEqual(
      Int(fixed.dueDate.timeIntervalSince1970),
      Int(service.calculateDueDate(closingDate: fixed.closingDate, card: card).timeIntervalSince1970),
      "The statement is no longer due on the old day 13")
    XCTAssertEqual(try transaction(id: txId).dateTimestamp, Int(fixed.dueDate.timeIntervalSince1970))
  }

  /// Editing the card itself: the open statement's dates move, and its installment moves with it.
  func testChangingTheDueDayMovesInstallmentsOnOpenStatements() throws {
    var card = try makeCard(closingDay: 6, dueDay: 13)
    let cardId = try XCTUnwrap(card.id)
    let stmt = try XCTUnwrap(
      service.getOrCreateStatement(for: card, transactionDate: day(3, monthsFromNow: 1), userId: uid))

    let txId = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: "Nike", category: "meals", amount: 45_499, type: "expense",
        dateTimestamp: 0, budgetMonthDate: 0,
        installmentNumber: 2, totalInstallments: 4))
    try link(txId, to: stmt, cardId: cardId)

    card.closingDay = 1
    card.dueDay = 5
    XCTAssertTrue(cardRepo.updateCard(card))
    service.recalculateStatementDatesForCard(card, userId: uid, transactionRepo: transactionRepo)

    let updated = try XCTUnwrap(stmtRepo.fetchStatements(forCardId: cardId).first { $0.id == stmt.id })
    XCTAssertEqual(calendar.component(.day, from: updated.closingDate), 1)

    let moved = try transaction(id: txId)
    XCTAssertEqual(moved.statementId, stmt.id)
    XCTAssertEqual(
      moved.dateTimestamp, Int(updated.dueDate.timeIntervalSince1970),
      "The installment follows its invoice to the new due date")
  }
}
