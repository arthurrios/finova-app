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
        // Don't touch cloud-synced statements — they may appear empty locally because
        // cross-device credit card ID remapping hasn't resolved yet. Deleting or
        // recalculating them here would push a wrong totalAmount=0 to CloudKit and
        // permanently remove the statement from the cloud.
        guard stmtRepo.fetchCKRecordName(for: statementId) == nil else { return }

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

        // Use the same source as the ViewModel
        let allSecureTransactions = TransactionRepository().fetchAllTransactions()

        for card in cards {
            let statements = stmtRepo.fetchStatements(forCardId: card.id!)

            for stmt in statements {
                // Count and sum from the secure store (consistent with what StatementDetailsViewModel shows)
                let stmtTransactions = allSecureTransactions.filter {
                    $0.statementId == stmt.id && $0.isCreditCardStatement != true
                }

                let realCount = stmtTransactions.count
                let realTotal = stmtTransactions.reduce(0) { $0 + $1.amount }

                // Clean up stale statements with no transactions.
                // Skip cloud-synced statements — recalculateStatementTotal already guards
                // against touching them, but also avoid calling it at all to prevent
                // the no-op recalculate from marking them 'pending' unnecessarily.
                if realCount == 0 {
                    if stmtRepo.fetchCKRecordName(for: stmt.id!) == nil {
                        recalculateStatementTotal(statementId: stmt.id!)
                    }
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
        // Skip CC installments that already have a statementId — their dateTimestamp
        // has been remapped to the statement due date, so getOrCreateStatement would
        // compute the wrong statement from the remapped date.
        let cardTransactions = allTransactions.filter {
            $0.creditCardId == cardId && $0.isCreditCardStatement != true
            && !($0.installmentNumber != nil && $0.statementId != nil)
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

    /// Generates synthetic statement transactions for a specific card.
    /// When `includeAllUsers` is true, uses DB queries (all users) instead of UID-isolated store.
    func generateStatementTransactions(forCard card: CreditCard, includeAllUsers: Bool) -> [Transaction] {
        guard let cardId = card.id else { return [] }
        var statementTransactions: [Transaction] = []

        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        for stmt in statements {
            guard let stmtId = stmt.id else { continue }

            let realCount: Int
            let realTotal: Int

            if includeAllUsers {
                // Use DB directly — includes ALL users' transactions
                realCount = (try? DBHelper.shared.getTransactionCountForStatement(statementId: stmtId)) ?? 0
                realTotal = (try? DBHelper.shared.getTransactionSumForStatement(statementId: stmtId)) ?? 0
            } else {
                let allTransactions = TransactionRepository().fetchAllTransactions()
                let stmtTransactions = allTransactions.filter {
                    $0.statementId == stmtId && $0.isCreditCardStatement != true
                }
                realCount = stmtTransactions.count
                realTotal = stmtTransactions.reduce(0) { $0 + $1.amount }
            }

            if realCount == 0 {
                if stmtRepo.fetchCKRecordName(for: stmtId) == nil {
                    recalculateStatementTotal(statementId: stmtId)
                }
                continue
            }

            guard realTotal > 0 else { continue }

            let title = String(format: "creditCard.statement.title".localized, card.name)
            let dueTimestamp = Int(stmt.dueDate.timeIntervalSince1970)

            let data = UITransactionData(
                id: -(stmtId * 1000 + cardId),
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
                creditCardId: cardId,
                statementId: stmtId,
                isCreditCardStatement: true,
                category: .creditCard,
                type: .expense
            )

            statementTransactions.append(Transaction(data: data))
        }

        return statementTransactions
    }

    /// Recalculates a shared statement total using DB (all users) instead of UID-isolated store.
    func recalculateSharedStatementTotal(statementId: Int) {
        stmtRepo.recalculateTotal(statementId: statementId)

        do {
            let count = try DBHelper.shared.getTransactionCountForStatement(statementId: statementId)
            if count == 0 {
                _ = stmtRepo.deleteStatement(statementId: statementId)
            }
        } catch {
            logError("Failed to check shared statement transaction count: \(error)")
        }
    }

    /// One-time migration: updates existing CC installments to use the statement due date
    /// for their dateTimestamp and budgetMonthDate, instead of the original purchase date.
    /// Also cleans up ghost duplicates created by lazy gen before the fix.
    func migrateInstallmentDatesToStatementDueDates(transactionRepo: TransactionRepository) {
        let migrationKey = "hasMigratedCCInstallmentDates_v4"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let allTransactions = transactionRepo.fetchAllTransactions()

        // Phase 1: Clean up ghost duplicates — for each installment parent
        // whose children have a creditCardId, if two children share the same
        // installmentNumber, keep the one with the lowest ID (the original)
        // and delete the rest (ghosts from lazy gen).
        // Note: parent transactions don't have creditCardId, only children do.
        let installmentParents = allTransactions.filter {
            $0.hasInstallments == true && $0.parentTransactionId == nil
        }
        // Only process parents that have CC installment children
        let ccInstallmentParents = installmentParents.filter { parent in
            guard let parentId = parent.id else { return false }
            return allTransactions.contains { $0.parentTransactionId == parentId && $0.creditCardId != nil }
        }

        var deletedCount = 0
        for parent in ccInstallmentParents {
            guard let parentId = parent.id else { continue }
            let children = allTransactions.filter { $0.parentTransactionId == parentId && $0.installmentNumber != nil }

            // Group children by installmentNumber
            var byNumber: [Int: [Transaction]] = [:]
            for child in children {
                if let num = child.installmentNumber {
                    byNumber[num, default: []].append(child)
                }
            }

            for (_, duplicates) in byNumber where duplicates.count > 1 {
                // Sort by ID ascending — keep the lowest (the original), delete the rest
                let sorted = duplicates.sorted { ($0.id ?? Int.max) < ($1.id ?? Int.max) }
                for ghost in sorted.dropFirst() {
                    if let ghostId = ghost.id {
                        try? transactionRepo.delete(id: ghostId)
                        deletedCount += 1
                    }
                }
            }
        }

        if deletedCount > 0 {
            logWarning("[CCInstallmentMigration] Deleted \(deletedCount) ghost duplicate installments")
        }

        // Phase 2: Remap remaining CC installments to statement due dates
        // Re-fetch after deletions
        let freshTransactions = transactionRepo.fetchAllTransactions()
        let ccInstallments = freshTransactions.filter {
            $0.creditCardId != nil && $0.statementId != nil && $0.installmentNumber != nil
        }

        guard !ccInstallments.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Build a lookup of statementId → dueDate
        var statementDueDates: [Int: Date] = [:]
        for cardId in Set(ccInstallments.compactMap({ $0.creditCardId })) {
            let statements = stmtRepo.fetchStatements(forCardId: cardId)
            for stmt in statements {
                if let stmtId = stmt.id {
                    statementDueDates[stmtId] = stmt.dueDate
                }
            }
        }

        var migratedCount = 0
        for tx in ccInstallments {
            guard let txId = tx.id, let stmtId = tx.statementId,
                  let dueDate = statementDueDates[stmtId] else { continue }

            let dueDateTimestamp = Int(dueDate.timeIntervalSince1970)
            let dueDateBudgetMonth = dueDate.monthAnchor
            // Only update if the date is actually different
            if tx.dateTimestamp != dueDateTimestamp || tx.budgetMonthDate != dueDateBudgetMonth {
                transactionRepo.updateDateAndBudgetMonth(
                    transactionId: txId,
                    newDateTimestamp: dueDateTimestamp,
                    newBudgetMonthDate: dueDateBudgetMonth
                )
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            logWarning("[CCInstallmentMigration] Migrated \(migratedCount) installments to statement due dates")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
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
