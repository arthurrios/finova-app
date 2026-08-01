//
//  InstallmentCancellationTests.swift
//  FinovaTests
//
//  Cancelling an installment purchase: the remaining installments keep being charged and a single
//  credit for their total offsets them, so the net effect over the life of the series is zero.
//

import Foundation
import XCTest

@testable import Finova

final class InstallmentCancellationTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var addViewModel: AddTransactionModalViewModel!
    private var service: InstallmentCancellationService!
    private var earlyPaymentService: EarlyPaymentService!
    private var db: DBHelper!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_cancellation_\(UUID().uuidString)"
        transactionRepo = TransactionRepository()
        addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        service = InstallmentCancellationService(transactionRepo: transactionRepo)
        earlyPaymentService = EarlyPaymentService(transactionRepo: transactionRepo)
        db = DBHelper.shared
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    /// A plain installment series starting next month, so every installment is still to be billed.
    private func makeSeries(
        title: String = "Sofa",
        totalAmount: Int = 60000,
        installments: Int = 6,
        monthsFromNow: Int = 1
    ) -> [Transaction] {
        let start = Calendar.current.date(byAdding: .month, value: monthsFromNow, to: Date())!
        let result = addViewModel.addTransactionWithInstallments(
            InstallmentTransactionData(
                title: title,
                totalAmount: totalAmount,
                date: DateFormatter.fullDateFormatter.string(from: start),
                category: "market",
                transactionType: "expense",
                installments: installments
            )
        )
        guard case .success = result else {
            XCTFail("Could not create the installment series fixture: \(result)")
            return []
        }
        TransactionRepository.invalidateCache()
        return children(titled: title)
    }

    private func children(titled title: String) -> [Transaction] {
        TransactionRepository.invalidateCache()
        return transactionRepo.fetchAllTransactions()
            .filter { $0.title == title && $0.installmentNumber != nil }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    }

    private func anyChild(_ series: [Transaction]) throws -> Transaction {
        try XCTUnwrap(series.first, "Fixture produced no installments")
    }

    // MARK: - Refund amount

    func testRefundCoversEveryInstallmentStillToBeBilled() throws {
        let series = makeSeries(totalAmount: 60000, installments: 6)
        let child = try anyChild(series)

        let refundable = service.refundableInstallments(for: child)

        XCTAssertEqual(refundable.count, 6, "Nothing has been billed yet, so all six are refundable")
        XCTAssertEqual(
            service.refundAmount(for: child), 60000,
            "The credit is the sum of everything still to be billed")
    }

    func testAlreadyBilledInstallmentsAreNotRefunded() throws {
        // Starts two months ago: #1 and #2 have been billed and cannot be cancelled.
        let series = makeSeries(title: "Bed", installments: 5, monthsFromNow: -2)
        let child = try anyChild(series)

        let refundable = service.refundableInstallments(for: child)

        XCTAssertFalse(
            refundable.contains { $0.installmentNumber <= 2 },
            "An installment already billed is not part of the refund")
        XCTAssertEqual(
            service.refundAmount(for: child),
            refundable.reduce(0) { $0 + $1.amount },
            "The credit matches exactly the installments listed as refundable")
    }

    func testInstallmentsPaidEarlyAreNotRefundedAgain() throws {
        let series = makeSeries(title: "Desk", totalAmount: 40000, installments: 4)
        let child = try anyChild(series)

        let payable = earlyPaymentService.payableInstallments(for: child)
        let paidEarly = try XCTUnwrap(payable.first)
        _ = try earlyPaymentService.payEarly(
            installments: [paidEarly], paymentDate: Date(), destination: .standalone,
            seriesTitle: "Desk")

        let refundable = service.refundableInstallments(for: child)

        XCTAssertFalse(
            refundable.contains { $0.id == paidEarly.id },
            "An installment already charged via an early payment must not be refunded as well")
        XCTAssertEqual(
            service.refundAmount(for: child), 40000 - paidEarly.amount,
            "The credit excludes what was already paid")
    }

    // MARK: - Cancelling

    func testCancellingCreatesACreditForTheRemainingTotal() throws {
        let series = makeSeries(totalAmount: 60000, installments: 6)
        let child = try anyChild(series)

        let refundId = try service.cancelPurchase(for: child)

        TransactionRepository.invalidateCache()
        let refund = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == refundId })

        XCTAssertEqual(refund.amount, 60000)
        XCTAssertEqual(refund.type, .income, "A cancellation is money coming back, not going out")
        XCTAssertEqual(refund.category, .creditCard)
        XCTAssertTrue(db.isCancellationRefund(transactionId: refundId))
    }

    func testCancelledInstallmentsKeepCountingTowardTotals() throws {
        // This is the defining difference from an early payment. Excluding them here as well as
        // crediting them would refund the user twice.
        let series = makeSeries(installments: 6)
        let child = try anyChild(series)
        let refundId = try service.cancelPurchase(for: child)

        let cancelledIds = db.installmentIdsCancelled(by: refundId)
        XCTAssertEqual(cancelledIds.count, 6, "Precondition: all six should be marked")

        let visible = transactionRepo.fetchAllTransactions().excludingEarlyPaidInstallments()
        for id in cancelledIds {
            XCTAssertTrue(
                visible.contains { $0.id == id },
                "Cancelled installment \(id) must still count — the card goes on charging it")
        }
    }

    func testNetEffectOverTheSeriesIsZero() throws {
        let series = makeSeries(totalAmount: 60000, installments: 6)
        let child = try anyChild(series)

        let refundId = try service.cancelPurchase(for: child)

        TransactionRepository.invalidateCache()
        let refund = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == refundId })
        let stillCharged = children(titled: "Sofa")
            .excludingEarlyPaidInstallments()
            .reduce(0) { $0 + $1.amount }

        XCTAssertEqual(
            stillCharged - refund.amount, 0,
            "Charges that remain minus the credit must be zero — the refund arrives up front and the "
                + "installments continue")
    }

    func testCancellingTwiceIsRejected() throws {
        let series = makeSeries(installments: 4)
        let child = try anyChild(series)
        _ = try service.cancelPurchase(for: child)

        TransactionRepository.invalidateCache()
        let refreshed = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == child.id })

        XCTAssertThrowsError(try service.cancelPurchase(for: refreshed)) { error in
            XCTAssertEqual(
                error as? InstallmentCancellationError, .alreadyCancelled,
                "A second credit would hand the user the remaining balance all over again")
        }
    }

    func testCancellingIsRejectedWhenNothingIsLeftToBill() throws {
        // Every installment is in the past, so there is nothing to cancel.
        let series = makeSeries(title: "OldTV", installments: 3, monthsFromNow: -6)
        let child = try anyChild(series)

        XCTAssertFalse(service.canCancel(child))
        XCTAssertThrowsError(try service.cancelPurchase(for: child)) { error in
            XCTAssertEqual(error as? InstallmentCancellationError, .nothingLeftToCancel)
        }
    }

    func testCancellingIsRejectedForANonInstallmentTransaction() throws {
        let result = addViewModel.addTransaction(
            title: "Coffee", amount: 800,
            dateString: DateFormatter.fullDateFormatter.string(from: Date()),
            categoryKey: "meals", typeRaw: "expense")
        guard case .success = result else { return XCTFail("Could not create the fixture") }
        TransactionRepository.invalidateCache()
        let plain = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.title == "Coffee" })

        XCTAssertThrowsError(try service.cancelPurchase(for: plain)) { error in
            XCTAssertEqual(error as? InstallmentCancellationError, .notAnInstallmentSeries)
        }
    }

    func testACancelledPurchaseCannotAlsoBePaidEarly() throws {
        let series = makeSeries(installments: 5)
        let child = try anyChild(series)
        _ = try service.cancelPurchase(for: child)

        TransactionRepository.invalidateCache()
        let refreshed = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == child.id })

        XCTAssertTrue(
            earlyPaymentService.payableInstallments(for: refreshed).isEmpty,
            "Anticipating a purchase that has already been refunded would move money for something "
                + "that no longer stands")
    }

    // MARK: - Statement effect

    func testTheCreditReducesTheStatementItLandsOn() throws {
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let cardRepo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            cardRepo.insertCard(
                CreditCard(
                    name: "TestCard", lastFourDigits: "4242", cardBrand: .visa,
                    closingDay: 28, dueDay: 5, creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: true, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(cardRepo.fetchCard(byId: cardId))

        let statement = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: Date(), userId: uid))
        let statementId = try XCTUnwrap(statement.id)

        // A credit attached to a statement has to bring the invoice DOWN. Summing amounts without
        // regard to type made an income row raise it instead.
        let refundModel = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Refund", category: "creditCard", amount: 25000, type: "income")
        let refundId = try transactionRepo.insertTransactionAndGetId(refundModel)
        try transactionRepo.updateCreditCardFields(
            transactionId: refundId, creditCardId: cardId,
            statementId: statementId, isCreditCardStatement: false)
        TransactionRepository.invalidateCache()

        let totals = DBHelper.shared.statementTotals(
            statementId: statementId, scope: LedgerScope(.personal))

        XCTAssertEqual(
            totals.total, -25000,
            "A credit on the card reduces what the invoice charges")
    }

    func testTheCreditLandsOnTheNextOPENStatement() throws {
        // Same hazard as early payment: on a card closing today, date routing resolves to the cycle
        // closing today — an invoice already issued, where the user would never see the refund.
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let today = Calendar.current.component(.day, from: Date())

        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: "ClosesToday", lastFourDigits: "0002", cardBrand: .visa,
                    closingDay: today, dueDay: min(today + 4, 28), creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))

        let closedToday = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: Date(), userId: uid))
        XCTAssertLessThanOrEqual(
            closedToday.closingDate, Date(), "Precondition: that cycle should already be closed")

        // Attach the series to the card so cancellation routes to a statement at all.
        let series = makeSeries(title: "Camera", totalAmount: 50000, installments: 5)
        let firstChildId = try XCTUnwrap(series.first?.id)
        try transactionRepo.updateCreditCardFields(
            transactionId: firstChildId, creditCardId: cardId,
            statementId: try XCTUnwrap(closedToday.id), isCreditCardStatement: false)
        TransactionRepository.invalidateCache()

        let refreshed = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == firstChildId })
        let refundId = try service.cancelPurchase(for: refreshed)

        TransactionRepository.invalidateCache()
        let refund = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == refundId })
        let refundStatementId = try XCTUnwrap(
            refund.statementId, "The credit should be attached to a statement")

        XCTAssertNotEqual(
            refundStatementId, closedToday.id,
            "The refund must not land on the invoice that already closed")

        let target = try XCTUnwrap(
            StatementRepository().fetchStatements(forCardId: cardId)
                .first { $0.id == refundStatementId })
        XCTAssertGreaterThan(
            target.closingDate, Date(),
            "The refund has to land on a statement still open, or the user never gets it back")
    }

    // MARK: - Reversing

    func testReleasingClearsTheCancellationPointers() throws {
        let series = makeSeries(installments: 4)
        let child = try anyChild(series)
        let refundId = try service.cancelPurchase(for: child)
        let cancelledIds = db.installmentIdsCancelled(by: refundId)

        service.releaseInstallments(cancelledBy: refundId)

        for id in cancelledIds {
            XCTAssertNil(
                db.cancelledByTransactionId(transactionId: id),
                "Releasing must un-cancel installment \(id)")
        }
    }

    func testDeletingTheCreditUnCancelsThePurchase() throws {
        let series = makeSeries(installments: 4)
        let child = try anyChild(series)
        let refundId = try service.cancelPurchase(for: child)

        try transactionRepo.delete(id: refundId)

        TransactionRepository.invalidateCache()
        let refreshed = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == child.id })

        XCTAssertFalse(
            service.isCancelled(refreshed),
            "Deleting the credit must un-cancel the purchase — otherwise it stays flagged with no "
                + "refund backing it and can never be cancelled again")
        XCTAssertTrue(
            service.canCancel(refreshed), "And it becomes cancellable once more")
    }

    func testUndoCancellationRejectsAnOrdinaryTransaction() throws {
        let series = makeSeries(installments: 3)
        let child = try anyChild(series)
        let childId = try XCTUnwrap(child.id)

        XCTAssertThrowsError(try service.undoCancellation(refundId: childId)) { error in
            XCTAssertEqual(error as? InstallmentCancellationError, .notACancellationRefund)
        }
    }

    // MARK: - Reading back

    func testRefundedInstallmentsAreReadableFromTheCredit() throws {
        let series = makeSeries(installments: 5)
        let child = try anyChild(series)
        let refundId = try service.cancelPurchase(for: child)

        let refunded = service.refundedInstallments(forRefund: refundId)

        XCTAssertEqual(refunded.count, 5)
        XCTAssertEqual(
            refunded.compactMap { $0.installmentNumber },
            refunded.compactMap { $0.installmentNumber }.sorted(),
            "Refunded installments are returned in installment order")
    }

    func testTheCreditIsDiscoverableFromACancelledInstallment() throws {
        let series = makeSeries(installments: 3)
        let child = try anyChild(series)
        let refundId = try service.cancelPurchase(for: child)

        TransactionRepository.invalidateCache()
        let refreshed = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == child.id })

        XCTAssertEqual(service.refund(cancelling: refreshed)?.id, refundId)
    }
}
