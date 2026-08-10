//
//  StatementPaymentService.swift
//  Finova
//
//  Paying a credit-card statement, in part or in full ("pagamento de fatura").
//

import Foundation

enum StatementPaymentError: Error, Equatable {
    case invalidAmount
    case exceedsBalance
    case missingStatement
    case missingUser
    /// A pointer or flag write did not land. Fatal on purpose: a debit whose credit never made it
    /// into the statement charges the user for an invoice that still shows the full balance.
    case couldNotLink
}

/// Records a payment against a credit-card statement.
///
/// A payment is a PAIR of rows, and both halves are the point:
///
/// - a **debit** on the chosen date with no card link — the money actually leaving the account. It
///   has no `creditCardId`, which is what puts it in the dashboard ledger
///   (`TransactionLedgerService` counts a row only when `creditCardId == nil`).
/// - a **credit** inside the statement for the same amount — what makes the invoice total drop. It
///   IS card-linked, so it stays out of the ledger and cannot double-count, and it is typed
///   `.income`, which `DBHelper.signedAmount` already subtracts from the invoice.
///
/// The credit points at the debit through `statement_payment_id`, so either row can find the other
/// and deleting one takes the other with it. Partial payments are ordinary: each one adds another
/// pair, and the statement is marked paid only once the balance reaches zero.
final class StatementPaymentService {
    private let transactionRepo: TransactionRepository
    private let stmtRepo: StatementRepository
    private let creditCardService: CreditCardService
    private let db: DBHelper

    /// Payment ids whose cascade delete is already running, so the two halves cannot delete each
    /// other in a loop. See `handleDeletion`.
    private static var cascadingIds: Set<Int> = []
    private static let cascadeLock = NSLock()

    init(
        transactionRepo: TransactionRepository = TransactionRepository(),
        statementRepo: StatementRepository = StatementRepository(),
        creditCardService: CreditCardService = CreditCardService(),
        db: DBHelper = .shared
    ) {
        self.transactionRepo = transactionRepo
        self.stmtRepo = statementRepo
        self.creditCardService = creditCardService
        self.db = db
    }

    /// The user rows are written under. Same resolution order as `EarlyPaymentService`, and for the
    /// same reason: `UIDUserDefaultsManager` is what scopes every read in `TransactionRepository`, so
    /// writing under a different id would make the new rows invisible.
    private static func currentUserId() -> String? {
        UIDUserDefaultsManager.shared.currentUserUID ?? AuthenticationManager.shared.currentUser?.uid
    }

    // MARK: - Balance

    /// What the statement still owes, never negative.
    ///
    /// Uses the same SQL the stored `total_amount` is recalculated from, so the cap this enforces and
    /// the number the invoice shows cannot drift. Credits already recorded against the statement —
    /// refunds, earlier payments — are subtracted by `signedAmount`, which is what makes a second
    /// partial payment see the reduced balance rather than the original one.
    func remainingBalance(statementId: Int) -> Int {
        guard let total = try? db.getTransactionSumForStatement(statementId: statementId) else {
            return 0
        }
        return max(0, total)
    }

    // MARK: - Paying

