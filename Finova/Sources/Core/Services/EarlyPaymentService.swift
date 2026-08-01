//
//  EarlyPaymentService.swift
//  Finova
//
//  Early payment of future installments ("antecipação de parcelas").
//

import Foundation

/// One future installment offered for early payment, with the billing context the user needs to
/// recognise it.
struct EarlyPayableInstallment {
    let transaction: Transaction
    let installmentNumber: Int
    let totalInstallments: Int
    let amount: Int
    /// When the money would otherwise have left: the statement due date for a card installment,
    /// the installment's own date otherwise.
    let dueDate: Date
    let statementId: Int?

    var id: Int? { transaction.id }
}

/// Where the resulting debit is booked.
enum EarlyPaymentDestination {
    /// A plain expense on the chosen date, with no card or statement link.
    case standalone
    /// Charged to whichever statement of `card` is open on the chosen date — the behaviour bank
    /// apps describe as "added to your open statement".
    case openStatement(CreditCard)

    var card: CreditCard? {
        if case .openStatement(let card) = self { return card }
        return nil
    }
}

enum EarlyPaymentError: Error, Equatable {
    case noInstallmentsSelected
    case notAnInstallment
    case notAnEarlyPayment
    case missingUser
}

/// Pays selected future installments ahead of schedule.
///
/// The shape of the operation: one new debit for the total, and each installment it covers marked
/// `settled_by_transaction_id = <that debit>`. The installment rows are deliberately kept — see
/// `DBHelper.migrateEarlyPaymentColumns` — so the series stays intact, the statement history stays
/// readable, and the whole thing can be undone by clearing the pointers.
final class EarlyPaymentService {
    private let transactionRepo: TransactionRepository
    private let statementRepo: StatementRepository
    private let creditCardService: CreditCardService
    private let db: DBHelper

    init(
        transactionRepo: TransactionRepository = TransactionRepository(),
        statementRepo: StatementRepository = StatementRepository(),
        creditCardService: CreditCardService = CreditCardService(),
        db: DBHelper = .shared
    ) {
        self.transactionRepo = transactionRepo
        self.statementRepo = statementRepo
        self.creditCardService = creditCardService
        self.db = db
    }

    /// The user rows are written under.
    ///
    /// `UIDUserDefaultsManager` first, because that is what scopes every read in
    /// `TransactionRepository` — writing under a different id than reads are filtered by would make
    /// the new row invisible. Falls back to the auth session for the case where the cached id is
    /// missing but the user is signed in.
    private static func currentUserId() -> String? {
        UIDUserDefaultsManager.shared.currentUserUID ?? AuthenticationManager.shared.currentUser?.uid
    }

    // MARK: - Eligibility

    /// Whether `transaction` belongs to an installment series with anything left to anticipate.
    func canPayEarly(_ transaction: Transaction) -> Bool {
        !payableInstallments(for: transaction).isEmpty
    }

    /// The installments of `transaction`'s series that can still be paid early, newest first.
    ///
    /// Ordered last-installment-first to match how the operation is normally used (and how bank apps
    /// present it): you bring the tail of the series forward, not the part that is about to be billed
    /// anyway. Selection itself is unrestricted.
    ///
    /// Excluded: installments already settled by an earlier early payment, and installments whose
    /// billing cycle has already closed — the money for those is either gone or on the invoice the
    /// user is about to pay, so "paying early" is meaningless.
    func payableInstallments(for transaction: Transaction) -> [EarlyPayableInstallment] {
        guard let parentId = seriesParentId(of: transaction) else { return [] }

        let all = transactionRepo.fetchAllTransactions()
        let settled = db.settledInstallmentIds()
        let now = Date()

        // Cache statements per card — a 24-installment series would otherwise re-read the same
        // card's statement list 24 times.
        var statementsByCard: [Int: [CreditCardStatement]] = [:]

        let children = all.filter { tx in
            tx.parentTransactionId == parentId && tx.installmentNumber != nil
                && tx.totalInstallments != nil
        }

        var payable: [EarlyPayableInstallment] = []
        for child in children {
            guard let childId = child.id,
                  let number = child.installmentNumber,
                  let total = child.totalInstallments,
                  !settled.contains(childId)
            else { continue }

            if let cardId = child.creditCardId, let stmtId = child.statementId {
                if statementsByCard[cardId] == nil {
                    statementsByCard[cardId] = statementRepo.fetchStatements(forCardId: cardId)
                }
                guard let stmt = statementsByCard[cardId]?.first(where: { $0.id == stmtId }) else { continue }
                guard stmt.closingDate > now, !stmt.isPaid else { continue }
                payable.append(
                    EarlyPayableInstallment(
                        transaction: child, installmentNumber: number, totalInstallments: total,
                        amount: child.amount, dueDate: stmt.dueDate, statementId: stmtId))
            } else {
                guard child.date > now else { continue }
                payable.append(
                    EarlyPayableInstallment(
                        transaction: child, installmentNumber: number, totalInstallments: total,
                        amount: child.amount, dueDate: child.date, statementId: nil))
            }
        }

        return payable.sorted { $0.installmentNumber > $1.installmentNumber }
    }

