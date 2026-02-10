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
        transactions = allTransactions.filter { $0.statementId == stmtId && $0.isCreditCardStatement != true }
        transactions.sort { $0.date > $1.date }
        delegate?.didLoadTransactions(transactions)
    }

    var statementTotal: Int {
        transactions.reduce(0) { $0 + $1.amount }
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