    /// Books a payment of `amount` against `statement` on `paymentDate`, returning the debit's id.
    ///
    /// Everything runs in one SQLite transaction. A half-applied payment — debit created, credit
    /// missing — would take real money out of the ledger while the invoice went on charging the full
    /// amount, which is the one outcome worth paying for a rollback to avoid.
    @discardableResult
    func pay(
        statement: CreditCardStatement,
        card: CreditCard,
        amount: Int,
        paymentDate: Date
    ) throws -> Int {
        guard let stmtId = statement.id, let cardId = card.id else {
            throw StatementPaymentError.missingStatement
        }
        guard amount > 0 else { throw StatementPaymentError.invalidAmount }
        guard amount <= remainingBalance(statementId: stmtId) else {
            throw StatementPaymentError.exceedsBalance
        }
        guard Self.currentUserId() != nil else { throw StatementPaymentError.missingUser }

        // Both rows inherit the invoice's ledger. Without this, paying a group card's statement would
        // create a personal debit while the credit stayed in the group — the group's invoice would
        // drop with nothing in the group accounting for it.
        let groupId = transactionRepo.fetchAllTransactions()
            .filter { $0.statementId == stmtId && $0.isCreditCardStatement != true }
            .compactMap { $0.id }
            .compactMap { db.getSharedGroupId(transactionId: $0) }
            .first

        let statementLabel = DateFormatter.monthYearShortFormatter.string(from: statement.dueDate)
        let debitModel = TransactionModel(
            title: String(
                format: "statementPayment.transaction.title".localized, card.name, statementLabel),
            category: TransactionCategory.creditCard.key,
            amount: amount,
            type: TransactionType.expense.key,
            dateTimestamp: Int(paymentDate.timeIntervalSince1970),
            budgetMonthDate: paymentDate.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            originalAmount: amount,
            installmentNumber: nil,
            totalInstallments: nil
        )

        // The credit is anchored to the statement's own budget month — the anchor the synthetic
        // statement row uses (`CreditCardService.generateStatementTransactions`) — so it reduces the
        // invoice in the month that invoice belongs to, not the month the money left.
        let creditModel = TransactionModel(
            title: String(format: "statementPayment.credit.title".localized, statementLabel),
            category: TransactionCategory.creditCard.key,
            amount: amount,
            type: TransactionType.income.key,
            dateTimestamp: Int(paymentDate.timeIntervalSince1970),
            budgetMonthDate: statement.closingDate.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            originalAmount: amount,
            installmentNumber: nil,
            totalInstallments: nil
        )

        var paymentId = 0

        try db.inTransaction {
            paymentId = try transactionRepo.insertTransactionAndGetId(debitModel)
            // Pre-generated so the group activity log can reference the record, matching how
            // AddTransactionModalViewModel and EarlyPaymentService create transactions.
            transactionRepo.setCKRecordId(
                for: paymentId, ckRecordName: "transaction-\(UUID().uuidString)")

            guard db.setStatementPaymentFlag(transactionId: paymentId, isStatementPayment: true)
            else { throw StatementPaymentError.couldNotLink }

            let creditId = try transactionRepo.insertTransactionAndGetId(creditModel)
            transactionRepo.setCKRecordId(
                for: creditId, ckRecordName: "transaction-\(UUID().uuidString)")

            try transactionRepo.updateCreditCardFields(
                transactionId: creditId,
                creditCardId: cardId,
                statementId: stmtId,
                isCreditCardStatement: false
            )
            // Pins the credit to THIS statement. A payment scheduled into next month would otherwise
            // be reassigned to next month's invoice by `reassignMisplacedTransactions`, and the
            // invoice it was meant to pay would spring back to its full balance.
            db.setStatementOverridden(transactionId: creditId, overridden: true)

            guard db.setStatementPaymentLink(transactionId: creditId, paymentId: paymentId) else {
                throw StatementPaymentError.couldNotLink
            }

            if let groupId = groupId {
                transactionRepo.updateSharedGroupId(transactionId: paymentId, groupId: groupId)
                transactionRepo.updateSharedGroupId(transactionId: creditId, groupId: groupId)
            }
        }

        finishMutation(
            paymentId: paymentId,
            model: debitModel,
            statementId: stmtId,
            paymentDate: paymentDate,
            groupId: groupId
        )

        return paymentId
    }

    // MARK: - Reversing

    /// Undoes the payment `transactionId` belongs to, whichever half of the pair it is.
    ///
    /// Called from `TransactionRepository.deleteRow` so removing either row by ANY route — its own
    /// details screen, a swipe in the statement list, a swipe on the dashboard — takes its partner
    /// with it. Leaving one behind is a real loss either way: an orphaned debit charges for a payment
    /// the invoice no longer records, and an orphaned credit discounts an invoice nobody paid.
    ///
    /// `transactionId` is being deleted by the caller; this only handles the OTHER half and the
    /// statement's own state.
    func handleDeletion(of transactionId: Int) {
        let isDebit = db.isStatementPayment(transactionId: transactionId)
        let linkedPaymentId = db.statementPaymentId(transactionId: transactionId)
        guard isDebit || linkedPaymentId != nil else { return }

        // One cascade key for the pair, so whichever half the user deleted, the partner's own
        // delete does not come back round and try to delete the first one again.
        let cascadeKey = isDebit ? transactionId : (linkedPaymentId ?? transactionId)
        Self.cascadeLock.lock()
        guard !Self.cascadingIds.contains(cascadeKey) else {
            Self.cascadeLock.unlock()
            return
        }
        Self.cascadingIds.insert(cascadeKey)
        Self.cascadeLock.unlock()
        defer {
            Self.cascadeLock.lock()
            Self.cascadingIds.remove(cascadeKey)
            Self.cascadeLock.unlock()
        }

        let all = transactionRepo.fetchAllTransactions()
        var partnerIds: [Int] = []
        var statementIds: Set<Int> = []

        // The caller has NOT deleted `transactionId` yet — `deleteRow` removes it after this hook
        // returns — so a balance read here still counts it. When the row going away is the credit,
        // its own amount has to be added back by hand, or the invoice below still looks settled and
        // keeps a "paid" flag it no longer deserves.
        var pendingCredit = 0

        if isDebit {
            partnerIds = db.creditIds(paidBy: transactionId)
        } else if let paymentId = linkedPaymentId {
            partnerIds = [paymentId]
            if let credit = all.first(where: { $0.id == transactionId }) {
                if let stmtId = credit.statementId { statementIds.insert(stmtId) }
                pendingCredit = credit.amount
            }
        }

        statementIds.formUnion(
            all.filter { $0.id.map(partnerIds.contains) ?? false }.compactMap { $0.statementId })

        for partnerId in partnerIds {
            try? transactionRepo.delete(id: partnerId)
        }

        TransactionRepository.invalidateCache()
        for stmtId in statementIds {
            // `deleteBatch` recalculates the stored total once the rows are actually gone; this only
            // decides the paid flag. The invoice owes money again, so it must stop reading "paid" —
            // but only when there really is a balance, so a statement settled by some other means and
            // left at zero keeps its flag.
            if remainingBalance(statementId: stmtId) + pendingCredit > 0 {
                _ = stmtRepo.markAsUnpaid(statementId: stmtId)
            }
        }

        Self.announceDataChanged()
    }

