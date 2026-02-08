//
//  CreditCardService.swift
//  Finova
//

import Foundation
import UIKit

class CreditCardService {
    private let cardRepo = CreditCardRepository()
    private let stmtRepo = StatementRepository()

    /// Returns the closing date for a transaction on a given card.
    /// If transactionDay <= closingDay -> current month closing.
    /// If transactionDay > closingDay -> next month closing.
    func calculateClosingDate(card: CreditCard, transactionDate: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: transactionDate)
        let month = calendar.component(.month, from: transactionDate)
        let year = calendar.component(.year, from: transactionDate)

        if day <= card.closingDay {
            // Current month statement
            let closingDay = min(card.closingDay, daysInMonth(month: month, year: year))
            return calendar.date(from: DateComponents(year: year, month: month, day: closingDay))!
        } else {
            // Next month statement
            var nextMonth = month + 1
            var nextYear = year
            if nextMonth > 12 { nextMonth = 1; nextYear += 1 }
            let closingDay = min(card.closingDay, daysInMonth(month: nextMonth, year: nextYear))
            return calendar.date(from: DateComponents(year: nextYear, month: nextMonth, day: closingDay))!
        }
    }

    /// Calculates due date from a closing date.
    func calculateDueDate(closingDate: Date, card: CreditCard) -> Date {
        let calendar = Calendar.current
        let closingDay = calendar.component(.day, from: closingDate)
        let closingMonth = calendar.component(.month, from: closingDate)
        let closingYear = calendar.component(.year, from: closingDate)

        if card.dueDay > closingDay {
            // Due date same month as closing
            let dueDay = min(card.dueDay, daysInMonth(month: closingMonth, year: closingYear))
            return calendar.date(from: DateComponents(year: closingYear, month: closingMonth, day: dueDay))!
        } else {
            // Due date next month after closing
            var dueMonth = closingMonth + 1
            var dueYear = closingYear
            if dueMonth > 12 { dueMonth = 1; dueYear += 1 }
            let dueDay = min(card.dueDay, daysInMonth(month: dueMonth, year: dueYear))
            return calendar.date(from: DateComponents(year: dueYear, month: dueMonth, day: dueDay))!
        }
    }

    /// Gets or creates a statement for a transaction on a given card/date.
    func getOrCreateStatement(for card: CreditCard, transactionDate: Date, userId: String) -> CreditCardStatement? {
        let closingDate = calculateClosingDate(card: card, transactionDate: transactionDate)
        let dueDate = calculateDueDate(closingDate: closingDate, card: card)

        // Check if statement already exists
        if let existingId = stmtRepo.findStatement(creditCardId: card.id!, closingDate: closingDate) {
            let statements = stmtRepo.fetchStatements(forCardId: card.id!)
            return statements.first(where: { $0.id == existingId })
        }

        // Create new statement
        let newStatement = CreditCardStatement(
            id: nil,
            creditCardId: card.id!,
            closingDate: closingDate,
            dueDate: dueDate,
            totalAmount: 0,
            isPaid: false,
            paidDate: nil,
            paidAmount: nil,
            userId: userId,
            createdAt: Date(),
            updatedAt: Date()
        )

        guard let newId = stmtRepo.insertStatement(newStatement) else { return nil }

        var created = newStatement
        created.id = newId
        return created
    }

    func recalculateStatementTotal(statementId: Int) {
        stmtRepo.recalculateTotal(statementId: statementId)

        // Delete statement if it has no transactions
        do {
            let count = try DBHelper.shared.getTransactionCountForStatement(statementId: statementId)
            if count == 0 {
                _ = stmtRepo.deleteStatement(statementId: statementId)
            }
        } catch {
            logError("Failed to check statement transaction count: \(error)")
        }
    }

    /// Generates synthetic statement transactions for the dashboard.
    func generateStatementTransactions(userId: String) -> [Transaction] {
        let cards = cardRepo.fetchAllCards(userId: userId)
        var statementTransactions: [Transaction] = []

        for card in cards {
            let statements = stmtRepo.fetchStatements(forCardId: card.id!)

            for stmt in statements {
                guard stmt.totalAmount > 0 else { continue }

                let txCount: Int
                do {
                    txCount = try DBHelper.shared.getTransactionCountForStatement(statementId: stmt.id!)
                } catch {
                    txCount = 0
                }

                let title = String(format: "creditCard.statement.title".localized, card.name)
                let dueTimestamp = Int(stmt.dueDate.timeIntervalSince1970)

                let data = UITransactionData(
                    id: -(stmt.id! * 1000 + (card.id ?? 0)),
                    title: title,
                    amount: stmt.totalAmount,
                    dateTimestamp: dueTimestamp,
                    budgetMonthDate: stmt.closingDate.monthAnchor,
                    isRecurring: false,
                    hasInstallments: false,
                    parentTransactionId: nil,
                    installmentNumber: nil,
                    totalInstallments: nil,
                    originalAmount: stmt.totalAmount,
                    creditCardId: card.id,
                    statementId: stmt.id,
                    isCreditCardStatement: true,
                    category: .creditCard,
                    type: .expense
                )

                let tx = Transaction(data: data)
                statementTransactions.append(tx)
            }
        }

        return statementTransactions
    }

    /// Recalculates closing and due dates for all unpaid statements of a card.
    /// Call this after editing a card's closingDay or dueDay.
    func recalculateStatementDatesForCard(_ card: CreditCard) {
        guard let cardId = card.id else { return }
        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        for stmt in statements where !stmt.isPaid {
            // Recalculate due date from the existing closing date using updated card settings
            let newDueDate = calculateDueDate(closingDate: stmt.closingDate, card: card)

            // Recalculate closing date based on existing closing date's month
            let calendar = Calendar.current
            let month = calendar.component(.month, from: stmt.closingDate)
            let year = calendar.component(.year, from: stmt.closingDate)
            let newClosingDay = min(card.closingDay, daysInMonth(month: month, year: year))
            let newClosingDate = calendar.date(from: DateComponents(year: year, month: month, day: newClosingDay))!

            // Also recalculate the due date using the new closing date
            let finalDueDate = calculateDueDate(closingDate: newClosingDate, card: card)

            _ = stmtRepo.updateDates(statementId: stmt.id!, closingDate: newClosingDate, dueDate: finalDueDate)
        }
    }

    /// Finds transactions that have a creditCardId but no statementId and assigns them to the correct statement.
    /// This repairs data from a bug where editing a transaction to use a credit card didn't create statements.
    func repairOrphanedCreditCardTransactions(userId: String, transactionRepo: TransactionRepository) {
        let allTransactions = transactionRepo.fetchAllTransactions()

        let orphaned = allTransactions.filter { tx in
            tx.creditCardId != nil && tx.statementId == nil && tx.isCreditCardStatement != true
        }

        guard !orphaned.isEmpty else { return }

        for tx in orphaned {
            guard let cardId = tx.creditCardId,
                  let txId = tx.id,
                  let card = cardRepo.fetchCard(byId: cardId) else { continue }

            let transactionDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
            if let statement = getOrCreateStatement(for: card, transactionDate: transactionDate, userId: userId) {
                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: txId,
                        creditCardId: cardId,
                        statementId: statement.id!,
                        isCreditCardStatement: false
                    )
                    recalculateStatementTotal(statementId: statement.id!)
                } catch {
                    logError("Failed to repair orphaned transaction \(txId): \(error)")
                }
            }
        }
    }

    private func daysInMonth(month: Int, year: Int) -> Int {
        let calendar = Calendar.current
        let components = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 28 }
        return range.count
    }
}
