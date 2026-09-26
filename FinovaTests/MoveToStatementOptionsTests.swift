//
//  MoveToStatementOptionsTests.swift
//  FinovaTests
//
//  The move-to-statement list named each option by the month the statement CLOSES in, while the
//  details row names the current statement by the month it is DUE. On a card due on or before its
//  closing day, the row read "November" and the list still offered "November": a different statement.
//

import Foundation
import XCTest

@testable import Finova

final class MoveToStatementOptionsTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var uid: String!

    override func setUp() {
        super.setUp()
        uid = "test_move_statement_options_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = uid
        transactionRepo = TransactionRepository()
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    func testOptionsAreNamedByTheDueMonthOfTheStatementTheyMoveTo() throws {
        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: "DueEarly", lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: 25, dueDay: 5, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))
        let service = CreditCardService()
        let current = try XCTUnwrap(
            service.getOrCreateStatement(for: card, transactionDate: Date(), userId: uid))

        let txId = try transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Purchase", amount: 5000))
        try transactionRepo.updateCreditCardFields(
            transactionId: txId, creditCardId: cardId,
            statementId: try XCTUnwrap(current.id), isCreditCardStatement: false)
        TransactionRepository.invalidateCache()
        let tx = try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == txId })
        let statementCount = StatementRepository().fetchStatements(forCardId: cardId).count

        let options = TransactionDetailsViewModel(transactionRepository: transactionRepo, transaction: tx)
            .getMonthOptionsForMove()

        let formatter = DateFormatter.monthYearFormatter
        XCTAssertFalse(
            options.map(\.label).contains(formatter.string(from: current.dueDate)),
            "The row names the current statement by its due month; the list must not offer that name again")
        XCTAssertEqual(options.count, 8, "Nine months, minus the one that lands on the current statement")
        for option in options {
            let closing = service.calculateClosingDate(card: card, transactionDate: option.firstOfMonth)
            let due = service.calculateDueDate(closingDate: closing, card: card)
            XCTAssertEqual(option.label, formatter.string(from: due))
        }
        XCTAssertEqual(
            StatementRepository().fetchStatements(forCardId: cardId).count, statementCount,
            "Building the list creates no statements")
    }
}
