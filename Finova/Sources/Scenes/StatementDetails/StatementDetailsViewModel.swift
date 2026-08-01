//
//  StatementDetailsViewModel.swift
//  Finova
//

import Foundation
import UIKit

protocol StatementDetailsViewModelDelegate: AnyObject {
    func didLoadTransactions(_ transactions: [Transaction])
    func didMarkStatementPaid()
}

final class StatementDetailsViewModel {
    weak var delegate: StatementDetailsViewModelDelegate?

    let card: CreditCard
    var statement: CreditCardStatement
    private let stmtRepo = StatementRepository()
    private let transactionRepo = TransactionRepository()
    private(set) var transactions: [Transaction] = []

    init(card: CreditCard, statement: CreditCardStatement) {
        self.card = card
        self.statement = statement
    }

    func loadTransactions() {
        guard let stmtId = statement.id else { return }
        let allTransactions = transactionRepo.fetchAllTransactions()
        transactions = allTransactions.filter { tx in
            guard tx.statementId == stmtId && tx.isCreditCardStatement != true else { return false }
            if tx.hasInstallments == true && tx.parentTransactionId == nil { return false }
            if tx.isRecurring == true && tx.parentTransactionId == nil { return false }
            return true
        }
        transactions.sort { $0.date > $1.date }
        let settled = DBHelper.shared.settledInstallmentIds()
        earlyPaidIds = Set(transactions.compactMap { $0.id }.filter(settled.contains))
        delegate?.didLoadTransactions(transactions)
    }

    /// Ids of the rows in `transactions` that were paid ahead of schedule.
    ///
    /// They stay in the list — hiding them would make the statement look like it never carried the
    /// installment — but they are shown struck through and excluded from the total, because that
    /// money is charged on the early-payment debit instead.
    private(set) var earlyPaidIds: Set<Int> = []

    var statementTotal: Int {
        // Signed by type, mirroring `DBHelper.signedAmount`: a credit on the card (a refund, a
        // chargeback, or the estorno from a cancelled installment purchase) reduces what this
        // invoice charges rather than adding to it. Installments paid ahead drop out entirely —
        // that money is charged on the early-payment debit instead.
        transactions
            .filter { !($0.id.map(earlyPaidIds.contains) ?? false) }
            .reduce(0) { $1.type == .income ? $0 - $1.amount : $0 + $1.amount }
    }

    func isEarlyPaid(_ transaction: Transaction) -> Bool {
        transaction.id.map(earlyPaidIds.contains) ?? false
    }

    var periodText: String {
        let formatter = DateFormatter.fullDateFormatter
        let startStr = formatter.string(from: previousClosingDate())
        let endStr = formatter.string(from: statement.closingDate)
        return "\(startStr) — \(endStr)"
    }

    var closingDateText: String {
        DateFormatter.fullDateFormatter.string(from: statement.closingDate)
    }

    var dueDateText: String {
        DateFormatter.fullDateFormatter.string(from: statement.dueDate)
    }

    var statusText: String {
        statement.status.displayName
    }

    var statusColor: UIColor {
        statement.status.color
    }

    var isPaid: Bool {
        statement.isPaid
    }

    var paidDateText: String? {
        guard let paidDate = statement.paidDate else { return nil }
        return String(format: "statementDetails.paidOn".localized, DateFormatter.fullDateFormatter.string(from: paidDate))
    }

    func markAsPaid() {
        guard let stmtId = statement.id else { return }
        let success = stmtRepo.markAsPaid(statementId: stmtId, paidAmount: statementTotal, paidDate: Date())
        if success {
            statement.isPaid = true
            statement.paidDate = Date()
            statement.paidAmount = statementTotal
            delegate?.didMarkStatementPaid()
        }
    }

    // MARK: - Transaction Deletion

    func getTransactionType(for transaction: Transaction) -> TransactionComplexityType {
        guard let transactionId = transaction.id else { return .simple }

        if let parentId = transaction.parentTransactionId {
            if parentId == transactionId {
                // Continue to parent checks
            } else {
                let allTransactions = transactionRepo.fetchAllTransactions()
                let parentTransaction = allTransactions.first(where: { $0.id == parentId })
                if parentTransaction?.isRecurring == true {
                    return .recurringInstance
                }
                if parentTransaction?.hasInstallments == true {
                    return .installmentInstance
                }
                return .simple
            }
        }

        if transaction.isRecurring == true {
            return .recurringParent
        }
        if transaction.hasInstallments == true {
            return .installmentParent
        }
        return .simple
    }

    func deleteTransaction(_ transaction: Transaction) -> Result<Void, Error> {
        guard let transactionId = transaction.id else {
            return .failure(NSError(
                domain: "StatementDetails", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid transaction ID"]))
        }

        do {
            try transactionRepo.deleteTransactionAndRelated(id: transactionId)
            recalculateAndReload()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func deleteTransactionWithOption(
        transactionId: Int,
        option: RecurringCleanupOption
    ) -> Result<Void, Error> {
        do {
            let allTransactions = transactionRepo.fetchAllTransactions()
            guard allTransactions.first(where: { $0.id == transactionId }) != nil else {
                return .failure(TransactionError.transactionNotFound)
            }

            try transactionRepo.deleteTransactionWithOption(id: transactionId, option: option)

            recalculateAndReload()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func recalculateAndReload() {
        // Recalculate statement total in DB
        if let stmtId = statement.id {
            let creditCardService = CreditCardService()
            creditCardService.recalculateStatementTotal(statementId: stmtId)
        }
        // Reload transactions and notify
        loadTransactions()
    }

    private func previousClosingDate() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: -1, to: statement.closingDate)!
    }
}