    /// Undoes a statement payment completely: the debit and its credit both go.
    func cancelStatementPayment(paymentId: Int) throws {
        guard db.isStatementPayment(transactionId: paymentId) else {
            throw StatementPaymentError.couldNotLink
        }
        // `delete` runs the cascade through the hook in TransactionRepository, so going through it
        // keeps soft-delete and tombstone handling in the one place that knows about them.
        try transactionRepo.delete(id: paymentId)
    }

    // MARK: - Reading back

    func isStatementPayment(_ transaction: Transaction) -> Bool {
        guard let id = transaction.id else { return false }
        return db.isStatementPayment(transactionId: id)
    }

    /// The statement credit a payment debit produced.
    func creditRow(forPayment paymentId: Int) -> Transaction? {
        guard let creditId = db.creditIds(paidBy: paymentId).first else { return nil }
        return transactionRepo.fetchAllTransactions().first { $0.id == creditId }
    }

    /// The debit that produced a statement credit.
    func payment(for transaction: Transaction) -> Transaction? {
        guard let id = transaction.id,
              let paymentId = db.statementPaymentId(transactionId: id)
        else { return nil }
        return transactionRepo.fetchAllTransactions().first { $0.id == paymentId }
    }

    // MARK: - Shared post-mutation work

    private func finishMutation(
        paymentId: Int,
        model: TransactionModel,
        statementId: Int,
        paymentDate: Date,
        groupId: String?
    ) {
        TransactionRepository.invalidateCache()
        creditCardService.recalculateStatementTotal(statementId: statementId)

        // Fully settled: flag the invoice. `paidDate` is the PAYMENT's date, not today — a payment
        // scheduled for next month is what makes `CreditCardStatement.status` read `.scheduled`
        // instead of `.paid` until that day arrives.
        if remainingBalance(statementId: statementId) == 0 {
            _ = stmtRepo.markAsPaid(
                statementId: statementId,
                paidAmount: totalPaid(statementId: statementId),
                paidDate: paymentDate
            )
        }

        TransactionNotificationManager.shared.scheduleNotification(
            transactionId: paymentId, model: model)

        if let groupId = groupId {
            GroupNotificationService.shared.logActivity(
                action: .transactionCreated, groupId: groupId, detail: model.data.title,
                targetRecordName: transactionRepo.fetchCKRecordName(for: paymentId))
        }

        Self.announceDataChanged()
        SyncEngine.shared.pushPendingChangesNow()
    }

    /// Both entry points run off the main thread — the screen dispatches `pay` to a background queue,
    /// and deletes come in from wherever the row was swiped away. Observers of these two names redraw
    /// the dashboard and the statement list, so the post is hopped to main rather than left to run
    /// UIKit work on whichever queue happened to call in.
    private static func announceDataChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
        }
    }

    /// Everything paid against this statement so far, across however many partial payments it took.
    private func totalPaid(statementId: Int) -> Int {
        transactionRepo.fetchAllTransactions()
            .filter { tx in
                tx.statementId == statementId
                    && tx.id.map { db.statementPaymentId(transactionId: $0) != nil } ?? false
            }
            .reduce(0) { $0 + $1.amount }
    }
}
