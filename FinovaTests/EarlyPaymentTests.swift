//
//  EarlyPaymentTests.swift
//  FinovaTests
//
//  Early payment of future installments.
//

import Foundation
import XCTest

@testable import Finova

final class EarlyPaymentTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var addViewModel: AddTransactionModalViewModel!
    private var service: EarlyPaymentService!
    private var db: DBHelper!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_early_payment_\(UUID().uuidString)"
        transactionRepo = TransactionRepository()
        addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        service = EarlyPaymentService(transactionRepo: transactionRepo)
        db = DBHelper.shared
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a plain (non credit card) installment series starting `monthsFromNow` months out, so
    /// every installment is comfortably in the future and therefore payable early.
    /// - Returns: the series' children, in installment order.
    private func makeInstallmentSeries(
        title: String = "Notebook",
        totalAmount: Int = 90000,
        installments: Int = 9,
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
        return children(ofSeriesTitled: title)
    }

    private func children(ofSeriesTitled title: String) -> [Transaction] {
        TransactionRepository.invalidateCache()
        return transactionRepo.fetchAllTransactions()
            .filter { $0.title == title && $0.installmentNumber != nil }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    }

    private func payable(from children: [Transaction]) -> [EarlyPayableInstallment] {
        guard let anyChild = children.first else { return [] }
        return service.payableInstallments(for: anyChild)
    }

    // MARK: - Eligibility

    func testPayableInstallmentsListsFutureInstallmentsNewestFirst() {
        let children = makeInstallmentSeries(installments: 5)
        XCTAssertEqual(children.count, 5, "Fixture should have created 5 installments")

        let options = payable(from: children)

        XCTAssertEqual(options.count, 5, "Every installment is in the future, so all are payable")
        XCTAssertEqual(
            options.map { $0.installmentNumber }, [5, 4, 3, 2, 1],
            "Options are ordered last-installment-first")
    }

    func testPastInstallmentsAreNotPayableEarly() {
        // Starts 2 months ago: #1 and #2 are already due, #3 onward are not.
        let children = makeInstallmentSeries(title: "Sofa", installments: 5, monthsFromNow: -2)
        let options = payable(from: children)

        XCTAssertFalse(
            options.contains { $0.installmentNumber <= 2 },
            "An installment whose date has passed cannot be paid early")
        XCTAssertTrue(options.allSatisfy { $0.dueDate > Date() })
    }

    func testAlreadySettledInstallmentsDropOutOfTheOptions() throws {
        let children = makeInstallmentSeries(installments: 4)
        let options = payable(from: children)
        let last = try XCTUnwrap(options.first)

        let paymentId = try service.payEarly(
            installments: [last], paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        let remaining = payable(from: children)

        XCTAssertEqual(
            db.settledByTransactionId(transactionId: last.id ?? -1), paymentId,
            "Precondition: the installment should be pointing at the debit that paid it")
        XCTAssertEqual(remaining.count, options.count - 1)
        XCTAssertFalse(
            remaining.contains { $0.id == last.id },
            "An installment already paid early is not offered a second time")
    }

    // MARK: - Paying

    func testPayEarlyCreatesOneDebitForTheSelectedTotal() throws {
        let children = makeInstallmentSeries(totalAmount: 90000, installments: 9)
        let options = payable(from: children)
        let selection = Array(options.prefix(2))
        let expectedTotal = selection.reduce(0) { $0 + $1.amount }

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        TransactionRepository.invalidateCache()
        let payment = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == paymentId })

        XCTAssertEqual(payment.amount, expectedTotal, "The debit charges exactly what was selected")
        XCTAssertEqual(payment.type, .expense)
        XCTAssertEqual(
            payment.category, .creditCard,
            "Booked under Credit Card so it shows in that budget-allocation row")
        XCTAssertTrue(db.isEarlyPayment(transactionId: paymentId))
    }

    func testSelectedInstallmentsPointAtThePaymentAndStopCounting() throws {
        let children = makeInstallmentSeries(installments: 6)
        let options = payable(from: children)
        let selection = Array(options.prefix(3))
        let selectedIds = selection.compactMap { $0.id }

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        for id in selectedIds {
            XCTAssertEqual(
                db.settledByTransactionId(transactionId: id), paymentId,
                "Installment \(id) should point at the debit that paid it")
        }

        let settled = db.settledInstallmentIds()
        XCTAssertTrue(Set(selectedIds).isSubset(of: settled))

        // The ledger filter is what keeps the amount from being counted twice.
        let visible = transactionRepo.fetchAllTransactions().excludingEarlyPaidInstallments()
        XCTAssertTrue(
            visible.allSatisfy { !selectedIds.contains($0.id ?? -1) },
            "Early-paid installments are excluded from ledger totals")
    }

    func testUnselectedInstallmentsAreUntouched() throws {
        let children = makeInstallmentSeries(installments: 6)
        let options = payable(from: children)
        let selection = Array(options.prefix(2))
        let untouchedIds = options.dropFirst(2).compactMap { $0.id }

        _ = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        for id in untouchedIds {
            XCTAssertNil(
                db.settledByTransactionId(transactionId: id),
                "Installment \(id) was not selected and must stay outstanding")
        }
    }

    func testPayingWithAnEmptySelectionIsRejected() {
        XCTAssertThrowsError(
            try service.payEarly(
                installments: [], paymentDate: Date(), destination: .standalone,
                seriesTitle: "Notebook")
        ) { error in
            XCTAssertEqual(error as? EarlyPaymentError, .noInstallmentsSelected)
        }
    }

    func testTotalIsPreservedAcrossTheSeries() throws {
        // Paying part of a series early must not change what the purchase cost in total: the
        // early-payment debit plus the still-outstanding installments has to equal the original.
        let series = makeInstallmentSeries(totalAmount: 90000, installments: 9)
        let options = payable(from: series)
        let selection = Array(options.prefix(4))

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        TransactionRepository.invalidateCache()
        let all = transactionRepo.fetchAllTransactions()
        let payment = try XCTUnwrap(all.first { $0.id == paymentId })
        let outstanding = children(ofSeriesTitled: "Notebook")
            .excludingEarlyPaidInstallments()
            .reduce(0) { $0 + $1.amount }

        XCTAssertEqual(
            payment.amount + outstanding, 90000,
            "Debit + outstanding installments must still add up to the purchase total")
    }

    // MARK: - Credit card destination

    /// A card whose cycle closes late in the month, so a payment made today lands in a still-open
    /// statement and every generated installment sits in a future cycle.
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
        return repo.fetchCard(byId: id)
    }

    private func makeCardInstallmentSeries(
        card: CreditCard, title: String = "TV", totalAmount: Int = 60000, installments: Int = 6
    ) -> [Transaction] {
        let start = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        let result = addViewModel.addTransactionWithInstallments(
            InstallmentTransactionData(
                title: title,
                totalAmount: totalAmount,
                date: DateFormatter.fullDateFormatter.string(from: start),
                category: "market",
                transactionType: "expense",
                installments: installments,
                creditCardId: card.id
            )
        )
        guard case .success = result else {
            XCTFail("Could not create the card installment series: \(result)")
            return []
        }
        TransactionRepository.invalidateCache()
        return children(ofSeriesTitled: title)
    }

    func testChargingToTheOpenStatementLinksTheDebitToThatStatement() throws {
        let card = try XCTUnwrap(makeCard(), "Could not create the card fixture")
        let series = makeCardInstallmentSeries(card: card)
        XCTAssertFalse(series.isEmpty, "Fixture produced no installments")

        let options = payable(from: series)
        let selection = try XCTUnwrap(options.first.map { [$0] })

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(),
            destination: .openStatement(card), seriesTitle: "TV")

        TransactionRepository.invalidateCache()
        let payment = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == paymentId })

        XCTAssertEqual(payment.creditCardId, card.id, "The debit belongs to the card it was paid on")
        XCTAssertNotNil(
            payment.statementId,
            "Charging to the open statement has to attach the debit to a statement")
    }

    /// The list must not depend on which installment the user opened.
    ///
    /// `parentTransactionId` is not stable — editing a series rebuilds its children, and the repair
    /// passes exist because links get scrambled. When a series splits across two parent ids, filtering
    /// on one returns only half, and which half depends on the entry point.
    func testEveryInstallmentOffersTheSameListEvenWhenTheParentLinkHasSplit() throws {
        let series = makeInstallmentSeries(title: "Split", totalAmount: 60000, installments: 6)
        XCTAssertEqual(series.count, 6, "Fixture should have created 6 installments")

        // Re-point the back half at a different parent, reproducing a drifted series.
        let strayParent = try XCTUnwrap(series.first?.parentTransactionId) + 9999
        for child in series.suffix(3) {
            let childId = try XCTUnwrap(child.id)
            try transactionRepo.updateTransactionParentId(
                transactionId: childId, parentId: strayParent)
        }
        TransactionRepository.invalidateCache()

        let refreshed = children(ofSeriesTitled: "Split")
        XCTAssertEqual(refreshed.count, 6, "All six rows should still exist")

        // Opening any installment must surface the same set.
        let listsPerEntryPoint = refreshed.map { entry in
            Set(service.payableInstallments(for: entry).compactMap { $0.installmentNumber })
        }
        let first = try XCTUnwrap(listsPerEntryPoint.first)

        XCTAssertEqual(
            first.count, 6,
            "Every installment is in the future, so all six should be offered regardless of the split")
        for (index, list) in listsPerEntryPoint.enumerated() {
            XCTAssertEqual(
                list, first,
                "Installment #\(index + 1) offered a different list — the options must not depend on "
                    + "which one the user opened")
        }
    }

    /// Regression: the tail of a series whose statement row is missing.
    ///
    /// An installment pointing at a statement that no longer exists used to be skipped outright, so the
    /// last installment of a long series — the one furthest out, e.g. #10 of 10 landing in January —
    /// silently never appeared in the list. It is still unbilled and still payable; the statement
    /// lookup only exists to decide whether the cycle has closed, which its own date answers too.
    func testInstallmentWithAMissingStatementIsStillOffered() throws {
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let card = try XCTUnwrap(makeCard(), "Could not create the card fixture")
        let cardId = try XCTUnwrap(card.id)

        let series = makeInstallmentSeries(title: "Fridge", totalAmount: 100000, installments: 10)
        XCTAssertEqual(series.count, 10, "Fixture should have created 10 installments")

        // Attach the LAST installment to a real statement, then delete that statement to reproduce the
        // dangling pointer the tail of a long series ends up with.
        let last = try XCTUnwrap(series.last)
        let lastId = try XCTUnwrap(last.id)
        let farFuture = Calendar.current.date(byAdding: .month, value: 10, to: Date())!
        let doomed = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: farFuture, userId: uid))
        let doomedId = try XCTUnwrap(doomed.id)

        try transactionRepo.updateCreditCardFields(
            transactionId: lastId, creditCardId: cardId,
            statementId: doomedId, isCreditCardStatement: false)
        _ = StatementRepository().deleteStatement(statementId: doomedId)
        TransactionRepository.invalidateCache()

        let offered = payable(from: series)

        XCTAssertTrue(
            offered.contains { $0.id == lastId },
            "The last installment is unbilled and still payable — a missing statement row must not "
                + "hide it from the list")
    }

    /// Regression: a card whose cycle closes TODAY.
    ///
    /// Date routing (`getOrCreateStatement`) resolves "today" to the cycle closing today, because for a
    /// purchase that is correct. For an early payment it is not: the invoice has already been issued,
    /// so the user would never be billed for the anticipation and the money would vanish from view.
    func testEarlyPaymentSkipsAStatementThatClosesToday() throws {
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let today = Calendar.current.component(.day, from: Date())

        let repo = CreditCardRepository()
        let cardId = try XCTUnwrap(
            repo.insertCard(
                CreditCard(
                    name: "ClosesToday", lastFourDigits: "0001", cardBrand: .visa,
                    closingDay: today, dueDay: min(today + 4, 28), creditLimit: 5_000_000,
                    cardColor: .blue, userId: uid,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())))
        let card = try XCTUnwrap(repo.fetchCard(byId: cardId))

        let closingToday = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card, transactionDate: Date(), userId: uid),
            "Precondition: date routing should produce the cycle closing today")
        XCTAssertLessThanOrEqual(
            closingToday.closingDate, Date(),
            "Precondition: that statement should already be closed")

        let target = try XCTUnwrap(
            CreditCardService().nextOpenStatement(for: card, userId: uid),
            "There should always be a next open statement to route to")

        XCTAssertNotEqual(
            target.id, closingToday.id,
            "An early payment must not land on the invoice that just closed")
        XCTAssertGreaterThan(
            target.closingDate, Date(),
            "The target statement has to still be open for the user to be billed on it")
    }

    func testAnticipatedInstallmentLeavesItsOwnStatementTotal() throws {
        // The statement link is made explicitly here rather than by creating the series through
        // AddTransactionModalViewModel: that path only attaches statements when a Firebase session is
        // live, which it is not under test. What matters for this assertion is the SQL filter on
        // statement totals, and this sets that up directly.
        let uid = try XCTUnwrap(UIDUserDefaultsManager.shared.currentUserUID)
        let card = try XCTUnwrap(makeCard(), "Could not create the card fixture")
        let statement = try XCTUnwrap(
            CreditCardService().getOrCreateStatement(
                for: card,
                transactionDate: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
                userId: uid),
            "Could not create the statement fixture")
        let statementId = try XCTUnwrap(statement.id)

        let series = makeInstallmentSeries(title: "Camera", totalAmount: 50000, installments: 5)
        let target = try XCTUnwrap(payable(from: series).first, "No payable installment")
        let targetId = try XCTUnwrap(target.id)

        try transactionRepo.updateCreditCardFields(
            transactionId: targetId, creditCardId: try XCTUnwrap(card.id),
            statementId: statementId, isCreditCardStatement: false)
        TransactionRepository.invalidateCache()

        let scope = LedgerScope(.personal)
        let before = DBHelper.shared.statementTotals(statementId: statementId, scope: scope)
        XCTAssertEqual(
            before.total, target.amount,
            "Precondition: the statement should carry the installment before it is anticipated")

        // Re-read the installment so its statement link is part of the option we pay.
        let linked = try XCTUnwrap(payable(from: series).first { $0.id == targetId })
        _ = try service.payEarly(
            installments: [linked], paymentDate: Date(),
            destination: .standalone, seriesTitle: "Camera")

        let after = DBHelper.shared.statementTotals(statementId: statementId, scope: scope)
        XCTAssertEqual(
            after.total, 0,
            "The anticipated installment must drop out of its original statement's total")
    }

    // MARK: - Reversing

    func testReleasingInstallmentsClearsTheirPointers() throws {
        let children = makeInstallmentSeries(installments: 4)
        let options = payable(from: children)
        let selection = Array(options.prefix(2))
        let selectedIds = selection.compactMap { $0.id }

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        service.releaseInstallments(settledBy: paymentId)

        for id in selectedIds {
            XCTAssertNil(
                db.settledByTransactionId(transactionId: id),
                "Releasing must put installment \(id) back")
        }
        XCTAssertTrue(db.settledInstallmentIds().isDisjoint(with: Set(selectedIds)))
    }

    func testDeletingTheDebitAutomaticallyUnsettlesItsInstallments() throws {
        // The hook in TransactionRepository.delete is what makes this safe: without it, deleting the
        // debit would leave the installments excluded from every total with nothing charging for them.
        let children = makeInstallmentSeries(installments: 4)
        let options = payable(from: children)
        let selection = Array(options.prefix(2))
        let selectedIds = selection.compactMap { $0.id }

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        try transactionRepo.delete(id: paymentId)

        for id in selectedIds {
            XCTAssertNil(
                db.settledByTransactionId(transactionId: id),
                "Deleting the debit must restore installment \(id)")
        }

        let visible = transactionRepo.fetchAllTransactions().excludingEarlyPaidInstallments()
        XCTAssertEqual(
            Set(selectedIds).subtracting(Set(visible.compactMap { $0.id })), [],
            "The restored installments count toward the ledger again")
    }

    func testCancelEarlyPaymentRejectsAnOrdinaryTransaction() {
        let children = makeInstallmentSeries(installments: 3)
        guard let ordinaryId = children.first?.id else {
            return XCTFail("Fixture produced no installments")
        }

        XCTAssertThrowsError(try service.cancelEarlyPayment(paymentId: ordinaryId)) { error in
            XCTAssertEqual(error as? EarlyPaymentError, .notAnEarlyPayment)
        }
    }

    // MARK: - Reading back

    func testSettledInstallmentsAreReadableFromThePayment() throws {
        let children = makeInstallmentSeries(installments: 5)
        let options = payable(from: children)
        let selection = Array(options.prefix(3))

        let paymentId = try service.payEarly(
            installments: selection, paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        let included = service.settledInstallments(forPayment: paymentId)

        XCTAssertEqual(Set(included.compactMap { $0.id }), Set(selection.compactMap { $0.id }))
        XCTAssertEqual(
            included.compactMap { $0.installmentNumber },
            included.compactMap { $0.installmentNumber }.sorted(),
            "Included installments are returned in installment order")
    }

    func testPaymentIsDiscoverableFromASettledInstallment() throws {
        let children = makeInstallmentSeries(installments: 3)
        let options = payable(from: children)
        let last = try XCTUnwrap(options.first)

        let paymentId = try service.payEarly(
            installments: [last], paymentDate: Date(), destination: .standalone,
            seriesTitle: "Notebook")

        TransactionRepository.invalidateCache()
        let installment = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.id == last.id })

        XCTAssertEqual(service.payment(settling: installment)?.id, paymentId)
    }
}
