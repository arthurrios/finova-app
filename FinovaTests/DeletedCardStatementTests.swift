//
//  DeletedCardStatementTests.swift
//  FinovaTests
//
//  Two ways card money used to land in the wrong place:
//  - Deleting a card dropped every one of its statements from the balance, though the delete prompt
//    promises its transactions are kept. Card purchases reach the balance only through their
//    statement row, so the whole card spend vanished from the balance history.
//  - `nextOpenStatement` on a card left unused for a while returned a statement that had already
//    closed, so an early payment or a cancellation credit landed on an invoice issued in the past.
//

import Foundation
import XCTest

@testable import Finova

final class DeletedCardStatementTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var uid: String!

    override func setUp() {
        super.setUp()
        uid = "test_deleted_card_statement_\(UUID().uuidString)"
        // Secure storage is the source of truth on this release.
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
        transactionRepo = TransactionRepository()
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        SecureLocalDataManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCard(name: String, closingDay: Int, dueDay: Int) throws -> CreditCard {
        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: name, lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: closingDay, dueDay: dueDay, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        return try XCTUnwrap(repo.fetchCard(byId: cardId))
    }

    private func attachPurchase(amount: Int, to statementId: Int, card: CreditCard) throws {
        let model = TransactionModel(
            title: "Purchase",
            category: "market",
            amount: amount,
            type: "expense",
            dateTimestamp: Int(Date().timeIntervalSince1970),
            budgetMonthDate: Date().monthAnchor
        )
        let id = try transactionRepo.insertTransactionAndGetId(model)
        try transactionRepo.updateCreditCardFields(
            transactionId: id, creditCardId: try XCTUnwrap(card.id),
            statementId: statementId, isCreditCardStatement: false)
        TransactionRepository.invalidateCache()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Deleted card

    func testADeletedCardStillChargesItsStatementsToTheBalance() throws {
        let card = try makeCard(name: "OldCard", closingDay: 28, dueDay: 5)
        let cardId = try XCTUnwrap(card.id)
        let statement = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: Date(), userId: uid))
        let statementId = try XCTUnwrap(statement.id)
        try attachPurchase(amount: 50000, to: statementId, card: card)

        let before = CreditCardService().generateStatementTransactions(userId: uid)
            .first { $0.statementId == statementId }
        XCTAssertEqual(before?.amount, 50000, "Precondition: the statement row charges the purchase")

        XCTAssertTrue(CreditCardRepository().deleteCard(id: cardId))

        let row = try XCTUnwrap(
            CreditCardService().generateStatementTransactions(userId: uid)
                .first { $0.statementId == statementId },
            "The purchase was made and is kept, so its statement must still reach the balance")
        XCTAssertEqual(row.amount, 50000)
        XCTAssertEqual(row.isCreditCardStatement, true)
        XCTAssertEqual(row.creditCardId, cardId)
        XCTAssertEqual(row.title, String(format: "creditCard.statement.title".localized, "OldCard"))

        XCTAssertFalse(
            CreditCardRepository().fetchAllCards(userId: uid).contains { $0.id == cardId },
            "The card itself stays hidden from every list")
    }

    // MARK: - Next open statement

    func testNextOpenStatementSkipsCyclesThatClosedWhileTheCardWasUnused() throws {
        let card = try makeCard(name: "Unused", closingDay: 10, dueDay: 20)
        let asOf = date(2030, 6, 15, hour: 12)
        // Last used in March: that statement closed on 10 March, and April and May closed too.
        let old = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: date(2030, 3, 5), userId: uid))
        XCTAssertLessThan(old.closingDate, asOf, "Precondition: the only statement is long closed")

        let target = try XCTUnwrap(
            CreditCardService().nextOpenStatement(for: card, userId: uid, asOf: asOf))

        XCTAssertGreaterThan(
            target.closingDate, asOf,
            "Money moved on 15 June must land on an invoice that has not been issued yet")
        XCTAssertEqual(target.closingDate, date(2030, 7, 10))
        XCTAssertFalse(target.isPaid)
        XCTAssertEqual(
            StatementRepository().fetchStatements(forCardId: try XCTUnwrap(card.id)).count, 2,
            "Only the target cycle is created, not an empty statement for every month skipped")
    }

    func testNextOpenStatementOnTheClosingDayOfACardWithNoStatements() throws {
        let card = try makeCard(name: "Fresh", closingDay: 10, dueDay: 20)
        // Midday on the closing day: the cycle closing today closed at the start of the day.
        let asOf = date(2030, 6, 10, hour: 12)

        let target = try XCTUnwrap(
            CreditCardService().nextOpenStatement(for: card, userId: uid, asOf: asOf))

        XCTAssertGreaterThan(target.closingDate, asOf)
        XCTAssertEqual(target.closingDate, date(2030, 7, 10))
    }
}
