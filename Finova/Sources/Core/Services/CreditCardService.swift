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
    /// This is a *payment* date, so it is business-day adjusted using the global default rule - a
    /// statement is shared by many transactions with potentially different per-transaction rules, so
    /// the per-transaction one is meaningless here.
    ///
    /// `calculateClosingDate` is deliberately NOT adjusted: the closing day is an internal billing
    /// boundary, and shifting it would reroute purchases between cycles and break the exact-match
    /// statement lookup and consecutive-cycle chaining that depend on it.
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
    /// The billing cycle a transaction belongs to is decided solely by the card's
    /// *current* closing day (`calculateClosingDate`): purchase day <= closingDay →
    /// this month's statement, otherwise next month's. This matches how credit cards
    /// actually work and must never be overridden by which existing (possibly stale)
    /// statement's date range happens to overlap the purchase date.
    ///
    /// Lookup order:
    /// 1. An existing statement with an exact closing-date match under current rules.
    /// 2. An existing statement in the same calendar month as the computed closing
    ///    date (enforces "at most one statement per (card, month)" and reuses a
    ///    statement that kept old dates after the card's closingDay/dueDay changed).
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

        // 2. Same-month fallback
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
        assignStatementIdentity(
            statementId: newId, cardId: newStatement.creditCardId, closingDate: newStatement.closingDate)

        var created = newStatement
        created.id = newId
        return created
    }

    /// Returns the statement representing the billing cycle that comes immediately
    /// after `current`, using the card's *current* closingDay/dueDay to compute the
    /// new cycle's dates. Creates the next statement if it doesn't already exist.
    ///
    /// Use this for CC installment series so each installment N+1 lands one cycle
    /// after installment N regardless of how card rules have changed mid-series.
    /// Date-based routing (`getOrCreateStatement`) can skip a cycle when the
    /// closing day moves earlier, leaving installments orphaned or one month late.
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
        assignStatementIdentity(
            statementId: newId, cardId: newStmt.creditCardId, closingDate: newStmt.closingDate)
        var created = newStmt
        created.id = newId
        return created
    }

    /// Gives a newly created statement the identity every device derives for (card, month).
    ///
    /// Statements are created on demand — whichever device first books a transaction into a cycle
    /// creates it — so two devices independently created two statements for the same cycle and
    /// `ConflictResolver` had to match them on `creditCardId + closingDate`. Deriving the identity
    /// also makes "one statement per (card, month)" true by construction rather than something a
    /// repair pass has to enforce afterwards.
    private func assignStatementIdentity(statementId: Int, cardId: Int, closingDate: Date) {
        let db = DBHelper.shared
        guard let cardUuid = db.uuidIdentity(table: "CreditCards", localId: cardId)?.uuid else { return }
        db.assignDeterministicUuid(
            table: "CreditCardStatements", localId: statementId,
            uuid: DeterministicIdentity.statement(
                cardUuid: cardUuid, statementMonth: closingDate.monthAnchor))
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

    /// Finds an existing statement for a transaction on a given card/date.
    /// Unlike `getOrCreateStatement`, this never creates a new statement.
    /// Uses the same current-rules lookup order minus the create step.
    func getExistingStatement(for card: CreditCard, transactionDate: Date) -> CreditCardStatement? {
        let statements = stmtRepo.fetchStatements(forCardId: card.id!)

        let closingDate = calculateClosingDate(card: card, transactionDate: transactionDate)

        if let existingId = stmtRepo.findStatement(creditCardId: card.id!, closingDate: closingDate),
           let exact = statements.first(where: { $0.id == existingId }) {
            return exact
        }

        let calendar = Calendar.current
        return statements
            .filter { calendar.isDate($0.closingDate, equalTo: closingDate, toGranularity: .month) }
            .sorted { ($0.id ?? Int.max) < ($1.id ?? Int.max) }
            .first
    }

    /// One-time repair: updates `budget_month_date` for transactions that were manually
    /// moved to a different statement (is_statement_overridden = 1). Also restores
    /// `date` values that were incorrectly overwritten with the statement's dueDate.
    func repairBudgetMonthForOverriddenTransactions() {
        let transactionRepo = TransactionRepository()
        let allTransactions = transactionRepo.fetchAllTransactions()

        let overridden = allTransactions.filter { tx in
            guard let txId = tx.id,
                  tx.creditCardId != nil,
                  tx.statementId != nil,
                  tx.isCreditCardStatement != true
            else { return false }
            return DBHelper.shared.isStatementOverridden(transactionId: txId)
        }

        guard !overridden.isEmpty else { return }
        logDebug("[CCRepair] Found \(overridden.count) overridden transactions to check")

        // Build a statement lookup: cardId -> [CreditCardStatement]
        var stmtCache: [Int: [CreditCardStatement]] = [:]

        var fixCount = 0
        for tx in overridden {
            guard let stmtId = tx.statementId, let cardId = tx.creditCardId, let txId = tx.id else { continue }

            if stmtCache[cardId] == nil {
                stmtCache[cardId] = stmtRepo.fetchStatements(forCardId: cardId)
            }
            guard let stmt = stmtCache[cardId]?.first(where: { $0.id == stmtId }) else { continue }

            let expectedBudgetMonth = stmt.dueDate.monthAnchor
            let dueDateTimestamp = Int(stmt.dueDate.timeIntervalSince1970)

            // Restore date if it was incorrectly set to the statement's dueDate
            if tx.dateTimestamp == dueDateTimestamp {
                // Date was overwritten — use the statement's closing date as a reasonable
                // fallback (the purchase happened before the closing date)
                let closingTimestamp = Int(stmt.closingDate.timeIntervalSince1970)
                transactionRepo.updateDateAndBudgetMonth(
                    transactionId: txId,
                    newDateTimestamp: closingTimestamp,
                    newBudgetMonthDate: expectedBudgetMonth
                )
                transactionRepo.markSyncPending(for: txId)
                fixCount += 1
                logDebug("[CCRepair] Restored date for tx \(txId) from dueDate -> closingDate, budgetMonth -> \(expectedBudgetMonth)")
            } else if tx.budgetMonthDate != expectedBudgetMonth {
                // Only fix budget_month_date, keep original purchase date
                transactionRepo.updateBudgetMonthDate(
                    transactionId: txId,
                    newBudgetMonthDate: expectedBudgetMonth
                )
                transactionRepo.markSyncPending(for: txId)
                fixCount += 1
                logDebug("[CCRepair] Fixed tx \(txId) budgetMonth \(tx.budgetMonthDate) -> \(expectedBudgetMonth)")
            }
        }

        if fixCount > 0 {
            logDebug("[CCRepair] Repaired \(fixCount) overridden transactions")
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        }
    }

    /// Recalculates totals for every statement belonging to the current user.
    /// Useful on launch to fix stale totals from past deletes that didn't recalculate.
    func recalculateAllStatementTotals() {
        guard let uid = AuthenticationManager.shared.currentUser?.uid else { return }
        let cards = cardRepo.fetchAllCards(userId: uid)
        for card in cards where !card.isDeleted {
            guard let cardId = card.id else { continue }
            let statements = stmtRepo.fetchStatements(forCardId: cardId)
            for statement in statements {
                guard let stmtId = statement.id else { continue }
                recalculateStatementTotal(statementId: stmtId)
            }
        }
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
                StatementNotificationManager.shared.cancelNotifications(for: statementId)
                _ = stmtRepo.deleteStatement(statementId: statementId)
            } else {
                // Statement total changed — reschedule its notifications with updated amount
                StatementNotificationManager.shared.rescheduleAllNotifications()
            }
        } catch {
            logError("Failed to check statement transaction count: \(error)")
        }
    }

    /// Moves a CC transaction from one statement to another, recalculating both totals.
    /// Sets `is_statement_overridden` so `reassignMisplacedTransactions` won't move it back.
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

            // Mark as manually overridden so auto-reassign won't undo this
            DBHelper.shared.setStatementOverridden(transactionId: transactionId, overridden: true)

            // Update budget_month_date to match the target statement's period so the
            // expense counts toward the correct budget month. Keep the original
            // purchase date (dateTimestamp) unchanged.
            let targetStatements = stmtRepo.fetchStatements(forCardId: creditCardId)
            if let targetStatement = targetStatements.first(where: { $0.id == toStatementId }) {
                let newBudgetMonth = targetStatement.dueDate.monthAnchor
                transactionRepo.updateBudgetMonthDate(
                    transactionId: transactionId,
                    newBudgetMonthDate: newBudgetMonth
                )
            }

            // Mark transaction as pending sync
            transactionRepo.markSyncPending(for: transactionId)

            // Recalculate totals for both statements
            stmtRepo.recalculateTotal(statementId: toStatementId)
            stmtRepo.markSyncPending(for: toStatementId)

            if let fromId = fromStatementId {
                stmtRepo.recalculateTotal(statementId: fromId)
                stmtRepo.markSyncPending(for: fromId)
            }

            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        } catch {
            logError("Failed to move transaction \(transactionId) to statement \(toStatementId): \(error)")
        }
    }

    /// Generates synthetic statement transactions for the dashboard.
    func generateStatementTransactions(userId: String) -> [Transaction] {
        let cards = cardRepo.fetchAllCards(userId: userId)
        var statementTransactions: [Transaction] = []

        // Use the same source as the ViewModel
        let allSecureTransactions = TransactionRepository().fetchAllTransactions()
        let settledInstallmentIds = DBHelper.shared.settledInstallmentIds()

        for card in cards {
            let statements = stmtRepo.fetchStatements(forCardId: card.id!)

            // --- Diagnostic: detect duplicate statements (same closingDate) ---
            var closingDateMap: [Int: [CreditCardStatement]] = [:]
            for s in statements {
                let key = Int(s.closingDate.timeIntervalSince1970)
                closingDateMap[key, default: []].append(s)
            }
            for (closingTs, dupes) in closingDateMap where dupes.count > 1 {
                let closingDate = Date(timeIntervalSince1970: TimeInterval(closingTs))
                logWarning("[DiagStmt] DUPLICATE statements for card \(card.name) closing=\(closingDate): \(dupes.map { "id=\($0.id ?? -1) due=\($0.dueDate)" })")
            }

            // Diagnostic: log current + previous month statements with duplicate detection
            let now = Date()
            let calendar = Calendar.current
            for label in ["CURRENT", "PREVIOUS"] {
                let refDate = label == "CURRENT" ? now : calendar.date(byAdding: .month, value: -1, to: now)!
                let monthStmts = statements.filter { calendar.isDate($0.dueDate, equalTo: refDate, toGranularity: .month) }
                for s in monthStmts {
                    let txs = allSecureTransactions.filter { $0.statementId == s.id && $0.isCreditCardStatement != true }
                    logWarning("[DiagStmt] \(label) month stmt id=\(s.id ?? -1) closing=\(s.closingDate) due=\(s.dueDate) txCount=\(txs.count) txSum=\(txs.reduce(0) { $0 + $1.amount })")
                    for t in txs {
                        logWarning("[DiagStmt]   tx id=\(t.id ?? -1) '\(t.title)' amt=\(t.amount) install#=\(t.installmentNumber ?? -1)/\(t.totalInstallments ?? -1) date=\(Date(timeIntervalSince1970: TimeInterval(t.dateTimestamp)))")
                    }
                    // Flag potential duplicates: same title + same installmentNumber in one statement
                    struct TxKey: Hashable { let title: String; let installmentNumber: Int? }
                    var seen: [TxKey: [Int]] = [:]
                    for t in txs {
                        let key = TxKey(title: t.title, installmentNumber: t.installmentNumber)
                        seen[key, default: []].append(t.id ?? -1)
                    }
                    for (key, ids) in seen where ids.count > 1 {
                        logWarning("[DiagStmt]   ⚠️ DUPLICATE: '\(key.title)' install#=\(key.installmentNumber ?? -1) appears \(ids.count)x, ids=\(ids)")
                    }
                }
            }

            // Also check: CC transactions for this card NOT in any live statement
            let liveStmtIds = Set(statements.compactMap { $0.id })
            let orphanedForCard = allSecureTransactions.filter {
                $0.creditCardId == card.id && $0.isCreditCardStatement != true
                && ($0.statementId == nil || !liveStmtIds.contains($0.statementId!))
            }
            if !orphanedForCard.isEmpty {
                logWarning("[DiagStmt] \(orphanedForCard.count) CC txs for card \(card.name) with NO live statement")
                for t in orphanedForCard.prefix(10) {
                    logWarning("[DiagStmt]   orphan id=\(t.id ?? -1) '\(t.title)' stmtId=\(t.statementId ?? -1) amt=\(t.amount)")
                }
            }
            // --- End diagnostic ---

            for stmt in statements {
                // Count and sum from the secure store (consistent with what StatementDetailsViewModel shows)
                // Installments paid early are excluded: their amount has already been charged on the
                // early-payment debit, so counting them here would bill the user twice for the same
                // installment. Mirrors `DBHelper.statementRowFilter`, which the scoped overload uses.
                let stmtTransactions = allSecureTransactions.filter {
                    $0.statementId == stmt.id && $0.isCreditCardStatement != true
                    && !($0.hasInstallments == true && $0.parentTransactionId == nil)
                    && !($0.isRecurring == true && $0.parentTransactionId == nil)
                    && !($0.id.map(settledInstallmentIds.contains) ?? false)
                }

                let realCount = stmtTransactions.count
                // Signed by type, mirroring `DBHelper.signedAmount`: a credit on the card reduces
                // what the invoice charges.
                let realTotal = stmtTransactions.reduce(0) {
                    $1.type == .income ? $0 - $1.amount : $0 + $1.amount
                }

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

    /// One-time migration: collapses duplicate (same year+month) statements per card
    /// into the oldest one, preserving the keeper's closing/due dates. Fixes the case
    /// where editing a card's closingDay/dueDay then correcting transactions created
    /// a second statement in the same month with the new dates.
    func consolidateDuplicateStatementsByMonth(userId: String, transactionRepo: TransactionRepository) {
        let migrationKey = "hasConsolidatedDuplicateMonthlyStatements_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let cards = cardRepo.fetchAllCards(userId: userId)
        let calendar = Calendar.current
        var mergedTxCount = 0
        var deletedStmtCount = 0

        struct MonthKey: Hashable { let year: Int; let month: Int }

        for card in cards {
            guard let cardId = card.id else { continue }
            let statements = stmtRepo.fetchStatements(forCardId: cardId)

            var byMonth: [MonthKey: [CreditCardStatement]] = [:]
            for stmt in statements {
                let key = MonthKey(
                    year: calendar.component(.year, from: stmt.closingDate),
                    month: calendar.component(.month, from: stmt.closingDate)
                )
                byMonth[key, default: []].append(stmt)
            }

            for (_, group) in byMonth where group.count > 1 {
                let sorted = group.sorted { ($0.id ?? Int.max) < ($1.id ?? Int.max) }
                guard let keeper = sorted.first, let keeperId = keeper.id else { continue }

                // Re-fetch transactions per merge so we see updates from prior iterations
                let allTransactions = transactionRepo.fetchAllTransactions()

                for stmt in sorted.dropFirst() {
                    guard let dropId = stmt.id else { continue }

                    let dropTxs = allTransactions.filter {
                        $0.statementId == dropId && $0.isCreditCardStatement != true
                    }
                    for tx in dropTxs {
                        guard let txId = tx.id else { continue }
                        do {
                            try transactionRepo.updateCreditCardFields(
                                transactionId: txId,
                                creditCardId: cardId,
                                statementId: keeperId,
                                isCreditCardStatement: false
                            )
                            mergedTxCount += 1
                        } catch {
                            logError("[StmtConsolidation] Failed to move tx \(txId) from \(dropId) to \(keeperId): \(error)")
                        }
                    }

                    _ = stmtRepo.deleteStatement(statementId: dropId)
                    deletedStmtCount += 1
                    logWarning("[StmtConsolidation] Merged stmt \(dropId) into \(keeperId) (card \(cardId))")
                }

                // Recalculate keeper total directly (bypassing the cloud-synced guard
                // in recalculateStatementTotal — keeper now has freshly-attached txs).
                stmtRepo.recalculateTotal(statementId: keeperId)
            }
        }

        if mergedTxCount > 0 || deletedStmtCount > 0 {
            logWarning("[StmtConsolidation] Done: moved \(mergedTxCount) txs, deleted \(deletedStmtCount) duplicate statements")
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Recalculates closing and due dates for statements that haven't closed yet,
    /// then reassigns transactions in those future cycles to the correct statements.
    /// Past statements (closingDate already in the past) are left untouched so historical
    /// records remain stable.
    /// Call this after editing a card's closingDay or dueDay.
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
        reassignCardTransactions(card: card, userId: userId, transactionRepo: transactionRepo, onlyFutureCycles: true)
    }

    /// Reassigns all transactions for a card to their correct statements based on current card settings.
    /// When `onlyFutureCycles` is true, leaves transactions in already-closed statements alone and
    /// avoids moving any transaction into a target whose closing date is in the past — preserving
    /// historical records when the user only wants to reshape future billing cycles.
    private func reassignCardTransactions(card: CreditCard, userId: String, transactionRepo: TransactionRepository, onlyFutureCycles: Bool = false) {
        guard let cardId = card.id else { return }
        let allTransactions = transactionRepo.fetchAllTransactions()
        // Skip CC installments that already have a statementId — their dateTimestamp
        // has been remapped to the statement due date, so getOrCreateStatement would
        // compute the wrong statement from the remapped date.
        let cardTransactions = allTransactions.filter {
            $0.creditCardId == cardId && $0.isCreditCardStatement != true
            && !($0.installmentNumber != nil && $0.statementId != nil)
        }

        let now = Date()
        var closedStatementIds: Set<Int> = []
        if onlyFutureCycles {
            let stmts = stmtRepo.fetchStatements(forCardId: cardId)
            closedStatementIds = Set(stmts.filter { $0.closingDate <= now }.compactMap { $0.id })
        }

        var affectedStatementIds = Set<Int>()

        for tx in cardTransactions {
            guard let txId = tx.id else { continue }

            // Skip transactions whose statement was manually overridden by the user
            if DBHelper.shared.isStatementOverridden(transactionId: txId) { continue }

            // Don't move transactions out of past statements
            if onlyFutureCycles, let stmtId = tx.statementId, closedStatementIds.contains(stmtId) {
                continue
            }

            let transactionDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))

            // Don't pull transactions into a past cycle (also avoids creating empty past statements)
            if onlyFutureCycles {
                let targetClosingDate = calculateClosingDate(card: card, transactionDate: transactionDate)
                if targetClosingDate <= now { continue }
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

    /// Propagates credit_card_id from installment parents to children that lost their CC link.
    /// This repairs data from a sync bug that set credit_card_id = NULL on some CC transactions.
    func repairCreditCardLinksFromParents(userId: String, transactionRepo: TransactionRepository) {
        let allTransactions = transactionRepo.fetchAllTransactions()
        let calendar = Calendar.current
        var fixedCount = 0

        // Phase 1: Parent → children propagation
        // Parents that still have creditCardId — restore on orphaned children
        let ccParents = allTransactions.filter {
            $0.hasInstallments == true && $0.parentTransactionId == nil && $0.creditCardId != nil
        }

        for parent in ccParents {
            guard let parentId = parent.id,
                  let cardId = parent.creditCardId,
                  let card = cardRepo.fetchCard(byId: cardId),
                  let totalInstallments = parent.totalInstallments,
                  totalInstallments > 1 else { continue }

            let startDate = Date(timeIntervalSince1970: TimeInterval(parent.dateTimestamp))

            // Children missing their CC link
            let orphanedChildren = allTransactions.filter {
                $0.parentTransactionId == parentId && $0.installmentNumber != nil && $0.creditCardId == nil
            }

            for child in orphanedChildren {
                guard let childId = child.id,
                      let installmentNumber = child.installmentNumber else { continue }

                let targetDate = calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
                guard let statement = getOrCreateStatement(for: card, transactionDate: targetDate, userId: userId),
                      let stmtId = statement.id else { continue }

                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: childId,
                        creditCardId: cardId,
                        statementId: stmtId,
                        isCreditCardStatement: false
                    )
                    let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
                    let dueDateBudgetMonth = statement.dueDate.monthAnchor
                    transactionRepo.updateDateAndBudgetMonth(
                        transactionId: childId,
                        newDateTimestamp: dueDateTimestamp,
                        newBudgetMonthDate: dueDateBudgetMonth
                    )
                    recalculateStatementTotal(statementId: stmtId)
                    fixedCount += 1
                    logWarning("[CCRepair] Restored CC link for child \(childId) #\(installmentNumber) → card \(cardId), stmt \(stmtId)")
                } catch {
                    logError("[CCRepair] Failed to restore CC link for child \(childId): \(error)")
                }
            }
        }

        // Phase 2: Child → parent reverse propagation
        // If parent lost its creditCardId but any child still has it, restore from child
        let parentsWithoutCC = allTransactions.filter {
            $0.hasInstallments == true && $0.parentTransactionId == nil && $0.creditCardId == nil
        }

        for parent in parentsWithoutCC {
            guard let parentId = parent.id else { continue }

            guard let childWithCC = allTransactions.first(where: {
                $0.parentTransactionId == parentId && $0.creditCardId != nil
            }),
            let cardId = childWithCC.creditCardId,
            let card = cardRepo.fetchCard(byId: cardId) else { continue }

            let parentDate = Date(timeIntervalSince1970: TimeInterval(parent.dateTimestamp))
            guard let statement = getOrCreateStatement(for: card, transactionDate: parentDate, userId: userId),
                  let stmtId = statement.id else { continue }

            do {
                try transactionRepo.updateCreditCardFields(
                    transactionId: parentId,
                    creditCardId: cardId,
                    statementId: stmtId,
                    isCreditCardStatement: false
                )
                recalculateStatementTotal(statementId: stmtId)
                fixedCount += 1
                logWarning("[CCRepair] Restored CC link for parent \(parentId) from child → card \(cardId)")

                // Now also fix remaining orphaned children of this parent
                let remainingOrphans = allTransactions.filter {
                    $0.parentTransactionId == parentId && $0.installmentNumber != nil && $0.creditCardId == nil
                }
                for child in remainingOrphans {
                    guard let childId = child.id,
                          let installmentNumber = child.installmentNumber else { continue }
                    let targetDate = calendar.date(byAdding: .month, value: installmentNumber - 1, to: parentDate) ?? parentDate
                    guard let childStmt = getOrCreateStatement(for: card, transactionDate: targetDate, userId: userId),
                          let childStmtId = childStmt.id else { continue }
                    do {
                        try transactionRepo.updateCreditCardFields(
                            transactionId: childId,
                            creditCardId: cardId,
                            statementId: childStmtId,
                            isCreditCardStatement: false
                        )
                        let dueDateTimestamp = Int(childStmt.dueDate.timeIntervalSince1970)
                        transactionRepo.updateDateAndBudgetMonth(
                            transactionId: childId,
                            newDateTimestamp: dueDateTimestamp,
                            newBudgetMonthDate: childStmt.dueDate.monthAnchor
                        )
                        recalculateStatementTotal(statementId: childStmtId)
                        fixedCount += 1
                    } catch {
                        logError("[CCRepair] Failed to restore CC link for child \(childId) in phase 2: \(error)")
                    }
                }
            } catch {
                logError("[CCRepair] Failed to restore CC link for parent \(parentId): \(error)")
            }
        }

        // Phase 3: Match orphaned installment children to statements by dueDate timestamp.
        // If an installment's dateTimestamp matches a statement's dueDate, it belonged to that card/statement.
        let cards = cardRepo.fetchAllCards(userId: userId)
        var dueDateMap: [Int: (cardId: Int, stmtId: Int)] = [:]
        for card in cards {
            guard let cardId = card.id else { continue }
            let stmts = stmtRepo.fetchStatements(forCardId: cardId)
            for stmt in stmts {
                guard let stmtId = stmt.id else { continue }
                let dueDateTimestamp = Int(stmt.dueDate.timeIntervalSince1970)
                dueDateMap[dueDateTimestamp] = (cardId: cardId, stmtId: stmtId)
            }
        }

        // Re-fetch to pick up phase 1/2 fixes
        TransactionRepository.invalidateCache()
        let refreshedTransactions = transactionRepo.fetchAllTransactions()

        let orphanedByDueDate = refreshedTransactions.filter {
            $0.creditCardId == nil && $0.parentTransactionId != nil && $0.installmentNumber != nil
        }

        if !orphanedByDueDate.isEmpty {
            logWarning("[CCRepair] Phase 3: \(orphanedByDueDate.count) orphaned installments, checking dueDate match against \(dueDateMap.count) statement due dates")
        }

        for tx in orphanedByDueDate {
            guard let txId = tx.id else { continue }
            if let match = dueDateMap[tx.dateTimestamp] {
                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: txId,
                        creditCardId: match.cardId,
                        statementId: match.stmtId,
                        isCreditCardStatement: false
                    )
                    recalculateStatementTotal(statementId: match.stmtId)
                    fixedCount += 1
                    logWarning("[CCRepair] Phase 3: matched tx \(txId) #\(tx.installmentNumber ?? 0) to card \(match.cardId) stmt \(match.stmtId) via dueDate")
                } catch {
                    logError("[CCRepair] Phase 3: failed to restore tx \(txId): \(error)")
                }
            }
        }

        // Phase 4: Single-card fallback — if exactly one card exists, assign remaining
        // orphaned installments to it using parent startDate + installmentNumber.
        TransactionRepository.invalidateCache()
        let finalTransactions = transactionRepo.fetchAllTransactions()

        let stillOrphaned = finalTransactions.filter {
            $0.creditCardId == nil && $0.parentTransactionId != nil && $0.installmentNumber != nil
        }

        if !stillOrphaned.isEmpty && cards.count == 1, let card = cards.first, let cardId = card.id {
            logWarning("[CCRepair] Phase 4: \(stillOrphaned.count) orphans remain, single card \(cardId) fallback")

            // Group orphans by parent
            let parentIds = Set(stillOrphaned.compactMap { $0.parentTransactionId })
            for parentId in parentIds {
                guard let parent = finalTransactions.first(where: { $0.id == parentId }) else { continue }
                let startDate = Date(timeIntervalSince1970: TimeInterval(parent.dateTimestamp))

                // Fix parent if needed
                if parent.creditCardId == nil {
                    let parentDate = startDate
                    if let stmt = getOrCreateStatement(for: card, transactionDate: parentDate, userId: userId),
                       let stmtId = stmt.id {
                        do {
                            try transactionRepo.updateCreditCardFields(
                                transactionId: parentId,
                                creditCardId: cardId,
                                statementId: stmtId,
                                isCreditCardStatement: false
                            )
                            recalculateStatementTotal(statementId: stmtId)
                            fixedCount += 1
                            logWarning("[CCRepair] Phase 4: restored parent \(parentId) → card \(cardId)")
                        } catch {
                            logError("[CCRepair] Phase 4: failed to restore parent \(parentId): \(error)")
                        }
                    }
                }

                // Fix children
                let orphanChildren = stillOrphaned.filter { $0.parentTransactionId == parentId }
                for child in orphanChildren {
                    guard let childId = child.id,
                          let installmentNumber = child.installmentNumber else { continue }
                    let targetDate = calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
                    guard let stmt = getOrCreateStatement(for: card, transactionDate: targetDate, userId: userId),
                          let stmtId = stmt.id else { continue }
                    do {
                        try transactionRepo.updateCreditCardFields(
                            transactionId: childId,
                            creditCardId: cardId,
                            statementId: stmtId,
                            isCreditCardStatement: false
                        )
                        let dueDateTimestamp = Int(stmt.dueDate.timeIntervalSince1970)
                        transactionRepo.updateDateAndBudgetMonth(
                            transactionId: childId,
                            newDateTimestamp: dueDateTimestamp,
                            newBudgetMonthDate: stmt.dueDate.monthAnchor
                        )
                        recalculateStatementTotal(statementId: stmtId)
                        fixedCount += 1
                    } catch {
                        logError("[CCRepair] Phase 4: failed to restore child \(childId): \(error)")
                    }
                }
            }
        } else if !stillOrphaned.isEmpty && cards.count > 1 {
            logWarning("[CCRepair] Phase 4: \(stillOrphaned.count) orphans remain but \(cards.count) cards exist — cannot auto-assign. Need manual or cloud recovery.")
        }

        // Final diagnostic
        TransactionRepository.invalidateCache()
        let diagnosticTxs = transactionRepo.fetchAllTransactions()
        let remainingOrphanedInstallments = diagnosticTxs.filter {
            $0.creditCardId == nil && $0.parentTransactionId != nil && $0.installmentNumber != nil
        }
        let installmentParentsNoCC = diagnosticTxs.filter {
            $0.hasInstallments == true && $0.parentTransactionId == nil && $0.creditCardId == nil
        }
        logWarning("[CCRepair] repairCreditCardLinksFromParents DONE: restored \(fixedCount) total")
        logWarning("[CCRepair]   Cards: \(cards.count), Statements: \(dueDateMap.count)")
        logWarning("[CCRepair]   Remaining orphaned installment children: \(remainingOrphanedInstallments.count)")
        logWarning("[CCRepair]   Installment parents without CC: \(installmentParentsNoCC.count)")

        if !installmentParentsNoCC.isEmpty {
            for p in installmentParentsNoCC.prefix(5) {
                logWarning("[CCRepair]     parent id=\(p.id ?? -1) '\(p.title)' total=\(p.totalInstallments ?? 0) date=\(Date(timeIntervalSince1970: TimeInterval(p.dateTimestamp)))")
            }
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

            // Installment dates are remapped to statement due dates — reverse-compute
            // the closing date so getOrCreateStatement finds/creates the correct statement.
            let transactionDate: Date
            if tx.installmentNumber != nil {
                let dueDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                transactionDate = reverseClosingDate(dueDate: dueDate, card: card)
            } else {
                transactionDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
            }
            if let statement = getOrCreateStatement(for: card, transactionDate: transactionDate, userId: userId) {
                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: txId,
                        creditCardId: cardId,
                        statementId: statement.id!,
                        isCreditCardStatement: false
                    )
                    // Only remap date for installments — their dates are mapped to
                    // statement due dates at creation. Regular CC transactions keep
                    // their original purchase date.
                    if tx.installmentNumber != nil {
                        let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
                        let dueDateBudgetMonth = statement.dueDate.monthAnchor
                        transactionRepo.updateDateAndBudgetMonth(
                            transactionId: txId,
                            newDateTimestamp: dueDateTimestamp,
                            newBudgetMonthDate: dueDateBudgetMonth
                        )
                    }
                    recalculateStatementTotal(statementId: statement.id!)
                } catch {
                    logError("Failed to repair orphaned transaction \(txId): \(error)")
                }
            }
        }
    }

    /// Authoritative repair for CC installments: recomputes the correct statement for each
    /// installment child using the parent's start date + installmentNumber, regardless of
    /// what the child's current dateTimestamp or statementId says.
    /// This handles all cases: NULL statementId, stale statementId, wrong statementId.
    func repairInstallmentStatementLinks(userId: String, transactionRepo: TransactionRepository) {
        let allTransactions = transactionRepo.fetchAllTransactions()
        let calendar = Calendar.current

        logWarning("[CCRepair] repairInstallmentStatementLinks: total transactions = \(allTransactions.count)")

        // Find installment parents
        let parents = allTransactions.filter { $0.hasInstallments == true && $0.parentTransactionId == nil }
        logWarning("[CCRepair] Found \(parents.count) installment parents (hasInstallments=true, parentTransactionId=nil)")

        if parents.isEmpty {
            // Also check for parents with parentTransactionId == self.id
            let altParents = allTransactions.filter { $0.hasInstallments == true }
            logWarning("[CCRepair] Alt check: \(altParents.count) transactions with hasInstallments=true")
            for p in altParents {
                logWarning("[CCRepair]   parent id=\(p.id ?? -1), parentTxId=\(p.parentTransactionId ?? -1), title=\(p.title), totalInstallments=\(p.totalInstallments ?? 0)")
            }
        }

        guard !parents.isEmpty else { return }

        var fixedCount = 0

        for parent in parents {
            guard let parentId = parent.id,
                  let totalInstallments = parent.totalInstallments,
                  totalInstallments > 1 else { continue }

            let startDate = Date(timeIntervalSince1970: TimeInterval(parent.dateTimestamp))

            // Find children of this parent
            let children = allTransactions.filter {
                $0.parentTransactionId == parentId && $0.installmentNumber != nil
            }

            logWarning("[CCRepair] Parent \(parentId) '\(parent.title)': startDate=\(startDate), totalInstallments=\(totalInstallments), children found=\(children.count)")

            // Process children in installmentNumber order so consecutive-cycle routing
            // (each installment N+1 lands one cycle after N) stays stable.
            let sortedChildren = children.sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
            var previousChildStatement: CreditCardStatement? = nil

            for child in sortedChildren {
                guard let childId = child.id,
                      let installmentNumber = child.installmentNumber else {
                    logWarning("[CCRepair]   Skipping child: missing id or installmentNumber")
                    continue
                }

                guard let cardId = child.creditCardId else {
                    logWarning("[CCRepair]   Child \(childId) #\(installmentNumber): no creditCardId, skipping")
                    previousChildStatement = nil
                    continue
                }

                guard let card = cardRepo.fetchCard(byId: cardId) else {
                    logWarning("[CCRepair]   Child \(childId) #\(installmentNumber): card \(cardId) not found, skipping")
                    previousChildStatement = nil
                    continue
                }

                // Compute the correct original installment date from parent start date
                let targetDate = calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
                let targetYear = calendar.component(.year, from: targetDate)
                let targetMonth = calendar.component(.month, from: targetDate)
                let originalDay = calendar.component(.day, from: startDate)
                let maxDay = calendar.range(of: .day, in: .month, for: targetDate)?.count ?? 28
                let validDay = min(originalDay, maxDay)
                let installmentDate = calendar.date(from: DateComponents(year: targetYear, month: targetMonth, day: validDay)) ?? targetDate

                // For installment 1 (or when we lost the anchor), route by date.
                // For installments 2+, route via nextStatement(after: previous) so
                // the series stays on consecutive billing cycles even when card
                // rules have changed mid-series.
                let correctStatement: CreditCardStatement?
                if let prev = previousChildStatement {
                    correctStatement = nextStatement(after: prev, for: card, userId: userId)
                } else {
                    correctStatement = getOrCreateStatement(for: card, transactionDate: installmentDate, userId: userId)
                }

                guard let correctStatement = correctStatement,
                      let correctStmtId = correctStatement.id else { continue }

                // Check if already correct
                let correctDueTimestamp = Int(correctStatement.dueDate.timeIntervalSince1970)
                if child.statementId == correctStmtId && child.dateTimestamp == correctDueTimestamp {
                    previousChildStatement = correctStatement
                    continue // Already correct
                }

                // Fix: re-link and remap date
                let oldStmtId = child.statementId
                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: childId,
                        creditCardId: cardId,
                        statementId: correctStmtId,
                        isCreditCardStatement: false
                    )
                    transactionRepo.updateDateAndBudgetMonth(
                        transactionId: childId,
                        newDateTimestamp: correctDueTimestamp,
                        newBudgetMonthDate: correctStatement.dueDate.monthAnchor
                    )
                    recalculateStatementTotal(statementId: correctStmtId)
                    if let oldId = oldStmtId, oldId != correctStmtId {
                        recalculateStatementTotal(statementId: oldId)
                    }
                    previousChildStatement = correctStatement
                    fixedCount += 1
                } catch {
                    logError("Failed to fix installment \(childId) statement link: \(error)")
                }
            }
        }

        if fixedCount > 0 {
            logWarning("[CCRepair] Fixed \(fixedCount) installment statement links")
        }

        // Diagnostic: find CC transactions without statements
        let ccWithoutStmt = allTransactions.filter {
            $0.creditCardId != nil && $0.statementId == nil && $0.isCreditCardStatement != true
        }
        logWarning("[CCRepair] CC transactions with NO statementId: \(ccWithoutStmt.count)")
        for tx in ccWithoutStmt.prefix(10) {
            logWarning("[CCRepair]   id=\(tx.id ?? -1) '\(tx.title)' cardId=\(tx.creditCardId ?? -1) parentTxId=\(tx.parentTransactionId ?? -1) installment#=\(tx.installmentNumber ?? -1) date=\(Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp)))")
        }

        // Diagnostic: find CC transactions with stale statements
        let ccWithStmt = allTransactions.filter {
            $0.creditCardId != nil && $0.statementId != nil && $0.isCreditCardStatement != true
        }
        var staleCount = 0
        var statementsCache: [Int: Set<Int>] = [:]
        for tx in ccWithStmt {
            guard let cardId = tx.creditCardId, let stmtId = tx.statementId else { continue }
            if statementsCache[cardId] == nil {
                let stmts = stmtRepo.fetchStatements(forCardId: cardId)
                statementsCache[cardId] = Set(stmts.compactMap { $0.id })
            }
            if !(statementsCache[cardId]?.contains(stmtId) ?? false) {
                staleCount += 1
                if staleCount <= 5 {
                    logWarning("[CCRepair]   STALE: id=\(tx.id ?? -1) '\(tx.title)' stmtId=\(stmtId) cardId=\(cardId)")
                }
            }
        }
        logWarning("[CCRepair] CC transactions with STALE statementId: \(staleCount)")
        logWarning("[CCRepair] CC transactions with VALID statementId: \(ccWithStmt.count - staleCount)")
    }

    /// Deduplicates CC installment series and reassigns each installment to the correct
    /// statement based on sequential monthly progression from installment #1.
    /// Groups installments by (title, totalInstallments, creditCardId) to identify series.
    func deduplicateAndFixCCInstallments(userId: String, transactionRepo: TransactionRepository) {
        let migrationKey = "hasDeduplicatedCCInstallments_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let allTransactions = transactionRepo.fetchAllTransactions()

        // Find all CC installment transactions (have creditCardId + installmentNumber)
        let ccInstallments = allTransactions.filter {
            $0.creditCardId != nil && $0.installmentNumber != nil && $0.isCreditCardStatement != true
        }

        guard !ccInstallments.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Group into series by (title, creditCardId, totalInstallments)
        struct SeriesKey: Hashable {
            let title: String
            let creditCardId: Int
            let totalInstallments: Int
        }

        var series: [SeriesKey: [Transaction]] = [:]
        for tx in ccInstallments {
            guard let cardId = tx.creditCardId,
                  let total = tx.totalInstallments else { continue }
            let key = SeriesKey(title: tx.title, creditCardId: cardId, totalInstallments: total)
            series[key, default: []].append(tx)
        }

        var totalDeleted = 0
        var totalFixed = 0

        for (key, transactions) in series {
            guard let card = cardRepo.fetchCard(byId: key.creditCardId) else { continue }

            // Group by installmentNumber
            var byNumber: [Int: [Transaction]] = [:]
            for tx in transactions {
                if let num = tx.installmentNumber {
                    byNumber[num, default: []].append(tx)
                }
            }

            // Step 1: Deduplicate — keep lowest ID for each installment number
            for (num, duplicates) in byNumber where duplicates.count > 1 {
                let sorted = duplicates.sorted { ($0.id ?? Int.max) < ($1.id ?? Int.max) }
                for dup in sorted.dropFirst() {
                    if let dupId = dup.id {
                        if let stmtId = dup.statementId {
                            try? transactionRepo.delete(id: dupId)
                            recalculateStatementTotal(statementId: stmtId)
                        } else {
                            try? transactionRepo.delete(id: dupId)
                        }
                        totalDeleted += 1
                    }
                }
                // Keep only the survivor
                byNumber[num] = [sorted[0]]
            }

            // Step 2: Find installment #1 to determine the series start date
            // Use reverseClosingDate to recover the original transaction date from the due date
            guard let firstInstallment = byNumber[1]?.first else {
                logWarning("[CCRepair] Series '\(key.title)': no installment #1 found, skipping")
                continue
            }

            let firstDueDate = Date(timeIntervalSince1970: TimeInterval(firstInstallment.dateTimestamp))
            let originalStartDate = reverseClosingDate(dueDate: firstDueDate, card: card)

            logWarning("[CCRepair] Series '\(key.title)' (\(key.totalInstallments) installments): startDate=\(originalStartDate)")

            let calendar = Calendar.current

            // Step 3: Reassign each installment to the correct statement
            for installmentNumber in 1...key.totalInstallments {
                guard let tx = byNumber[installmentNumber]?.first,
                      let txId = tx.id else { continue }

                // Compute correct date: startDate + (N-1) months
                let correctDate = calendar.date(byAdding: .month, value: installmentNumber - 1, to: originalStartDate) ?? originalStartDate

                guard let correctStatement = getOrCreateStatement(for: card, transactionDate: correctDate, userId: userId),
                      let correctStmtId = correctStatement.id else { continue }

                let correctDueTimestamp = Int(correctStatement.dueDate.timeIntervalSince1970)

                // Only update if wrong
                if tx.statementId != correctStmtId || tx.dateTimestamp != correctDueTimestamp {
                    let oldStmtId = tx.statementId
                    do {
                        try transactionRepo.updateCreditCardFields(
                            transactionId: txId,
                            creditCardId: key.creditCardId,
                            statementId: correctStmtId,
                            isCreditCardStatement: false
                        )
                        transactionRepo.updateDateAndBudgetMonth(
                            transactionId: txId,
                            newDateTimestamp: correctDueTimestamp,
                            newBudgetMonthDate: correctStatement.dueDate.monthAnchor
                        )
                        recalculateStatementTotal(statementId: correctStmtId)
                        if let oldId = oldStmtId, oldId != correctStmtId {
                            recalculateStatementTotal(statementId: oldId)
                        }
                        totalFixed += 1
                        logWarning("[CCRepair]   Fixed '\(key.title)' #\(installmentNumber) → stmt \(correctStmtId) (due \(correctStatement.dueDate))")
                    } catch {
                        logError("[CCRepair] Failed to fix '\(key.title)' #\(installmentNumber): \(error)")
                    }
                }
            }
        }

        // Force-recalculate ALL CC statement totals (bypasses the ck_record_name guard
        // which would skip cloud-synced statements with stale totals)
        let allCards = cardRepo.fetchAllCards(userId: userId)
        if allCards.isEmpty {
            // Fallback: get card IDs from the CC transactions themselves
            let cardIds = Set(ccInstallments.compactMap { $0.creditCardId })
            for cardId in cardIds {
                let stmts = stmtRepo.fetchStatements(forCardId: cardId)
                for stmt in stmts {
                    if let stmtId = stmt.id {
                        stmtRepo.recalculateTotal(statementId: stmtId)
                    }
                }
            }
        } else {
            for card in allCards {
                let stmts = stmtRepo.fetchStatements(forCardId: card.id!)
                for stmt in stmts {
                    if let stmtId = stmt.id {
                        stmtRepo.recalculateTotal(statementId: stmtId)
                    }
                }
            }
        }

        logWarning("[CCRepair] Deduplicated: deleted \(totalDeleted), reassigned \(totalFixed)")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// One-time repair v2: fixes CC transaction dates using BTG bank data, then reassigns
    /// to correct statements. Previous version only moved statements but didn't fix dates,
    /// so reassignMisplacedTransactions moved them again based on wrong dates.
    func repairBTGStatementAssignments(userId: String, transactionRepo: TransactionRepository) {
        let migrationKey = "hasRepairedBTGStatements_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let allTransactions = transactionRepo.fetchAllTransactions()

        // Find the BTG card
        let ccTransactions = allTransactions.filter { $0.creditCardId != nil && $0.isCreditCardStatement != true }
        guard let cardId = ccTransactions.first?.creditCardId,
              let card = cardRepo.fetchCard(byId: cardId) else {
            logWarning("[BTGRepair] No CC card found, skipping")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let calendar = Calendar.current

        // Step 1: Delete confirmed duplicates (old edited versions)
        let duplicateIds = [26712, 26714, 26717]
        var deletedCount = 0
        for dupId in duplicateIds {
            if allTransactions.contains(where: { $0.id == dupId }) {
                try? transactionRepo.delete(id: dupId)
                deletedCount += 1
                logWarning("[BTGRepair] Deleted duplicate id=\(dupId)")
            }
        }

        // Step 2: Build amount → purchase date mapping from BTG statements
        // BTG February (period 09/01-09/02, due 13/02) — regular transactions only
        let btgFebDateMap: [(amount: Int, date: DateComponents, fuzzyRange: Int)] = [
            (7890,  DateComponents(year: 2026, month: 1, day: 7), 0),
            (3390,  DateComponents(year: 2026, month: 1, day: 8), 0),
            (22996, DateComponents(year: 2026, month: 1, day: 10), 0),
            (4990,  DateComponents(year: 2026, month: 1, day: 10), 0),
            (9076,  DateComponents(year: 2026, month: 1, day: 13), 0),
            (66276, DateComponents(year: 2026, month: 1, day: 14), 0),
            (18190, DateComponents(year: 2026, month: 1, day: 17), 0),
            (16000, DateComponents(year: 2026, month: 1, day: 18), 0),
            (13515, DateComponents(year: 2026, month: 1, day: 19), 0),
            (53374, DateComponents(year: 2026, month: 1, day: 21), 200),  // app has 53238
            (16737, DateComponents(year: 2026, month: 1, day: 23), 0),
            (1999,  DateComponents(year: 2026, month: 1, day: 24), 0),
            (35628, DateComponents(year: 2026, month: 1, day: 26), 0),
            (21245, DateComponents(year: 2026, month: 1, day: 26), 0),
            (7497,  DateComponents(year: 2026, month: 1, day: 29), 0),
            (12158, DateComponents(year: 2026, month: 2, day: 2), 0),
            (66314, DateComponents(year: 2026, month: 2, day: 3), 0),
        ]

        // BTG March (period 09/02-09/03, due 13/03) — regular transactions only
        let btgMarDateMap: [(amount: Int, date: DateComponents, fuzzyRange: Int)] = [
            (84877,  DateComponents(year: 2026, month: 2, day: 10), 0),
            (16991,  DateComponents(year: 2026, month: 2, day: 12), 0),
            (26219,  DateComponents(year: 2026, month: 2, day: 12), 0),
            (7998,   DateComponents(year: 2026, month: 2, day: 14), 0),
            (22207,  DateComponents(year: 2026, month: 2, day: 15), 0),
            (6900,   DateComponents(year: 2026, month: 2, day: 16), 0),
            (21307,  DateComponents(year: 2026, month: 2, day: 18), 0),
            (9350,   DateComponents(year: 2026, month: 2, day: 21), 0),
            (8819,   DateComponents(year: 2026, month: 2, day: 21), 0),
            (10718,  DateComponents(year: 2026, month: 2, day: 22), 0),
            (54186,  DateComponents(year: 2026, month: 2, day: 24), 0),
            (16990,  DateComponents(year: 2026, month: 2, day: 25), 0),
            (18265,  DateComponents(year: 2026, month: 2, day: 26), 0),
            (29986,  DateComponents(year: 2026, month: 2, day: 26), 0),
            (19320,  DateComponents(year: 2026, month: 2, day: 27), 0),
            (11295,  DateComponents(year: 2026, month: 2, day: 28), 200),  // app has 11290
            (500000, DateComponents(year: 2026, month: 2, day: 28), 0),
            (10584,  DateComponents(year: 2026, month: 3, day: 2), 0),
            (14500,  DateComponents(year: 2026, month: 3, day: 3), 0),
            (6440,   DateComponents(year: 2026, month: 3, day: 8), 0),
        ]

        // Combine into one lookup: amount → correct purchase date
        var allBtgEntries = btgFebDateMap + btgMarDateMap

        // Step 3: For each non-installment CC transaction, fix date and reassign statement
        let freshAll = transactionRepo.fetchAllTransactions()
        let cardCCTxs = freshAll.filter {
            $0.creditCardId == cardId && $0.isCreditCardStatement != true && $0.installmentNumber == nil
        }

        var dateFixCount = 0
        var stmtFixCount = 0
        var usedEntryIndices = Set<Int>()

        for tx in cardCCTxs {
            guard let txId = tx.id else { continue }

            // Find matching BTG entry by amount (exact first, then fuzzy)
            var matchIdx: Int?
            for (i, entry) in allBtgEntries.enumerated() {
                if usedEntryIndices.contains(i) { continue }
                if entry.fuzzyRange == 0 && tx.amount == entry.amount {
                    matchIdx = i
                    break
                } else if entry.fuzzyRange > 0 && abs(tx.amount - entry.amount) <= entry.fuzzyRange {
                    matchIdx = i
                    break
                }
            }

            guard let idx = matchIdx else { continue }
            usedEntryIndices.insert(idx)
            let entry = allBtgEntries[idx]

            guard let correctDate = calendar.date(from: entry.date) else { continue }
            let correctTimestamp = Int(correctDate.timeIntervalSince1970)
            let correctBudgetMonth = correctDate.monthAnchor

            // Fix date if wrong
            if tx.dateTimestamp != correctTimestamp {
                transactionRepo.updateDateAndBudgetMonth(
                    transactionId: txId,
                    newDateTimestamp: correctTimestamp,
                    newBudgetMonthDate: correctBudgetMonth
                )
                dateFixCount += 1
                logWarning("[BTGRepair] Fixed date id=\(txId) '\(tx.title)' \(tx.amount) → \(correctDate)")
            }

            // Reassign to correct statement using the correct date
            if let correctStmt = getOrCreateStatement(for: card, transactionDate: correctDate, userId: userId),
               let correctStmtId = correctStmt.id,
               tx.statementId != correctStmtId {
                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: txId, creditCardId: cardId,
                        statementId: correctStmtId, isCreditCardStatement: false
                    )
                    stmtFixCount += 1
                    logWarning("[BTGRepair] Reassigned id=\(txId) '\(tx.title)' → stmt \(correctStmtId)")
                } catch {
                    logError("[BTGRepair] Failed to reassign \(txId): \(error)")
                }
            }
        }

        // Step 4: Recalculate ALL statement totals for this card
        let allStmts = stmtRepo.fetchStatements(forCardId: cardId)
        for stmt in allStmts {
            if let stmtId = stmt.id {
                stmtRepo.recalculateTotal(statementId: stmtId)
            }
        }

        // Step 5: Log unmatched BTG entries
        let unmatchedCount = allBtgEntries.count - usedEntryIndices.count
        if unmatchedCount > 0 {
            let unmatched = allBtgEntries.enumerated()
                .filter { !usedEntryIndices.contains($0.offset) }
                .map { "\($0.element.amount)" }
            logWarning("[BTGRepair] ⚠️ \(unmatchedCount) BTG amounts unmatched in DB: \(unmatched.joined(separator: ", "))")
        }

        logWarning("[BTGRepair] Done. Deleted \(deletedCount) dupes, fixed \(dateFixCount) dates, reassigned \(stmtFixCount) stmts")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Repair: finds CC transactions whose statementId points to a soft-deleted or missing statement
    /// and re-links them to the correct live statement by matching due dates.
    /// Cannot use repairOrphanedCreditCardTransactions for these because the installment's dateTimestamp
    /// has already been remapped to the due date, so calculateClosingDate would compute the wrong period.
    func repairStaleStatementLinks(userId: String, transactionRepo: TransactionRepository) {
        let allTransactions = transactionRepo.fetchAllTransactions()

        let linkedTransactions = allTransactions.filter { tx in
            tx.creditCardId != nil && tx.statementId != nil && tx.isCreditCardStatement != true
        }

        guard !linkedTransactions.isEmpty else { return }

        // Build lookups of live statements per card (by id and by dueDate timestamp)
        var statementsCache: [Int: [CreditCardStatement]] = [:]
        func liveStatements(forCard cardId: Int) -> [CreditCardStatement] {
            if let cached = statementsCache[cardId] { return cached }
            let stmts = stmtRepo.fetchStatements(forCardId: cardId)
            statementsCache[cardId] = stmts
            return stmts
        }

        for tx in linkedTransactions {
            guard let txId = tx.id, let stmtId = tx.statementId,
                  let cardId = tx.creditCardId else { continue }

            let stmts = liveStatements(forCard: cardId)
            let liveIds = Set(stmts.compactMap { $0.id })

            // Statement is still live — nothing to fix
            if liveIds.contains(stmtId) { continue }

            // Statement is deleted/missing — find the correct one by matching due date
            let txDueDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
            let txDueTimestamp = Int(txDueDate.timeIntervalSince1970)

            if let matchingStmt = stmts.first(where: { Int($0.dueDate.timeIntervalSince1970) == txDueTimestamp }),
               let matchingId = matchingStmt.id {
                // Re-link to the existing live statement with the same due date
                do {
                    try transactionRepo.updateCreditCardFields(
                        transactionId: txId,
                        creditCardId: cardId,
                        statementId: matchingId,
                        isCreditCardStatement: false
                    )
                    recalculateStatementTotal(statementId: matchingId)
                } catch {
                    logError("Failed to re-link transaction \(txId) to statement \(matchingId): \(error)")
                }
            } else if let card = cardRepo.fetchCard(byId: cardId) {
                // No live statement with matching due date — reverse-compute closing date and create one
                let closingDate = reverseClosingDate(dueDate: txDueDate, card: card)
                if let statement = getOrCreateStatement(for: card, transactionDate: closingDate, userId: userId) {
                    do {
                        try transactionRepo.updateCreditCardFields(
                            transactionId: txId,
                            creditCardId: cardId,
                            statementId: statement.id!,
                            isCreditCardStatement: false
                        )
                        recalculateStatementTotal(statementId: statement.id!)
                    } catch {
                        logError("Failed to re-link transaction \(txId) to new statement: \(error)")
                    }
                }
            }
        }
    }

    /// Reverse-computes the closing date from a due date for a given card.
    /// This is the inverse of calculateDueDate.
    private func reverseClosingDate(dueDate: Date, card: CreditCard) -> Date {
        let calendar = Calendar.current
        let dueMonth = calendar.component(.month, from: dueDate)
        let dueYear = calendar.component(.year, from: dueDate)

        if card.dueDay > card.closingDay {
            // Due date and closing date are in the same month
            let closingDay = min(card.closingDay, daysInMonth(month: dueMonth, year: dueYear))
            return calendar.date(from: DateComponents(year: dueYear, month: dueMonth, day: closingDay))!
        } else {
            // Closing date is one month before due date
            var closingMonth = dueMonth - 1
            var closingYear = dueYear
            if closingMonth < 1 { closingMonth = 12; closingYear -= 1 }
            let closingDay = min(card.closingDay, daysInMonth(month: closingMonth, year: closingYear))
            return calendar.date(from: DateComponents(year: closingYear, month: closingMonth, day: closingDay))!
        }
    }

    /// Generates synthetic statement transactions for a specific card.
    /// When `includeAllUsers` is true, uses DB queries (all users) instead of UID-isolated store.
    /// - Parameter scope: the ledger being rendered. Count, total and the transaction list beside
    ///   them must all come from it, or the screen contradicts itself — a statement reporting "4
    ///   transactions" with an empty table and no total is what the unscoped version produced once
    ///   the personal reads were narrowed.
    func generateStatementTransactions(forCard card: CreditCard, in scope: LedgerScope) -> [Transaction] {
        guard let cardId = card.id else { return [] }
        var statementTransactions: [Transaction] = []

        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        for stmt in statements {
            guard let stmtId = stmt.id else { continue }

            let realCount: Int
            let realTotal: Int

            // One scoped query for both, so they can never disagree with each other or with the
            // list. Previously the group branch read the database with no scope predicate at all
            // while the personal branch went through the (scoped) repository.
            let totals = DBHelper.shared.statementTotals(statementId: stmtId, scope: scope)
            realCount = totals.count
            realTotal = totals.total

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

    func daysInMonth(month: Int, year: Int) -> Int {
        let calendar = Calendar.current
        let components = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 28 }
        return range.count
    }
}
