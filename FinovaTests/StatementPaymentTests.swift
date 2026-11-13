//
//  StatementPaymentTests.swift
//  FinovaTests
//
//  Paying a credit-card statement, in part or in full.
//

import Foundation
import XCTest

@testable import Finova

final class StatementPaymentTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var addViewModel: AddTransactionModalViewModel!
    private var stmtRepo: StatementRepository!
    private var service: StatementPaymentService!
    private var db: DBHelper!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_stmt_payment_\(UUID().uuidString)"
        transactionRepo = TransactionRepository()
        addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        stmtRepo = StatementRepository()
        service = StatementPaymentService(transactionRepo: transactionRepo)
        db = DBHelper.shared
        transactionRepo.clearAllTransactionsForTesting()
    }

    /// Cards and statements this test created, so `tearDown` can take them with it.
    private var createdCardIds: [Int] = []

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        // `clearAllTransactionsForTesting` only empties `Transactions`. Every test here mints a card
        // and a statement, and those rows would otherwise survive into later suites on the shared
        // `DBHelper.shared` — statements carrying totals nobody expects, on cards belonging to a user
        // that no longer exists.
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
                isDeleted: false, isDefault: true, createdAt: Date(), updatedAt: Date()
            )
        )
        guard let id = id else { return nil }
        createdCardIds.append(id)
        return repo.fetchCard(byId: id)
    }

    /// A card carrying one charge, and the statement that charge landed on.
    ///
    /// The statement is created directly rather than through `AddTransactionModalViewModel`: that path
    /// resolves the owning user from `AuthenticationManager.shared.currentUser`, which has no session
    /// under test, so it silently skips statement creation. `CreditCardService.getOrCreateStatement`
    /// is the same call it would have made.
    ///
    /// The charge is dated a month out so its cycle is comfortably open — a statement that has already
    /// closed would drag the status assertions into date-boundary territory that has nothing to do
    /// with what these tests are checking.
    private func makeStatementWithCharge(
        amount: Int = 100_000, title: String = "Charge"
    ) throws -> (card: CreditCard, statement: CreditCardStatement) {
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let card = try XCTUnwrap(makeCard(), "Could not create the card fixture")
        let cardId = try XCTUnwrap(card.id)
        let date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

        let statement = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: date, userId: uid),
            "Could not create the statement fixture")
        let stmtId = try XCTUnwrap(statement.id)

        let chargeId = try transactionRepo.insertTransactionAndGetId(
            TransactionModel(
                title: title,
                category: TransactionCategory.market.key,
                amount: amount,
                type: TransactionType.expense.key,
                dateTimestamp: Int(date.timeIntervalSince1970),
                budgetMonthDate: date.monthAnchor
            )
        )
        try transactionRepo.updateCreditCardFields(
            transactionId: chargeId, creditCardId: cardId, statementId: stmtId,
            isCreditCardStatement: false)
        TransactionRepository.invalidateCache()

        return (card, try reload(statement))
    }

    private func reload(_ statement: CreditCardStatement) throws -> CreditCardStatement {
        try XCTUnwrap(
            stmtRepo.fetchStatements(forCardId: statement.creditCardId)
                .first { $0.id == statement.id },
            "The statement disappeared")
    }

    private func transaction(_ id: Int) -> Transaction? {
        TransactionRepository.invalidateCache()
        return transactionRepo.fetchAllTransactions().first { $0.id == id }
    }

    // MARK: - Balance

    func testRemainingBalanceIsTheStatementTotal() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 100_000)
    }

    // MARK: - Paying

    func testFullPaymentZeroesTheStatementAndMarksItPaid() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000, paymentDate: Date())

        XCTAssertEqual(
            service.remainingBalance(statementId: stmtId), 0,
            "The credit should cancel out the charge")

        let reloaded = try reload(fixture.statement)
        XCTAssertTrue(reloaded.isPaid, "A fully covered statement marks itself paid")
        XCTAssertEqual(reloaded.paidAmount, 100_000)
        XCTAssertEqual(reloaded.status, .paid)
    }

    func testPartialPaymentReducesTheBalanceAndLeavesTheStatementOpen() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 40_000, paymentDate: Date())

        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 60_000)

        let reloaded = try reload(fixture.statement)
        XCTAssertFalse(
            reloaded.isPaid, "A statement that still owes money must not be flagged paid")
    }

    func testTwoPartialPaymentsSettleTheStatement() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 40_000, paymentDate: Date())
        // The second payment has to see the REDUCED balance, otherwise the cap would let the user
        // overpay by the amount they already paid.
        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 60_000)

        try service.pay(
            statement: try reload(fixture.statement), card: fixture.card,
            amount: 60_000, paymentDate: Date())

        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 0)
        let reloaded = try reload(fixture.statement)
        XCTAssertTrue(reloaded.isPaid)
        XCTAssertEqual(
            reloaded.paidAmount, 100_000, "paid_amount is everything paid across both payments")
    }

    func testPayingMoreThanTheBalanceIsRejectedAndWritesNothing() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)
        let before = transactionRepo.fetchAllTransactions().count

        XCTAssertThrowsError(
            try service.pay(
                statement: fixture.statement, card: fixture.card,
                amount: 150_000, paymentDate: Date())
        ) { error in
            XCTAssertEqual(error as? StatementPaymentError, .exceedsBalance)
        }

        TransactionRepository.invalidateCache()
        XCTAssertEqual(
            transactionRepo.fetchAllTransactions().count, before,
            "A rejected payment must not leave a debit or a credit behind")
        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 100_000)
    }

    func testPayingZeroIsRejected() throws {
        let fixture = try makeStatementWithCharge()

        XCTAssertThrowsError(
            try service.pay(
                statement: fixture.statement, card: fixture.card,
                amount: 0, paymentDate: Date())
        ) { error in
            XCTAssertEqual(error as? StatementPaymentError, .invalidAmount)
        }
    }

    // MARK: - The two rows

    func testTheDebitIsStandaloneSoItCountsInTheLedger() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)

        let paymentId = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000, paymentDate: Date())

        let debit = try XCTUnwrap(transaction(paymentId))
        XCTAssertEqual(debit.amount, 100_000)
        XCTAssertEqual(debit.type, .expense)
        XCTAssertEqual(debit.category, .creditCard)
        XCTAssertNil(
            debit.creditCardId,
            "The debit must have no card link — that is what puts it in the dashboard ledger")
        XCTAssertNil(debit.statementId, "The debit must not be charged back to the invoice it pays")
        XCTAssertTrue(db.isStatementPayment(transactionId: paymentId))
    }

    func testTheCreditSitsInsideTheStatementAsIncome() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        let paymentId = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 60_000, paymentDate: Date())

        let credit = try XCTUnwrap(
            service.creditRow(forPayment: paymentId), "The payment should have produced a credit")
        XCTAssertEqual(credit.amount, 60_000)
        XCTAssertEqual(
            credit.type, .income,
            "Income is how a card credit subtracts from the invoice — see DBHelper.signedAmount")
        XCTAssertEqual(credit.statementId, stmtId)
        XCTAssertEqual(credit.creditCardId, fixture.card.id)
        XCTAssertEqual(
            db.statementPaymentId(transactionId: try XCTUnwrap(credit.id)), paymentId,
            "The credit points back at the debit that produced it")
    }

    /// The credit must not be filtered out the way an early-paid installment is.
    ///
    /// `statementRowFilter` drops rows carrying `settled_by_transaction_id`. If the statement payment
    /// had reused that column, the credit would vanish from the sum and the invoice would never go
    /// down — the whole feature would be a no-op with two extra rows.
    func testTheCreditIsCountedBySql() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 30_000, paymentDate: Date())

        let sum = try db.getTransactionSumForStatement(statementId: stmtId)
        XCTAssertEqual(sum, 70_000, "100,000 charged minus a 30,000 credit")
    }

    func testTheCreditIsPinnedToItsStatement() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)

        let paymentId = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000,
            paymentDate: Calendar.current.date(byAdding: .month, value: 2, to: Date())!)

        let credit = try XCTUnwrap(service.creditRow(forPayment: paymentId))
        XCTAssertTrue(
            db.isStatementOverridden(transactionId: try XCTUnwrap(credit.id)),
            "Without the override a future-dated credit gets reassigned to a later invoice, and the "
                + "one it was meant to pay springs back to full")
    }

    // MARK: - Scheduled payments

    func testAFutureDatedFullPaymentReadsAsScheduled() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let future = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000, paymentDate: future)

        let reloaded = try reload(fixture.statement)
        XCTAssertTrue(reloaded.isPaid, "The credit is applied immediately, so the flag is set")
        XCTAssertEqual(
            reloaded.status, .scheduled,
            "Until the payment date arrives the invoice reads as scheduled, not paid")
    }

    func testAPastPaidDateReadsAsPaid() throws {
        var statement = try makeStatementWithCharge(amount: 100_000).statement
        statement.isPaid = true
        statement.paidDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        XCTAssertEqual(
            statement.status, .paid,
            "Once the payment date has passed the scheduled label gives way to paid")
    }

    // MARK: - Reversing

    func testDeletingTheDebitRemovesTheCreditAndReopensTheStatement() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        let paymentId = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000, paymentDate: Date())
        let creditId = try XCTUnwrap(service.creditRow(forPayment: paymentId)?.id)
        XCTAssertTrue(try reload(fixture.statement).isPaid, "Precondition: the invoice was settled")

        try transactionRepo.delete(id: paymentId)

        TransactionRepository.invalidateCache()
        XCTAssertNil(transaction(creditId), "The credit goes with the debit that produced it")
        XCTAssertEqual(
            service.remainingBalance(statementId: stmtId), 100_000,
            "The invoice owes the full amount again")
        XCTAssertFalse(
            try reload(fixture.statement).isPaid,
            "An invoice that owes money again must stop reading as paid")
    }

    func testDeletingTheCreditRemovesTheDebit() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        let paymentId = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000, paymentDate: Date())
        let creditId = try XCTUnwrap(service.creditRow(forPayment: paymentId)?.id)

        // Swiping the credit away inside the statement list is the same operation from the other end.
        try transactionRepo.delete(id: creditId)

        TransactionRepository.invalidateCache()
        XCTAssertNil(
            transaction(paymentId),
            "Leaving the debit would charge for a payment the invoice no longer records")
        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 100_000)
        // Regression: the paid flag is decided inside the delete hook, which runs BEFORE the row is
        // actually removed. Reading the balance there without accounting for the credit on its way
        // out left the invoice reading "paid" while owing its full amount again.
        XCTAssertFalse(
            try reload(fixture.statement).isPaid,
            "Deleting the credit has to reopen the statement too, not just remove the debit")
    }

    func testCancelStatementPaymentRejectsAnOrdinaryTransaction() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let charge = try XCTUnwrap(
            transactionRepo.fetchAllTransactions()
                .first { $0.statementId == fixture.statement.id && $0.title == "Charge" })
        let chargeId = try XCTUnwrap(charge.id)

        XCTAssertThrowsError(try service.cancelStatementPayment(paymentId: chargeId))
    }

    func testUndoingOnePartialPaymentLeavesTheOther() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)
        let stmtId = try XCTUnwrap(fixture.statement.id)

        let first = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 30_000, paymentDate: Date())
        let second = try service.pay(
            statement: try reload(fixture.statement), card: fixture.card,
            amount: 20_000, paymentDate: Date())
        XCTAssertEqual(service.remainingBalance(statementId: stmtId), 50_000)

        try transactionRepo.delete(id: first)

        TransactionRepository.invalidateCache()
        XCTAssertNotNil(transaction(second), "Only the payment being undone should be removed")
        XCTAssertEqual(
            service.remainingBalance(statementId: stmtId), 80_000,
            "Undoing the 30,000 payment gives back exactly that much")
    }

    // MARK: - Reading back

    func testPaymentIsDiscoverableFromItsCredit() throws {
        let fixture = try makeStatementWithCharge(amount: 100_000)

        let paymentId = try service.pay(
            statement: fixture.statement, card: fixture.card,
            amount: 100_000, paymentDate: Date())

        let credit = try XCTUnwrap(service.creditRow(forPayment: paymentId))
        XCTAssertEqual(service.payment(for: credit)?.id, paymentId)
    }
}
