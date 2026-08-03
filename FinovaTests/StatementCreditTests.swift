//
//  StatementCreditTests.swift
//  FinovaTests
//
//  A credit on a card reduces the invoice. Summing `amount` without regard to type made an income
//  row raise the statement instead — a R$ 300 refund read as R$ 300 more owed.
//

import Foundation
import XCTest

@testable import Finova

final class StatementCreditTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var uid: String!

    override func setUp() {
        super.setUp()
        uid = "test_statement_credit_\(UUID().uuidString)"
        // Secure storage is the source of truth on this release.
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
        transactionRepo = TransactionRepository()
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        super.tearDown()
    }

    /// A card plus a statement to attach rows to.
    private func makeCardAndStatement() throws -> (card: CreditCard, statementId: Int) {
        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: "TestCard", lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: 28, dueDay: 5, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: true, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))
        let statement = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: Date(), userId: uid))
        return (card, try XCTUnwrap(statement.id))
    }

    private func attach(
        title: String, amount: Int, type: String, to statementId: Int, card: CreditCard
    ) throws {
        let model = TransactionModel(
            title: title,
            category: "market",
            amount: amount,
            type: type,
            dateTimestamp: Int(Date().timeIntervalSince1970),
            budgetMonthDate: Date().monthAnchor
        )
        let id = try transactionRepo.insertTransactionAndGetId(model)
        try transactionRepo.updateCreditCardFields(
            transactionId: id, creditCardId: try XCTUnwrap(card.id),
            statementId: statementId, isCreditCardStatement: false)
        TransactionRepository.invalidateCache()
    }

    func testACreditReducesTheStatementTotal() throws {
        let (card, statementId) = try makeCardAndStatement()

        try attach(title: "Purchase", amount: 50000, type: "expense", to: statementId, card: card)
        try attach(title: "Refund", amount: 20000, type: "income", to: statementId, card: card)

        let sum = try DBHelper.shared.getTransactionSumForStatement(statementId: statementId)

        XCTAssertEqual(
            sum, 30000,
            "R$ 500 charged minus a R$ 200 refund is R$ 300 owed — the refund must subtract, not add")
    }

    func testACreditAloneMakesTheStatementNegative() throws {
        let (card, statementId) = try makeCardAndStatement()

        try attach(title: "Refund", amount: 25000, type: "income", to: statementId, card: card)

        let sum = try DBHelper.shared.getTransactionSumForStatement(statementId: statementId)

        XCTAssertEqual(
            sum, -25000,
            "A statement holding only a credit is money owed BACK to the cardholder")
    }
}
