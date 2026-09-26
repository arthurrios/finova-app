//
//  StatementCreditRolloverTests.swift
//  FinovaTests
//
//  A credit larger than its statement carries to the card's next statements. The statement row used
//  to be skipped whenever its total was not positive, which dropped the rest of the credit: a
//  cancelled 3 x 100 purchase credited 300 on one statement, that statement charged nothing, and the
//  next two still charged 100 each, so the user paid 200 that had been refunded.
//

import Foundation
import XCTest

@testable import Finova

final class StatementCreditRolloverTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var addViewModel: AddTransactionModalViewModel!
    private var uid: String!

    override func setUp() {
        super.setUp()
        uid = "test_statement_rollover_\(UUID().uuidString)"
        // Secure storage is the source of truth on this release.
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
        transactionRepo = TransactionRepository()
        addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        SecureLocalDataManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCard(name: String) throws -> CreditCard {
        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: name, lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: 28, dueDay: 5, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        return try XCTUnwrap(repo.fetchCard(byId: cardId))
    }

    private func attach(
        title: String, amount: Int, type: String, to statementId: Int, cardId: Int
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
            transactionId: id, creditCardId: cardId,
            statementId: statementId, isCreditCardStatement: false)
        TransactionRepository.invalidateCache()
    }

    private func rows(for statementIds: [Int]) -> [Transaction] {
        CreditCardService().generateStatementTransactions(userId: uid)
            .filter { $0.statementId.map(statementIds.contains) ?? false }
    }

    // MARK: - Tests

    func testACancelledPurchaseIsNotChargedAgainOnTheLaterStatements() throws {
        let card = try makeCard(name: "Rollover")
        let cardId = try XCTUnwrap(card.id)
        let service = CreditCardService()

        // A 3 x 100 purchase, one installment on each of three consecutive statements.
        let start = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        let result = addViewModel.addTransactionWithInstallments(
            InstallmentTransactionData(
                title: "Headphones", totalAmount: 30000,
                date: DateFormatter.fullDateFormatter.string(from: start),
                category: "market", transactionType: "expense", installments: 3))
        guard case .success = result else { return XCTFail("Could not create the series: \(result)") }
        TransactionRepository.invalidateCache()
        let children = transactionRepo.fetchAllTransactions()
            .filter { $0.title == "Headphones" && $0.installmentNumber != nil }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
        XCTAssertEqual(children.count, 3)

        let first = try XCTUnwrap(service.getOrCreateStatement(for: card, transactionDate: start, userId: uid))
        let second = try XCTUnwrap(service.nextStatement(after: first, for: card, userId: uid))
        let third = try XCTUnwrap(service.nextStatement(after: second, for: card, userId: uid))
        let statementIds = try [first, second, third].map { try XCTUnwrap($0.id) }
        for (child, statementId) in zip(children, statementIds) {
            try transactionRepo.updateCreditCardFields(
                transactionId: try XCTUnwrap(child.id), creditCardId: cardId,
                statementId: statementId, isCreditCardStatement: false)
        }
        TransactionRepository.invalidateCache()
        XCTAssertEqual(
            rows(for: statementIds).map(\.amount), [10000, 10000, 10000],
            "Precondition: each statement charges its installment")

        // Cancelling credits the 300 on the next open statement, the first one.
        let child = try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == children[0].id })
        let refundId = try InstallmentCancellationService(transactionRepo: transactionRepo)
            .cancelPurchase(for: child)
        TransactionRepository.invalidateCache()
        let refund = try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == refundId })
        XCTAssertEqual(refund.statementId, statementIds[0], "Precondition: the credit lands on the first")

        XCTAssertTrue(
            rows(for: statementIds).isEmpty,
            "300 credited against 3 x 100 charged: none of the three statements charges anything")
        let payments = StatementPaymentService(transactionRepo: transactionRepo)
        XCTAssertEqual(payments.remainingBalance(statementId: statementIds[1]), 0)
        XCTAssertEqual(payments.remainingBalance(statementId: statementIds[2]), 0)
    }

    func testACreditOnOneCardDoesNotLowerAnotherCardsStatement() throws {
        let service = CreditCardService()
        let creditCard = try makeCard(name: "Refunded")
        let otherCard = try makeCard(name: "Other")
        let creditStatement = try XCTUnwrap(
            service.getOrCreateStatement(for: creditCard, transactionDate: Date(), userId: uid))
        let otherFirst = try XCTUnwrap(
            service.getOrCreateStatement(for: otherCard, transactionDate: Date(), userId: uid))
        let otherNext = try XCTUnwrap(service.nextStatement(after: otherFirst, for: otherCard, userId: uid))

        try attach(
            title: "Return", amount: 50000, type: "income",
            to: try XCTUnwrap(creditStatement.id), cardId: try XCTUnwrap(creditCard.id))
        for statement in [otherFirst, otherNext] {
            try attach(
                title: "Purchase", amount: 20000, type: "expense",
                to: try XCTUnwrap(statement.id), cardId: try XCTUnwrap(otherCard.id))
        }

        let otherIds = try [otherFirst, otherNext].map { try XCTUnwrap($0.id) }
        XCTAssertEqual(rows(for: otherIds).map(\.amount), [20000, 20000])
        XCTAssertTrue(rows(for: [try XCTUnwrap(creditStatement.id)]).isEmpty)
        let payments = StatementPaymentService(transactionRepo: transactionRepo)
        XCTAssertEqual(payments.remainingBalance(statementId: otherIds[0]), 20000)
        XCTAssertEqual(payments.remainingBalance(statementId: otherIds[1]), 20000)
    }
}
