//
//  StatementNotificationAmountTests.swift
//  FinovaTests
//
//  The figure in a statement reminder has to be the figure in the ledger, at the moment the
//  reminder is worked out - not the one the statement carried when it was first scheduled.
//

import Foundation
import XCTest

@testable import Finova

final class StatementNotificationAmountTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var stmtRepo: StatementRepository!
    private var paymentService: StatementPaymentService!
    private var createdCardIds: [Int] = []

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_stmt_notif_\(UUID().uuidString)"
        transactionRepo = TransactionRepository()
        stmtRepo = StatementRepository()
        paymentService = StatementPaymentService(transactionRepo: transactionRepo)
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        for cardId in createdCardIds {
            for statement in stmtRepo.fetchStatements(forCardId: cardId) {
                if let stmtId = statement.id { _ = stmtRepo.deleteStatement(statementId: stmtId) }
            }
            _ = CreditCardRepository().deleteCard(id: cardId)
        }
        createdCardIds = []
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeCard() -> CreditCard? {
        let repo = CreditCardRepository()
        let id = repo.insertCard(
            CreditCard(
                name: "TestCard", lastFourDigits: "4242", cardBrand: .visa,
                closingDay: 28, dueDay: 5, creditLimit: 5_000_000,
                cardColor: .blue, userId: UIDUserDefaultsManager.shared.currentUserUID ?? "",
                isDeleted: false, isDefault: true, createdAt: Date(), updatedAt: Date()))
        guard let id = id else { return nil }
        createdCardIds.append(id)
        return repo.fetchCard(byId: id)
    }

    /// A card with one charge on an open cycle, mirroring `StatementPaymentTests`.
    private func makeStatementWithCharge(amount: Int) throws -> (CreditCard, CreditCardStatement) {
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let card = try XCTUnwrap(makeCard())
        let cardId = try XCTUnwrap(card.id)
        let date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

        let statement = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(for: card, transactionDate: date, userId: uid))
        _ = try addCharge(amount: amount, to: statement, cardId: cardId, on: date)
        return (card, try reload(statement))
    }

    @discardableResult
    private func addCharge(
        amount: Int, to statement: CreditCardStatement, cardId: Int, on date: Date
    ) throws -> Int {
        let stmtId = try XCTUnwrap(statement.id)
        let chargeId = try transactionRepo.insertTransactionAndGetId(
            TransactionModel(
                title: "Charge \(amount)",
                category: TransactionCategory.market.key,
                amount: amount,
                type: TransactionType.expense.key,
                dateTimestamp: Int(date.timeIntervalSince1970),
                budgetMonthDate: date.monthAnchor))
        try transactionRepo.updateCreditCardFields(
            transactionId: chargeId, creditCardId: cardId, statementId: stmtId,
            isCreditCardStatement: false)
        TransactionRepository.invalidateCache()
        stmtRepo.recalculateTotal(statementId: stmtId)
        return chargeId
    }

    private func reload(_ statement: CreditCardStatement) throws -> CreditCardStatement {
        try XCTUnwrap(
            stmtRepo.fetchStatements(forCardId: statement.creditCardId)
                .first { $0.id == statement.id })
    }

    /// What the notifications would say about this statement right now.
    private func plannedAmounts(for statement: CreditCardStatement, card: CreditCard) throws -> [Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return StatementNotificationPlan.plan(
            statementId: try XCTUnwrap(statement.id),
            cardName: card.name,
            closingDate: statement.closingDate,
            dueDate: statement.dueDate,
            totalAmount: statement.totalAmount,
            isPaid: statement.isPaid,
            // Far enough back that both dates are ahead of "now" and inside the horizon, so the
            // test is about the amount and not about the calendar.
            calendar: cal,
            now: cal.date(byAdding: .day, value: -1, to: statement.closingDate)!
        ).map(\.amountMinor)
    }

    // MARK: - Tests

    func testTheReminderNamesTheChargeOnTheStatement() throws {
        let (card, statement) = try makeStatementWithCharge(amount: 100_000)

        XCTAssertEqual(try plannedAmounts(for: statement, card: card), [100_000, 100_000])
    }

    func testASecondChargeMovesTheFigureInTheReminder() throws {
        let (card, statement) = try makeStatementWithCharge(amount: 100_000)
        let cardId = try XCTUnwrap(card.id)
        let date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

        try addCharge(amount: 45_500, to: statement, cardId: cardId, on: date)
        let reloaded = try reload(statement)

        XCTAssertEqual(reloaded.totalAmount, 145_500)
        XCTAssertEqual(
            try plannedAmounts(for: reloaded, card: card), [145_500, 145_500],
            "The reminder must follow the statement, not the total it had when first scheduled")
    }

    func testAPartialPaymentLeavesTheReminderNamingWhatIsStillOwed() throws {
        let (card, statement) = try makeStatementWithCharge(amount: 100_000)

        try paymentService.pay(
            statement: statement, card: card, amount: 40_000, paymentDate: Date())
        let reloaded = try reload(statement)

        XCTAssertFalse(reloaded.isPaid, "40,000 of 100,000 does not settle it")
        XCTAssertEqual(
            try plannedAmounts(for: reloaded, card: card), [60_000, 60_000],
            "Reminding the user of the full amount after a part payment is the bug this pins")
    }

    func testPayingInFullSilencesTheReminder() throws {
        let (card, statement) = try makeStatementWithCharge(amount: 100_000)

        try paymentService.pay(
            statement: statement, card: card, amount: 100_000, paymentDate: Date())
        let reloaded = try reload(statement)

        XCTAssertTrue(reloaded.isPaid)
        XCTAssertEqual(
            try plannedAmounts(for: reloaded, card: card), [],
            "A settled invoice must stop reminding, and must never name a zero balance")
    }
}
