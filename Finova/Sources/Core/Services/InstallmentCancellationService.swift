//
//  InstallmentCancellationService.swift
//  Finova
//
//  Cancelling an installment purchase ("estorno de compra parcelada").
//

import Foundation

enum InstallmentCancellationError: Error, Equatable {
    case notAnInstallmentSeries
    case nothingLeftToCancel
    case alreadyCancelled
    case notACancellationRefund
    case missingUser
    case noStatementAvailable
    /// A cancellation write did not land. Fatal on purpose: a credit standing beside installments that
    /// were never marked cancelled lets the user cancel the same purchase again and be credited twice.
    case couldNotMarkCancelled
}

/// Cancels the remainder of an installment purchase and credits it back on the next statement.
///
/// The accounting deliberately mirrors how a card actually handles a cancelled instalment purchase:
/// **the remaining installments keep being charged**, and a single credit for their total arrives on
/// the next statement. The refund lands up front, the charges continue, and the two cancel out over
/// the life of the series — net zero.
///
/// This is why cancelled installments — unlike early-paid ones — are NOT excluded from any total.
/// Excluding them as well as crediting them would refund the user twice.
final class InstallmentCancellationService {
    private let transactionRepo: TransactionRepository
    private let creditCardService: CreditCardService
    private let locator: InstallmentSeriesLocator
    private let db: DBHelper

    init(
        transactionRepo: TransactionRepository = TransactionRepository(),
        statementRepo: StatementRepository = StatementRepository(),
        creditCardService: CreditCardService = CreditCardService(),
        db: DBHelper = .shared
    ) {
        self.transactionRepo = transactionRepo
        self.creditCardService = creditCardService
        self.locator = InstallmentSeriesLocator(
            transactionRepo: transactionRepo, statementRepo: statementRepo, db: db)
        self.db = db
    }

    // MARK: - Eligibility

    /// The installments that would be refunded, newest first.
    func refundableInstallments(for transaction: Transaction) -> [EarlyPayableInstallment] {
        guard !isCancelled(transaction) else { return [] }
        return locator.outstandingInstallments(for: transaction)
    }

    /// Total that would be credited: the sum of everything still to be billed.
    func refundAmount(for transaction: Transaction) -> Int {
        refundableInstallments(for: transaction).reduce(0) { $0 + $1.amount }
    }

    func canCancel(_ transaction: Transaction) -> Bool {
        !refundableInstallments(for: transaction).isEmpty
    }

    /// Whether this series has already been cancelled. Checked across the whole series, so the answer
    /// is the same whichever installment the user happens to be looking at.
    func isCancelled(_ transaction: Transaction) -> Bool {
        locator.cancellationRefundId(for: transaction) != nil
    }

    func card(for transaction: Transaction) -> CreditCard? {
        locator.card(for: transaction)
    }

    // MARK: - Cancelling

    /// Cancels the remainder of the purchase `transaction` belongs to and returns the id of the credit.
    ///
    /// Refuses to run twice on the same series: a second credit would hand the user the remaining
    /// balance again, and nothing downstream would notice.
    @discardableResult
    func cancelPurchase(for transaction: Transaction) throws -> Int {
        guard locator.seriesParentId(of: transaction) != nil else {
            throw InstallmentCancellationError.notAnInstallmentSeries
        }
        guard !isCancelled(transaction) else {
            throw InstallmentCancellationError.alreadyCancelled
        }

        let refundable = locator.outstandingInstallments(for: transaction)
        guard !refundable.isEmpty else {
            throw InstallmentCancellationError.nothingLeftToCancel
        }

        let total = refundable.reduce(0) { $0 + $1.amount }
        let installmentIds = refundable.compactMap { $0.id }
        let card = locator.card(for: transaction)

        // Without a card there is no statement to credit, so the refund simply falls on today.
        let refundDate = Date()

        let model = TransactionModel(
            title: String(format: "cancellation.transaction.title".localized, transaction.title),
            category: TransactionCategory.creditCard.key,
            amount: total,
            type: TransactionType.income.key,
            dateTimestamp: Int(refundDate.timeIntervalSince1970),
            budgetMonthDate: refundDate.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            originalAmount: total,
            installmentNumber: nil,
            totalInstallments: nil
        )

        var refundId = 0
        var statementsToRecalculate = Set(refundable.compactMap { $0.statementId })

        try db.inTransaction {
            refundId = try transactionRepo.insertTransactionAndGetId(model)

            guard db.setCancellationRefund(transactionId: refundId, isRefund: true) else {
                throw InstallmentCancellationError.couldNotMarkCancelled
            }

            if let card = card, let cardId = card.id {
                guard let uid = Self.currentUserId() else {
                    throw InstallmentCancellationError.missingUser
                }
                // The next OPEN statement — a credit attached to an invoice that has already closed is
                // money the user never sees returned.
                guard let statement = creditCardService.nextOpenStatement(
                    for: card, userId: uid, asOf: refundDate),
                    let stmtId = statement.id
                else {
                    throw InstallmentCancellationError.noStatementAvailable
                }
                try transactionRepo.updateCreditCardFields(
                    transactionId: refundId,
                    creditCardId: cardId,
                    statementId: stmtId,
                    isCreditCardStatement: false
                )
                statementsToRecalculate.insert(stmtId)
            }

            // Any failure here rolls the credit back with it — see `couldNotMarkCancelled`.
            for installmentId in installmentIds {
                guard db.setCancelledBy(
                    transactionId: installmentId, cancelledByTransactionId: refundId)
                else {
                    throw InstallmentCancellationError.couldNotMarkCancelled
                }
            }
        }

        finishMutation(refundId: refundId, statementIds: statementsToRecalculate)

        return refundId
    }

