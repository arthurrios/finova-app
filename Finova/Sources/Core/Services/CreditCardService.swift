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
            isDatesOverridden: false,
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

        // Use the same source as the ViewModel to avoid stale DB vs secure store mismatch
        let allSecureTransactions = SecureLocalDataManager.shared.loadTransactions()

        for card in cards {
            let statements = stmtRepo.fetchStatements(forCardId: card.id!)

            for stmt in statements {
                // Count and sum from the secure store (consistent with what StatementDetailsViewModel shows)
                let stmtTransactions = allSecureTransactions.filter {
                    $0.statementId == stmt.id && $0.isCreditCardStatement != true
                }

                let realCount = stmtTransactions.count
                // Signed by type, mirroring `DBHelper.signedAmount`: a credit on the card reduces
                // what the invoice charges.
                let realTotal = stmtTransactions.reduce(0) {
                    $1.type == .income ? $0 - $1.amount : $0 + $1.amount
                }

                // Clean up stale statements with no transactions
                if realCount == 0 {
                    recalculateStatementTotal(statementId: stmt.id!)
                    continue
                }

                guard realTotal > 0 else { continue }

                let title = String(format: "creditCard.statement.title".localized, card.name)
                let dueTimestamp = Int(stmt.dueDate.timeIntervalSince1970)

                let data = UITransactionData(
                    id: -(stmt.id! * 1000 + (card.id ?? 0)),
                    title: title,
                    amount: realTotal,
                    dateTimestamp: dueTimestamp,
                    budgetMonthDate: stmt.closingDate.monthAnchor,
                    isRecurring: false,
                    hasInstallments: false,
                    parentTransactionId: nil,
                    installmentNumber: nil,
                    totalInstallments: realCount,
                    originalAmount: realTotal,
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

    /// Recalculates closing and due dates for all unpaid statements of a card,
    /// then reassigns transactions to the correct statements based on the new dates.
    /// Call this after editing a card's closingDay or dueDay.
    func recalculateStatementDatesForCard(_ card: CreditCard, userId: String? = nil, transactionRepo: TransactionRepository? = nil) {
        guard let cardId = card.id else { return }
        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        for stmt in statements where !stmt.isPaid {
            // Recalculate closing date based on existing closing date's month
            let calendar = Calendar.current
            let month = calendar.component(.month, from: stmt.closingDate)
            let year = calendar.component(.year, from: stmt.closingDate)
            let newClosingDay = min(card.closingDay, daysInMonth(month: month, year: year))
            let newClosingDate = calendar.date(from: DateComponents(year: year, month: month, day: newClosingDay))!

            // Calculate due date using the new closing date
            let finalDueDate = calculateDueDate(closingDate: newClosingDate, card: card)

            _ = stmtRepo.updateDates(statementId: stmt.id!, closingDate: newClosingDate, dueDate: finalDueDate)
        }

        // Reassign transactions to correct statements based on new dates
        guard let userId = userId, let transactionRepo = transactionRepo else { return }
        reassignCardTransactions(card: card, userId: userId, transactionRepo: transactionRepo)
    }

    /// Reassigns all transactions for a card to their correct statements based on current card settings.
    private func reassignCardTransactions(card: CreditCard, userId: String, transactionRepo: TransactionRepository) {
        guard let cardId = card.id else { return }
        let allTransactions = transactionRepo.fetchAllTransactions()
        let cardTransactions = allTransactions.filter {
            $0.creditCardId == cardId && $0.isCreditCardStatement != true
        }

        var affectedStatementIds = Set<Int>()

        for tx in cardTransactions {
            guard let txId = tx.id else { continue }

            let transactionDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
            guard let correctStatement = getOrCreateStatement(for: card, transactionDate: transactionDate, userId: userId),
                  let correctStmtId = correctStatement.id else { continue }

            // Only update if the transaction is in the wrong statement
            if tx.statementId != correctStmtId {
                if let oldStmtId = tx.statementId {
                    affectedStatementIds.insert(oldStmtId)
                }
                affectedStatementIds.insert(correctStmtId)

                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: txId,
                        creditCardId: cardId,
                        statementId: correctStmtId,
                        isCreditCardStatement: false
                    )
                } catch {
                    logError("Failed to reassign transaction \(txId) to statement \(correctStmtId): \(error)")
                }
            }
        }

        // Recalculate totals for all affected statements
        for stmtId in affectedStatementIds {
            recalculateStatementTotal(statementId: stmtId)
        }
    }

    /// Ensures all credit card transactions are in the correct statement based on current card settings.
    /// Moves misplaced transactions and cleans up empty statements.
    func reassignMisplacedTransactions(userId: String, transactionRepo: TransactionRepository) {
        let cards = cardRepo.fetchAllCards(userId: userId)
        for card in cards {
            reassignCardTransactions(card: card, userId: userId, transactionRepo: transactionRepo)
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

    /// The statement for the billing cycle after `current`, creating it if it does not exist yet.
    func nextStatement(after current: CreditCardStatement, for card: CreditCard, userId: String) -> CreditCardStatement? {
        guard let cardId = card.id else { return nil }
        let calendar = Calendar.current

        let currentMonth = calendar.component(.month, from: current.closingDate)
        let currentYear = calendar.component(.year, from: current.closingDate)
        var nextMonth = currentMonth + 1
        var nextYear = currentYear
        if nextMonth > 12 { nextMonth = 1; nextYear += 1 }

        let nextClosingDay = min(card.closingDay, daysInMonth(month: nextMonth, year: nextYear))
        let nextClosingDate = calendar.date(from: DateComponents(year: nextYear, month: nextMonth, day: nextClosingDay))!
        let nextDueDate = calculateDueDate(closingDate: nextClosingDate, card: card)

        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        if let existingId = stmtRepo.findStatement(creditCardId: cardId, closingDate: nextClosingDate),
           let exact = statements.first(where: { $0.id == existingId }) {
            return exact
        }

        // A statement that kept old dates after the card's closing day changed still IS that month's
        // invoice, so reuse it rather than creating a second one for the same cycle.
        if let sameMonth = statements
            .filter({ calendar.isDate($0.closingDate, equalTo: nextClosingDate, toGranularity: .month) })
            .sorted(by: { ($0.id ?? Int.max) < ($1.id ?? Int.max) })
            .first {
            return sameMonth
        }

        let newStmt = CreditCardStatement(
            id: nil,
            creditCardId: cardId,
            closingDate: nextClosingDate,
            dueDate: nextDueDate,
            totalAmount: 0,
            isPaid: false,
            paidDate: nil,
            paidAmount: nil,
            isDatesOverridden: false,
            userId: userId,
            createdAt: Date(),
            updatedAt: Date()
        )
        guard let newId = stmtRepo.insertStatement(newStmt) else { return nil }
        var created = newStmt
        created.id = newId
        return created
    }

    /// The earliest statement that is still open as of `date` — the next invoice the user will be
    /// billed for.
    ///
    /// Distinct from `getOrCreateStatement(transactionDate:)`, which routes by the card's closing day
    /// and is right for a *purchase*: a purchase made on the closing day belongs to the cycle that is
    /// closing. Money the user is choosing to move — an early payment, or the credit from a cancelled
    /// purchase — must land somewhere they can still be billed for it. On a card closing the 1st, on
    /// the 1st, date routing returns the statement closing that same day, so the amount would be
    /// attached to an invoice already issued and the user would never see it.
    ///
    /// Creates the following cycle only when every existing statement has already closed.
    func nextOpenStatement(for card: CreditCard, userId: String, asOf date: Date = Date())
        -> CreditCardStatement?
    {
        guard let cardId = card.id else { return nil }
        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        if let open = statements
            .filter({ $0.closingDate > date && !$0.isPaid })
            .min(by: { $0.closingDate < $1.closingDate })
        {
            return open
        }

        if let latest = statements.max(by: { $0.closingDate < $1.closingDate }) {
            return nextStatement(after: latest, for: card, userId: userId)
        }

        return getOrCreateStatement(for: card, transactionDate: date, userId: userId)
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
