//
//  CardRoutingUnadjustedDateTests.swift
//  FinovaTests
//
//  A card purchase is routed to a billing cycle by the day it was made, before any business-day
//  shift. The re-routing pass used the SHIFTED date instead, so a purchase made on a Saturday just
//  before the closing day, shown on the Monday after it, moved to the next month's statement on the
//  next dashboard load.
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
        UIDUserDefaultsManager.shared.currentUserUID = uid
        transactionRepo = TransactionRepository()
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        UIDUserDefaultsManager.shared.signOut()
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
                    name: "ClosesSunday", lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: 16, dueDay: 25, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))
        let service = CreditCardService()

        // What creation does: route by the picked day, store the day the rule shifted it to.
        let statement = try XCTUnwrap(
            service.getOrCreateStatement(for: card, transactionDate: saturday, userId: uid))
        let statementId = try XCTUnwrap(statement.id)
        XCTAssertEqual(
            statement.closingDate, calendar.date(from: DateComponents(year: 2030, month: 6, day: 16)),
            "Precondition: Saturday is before the closing day, and Monday is after it")

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
            "Made before the closing day, so the shifted date must not move it a cycle later")
    }

    func testATripToAnotherTimeZoneDoesNotMoveAPurchase() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/Sao_Paulo")!

        let calendar = Calendar.current
        let closingDay = calendar.date(from: DateComponents(year: 2030, month: 6, day: 17))!
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: "Traveller", lastFourDigits: "4243", cardBrand: .visa,
                    closingDay: 17, dueDay: 25, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))
        let service = CreditCardService()

        // Made on the closing day, at home, so it is on the next statement.
        let statement = try XCTUnwrap(
            service.getOrCreateStatement(for: card, transactionDate: closingDay, userId: uid))
        let statementId = try XCTUnwrap(statement.id)
        let txId = try transactionRepo.insertTransactionAndGetId(
            TransactionModel(
                title: "At home", category: "market", amount: 12000, type: "expense",
                dateTimestamp: Int(closingDay.timeIntervalSince1970),
                budgetMonthDate: closingDay.monthAnchor,
                businessDayRule: .nextBusinessDay,
                unadjustedDateTimestamp: Int(closingDay.timeIntervalSince1970)))
        try transactionRepo.updateCreditCardFields(
            transactionId: txId, creditCardId: cardId, statementId: statementId,
            isCreditCardStatement: false)
        TransactionRepository.invalidateCache()

        // In Los Angeles that midnight reads as the evening before the closing day.
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        service.reassignMisplacedTransactions(userId: uid, transactionRepo: transactionRepo)
        TransactionRepository.invalidateCache()

        let rows = transactionRepo.fetchAllTransactions()
        XCTAssertFalse(rows.isEmpty, "Precondition: the row can be read back")
        let row = try XCTUnwrap(rows.first { $0.id == txId })
        XCTAssertEqual(row.statementId, statementId, "A trip must not move a saved purchase")
    }
}
