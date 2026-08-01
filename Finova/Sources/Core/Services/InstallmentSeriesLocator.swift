//
//  InstallmentSeriesLocator.swift
//  Finova
//
//  Shared reads over an installment series, used by both early payment and cancellation.
//

import Foundation

/// One future installment of a series, with the billing context needed to name it.
struct EarlyPayableInstallment {
    let transaction: Transaction
    let installmentNumber: Int
    let totalInstallments: Int
    let amount: Int
    /// When the money would otherwise leave: the statement due date for a card installment, the
    /// installment's own date otherwise.
    let dueDate: Date
    let statementId: Int?

    var id: Int? { transaction.id }
}

/// Answers "which installments of this series are still ahead of us, and what card is it on?".
///
/// Extracted so early payment and cancellation cannot drift apart on the definition of *outstanding*.
/// Both operations act on exactly the same set — the difference is only what they do with it — and two
/// copies of this filter would eventually disagree about whether an installment in the currently-open
/// statement counts.
struct InstallmentSeriesLocator {
    private let transactionRepo: TransactionRepository
    private let statementRepo: StatementRepository
    private let cardRepo: CreditCardRepository
    private let db: DBHelper

    init(
        transactionRepo: TransactionRepository = TransactionRepository(),
        statementRepo: StatementRepository = StatementRepository(),
        cardRepo: CreditCardRepository = CreditCardRepository(),
        db: DBHelper = .shared
    ) {
        self.transactionRepo = transactionRepo
        self.statementRepo = statementRepo
        self.cardRepo = cardRepo
        self.db = db
    }

    /// The parent that owns the series, whether `transaction` is the parent or one of its children.
    func seriesParentId(of transaction: Transaction) -> Int? {
        if let parentId = transaction.parentTransactionId, parentId != transaction.id {
            return parentId
        }
        if transaction.hasInstallments == true { return transaction.id }
        return nil
    }

    /// Installments of `transaction`'s series that have not been billed yet, newest first.
    ///
    /// Ordered last-installment-first to match how these operations are normally used (and how bank
    /// apps present them): you act on the tail of the series, not the part about to be billed anyway.
    ///
    /// Excluded: installments already settled by an early payment — that money has been charged, so
    /// they are neither payable again nor refundable — and installments whose billing cycle has
    /// already closed, where the charge has left or is on the invoice now due.
    func outstandingInstallments(for transaction: Transaction) -> [EarlyPayableInstallment] {
        guard let parentId = seriesParentId(of: transaction) else { return [] }

        let all = transactionRepo.fetchAllTransactions()
        let settled = db.settledInstallmentIds()
        let now = Date()

        // Cache statements per card — a 24-installment series would otherwise re-read the same card's
        // statement list 24 times.
        var statementsByCard: [Int: [CreditCardStatement]] = [:]

        let children = all.filter { tx in
            tx.parentTransactionId == parentId && tx.installmentNumber != nil
                && tx.totalInstallments != nil
        }

        var outstanding: [EarlyPayableInstallment] = []
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
                outstanding.append(
                    EarlyPayableInstallment(
                        transaction: child, installmentNumber: number, totalInstallments: total,
                        amount: child.amount, dueDate: stmt.dueDate, statementId: stmtId))
            } else {
                guard child.date > now else { continue }
                outstanding.append(
                    EarlyPayableInstallment(
                        transaction: child, installmentNumber: number, totalInstallments: total,
                        amount: child.amount, dueDate: child.date, statementId: nil))
            }
        }

        return outstanding.sorted { $0.installmentNumber > $1.installmentNumber }
    }

    /// The card the series is charged to, or nil for a series with no card.
    func card(for transaction: Transaction) -> CreditCard? {
        if let cardId = transaction.creditCardId {
            return cardRepo.fetchCard(byId: cardId)
        }
        guard let parentId = seriesParentId(of: transaction) else { return nil }
        let all = transactionRepo.fetchAllTransactions()
        guard let cardId = all.first(where: {
            ($0.id == parentId || $0.parentTransactionId == parentId) && $0.creditCardId != nil
        })?.creditCardId else { return nil }
        return cardRepo.fetchCard(byId: cardId)
    }

    /// Every installment of the series, billed or not, in installment order.
    func allInstallments(for transaction: Transaction) -> [Transaction] {
        guard let parentId = seriesParentId(of: transaction) else { return [] }
        return transactionRepo.fetchAllTransactions()
            .filter { $0.parentTransactionId == parentId && $0.installmentNumber != nil }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    }

    /// The credit that cancelled this series, if any installment of it carries a cancellation pointer.
    ///
    /// Checked across the whole series rather than the one transaction in hand: cancellation applies to
    /// the purchase, and the user may be looking at an already-billed installment that carries no
    /// pointer itself.
    func cancellationRefundId(for transaction: Transaction) -> Int? {
        allInstallments(for: transaction)
            .compactMap { $0.id.flatMap { db.cancelledByTransactionId(transactionId: $0) } }
            .first
    }
}