    // MARK: - Reversing

    /// Clears the cancellation pointers a refund set, without touching the refund itself.
    ///
    /// Called from the delete path so removing the credit by any route also un-cancels the purchase —
    /// otherwise the series would stay flagged as cancelled with no refund backing it, and the user
    /// could never cancel it again.
    func releaseInstallments(cancelledBy refundId: Int) {
        let installmentIds = db.installmentIdsCancelled(by: refundId)
        guard !installmentIds.isEmpty else { return }

        let all = transactionRepo.fetchAllTransactions()
        let statementIds = Set(
            all.filter { $0.id.map(installmentIds.contains) ?? false }.compactMap { $0.statementId })

        for installmentId in installmentIds {
            db.setCancelledBy(transactionId: installmentId, cancelledByTransactionId: nil)
        }

        TransactionRepository.invalidateCache()
        for stmtId in statementIds {
            creditCardService.recalculateStatementTotal(statementId: stmtId)
        }
    }

    /// Undoes a cancellation completely: the pointers are cleared and the credit is removed.
    func undoCancellation(refundId: Int) throws {
        guard db.isCancellationRefund(transactionId: refundId) else {
            throw InstallmentCancellationError.notACancellationRefund
        }
        // Goes through `delete`, which releases the installments via the hook in
        // TransactionRepository and keeps soft-delete/tombstone handling in one place.
        try transactionRepo.delete(id: refundId)
    }

    // MARK: - Reading back

    /// The installments a given refund covers, in installment order.
    func refundedInstallments(forRefund refundId: Int) -> [Transaction] {
        let ids = db.installmentIdsCancelled(by: refundId)
        guard !ids.isEmpty else { return [] }
        let byId = Dictionary(
            transactionRepo.fetchAllTransactions().compactMap { tx in tx.id.map { ($0, tx) } },
            uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    func isCancellationRefund(_ transaction: Transaction) -> Bool {
        guard let id = transaction.id else { return false }
        return db.isCancellationRefund(transactionId: id)
    }

    /// The credit that cancelled this installment's purchase, if any.
    func refund(cancelling transaction: Transaction) -> Transaction? {
        guard let refundId = locator.cancellationRefundId(for: transaction) else { return nil }
        return transactionRepo.fetchAllTransactions().first { $0.id == refundId }
    }

    // MARK: - Shared

    /// Same resolution order as `EarlyPaymentService`: the cached id scopes every read, so writing
    /// under a different one would make the row invisible.
    private static func currentUserId() -> String? {
        SecureLocalDataManager.shared.getCurrentUserUID()
            ?? AuthenticationManager.shared.currentUser?.uid
    }

    private func finishMutation(refundId: Int, statementIds: Set<Int>) {
        TransactionRepository.invalidateCache()

        for stmtId in statementIds {
            creditCardService.recalculateStatementTotal(statementId: stmtId)
        }

        // The cancelled installments keep their own reminders — the card goes on charging them — so
        // only the new credit needs one.
        transactionRepo.reconcileNotification(transactionId: refundId)

        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
    }
}
