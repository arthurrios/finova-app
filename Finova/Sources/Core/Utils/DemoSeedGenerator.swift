//
//  DemoSeedGenerator.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

#if DEBUG
import Foundation

struct DemoSeedGenerator {

    // MARK: - Entry Point

    static func seed(for userUID: String) {
        logInfo("[DemoSeed] Starting seed for UID: \(userUID)")

        clearAll(userUID: userUID)
        seedData(userUID: userUID)

        logInfo("[DemoSeed] Seed complete")
    }

    // MARK: - Clear Phase

    private static func clearAll(userUID: String) {
        logInfo("[DemoSeed] Clearing existing data…")

        // Transactions (SQLite + secure storage)
        TransactionRepository().clearAllTransactionsForTesting()

        // User data
        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            DBHelper.shared.deleteAllTransactions(forUser: uid)
            DBHelper.shared.deleteAllBudgets(forUser: uid)
            ProfileImageManager.shared.removeProfileImage()
        }

        // Budgets
        try? DBHelper.shared.deleteAllBudgets()

        // Budget allocations
        UserDefaults.standard.removeObject(forKey: "budgetAllocations")

        // Credit cards & statements
        let cardRepo = CreditCardRepository()
        let stmtRepo = StatementRepository()
        let existingCards = cardRepo.fetchAllCards(userId: userUID)
        for card in existingCards {
            if let cardId = card.id {
                let stmts = stmtRepo.fetchStatements(forCardId: cardId)
                for stmt in stmts {
                    if let stmtId = stmt.id {
                        _ = stmtRepo.deleteStatement(statementId: stmtId)
                    }
                }
                _ = cardRepo.deleteCard(id: cardId)
            }
        }

        // Budget groups & invitations
        let groupRepo = BudgetGroupRepository()
        for group in groupRepo.fetchAllGroups() {
            groupRepo.softDeleteGroup(id: group.id)
        }
        groupRepo.deleteAllInvitations()

        // Balance offset
        UIDUserDefaultsManager.shared.setCurrentUserBalanceOffset(0)

