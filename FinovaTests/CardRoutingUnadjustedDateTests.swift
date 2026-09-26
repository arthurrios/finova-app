//
//  CardRoutingUnadjustedDateTests.swift
//  FinovaTests
//
//  A card purchase is routed to a billing cycle by the day it was made, before any business-day
//  shift. The re-routing pass used the SHIFTED date instead, so a purchase made on a Saturday that is
//  the card's closing day was created on that closing statement and then moved to the next month's
//  on the next dashboard load, because its shifted date (Monday) falls after the closing day.
//

import Foundation
import XCTest

@testable import Finova

final class CardRoutingUnadjustedDateTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var uid: String!

    override func setUp() {
        super.setUp()
        uid = "test_card_routing_unadjusted_\(UUID().uuidString)"
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

    func testReroutingKeepsAWeekendPurchaseOnTheCycleItWasMadeIn() throws {
        let calendar = Calendar.current
        let saturday = calendar.date(from: DateComponents(year: 2030, month: 6, day: 15))!
        let monday = calendar.date(from: DateComponents(year: 2030, month: 6, day: 17))!
        XCTAssertEqual(calendar.component(.weekday, from: saturday), 7, "Precondition: a Saturday")

        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: "ClosesSaturday", lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: 15, dueDay: 25, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))
        let service = CreditCardService()

        // What creation does: route by the picked day, store the day the rule shifted it to.
        let statement = try XCTUnwrap(
            service.getOrCreateStatement(for: card, transactionDate: saturday, userId: uid))
        let statementId = try XCTUnwrap(statement.id)
        XCTAssertEqual(statement.closingDate, saturday, "Precondition: the cycle closing that Saturday")

        let model = TransactionModel(
            title: "Weekend purchase",
            category: "market",
            amount: 12000,
            type: "expense",
            dateTimestamp: Int(monday.timeIntervalSince1970),
            budgetMonthDate: monday.monthAnchor,
            businessDayRule: .nextBusinessDay,
            unadjustedDateTimestamp: Int(saturday.timeIntervalSince1970)
        )
        let txId = try transactionRepo.insertTransactionAndGetId(model)
        try transactionRepo.updateCreditCardFields(
            transactionId: txId, creditCardId: cardId,
            statementId: statementId, isCreditCardStatement: false)
        TransactionRepository.invalidateCache()

        service.reassignMisplacedTransactions(userId: uid, transactionRepo: transactionRepo)
        TransactionRepository.invalidateCache()

        let row = try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == txId })
        XCTAssertEqual(
            row.statementId, statementId,
            "Made on the closing day, so it stays on the statement closing that day")
    }
}
