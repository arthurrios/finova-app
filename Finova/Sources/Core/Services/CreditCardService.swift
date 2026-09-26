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

    /// The statement `getOrCreateStatement` would return for this card and date, if it exists yet.
    /// Never creates one. Same lookup order, minus the create step.
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

    /// Puts a card transaction's `budget_month_date` back on the month it was spent in.
    /// Returns how many rows moved.
    ///
    /// `moveTransactionToStatement` used to stamp the target statement's DUE month onto that
    /// column. A due date almost always lands in the month AFTER the purchase, so every transaction
    /// the user had moved between statements — in every category — was charged to the following
    /// month's allocation, leaving its own month looking underspent and the next one over budget.
    ///
    /// Scoped to exactly that population: rows flagged `is_statement_overridden`, which is the flag
    /// that path sets. A card purchase nobody moved already carries the right month, and
    /// recomputing it would move a row that was never broken. `date` was never touched by that
    /// path, so it is the purchase date and therefore the answer.
    @discardableResult
    func repairBudgetMonthToSpendingMonth(transactionRepo: TransactionRepository) -> Int {
        let damaged = transactionRepo.fetchAllTransactions().filter { tx in
            guard let txId = tx.id, tx.statementId != nil, tx.isCreditCardStatement != true
            else { return false }
            return DBHelper.shared.isStatementOverridden(transactionId: txId)
        }
        guard !damaged.isEmpty else { return 0 }

        var fixCount = 0
        for tx in damaged {
            guard let txId = tx.id else { continue }
            let month = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp)).monthAnchor
            guard month != tx.budgetMonthDate else { continue }

            // `updateBudgetMonthDate` mirrors the row to the secure store itself, so there is
            // nothing further to mark on this branch.
            transactionRepo.updateBudgetMonthDate(transactionId: txId, newBudgetMonthDate: month)
            fixCount += 1
            logWarning(
                "[CCRepair] tx \(txId) ('\(tx.title)') budgetMonth \(tx.budgetMonthDate) -> \(month) (statement month was not the spending month)"
            )
        }

        if fixCount > 0 {
            logWarning("[CCRepair] Moved \(fixCount) card transaction(s) back to their spending month")
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        }
        return fixCount
    }

    /// One-time repair, run once per device. See `repairBudgetMonthToSpendingMonth`.
    func repairBudgetMonthToSpendingMonthIfNeeded(transactionRepo: TransactionRepository) {
        let key = "hasRepairedCCBudgetMonthToSpendingMonth_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        repairBudgetMonthToSpendingMonth(transactionRepo: transactionRepo)
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Moves a card transaction onto a different statement at the user's request.
    ///
    /// The move is flagged as an override so `reassignCardTransactions` — which re-derives every
    /// card transaction's statement from the card's current closing day — cannot silently undo it.
    ///
    /// Neither the purchase date NOR `budget_month_date` is touched: moving a purchase to another
    /// statement changes when the CARD BILLS IT, not when it was spent, and the budget month is the
    /// spending month — the one whose category allocation the purchase consumes.
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
        var statementTransactions: [Transaction] = []

        // Use the same source as the ViewModel to avoid stale DB vs secure store mismatch
        let allSecureTransactions = SecureLocalDataManager.shared.loadTransactions()

        let liveCards = cardRepo.fetchAllCards(userId: userId)
        let cards = liveCards + deletedCards(chargedBy: allSecureTransactions, liveCards: liveCards)

        for card in cards {
            let statements = stmtRepo.fetchStatements(forCardId: card.id!)

            // Count and sum from the secure store (consistent with what StatementDetailsViewModel shows)
            var rowsByStatement: [Int: [Transaction]] = [:]
            for stmt in statements {
                guard let stmtId = stmt.id else { continue }
                rowsByStatement[stmtId] = allSecureTransactions.filter {
                    $0.statementId == stmtId && $0.isCreditCardStatement != true
                }
            }
            // Signed by type, mirroring `DBHelper.signedAmount`: a credit on the card reduces
            // what the invoice charges. Installments already paid early are left out, as the
            // stored statement total leaves them out: they were paid by their own debit, so
            // counting them here charged the same money twice.
            let charges = Self.statementCharges(statements) { stmt in
                (rowsByStatement[stmt.id ?? -1] ?? []).excludingEarlyPaidInstallments().reduce(0) {
                    $1.type == .income ? $0 - $1.amount : $0 + $1.amount
                }
            }

            for stmt in statements {
                let stmtTransactions = rowsByStatement[stmt.id!] ?? []
                let realCount = stmtTransactions.count

                // Clean up stale statements with no transactions
                if realCount == 0 {
                    recalculateStatementTotal(statementId: stmt.id!)
                    continue
                }

                let charged = charges[stmt.id!]?.charged ?? 0
                guard charged > 0 else { continue }

                let title = String(format: "creditCard.statement.title".localized, card.name)
                let dueTimestamp = Int(stmt.dueDate.timeIntervalSince1970)

                let data = UITransactionData(
                    id: -(stmt.id! * 1000 + (card.id ?? 0)),
                    title: title,
                    amount: charged,
                    dateTimestamp: dueTimestamp,
                    budgetMonthDate: stmt.closingDate.monthAnchor,
                    isRecurring: false,
                    hasInstallments: false,
                    parentTransactionId: nil,
                    installmentNumber: nil,
                    totalInstallments: realCount,
                    originalAmount: charged,
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

    /// What each of one card's statements charges once credit left over from its earlier statements
    /// is counted in, keyed by statement id. `ownTotal` is a statement's own charges minus its own
    /// credits.
    ///
    /// A credit larger than its own statement (a cancelled installment purchase, a big return) is not
    /// lost: the rest carries to the card's next statements, as a bank does. Skipping that statement
    /// used to drop it, so a cancelled 3 x 100 purchase credited 300 on one statement, which then
    /// charged nothing, while the next two still charged 100 each.
    static func statementCharges(
        _ statements: [CreditCardStatement], ownTotal: (CreditCardStatement) -> Int
    ) -> [Int: (charged: Int, carriedIn: Int)] {
        let ordered = statements.sorted {
            ($0.closingDate, $0.id ?? Int.max) < ($1.closingDate, $1.id ?? Int.max)
        }
        var carry = 0
        var charges: [Int: (charged: Int, carriedIn: Int)] = [:]
        for stmt in ordered {
            guard let stmtId = stmt.id else { continue }
            let net = ownTotal(stmt) + carry
            charges[stmtId] = (charged: max(0, net), carriedIn: carry)
            carry = min(0, net)
        }
        return charges
    }

    /// Credit left over from the card's statements before this one: zero, or negative. What the
    /// statement owes is its own sum plus this, never below zero, which is what its dashboard row
    /// charges. Summed with the SQL the stored `total_amount` is recalculated from.
    func carriedCredit(intoStatementId statementId: Int) -> Int {
        guard let cardId = stmtRepo.fetchCardId(forStatementId: statementId) else { return 0 }
        let charges = Self.statementCharges(stmtRepo.fetchStatements(forCardId: cardId)) { stmt in
            stmt.id.flatMap { try? DBHelper.shared.getTransactionSumForStatement(statementId: $0) } ?? 0
        }
        return charges[statementId]?.carriedIn ?? 0
    }

    /// Deleted cards that still have purchases on a statement.
    ///
    /// `fetchAllCards` hides deleted cards, which is right for every list and picker, but not for the
    /// balance: the purchases on a deleted card happened, the delete prompt promises they are kept,
    /// and a card purchase reaches the balance only through its statement row. Leaving the card out
    /// of `generateStatementTransactions` erased its whole spend from the balance history.
    ///
    /// Found through the purchases that still point at a card, so a deleted card nobody used adds
    /// nothing. A card that is live but not in `liveCards` is left out, as it always was.
    private func deletedCards(chargedBy transactions: [Transaction], liveCards: [CreditCard]) -> [CreditCard] {
        let liveCardIds = Set(liveCards.compactMap(\.id))
        let cardIds = Set(transactions.compactMap { tx -> Int? in
            guard let cardId = tx.creditCardId, tx.statementId != nil,
                  tx.isCreditCardStatement != true, !liveCardIds.contains(cardId)
            else { return nil }
            return cardId
        })
        return cardIds.sorted().compactMap { cardId in
            guard let card = cardRepo.fetchCard(byId: cardId), card.isDeleted else { return nil }
            return card
        }
    }

    /// Reshapes a card's FUTURE billing cycles after its closingDay or dueDay changed.
    ///
    /// Deliberately limited to statements that have not closed yet. An invoice the user has already
    /// been billed for is a historical record: rewriting its dates, and then re-routing the
    /// transactions on it, changes what the user was charged last month. Only cycles still ahead of
    /// them can be reshaped, which is also all the card issuer would do.
    ///
    /// `respectingDateOverrides` is for the launch repair, which runs without the user asking: it
    /// must not undo dates the user set by hand on a statement.
    func recalculateStatementDatesForCard(
        _ card: CreditCard, userId: String? = nil, transactionRepo: TransactionRepository? = nil,
        respectingDateOverrides: Bool = false
    ) {
        guard let cardId = card.id else { return }
        let statements = stmtRepo.fetchStatements(forCardId: cardId)
        let now = Date()

        for stmt in statements where stmt.closingDate > now && !stmt.isPaid {
            if respectingDateOverrides && stmt.isDatesOverridden { continue }
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

        // A cycle can end up with two open statements in one month — one on the old closing day,
        // one on the new. Collapse them before anything routes by month, or an installment stays
        // stranded on the old one: a "ghost" invoice still showing the old due date.
        mergeSameMonthOpenStatements(for: card, transactionRepo: transactionRepo)

        // An installment's date IS its statement's due date. Moving the due date without moving the
        // installments left them showing (and reminding for) the old day.
        remapOpenInstallmentsToDueDate(cardId: cardId, transactionRepo: transactionRepo)

        reassignCardTransactions(
            card: card, userId: userId, transactionRepo: transactionRepo, onlyFutureCycles: true)
    }

    /// Collapses two or more OPEN statements that share a card and a closing month into one.
    /// Returns how many statements were removed.
    ///
    /// "One statement per (card, month)" is the rule every router relies on, but it is not enforced
    /// by the schema, and a closing-day change can leave a second statement for the same cycle on
    /// the old day. The keeper is the one already on the card's current closing day, else the one
    /// holding the most rows, else the oldest; its dates are then put on the current rules.
    ///
    /// Open statements only: a month with a closed or paid statement is history, and history is
    /// left exactly as it is.
    @discardableResult
    func mergeSameMonthOpenStatements(for card: CreditCard, transactionRepo: TransactionRepository) -> Int {
        guard let cardId = card.id else { return 0 }
        let calendar = Calendar.current
        let now = Date()

        struct MonthKey: Hashable { let year: Int; let month: Int }
        let byMonth = Dictionary(grouping: stmtRepo.fetchStatements(forCardId: cardId)) {
            MonthKey(
                year: calendar.component(.year, from: $0.closingDate),
                month: calendar.component(.month, from: $0.closingDate))
        }

        var removed = 0
        for (key, group) in byMonth where group.count > 1 {
            guard group.allSatisfy({ $0.closingDate > now && !$0.isPaid }) else {
                logWarning("[StmtMerge] card \(cardId) \(key.month)/\(key.year): \(group.count) statements, one is closed or paid — left alone")
                continue
            }

            let currentClosingDay = min(card.closingDay, daysInMonth(month: key.month, year: key.year))
            let allTransactions = transactionRepo.fetchAllTransactions()
            let rowCount = Dictionary(grouping: allTransactions.compactMap(\.statementId), by: { $0 })
                .mapValues(\.count)

            let sorted = group.sorted { a, b in
                let aDay = calendar.component(.day, from: a.closingDate) == currentClosingDay
                let bDay = calendar.component(.day, from: b.closingDate) == currentClosingDay
                if aDay != bDay { return aDay }
                let aRows = a.id.flatMap { rowCount[$0] } ?? 0
                let bRows = b.id.flatMap { rowCount[$0] } ?? 0
                if aRows != bRows { return aRows > bRows }
                return (a.id ?? Int.max) < (b.id ?? Int.max)
            }
            guard let keeper = sorted.first, let keeperId = keeper.id else { continue }

            for drop in sorted where drop.id != keeperId {
                guard let dropId = drop.id else { continue }
                for tx in allTransactions where tx.statementId == dropId && tx.isCreditCardStatement != true {
                    guard let txId = tx.id else { continue }
                    do {
                        try transactionRepo.updateCreditCardFields(
                            transactionId: txId,
                            creditCardId: cardId,
                            statementId: keeperId,
                            isCreditCardStatement: false
                        )
                    } catch {
                        logError("[StmtMerge] Failed to move tx \(txId) from \(dropId) to \(keeperId): \(error)")
                    }
                }
                _ = stmtRepo.deleteStatement(statementId: dropId)
                removed += 1
                logWarning("[StmtMerge] Merged statement \(dropId) into \(keeperId) (card \(cardId), \(key.month)/\(key.year))")
            }

            let closingDate = calendar.date(
                from: DateComponents(year: key.year, month: key.month, day: currentClosingDay))!
            let dueDate = calculateDueDate(closingDate: closingDate, card: card)
            if !keeper.isDatesOverridden, keeper.closingDate != closingDate || keeper.dueDate != dueDate {
                _ = stmtRepo.updateDates(statementId: keeperId, closingDate: closingDate, dueDate: dueDate)
            }
            stmtRepo.recalculateTotal(statementId: keeperId)
        }
        return removed
    }

    /// Puts every installment on an OPEN statement of this card onto that statement's due date, and
    /// budgets it in the due month — the same place creation puts it on this release. Returns how many
    /// rows moved.
    ///
    /// A closed or paid statement is history and keeps whatever its installments already say.
    @discardableResult
    func remapOpenInstallmentsToDueDate(cardId: Int, transactionRepo: TransactionRepository) -> Int {
        let now = Date()
        var openById: [Int: CreditCardStatement] = [:]
        for stmt in stmtRepo.fetchStatements(forCardId: cardId) where stmt.closingDate > now && !stmt.isPaid {
            if let id = stmt.id { openById[id] = stmt }
        }
        guard !openById.isEmpty else { return 0 }

        var moved = 0
        var touchedMonths = Set<String>()
        for tx in transactionRepo.fetchAllTransactions()
        where tx.creditCardId == cardId && tx.installmentNumber != nil && tx.isCreditCardStatement != true {
            guard let txId = tx.id, let stmtId = tx.statementId, let stmt = openById[stmtId] else { continue }
            let dueTimestamp = Int(stmt.dueDate.timeIntervalSince1970)
            guard tx.dateTimestamp != dueTimestamp else { continue }

            transactionRepo.updateDateAndBudgetMonth(
                transactionId: txId, newDateTimestamp: dueTimestamp,
                newBudgetMonthDate: stmt.dueDate.monthAnchor)
            touchedMonths.insert(SeriesNotificationScheduler.monthKey(for: tx.dateTimestamp))
            touchedMonths.insert(SeriesNotificationScheduler.monthKey(for: dueTimestamp))
            moved += 1
        }

        guard moved > 0 else { return 0 }
        rescheduleInstallmentReminders(monthKeys: touchedMonths, transactionRepo: transactionRepo)
        logWarning("[StmtMerge] Moved \(moved) installment(s) on card \(cardId) onto their statement's due date")
        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        return moved
    }

    /// Installment reminders are one per MONTH across every series, so a month that gained or lost
    /// a row is rebuilt from all installments, not from the ones that moved.
    private func rescheduleInstallmentReminders(monthKeys: Set<String>, transactionRepo: TransactionRepository) {
        var models: [TransactionModel] = []
        if NotificationPreferencesManager.shared.transactionNotificationsEnabled {
            let all = transactionRepo.fetchAllTransactions()
            let parentIds = Set(
                all.filter { $0.hasInstallments == true && $0.parentTransactionId == nil }.compactMap(\.id))
            models = all
                .filter { $0.parentTransactionId.map(parentIds.contains) ?? false }
                .map(MonthlyNotificationManager.notificationModel)
        }
        SeriesNotificationScheduler.reschedule(monthKeys: monthKeys, from: models, kind: .installment)
    }

    /// One-time repair for cards whose closing or due day was changed before
    /// `recalculateStatementDatesForCard` did the merge and remap above. It runs that same pass for
    /// every card: open statements still on the old days move to the current ones (a ghost can be
    /// alone in its month, with no new-day statement to merge into), same-month duplicates merge,
    /// and stranded installments move to their statement's due date. Re-running is harmless —
    /// every step only touches rows that are still wrong.
    func repairCardCycleChangeIfNeeded(userId: String, transactionRepo: TransactionRepository) {
        // Per account: a phone can sign in to more than one, and a pass run for one must not
        // mark the other as done.
        let key = "hasRepairedCardCycleChange_v1_\(userId)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        for card in cardRepo.fetchAllCards(userId: userId) where !card.isDeleted {
            recalculateStatementDatesForCard(
                card, userId: userId, transactionRepo: transactionRepo, respectingDateOverrides: true)
        }
        UserDefaults.standard.set(true, forKey: key)
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

            // The day it was made, as creation routes it — not the date a business-day rule moved it
            // to. A purchase made on a Saturday closing day and shown on Monday still belongs to the
            // cycle that closed on Saturday; routing by Monday moved it a month later on every load.
            let transactionDate = tx.unadjustedDate

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

            // Routed by the unadjusted date, as creation and `reassignCardTransactions` route it.
            let transactionDate = tx.unadjustedDate
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
        statement(
            closingOn: closingDate(inMonthAfter: current.closingDate, card: card),
            for: card, userId: userId)
    }

    /// The card's closing date in the calendar month after `date`'s.
    private func closingDate(inMonthAfter date: Date, card: CreditCard) -> Date {
        let calendar = Calendar.current

        let currentMonth = calendar.component(.month, from: date)
        let currentYear = calendar.component(.year, from: date)
        var nextMonth = currentMonth + 1
        var nextYear = currentYear
        if nextMonth > 12 { nextMonth = 1; nextYear += 1 }

        let nextClosingDay = min(card.closingDay, daysInMonth(month: nextMonth, year: nextYear))
        return calendar.date(from: DateComponents(year: nextYear, month: nextMonth, day: nextClosingDay))!
    }

    /// The statement already stored for the cycle closing on `closingDate`, or nil. Never writes.
    private func existingStatement(closingOn closingDate: Date, cardId: Int) -> CreditCardStatement? {
        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        if let existingId = stmtRepo.findStatement(creditCardId: cardId, closingDate: closingDate),
           let exact = statements.first(where: { $0.id == existingId }) {
            return exact
        }

        // A statement that kept old dates after the card's closing day changed still IS that month's
        // invoice, so reuse it rather than creating a second one for the same cycle.
        return statements
            .filter({ Calendar.current.isDate($0.closingDate, equalTo: closingDate, toGranularity: .month) })
            .sorted(by: { ($0.id ?? Int.max) < ($1.id ?? Int.max) })
            .first
    }

    /// The statement for the cycle closing on `nextClosingDate`, creating it if it does not exist yet.
    private func statement(
        closingOn nextClosingDate: Date, for card: CreditCard, userId: String
    ) -> CreditCardStatement? {
        guard let cardId = card.id else { return nil }
        let nextDueDate = calculateDueDate(closingDate: nextClosingDate, card: card)

        if let existing = existingStatement(closingOn: nextClosingDate, cardId: cardId) {
            return existing
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
    /// Creates a statement only when no existing one is open, and then only the one it returns: the
    /// first cycle closing after `date` that also comes after every existing statement. The cycles in
    /// between are skipped, not filled with empty statements.
    func nextOpenStatement(for card: CreditCard, userId: String, asOf date: Date = Date())
        -> CreditCardStatement?
    {
        switch nextOpenCycle(for: card, asOf: date) {
        case .existing(let open): return open
        case .toCreate(let closingDate): return statement(closingOn: closingDate, for: card, userId: userId)
        case nil: return nil
        }
    }

    /// The due date of the statement `nextOpenStatement` would return, without creating it.
    ///
    /// For labels. `EarlyPaymentViewModel.targetStatementLabel` called `nextOpenStatement`, so merely
    /// showing the early payment screen, or changing its date, inserted an empty statement.
    func nextOpenStatementDueDate(for card: CreditCard, asOf date: Date = Date()) -> Date? {
        switch nextOpenCycle(for: card, asOf: date) {
        case .existing(let open): return open.dueDate
        case .toCreate(let closingDate):
            return existingStatement(closingOn: closingDate, cardId: card.id ?? 0)?.dueDate
                ?? calculateDueDate(closingDate: closingDate, card: card)
        case nil: return nil
        }
    }

    private enum NextOpenCycle {
        case existing(CreditCardStatement)
        case toCreate(closingDate: Date)
    }

    /// `nextOpenStatement`'s decision, without the write.
    private func nextOpenCycle(for card: CreditCard, asOf date: Date) -> NextOpenCycle? {
        guard let cardId = card.id else { return nil }
        let statements = stmtRepo.fetchStatements(forCardId: cardId)

        if let open = statements
            .filter({ $0.closingDate > date && !$0.isPaid })
            .min(by: { $0.closingDate < $1.closingDate })
        {
            return .existing(open)
        }

        // Neither "the cycle after the latest statement" nor "the cycle `date` routes to" is enough
        // on its own. On a card left unused, the latest statement may have closed months ago, so the
        // cycle after it has closed too and the money landed on an invoice already issued. And on
        // the closing day, date routing returns the cycle that closed at the start of that day.
        var closingDate = calculateClosingDate(card: card, transactionDate: date)
        if closingDate <= date {
            closingDate = self.closingDate(inMonthAfter: closingDate, card: card)
        }
        // And past every existing statement, all of which are closed or paid by now. The cycle after
        // the latest one still closes after `date`: it is in a later month than `closingDate`.
        if let latest = statements.max(by: { $0.closingDate < $1.closingDate }),
           Calendar.current.compare(closingDate, to: latest.closingDate, toGranularity: .month)
            != .orderedDescending
        {
            closingDate = self.closingDate(inMonthAfter: latest.closingDate, card: card)
        }

        return .toCreate(closingDate: closingDate)
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
