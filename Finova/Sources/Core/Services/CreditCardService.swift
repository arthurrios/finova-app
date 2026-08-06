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
    ///
    /// This is a *payment* date, so it is business-day adjusted using the global default rule — a
    /// statement is shared by many transactions with potentially different per-transaction rules, so
    /// the per-transaction one is meaningless here.
    ///
    /// `calculateClosingDate` is deliberately NOT adjusted: the closing day is an internal billing
    /// boundary, and shifting it would reroute purchases between cycles and break both the exact-match
    /// statement lookup and the consecutive-cycle chaining that depend on it.
    ///
    /// Only new statements get this. Stored due dates are never rewritten, so changing the default
    /// later cannot mass-move existing installments.
    func calculateDueDate(closingDate: Date, card: CreditCard) -> Date {
        let calendar = Calendar.current
        let closingDay = calendar.component(.day, from: closingDate)
        let closingMonth = calendar.component(.month, from: closingDate)
        let closingYear = calendar.component(.year, from: closingDate)

        let raw: Date
        if card.dueDay > closingDay {
            // Due date same month as closing
            let dueDay = min(card.dueDay, daysInMonth(month: closingMonth, year: closingYear))
            raw = calendar.date(from: DateComponents(year: closingYear, month: closingMonth, day: dueDay))!
        } else {
            // Due date next month after closing
            var dueMonth = closingMonth + 1
            var dueYear = closingYear
            if dueMonth > 12 { dueMonth = 1; dueYear += 1 }
            let dueDay = min(card.dueDay, daysInMonth(month: dueMonth, year: dueYear))
            raw = calendar.date(from: DateComponents(year: dueYear, month: dueMonth, day: dueDay))!
        }

        return BusinessDayAdjuster.adjust(
            raw, rule: UserDefaultsManager.getDefaultBusinessDayRule(), calendar: calendar)
    }

    /// Gets or creates a statement for a transaction on a given card/date.
    ///
    /// The billing cycle a transaction belongs to is decided solely by the card's *current* closing
    /// day (`calculateClosingDate`): purchase day <= closingDay → this month's statement, otherwise
    /// next month's. This matches how credit cards actually work and must never be overridden by
    /// which existing (possibly stale) statement's date range happens to overlap the purchase date.
    ///
    /// Lookup order:
    /// 1. An existing statement with an exact closing-date match under current rules.
    /// 2. An existing statement in the same calendar month as the computed closing date — enforces
    ///    "at most one statement per (card, month)" and reuses a statement that kept old dates after
    ///    the card's closingDay/dueDay changed.
    /// 3. Create a new statement under current card rules.
    func getOrCreateStatement(for card: CreditCard, transactionDate: Date, userId: String) -> CreditCardStatement? {
        let statements = stmtRepo.fetchStatements(forCardId: card.id!)

        let closingDate = calculateClosingDate(card: card, transactionDate: transactionDate)
        let dueDate = calculateDueDate(closingDate: closingDate, card: card)

        // 1. Exact closing-date match under current rules
        if let existingId = stmtRepo.findStatement(creditCardId: card.id!, closingDate: closingDate),
           let exact = statements.first(where: { $0.id == existingId }) {
            return exact
        }

        // 2. Same-month fallback. Lowest id wins so every caller converges on the same survivor
        //    when duplicates already exist in the data.
        let calendar = Calendar.current
        if let sameMonth = statements
            .filter({ calendar.isDate($0.closingDate, equalTo: closingDate, toGranularity: .month) })
            .sorted(by: { ($0.id ?? Int.max) < ($1.id ?? Int.max) })
            .first {
            return sameMonth
        }

        // 3. Create new statement
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

    /// Moves a card transaction onto a different statement at the user's request.
    ///
    /// The move is flagged as an override so `reassignCardTransactions` — which re-derives every
    /// card transaction's statement from the card's current closing day — cannot silently undo it.
    ///
    /// `budget_month_date` follows the target statement's due month so the expense counts against
    /// the budget for the month it is actually billed; the purchase date itself is left alone,
    /// because the purchase still happened when it happened.
    func moveTransactionToStatement(
        transactionId: Int,
        creditCardId: Int,
        toStatementId: Int,
        fromStatementId: Int?,
        transactionRepo: TransactionRepository
    ) {
        do {
            try transactionRepo.updateCreditCardFields(
                transactionId: transactionId,
                creditCardId: creditCardId,
                statementId: toStatementId,
                isCreditCardStatement: false
            )

            DBHelper.shared.setStatementOverridden(transactionId: transactionId, overridden: true)

            let targetStatements = stmtRepo.fetchStatements(forCardId: creditCardId)
            if let targetStatement = targetStatements.first(where: { $0.id == toStatementId }) {
                transactionRepo.updateBudgetMonthDate(
                    transactionId: transactionId,
                    newBudgetMonthDate: targetStatement.dueDate.monthAnchor
                )
            }

            // The source statement is recalculated through `recalculateStatementTotal` so it is
            // deleted if this was its last row; the target cannot be empty, so a plain total is enough.
            stmtRepo.recalculateTotal(statementId: toStatementId)
            if let fromId = fromStatementId, fromId != toStatementId {
                recalculateStatementTotal(statementId: fromId)
            }

            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        } catch {
            logError(
                "Failed to move transaction \(transactionId) to statement \(toStatementId): \(error)")
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

    /// Reshapes a card's FUTURE billing cycles after its closingDay or dueDay changed.
    ///
    /// Deliberately limited to statements that have not closed yet. An invoice the user has already
    /// been billed for is a historical record: rewriting its dates, and then re-routing the
    /// transactions on it, changes what the user was charged last month. Only cycles still ahead of
    /// them can be reshaped, which is also all the card issuer would do.
    func recalculateStatementDatesForCard(_ card: CreditCard, userId: String? = nil, transactionRepo: TransactionRepository? = nil) {
        guard let cardId = card.id else { return }
        let statements = stmtRepo.fetchStatements(forCardId: cardId)
        let now = Date()

        for stmt in statements where stmt.closingDate > now && !stmt.isPaid {
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
        reassignCardTransactions(
            card: card, userId: userId, transactionRepo: transactionRepo, onlyFutureCycles: true)
    }

    /// Reassigns transactions for a card to the statement its date routes to under current card settings.
    ///
    /// Three things are deliberately left alone:
    /// - **Installments that already have a statement.** Their cycle was decided by consecutive
    ///   chaining at creation (`nextStatement`), not by their date, so re-deriving from the date would
    ///   scatter a series that is correctly sequenced — two installments onto one invoice and a month
    ///   with none.
    /// - **Transactions the user moved by hand** (`isStatementOverridden`), which this would silently undo.
    /// - **Anything in a closed cycle**, when `onlyFutureCycles` is set: neither moved out of a
    ///   statement that has closed nor pulled into one, so history stays put and no empty past
    ///   statements get created.
    private func reassignCardTransactions(
        card: CreditCard, userId: String, transactionRepo: TransactionRepository,
        onlyFutureCycles: Bool = false
    ) {
        guard let cardId = card.id else { return }
        let allTransactions = transactionRepo.fetchAllTransactions()
        let cardTransactions = allTransactions.filter {
            $0.creditCardId == cardId && $0.isCreditCardStatement != true
                && !($0.installmentNumber != nil && $0.statementId != nil)
        }

        let now = Date()
        var closedStatementIds: Set<Int> = []
        if onlyFutureCycles {
            closedStatementIds = Set(
                stmtRepo.fetchStatements(forCardId: cardId)
                    .filter { $0.closingDate <= now }
                    .compactMap { $0.id })
        }

        var affectedStatementIds = Set<Int>()

        for tx in cardTransactions {
            guard let txId = tx.id else { continue }

            if DBHelper.shared.isStatementOverridden(transactionId: txId) { continue }

            if onlyFutureCycles, let stmtId = tx.statementId, closedStatementIds.contains(stmtId) {
                continue
            }

            let transactionDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))

            if onlyFutureCycles,
                calculateClosingDate(card: card, transactionDate: transactionDate) <= now
            {
                continue
            }

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