        // In-memory cache
        TransactionRepository.invalidateCache()
    }

    // MARK: - Seed Phase

    private static func seedData(userUID: String) {
        let cal = Calendar.current
        let now = Date()
        let txRepo = TransactionRepository()
        let budgetRepo = BudgetRepository()
        let allocRepo = BudgetAllocationRepository()

        // Compute 6 month anchors: current month (index 0) + 5 past months
        var monthDates: [(date: Date, anchor: Int)] = []
        for i in 0..<6 {
            guard let monthDate = cal.date(byAdding: .month, value: -i, to: now) else { continue }
            monthDates.append((monthDate, monthDate.monthAnchor))
        }
        // Reverse so index 0 = oldest, index 5 = current
        monthDates.reverse()

        // --- Monthly budgets ---
        seedBudgets(monthDates: monthDates, budgetRepo: budgetRepo)

        // --- Budget allocations ---
        seedAllocations(monthDates: monthDates, allocRepo: allocRepo)

        // --- Recurring transactions ---
        seedRecurringTransactions(monthDates: monthDates, txRepo: txRepo, cal: cal)

        // --- One-off transactions ---
        seedOneOffTransactions(monthDates: monthDates, txRepo: txRepo, cal: cal)

        // --- Credit cards & statements ---
        seedCreditCards(userUID: userUID, monthDates: monthDates, txRepo: txRepo, cal: cal)

        // --- Budget groups & members ---
        seedBudgetGroups(userUID: userUID)

        // Refresh cache
        TransactionRepository.invalidateCache()
    }

    // MARK: - Budgets

    private static func seedBudgets(
        monthDates: [(date: Date, anchor: Int)],
        budgetRepo: BudgetRepository
    ) {
        for m in monthDates {
            let budget = BudgetModel(monthDate: m.anchor, amount: 800_000)
            try? budgetRepo.insert(budget: budget)
        }
        logInfo("[DemoSeed] Inserted \(monthDates.count) budgets")
    }

    // MARK: - Budget Allocations

    private static func seedAllocations(
        monthDates: [(date: Date, anchor: Int)],
        allocRepo: BudgetAllocationRepository
    ) {
        let categories: [(key: String, amount: Int)] = [
            ("market", 200_000),
            ("meals", 80_000),
            ("transportation", 30_000),
            ("utilities", 25_000),
            ("entertainment", 40_000),
            ("subscriptions", 10_000),
            ("fitness", 10_000),
        ]

        var count = 0
        for m in monthDates {
            for cat in categories {
                let model = BudgetAllocationModel(
                    monthDate: m.anchor,
                    categoryKey: cat.key,
                    allocatedAmount: cat.amount
                )
                _ = try? allocRepo.insertAllocation(model)
                count += 1
            }
        }
        logInfo("[DemoSeed] Inserted \(count) budget allocations")
    }

    // MARK: - Recurring Transactions

    private static func seedRecurringTransactions(
        monthDates: [(date: Date, anchor: Int)],
        txRepo: TransactionRepository,
        cal: Calendar
    ) {
        struct RecurringDef {
            let title: String
            let category: String
            let type: String
            let amount: Int
            let day: Int
        }

        let defs: [RecurringDef] = [
            RecurringDef(title: "Salary", category: "salary", type: "income", amount: 550_000, day: 5),
            RecurringDef(title: "Netflix", category: "subscriptions", type: "expense", amount: 4_490, day: 15),
            RecurringDef(title: "Gym", category: "fitness", type: "expense", amount: 9_990, day: 1),
        ]

        for def in defs {
            // Parent transaction (amount: 0, isRecurring: true)
            let parentDate = monthDates[0].date
            let parentTimestamp = Int(dateForDay(def.day, in: parentDate, cal: cal).timeIntervalSince1970)

            let parentModel = TransactionModel(
                title: def.title,
                category: def.category,
                amount: 0,
                type: def.type,
                dateTimestamp: parentTimestamp,
                budgetMonthDate: monthDates[0].anchor,
                isRecurring: true
            )

            guard let parentId = try? txRepo.insertTransactionAndGetId(parentModel) else {
                logError("[DemoSeed] Failed to insert recurring parent: \(def.title)")
                continue
            }

            // Instances
            for (idx, m) in monthDates.enumerated() {
                let instanceDate = dateForDay(def.day, in: m.date, cal: cal)
                let instanceTimestamp = Int(instanceDate.timeIntervalSince1970)

                let instance = TransactionModel(
                    title: def.title,
                    category: def.category,
                    amount: def.amount,
                    type: def.type,
                    dateTimestamp: instanceTimestamp,
                    budgetMonthDate: m.anchor,
                    isRecurring: false,
                    parentTransactionId: parentId
                )
                do {
                    try txRepo.insertTransaction(instance)
                } catch {
                    logError("[DemoSeed] Failed to insert recurring instance \(def.title) month \(idx): \(error)")
                }
            }
        }
        logInfo("[DemoSeed] Inserted recurring transactions")
    }

    // MARK: - One-off Transactions

    private static func seedOneOffTransactions(
        monthDates: [(date: Date, anchor: Int)],
        txRepo: TransactionRepository,
        cal: Calendar
    ) {
        struct OneOffDef {
            let category: String
            let title: String
            let baseAmount: Int
            let type: String
            let day: Int
            let activeMonths: Set<Int> // indices where this transaction appears
        }

        let allMonths: Set<Int> = [0, 1, 2, 3, 4, 5]

        let defs: [OneOffDef] = [
            OneOffDef(category: "market", title: "Supermarket", baseAmount: 35_000, type: "expense", day: 8, activeMonths: allMonths),
            OneOffDef(category: "meals", title: "Restaurant", baseAmount: 8_500, type: "expense", day: 12, activeMonths: allMonths),
            OneOffDef(category: "transportation", title: "Uber", baseAmount: 2_500, type: "expense", day: 18, activeMonths: allMonths),
            OneOffDef(category: "utilities", title: "Electricity", baseAmount: 18_000, type: "expense", day: 20, activeMonths: allMonths),
            OneOffDef(category: "entertainment", title: "Cinema", baseAmount: 4_000, type: "expense", day: 22, activeMonths: [0, 1, 3, 5]),
            OneOffDef(category: "healthcare", title: "Pharmacy", baseAmount: 6_000, type: "expense", day: 14, activeMonths: [1, 3, 4]),
            OneOffDef(category: "clothing", title: "Clothes", baseAmount: 15_000, type: "expense", day: 10, activeMonths: [2, 4]),
            OneOffDef(category: "transfer", title: "Transfer received", baseAmount: 20_000, type: "income", day: 25, activeMonths: [1, 4]),
        ]

        var count = 0
        for (idx, m) in monthDates.enumerated() {
            for def in defs {
                guard def.activeMonths.contains(idx) else { continue }

                let amount = def.baseAmount + (idx * 1_500)
                let txDate = dateForDay(def.day, in: m.date, cal: cal)
                let timestamp = Int(txDate.timeIntervalSince1970)

                let model = TransactionModel(
                    title: def.title,
                    category: def.category,
                    amount: amount,
                    type: def.type,
                    dateTimestamp: timestamp,
                    budgetMonthDate: m.anchor
                )
                do {
                    try txRepo.insertTransaction(model)
                    count += 1
                } catch {
                    logError("[DemoSeed] Failed to insert one-off \(def.title) month \(idx): \(error)")
                }
            }
        }
        logInfo("[DemoSeed] Inserted \(count) one-off transactions")
    }

    // MARK: - Credit Cards & Statements (v1.5.0)

    private static func seedCreditCards(
        userUID: String,
        monthDates: [(date: Date, anchor: Int)],
        txRepo: TransactionRepository,
        cal: Calendar
    ) {
        let cardRepo = CreditCardRepository()
        let stmtRepo = StatementRepository()

        // --- Chase Sapphire ---
        let chase = CreditCard(
            id: nil,
            name: "Chase Sapphire",
            lastFourDigits: "4321",
            cardBrand: .mastercard,
            closingDay: 3,
            dueDay: 10,
            creditLimit: 800_000,
            cardColor: .blue,
            userId: userUID,
            isDeleted: false,
            isDefault: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        // --- Amex Platinum ---
        let amex = CreditCard(
            id: nil,
            name: "Amex Platinum",
            lastFourDigits: "8765",
            cardBrand: .amex,
            closingDay: 15,
            dueDay: 22,
            creditLimit: 1_500_000,
            cardColor: .platinum,
            userId: userUID,
            isDeleted: false,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        guard let chaseId = cardRepo.insertCard(chase),
              let amexId = cardRepo.insertCard(amex)
        else {
            logError("[DemoSeed] Failed to insert credit cards")
            return
        }

        logInfo("[DemoSeed] Inserted credit cards: Chase(\(chaseId)), Amex(\(amexId))")

        // --- Statements for each card ---
        let chaseStmtIds = insertStatements(
            cardId: chaseId, closingDay: 3, dueDay: 10,
            userUID: userUID, monthDates: monthDates, stmtRepo: stmtRepo, cal: cal
        )
        let amexStmtIds = insertStatements(
            cardId: amexId, closingDay: 15, dueDay: 22,
            userUID: userUID, monthDates: monthDates, stmtRepo: stmtRepo, cal: cal
        )

        logInfo("[DemoSeed] Inserted statements: Chase(\(chaseStmtIds.count)), Amex(\(amexStmtIds.count))")

        // --- Credit card transactions ---
        // Chase: Restaurant, Cinema, Netflix instances
        // Amex: Clothes, larger purchases
        seedCreditCardTransactions(
            chaseId: chaseId, amexId: amexId,
            chaseStmtIds: chaseStmtIds, amexStmtIds: amexStmtIds,
            monthDates: monthDates, txRepo: txRepo, cal: cal
        )
    }

    private static func insertStatements(
        cardId: Int,
        closingDay: Int,
        dueDay: Int,
        userUID: String,
        monthDates: [(date: Date, anchor: Int)],
        stmtRepo: StatementRepository,
        cal: Calendar
    ) -> [Int] {
        var stmtIds: [Int] = []

        for (idx, m) in monthDates.enumerated() {
            let comps = cal.dateComponents([.year, .month], from: m.date)
            guard let year = comps.year, let month = comps.month else { continue }

            let closingDate = makeDateFromComponents(year: year, month: month, day: closingDay, cal: cal)
            let dueDate = makeDateFromComponents(year: year, month: month, day: dueDay, cal: cal)

            let isCurrentMonth = (idx == monthDates.count - 1)

            let stmt = CreditCardStatement(
                id: nil,
                creditCardId: cardId,
                closingDate: closingDate,
                dueDate: dueDate,
                totalAmount: 0,
                isPaid: false,
                paidDate: nil,
                paidAmount: nil,
                isDatesOverridden: false,
                userId: userUID,
                createdAt: Date(),
                updatedAt: Date()
            )

            if let stmtId = stmtRepo.insertStatement(stmt) {
                // Mark past months as paid
                if !isCurrentMonth {
                    let paidDate = cal.date(byAdding: .day, value: -2, to: dueDate) ?? dueDate
                    _ = stmtRepo.markAsPaid(statementId: stmtId, paidAmount: nil, paidDate: paidDate)
                }
                stmtIds.append(stmtId)
            }
        }

        return stmtIds
    }

    private static func seedCreditCardTransactions(
        chaseId: Int,
        amexId: Int,
        chaseStmtIds: [Int],
        amexStmtIds: [Int],
        monthDates: [(date: Date, anchor: Int)],
        txRepo: TransactionRepository,
        cal: Calendar
    ) {
        // Chase: Restaurant (every month), Cinema (months 0,1,3,5), Netflix recurring instances
        // Amex: Clothes, larger purchases
        struct CCTxDef {
            let title: String
            let category: String
            let baseAmount: Int
            let day: Int
            let activeMonths: Set<Int>
            let cardId: Int
        }

        let chaseTxDefs: [CCTxDef] = [
            CCTxDef(title: "Restaurant", category: "meals", baseAmount: 8_500, day: 12, activeMonths: [0, 1, 2, 3, 4, 5], cardId: chaseId),
            CCTxDef(title: "Cinema", category: "entertainment", baseAmount: 4_000, day: 22, activeMonths: [0, 1, 3, 5], cardId: chaseId),
        ]

        let amexTxDefs: [CCTxDef] = [
            CCTxDef(title: "Clothes", category: "clothing", baseAmount: 15_000, day: 10, activeMonths: [2, 4], cardId: amexId),
        ]

        var count = 0

        for def in chaseTxDefs + amexTxDefs {
            for (idx, m) in monthDates.enumerated() {
                guard def.activeMonths.contains(idx) else { continue }

                let stmtIds = def.cardId == chaseId ? chaseStmtIds : amexStmtIds
                guard idx < stmtIds.count else { continue }

                let amount = def.baseAmount + (idx * 1_500)
                let txDate = dateForDay(def.day, in: m.date, cal: cal)
                let timestamp = Int(txDate.timeIntervalSince1970)

                let model = TransactionModel(
                    title: def.title,
                    category: def.category,
                    amount: amount,
                    type: "expense",
                    dateTimestamp: timestamp,
                    budgetMonthDate: m.anchor,
                    creditCardId: def.cardId,
                    statementId: stmtIds[idx],
                    isCreditCardStatement: true
                )
                do {
                    try txRepo.insertTransaction(model)
                    count += 1
                } catch {
                    logError("[DemoSeed] Failed to insert CC tx \(def.title) month \(idx): \(error)")
                }
            }
        }

        // Also link Netflix recurring instances to Chase
        linkNetflixToChase(chaseId: chaseId, chaseStmtIds: chaseStmtIds, monthDates: monthDates, txRepo: txRepo)

        // Recalculate statement totals
        let stmtRepo = StatementRepository()
        for stmtId in chaseStmtIds + amexStmtIds {
            stmtRepo.recalculateTotal(statementId: stmtId)
        }

        logInfo("[DemoSeed] Inserted \(count) credit card transactions")
    }

    private static func linkNetflixToChase(
        chaseId: Int,
        chaseStmtIds: [Int],
        monthDates: [(date: Date, anchor: Int)],
        txRepo: TransactionRepository
    ) {
        // Find Netflix transactions and link them to Chase
        let allTx = txRepo.fetchAllTransactions()
        let netflixTxs = allTx.filter { $0.title == "Netflix" && $0.parentTransactionId != nil }

        for tx in netflixTxs {
            guard let txId = tx.id else { continue }

            // Match to the right statement by month
            for (idx, m) in monthDates.enumerated() {
                if tx.budgetMonthDate == m.anchor, idx < chaseStmtIds.count {
                    try? txRepo.updateCreditCardFields(
                        transactionId: txId,
                        creditCardId: chaseId,
                        statementId: chaseStmtIds[idx],
                        isCreditCardStatement: true
                    )
                    break
                }
            }
        }
    }

    // MARK: - Budget Groups

    private static func seedBudgetGroups(userUID: String) {
        let repo = BudgetGroupRepository()

        let userName = AuthenticationManager.shared.currentUser?.displayName ?? "You"
        let userEmail = AuthenticationManager.shared.currentUser?.email ?? "you@email.com"

        let groupId = UUID().uuidString

        let group = BudgetGroup(
            id: groupId,
            name: "Family Budget",
            ownerId: userUID,
            ownerName: userName,
            ownerEmail: userEmail,
            currency: "BRL"
        )
        repo.insertGroup(group)

        // Owner member
        let ownerMember = GroupMember(
            groupId: groupId,
            userId: userUID,
            name: userName,
            email: userEmail,
            role: .owner,
            permissions: .fullAccess,
            lastActive: Date()
        )
        repo.insertMember(ownerMember)

        // Regular member (for testing permissions screen)
        let regularMember = GroupMember(
            groupId: groupId,
            userId: "demo-user-alice",
            name: "Alice",
            email: "alice@email.com",
            role: .member,
            permissions: .canAdd,
            lastActive: Calendar.current.date(byAdding: .hour, value: -3, to: Date())
        )
        repo.insertMember(regularMember)

        // Another member
        let viewOnlyMember = GroupMember(
            groupId: groupId,
            userId: "demo-user-bob",
            name: "Bob",
            email: "bob@email.com",
            role: .member,
            permissions: .viewOnly,
            lastActive: Calendar.current.date(byAdding: .day, value: -2, to: Date())
        )
        repo.insertMember(viewOnlyMember)

        // Extra members to test "+N" indicator and scrolling
        let carol = GroupMember(
            groupId: groupId,
            userId: "demo-user-carol",
            name: "Carol",
            email: "carol@email.com",
            role: .member,
            permissions: .canAdd,
            lastActive: Calendar.current.date(byAdding: .hour, value: -12, to: Date())
        )
        repo.insertMember(carol)

        let dave = GroupMember(
            groupId: groupId,
            userId: "demo-user-dave",
            name: "Dave",
            email: "dave@email.com",
            role: .member,
            permissions: .memberDefault,
            lastActive: Calendar.current.date(byAdding: .day, value: -5, to: Date())
        )
        repo.insertMember(dave)

        // Pending invitation (for testing GroupInvitation screen)
        let pendingInvitation = GroupInvitation(
            groupId: UUID().uuidString,
            groupName: "Roommates Expenses",
            inviterName: "Emma",
            inviterEmail: "emma@email.com",
            inviteeEmail: userEmail
        )
        repo.insertInvitation(pendingInvitation)

        logInfo("[DemoSeed] Inserted 1 budget group with 5 members + 1 pending invitation")
    }

    // MARK: - Date Helpers

    private static func dateForDay(_ day: Int, in monthDate: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month], from: monthDate)
        comps.day = day
        comps.hour = 12

        // Clamp to the last day of the month
        if let range = cal.range(of: .day, in: .month, for: monthDate) {
            comps.day = min(day, range.upperBound - 1)
        }

        return cal.date(from: comps) ?? monthDate
    }

    private static func makeDateFromComponents(year: Int, month: Int, day: Int, cal: Calendar) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12

        // Clamp day to valid range
        if let date = cal.date(from: DateComponents(year: year, month: month)),
           let range = cal.range(of: .day, in: .month, for: date) {
            comps.day = min(day, range.upperBound - 1)
        }

        return cal.date(from: comps) ?? Date()
    }
}
#endif