    /// The card the series is charged to, if it is a credit-card series. Drives whether the
    /// "charge to the open statement" destination is offered at all.
    func card(for transaction: Transaction) -> CreditCard? {
        if let cardId = transaction.creditCardId {
            return CreditCardRepository().fetchCard(byId: cardId)
        }
        guard let parentId = seriesParentId(of: transaction) else { return nil }
        let all = transactionRepo.fetchAllTransactions()
        guard let cardId = all.first(where: {
            ($0.id == parentId || $0.parentTransactionId == parentId) && $0.creditCardId != nil
        })?.creditCardId else { return nil }
        return CreditCardRepository().fetchCard(byId: cardId)
    }

    /// The parent that owns the series, whether `transaction` is the parent or one of its children.
    private func seriesParentId(of transaction: Transaction) -> Int? {
        if let parentId = transaction.parentTransactionId, parentId != transaction.id {
            return parentId
        }
        if transaction.hasInstallments == true { return transaction.id }
        return nil
    }

    // MARK: - Paying

    /// Books `installments` as paid on `paymentDate` and returns the id of the debit created.
    ///
    /// Everything runs in one SQLite transaction: a half-applied early payment — debit created, some
    /// installments still unsettled — would double-count real money, which is the one outcome worth
    /// paying for a rollback to avoid.
    @discardableResult
    func payEarly(
        installments: [EarlyPayableInstallment],
        paymentDate: Date,
        destination: EarlyPaymentDestination,
        seriesTitle: String
    ) throws -> Int {
        guard !installments.isEmpty else { throw EarlyPaymentError.noInstallmentsSelected }

        let total = installments.reduce(0) { $0 + $1.amount }
        let installmentIds = installments.compactMap { $0.id }

        // The debit inherits the series' ledger. Without this an early payment made inside a group
        // would be created as a personal expense while the installments it settles stay in the
        // group — the group's statement total would drop with nothing to account for it.
        let groupId = installmentIds.compactMap { db.getSharedGroupId(transactionId: $0) }.first

        // Categorised as `.creditCard` rather than inheriting the purchase's category: what leaves
        // the account is a card payment, and this is what puts it in the Credit Card row of the
        // budget-allocation screen for the month it is actually paid.
        let model = TransactionModel(
            title: String(format: "earlyPayment.transaction.title".localized, seriesTitle),
            category: TransactionCategory.creditCard.key,
            amount: total,
            type: TransactionType.expense.key,
            dateTimestamp: Int(paymentDate.timeIntervalSince1970),
            budgetMonthDate: paymentDate.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            originalAmount: total,
            installmentNumber: nil,
            totalInstallments: nil
        )

        var paymentId = 0
        var statementsToRecalculate = Set(installments.compactMap { $0.statementId })

        try db.inTransaction {
            paymentId = try transactionRepo.insertTransactionAndGetId(model)

            // Pre-generate the CK name so the group activity log can reference the record, matching
            // how AddTransactionModalViewModel creates transactions.
            let ckRecordName = "transaction-\(UUID().uuidString)"
            transactionRepo.setCKRecordId(for: paymentId, ckRecordName: ckRecordName)

            db.setEarlyPayment(transactionId: paymentId, isEarlyPayment: true)

            if let groupId = groupId {
                transactionRepo.updateSharedGroupId(transactionId: paymentId, groupId: groupId)
            }

            // The owning user is only needed to stamp a NEWLY created statement, so it is resolved
            // here rather than up front: a standalone early payment touches no statement and must not
            // fail just because the auth session isn't live.
            if let card = destination.card, let cardId = card.id {
                guard let uid = Self.currentUserId() else { throw EarlyPaymentError.missingUser }
                if let statement = creditCardService.getOrCreateStatement(
                    for: card, transactionDate: paymentDate, userId: uid),
                    let stmtId = statement.id
                {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: paymentId,
                        creditCardId: cardId,
                        statementId: stmtId,
                        isCreditCardStatement: false
                    )
                    statementsToRecalculate.insert(stmtId)
                }
            }

            for installmentId in installmentIds {
                db.setSettledBy(transactionId: installmentId, settledByTransactionId: paymentId)
            }
        }

        finishMutation(
            paymentId: paymentId,
            model: model,
            statementIds: statementsToRecalculate,
            installmentIds: installmentIds,
            groupId: groupId
        )

        return paymentId
    }

    // MARK: - Reversing

    /// Releases the installments a debit settled, without touching the debit itself.
    ///
    /// Called from the delete path so removing the debit by ANY route — its own screen, the statement
    /// list, a swipe on the dashboard — puts the installments back. Deleting the debit while its
    /// pointers stood would silently erase the amount from the ledger entirely: the installments
    /// would stay excluded from every total with nothing left charging for them.
    func releaseInstallments(settledBy paymentId: Int) {
        let installmentIds = db.installmentIdsSettled(by: paymentId)
        guard !installmentIds.isEmpty else { return }

        let all = transactionRepo.fetchAllTransactions()
        let statementIds = Set(
            all.filter { $0.id.map(installmentIds.contains) ?? false }.compactMap { $0.statementId })

        for installmentId in installmentIds {
            db.setSettledBy(transactionId: installmentId, settledByTransactionId: nil)
        }

        TransactionRepository.invalidateCache()
        for stmtId in statementIds {
            creditCardService.recalculateStatementTotal(statementId: stmtId)
        }
        rescheduleInstallmentNotifications(for: installmentIds, in: transactionRepo.fetchAllTransactions())
    }

    /// Undoes an early payment completely: the installments go back to their own statements and the
    /// debit is removed.
    func cancelEarlyPayment(paymentId: Int) throws {
        guard db.isEarlyPayment(transactionId: paymentId) else {
            throw EarlyPaymentError.notAnEarlyPayment
        }
        // `delete` releases the installments through the hook in TransactionRepository, so ordering
        // is not load-bearing here — but going through `delete` keeps soft-delete/tombstone handling
        // in the one place that knows about it.
        try transactionRepo.delete(id: paymentId)
    }

    // MARK: - Reading back

    /// The installments a given early-payment debit covers, in installment order.
    func settledInstallments(forPayment paymentId: Int) -> [Transaction] {
        let ids = db.installmentIdsSettled(by: paymentId)
        guard !ids.isEmpty else { return [] }
        let byId = Dictionary(
            transactionRepo.fetchAllTransactions().compactMap { tx in tx.id.map { ($0, tx) } },
            uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    func isEarlyPayment(_ transaction: Transaction) -> Bool {
        guard let id = transaction.id else { return false }
        return db.isEarlyPayment(transactionId: id)
    }

    /// The debit that settled `transaction`, if it was paid early.
    func payment(settling transaction: Transaction) -> Transaction? {
        guard let id = transaction.id,
              let paymentId = db.settledByTransactionId(transactionId: id)
        else { return nil }
        return transactionRepo.fetchAllTransactions().first { $0.id == paymentId }
    }

    // MARK: - Shared post-mutation work

    private func finishMutation(
        paymentId: Int,
        model: TransactionModel,
        statementIds: Set<Int>,
        installmentIds: [Int],
        groupId: String?
    ) {
        TransactionRepository.invalidateCache()

        for stmtId in statementIds {
            creditCardService.recalculateStatementTotal(statementId: stmtId)
        }

        TransactionNotificationManager.shared.scheduleNotification(
            transactionId: paymentId, model: model)
        rescheduleInstallmentNotifications(
            for: installmentIds, in: transactionRepo.fetchAllTransactions())

        if let groupId = groupId {
            GroupNotificationService.shared.logActivity(
                action: .transactionCreated, groupId: groupId, detail: model.data.title,
                targetRecordName: transactionRepo.fetchCKRecordName(for: paymentId))
        }

        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
        SyncEngine.shared.pushPendingChangesNow()
    }

    /// Installment reminders are bucketed per series, so the whole series has to be rescheduled —
    /// an anticipated installment must stop reminding the user about a payment already made.
    private func rescheduleInstallmentNotifications(for installmentIds: [Int], in all: [Transaction]) {
        let parentIds = Set(
            all.filter { $0.id.map(installmentIds.contains) ?? false }
                .compactMap { $0.parentTransactionId })
        for parentId in parentIds {
            InstallmentNotificationManager.shared.rescheduleNotifications(
                parentTransactionId: parentId)
        }
    }
}

// MARK: - Ledger filtering

extension Array where Element == Transaction {
    /// Drops installments already paid ahead of schedule.
    ///
    /// The money they represent left the account on the early-payment debit's own date, so counting
    /// them again in the future month they were originally scheduled for would double-count it and
    /// would show the user an upcoming expense they have already settled. The rows stay in the
    /// database; this only concerns what a total includes.
    ///
    /// Pass `settled` when the caller already has the set, to avoid re-querying per call.
    func excludingEarlyPaidInstallments(settled: Set<Int>? = nil) -> [Transaction] {
        let settledIds = settled ?? DBHelper.shared.settledInstallmentIds()
        guard !settledIds.isEmpty else { return self }
        return filter { tx in
            guard let id = tx.id else { return true }
            return !settledIds.contains(id)
        }
    }
}
