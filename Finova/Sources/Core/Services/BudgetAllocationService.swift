//
//  BudgetAllocationService.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import Foundation

/// Service layer for Budget Allocations.
/// Contains business logic - calculations, validations, and coordination between repositories.
final class BudgetAllocationService {

    // MARK: - Dependencies

    private let allocationRepo: BudgetAllocationRepositoryProtocol
    private let transactionRepo: TransactionRepository
    private let budgetRepo: BudgetRepository
    private let statementRepo: StatementRepository

    // MARK: - Initialization

    init(
        allocationRepo: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository(),
        statementRepo: StatementRepository = StatementRepository()
    ) {
        self.allocationRepo = allocationRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
        self.statementRepo = statementRepo
    }

    // MARK: - Create

    /// Creates a new budget allocation for a category in a given month.
    /// - Parameters:
    ///   - category: The transaction category to allocate budget for
    ///   - amount: The allocated amount in cents
    ///   - monthAnchor: The month anchor timestamp
    ///   - isRecurring: Whether this allocation should recur monthly
    ///   - recurrenceEndMonth: last month anchor the series should cover. `nil` = ongoing
    ///     ("Always"). A bounded series materializes only up to this month and then stops recurring.
    /// - Returns: The ID of the created allocation
    @discardableResult
    func createAllocation(
        category: TransactionCategory,
        amount: Int,
        monthAnchor: Int,
        isRecurring: Bool,
        recurrenceEndMonth: Int?
    ) throws -> Int {
        try createAllocationInternal(
            category: category, amount: amount, monthAnchor: monthAnchor,
            isRecurring: isRecurring, recurrenceEndMonth: recurrenceEndMonth)
    }

    /// Back-compat overload: ongoing recurrence (no end month).
    @discardableResult
    func createAllocation(
        category: TransactionCategory,
        amount: Int,
        monthAnchor: Int,
        isRecurring: Bool
    ) throws -> Int {
        try createAllocationInternal(
            category: category, amount: amount, monthAnchor: monthAnchor,
            isRecurring: isRecurring, recurrenceEndMonth: nil)
    }

    private func createAllocationInternal(
        category: TransactionCategory,
        amount: Int,
        monthAnchor: Int,
        isRecurring: Bool,
        recurrenceEndMonth: Int?
    ) throws -> Int {
        guard amount > 0 else { throw BudgetAllocationError.invalidAmount }

        let model = BudgetAllocationModel(
            monthDate: monthAnchor,
            categoryKey: category.key,
            allocatedAmount: amount,
            isRecurring: isRecurring
        )

        let newId = try allocationRepo.insertAllocation(model)

        // EAGER BOUNDED GENERATION: materialize the full forward horizon now, so every future
        // occurrence exists as a real, syncable row at creation time (not lazily on navigation).
        // Series-scoped + tombstone-aware, so it only touches this brand-new series. Then push
        // immediately so sync happens right after creation.
        if isRecurring {
            generateRecurringAllocationHorizon(parentId: newId, endMonth: recurrenceEndMonth)
            SyncEngine.shared.pushPendingChangesNow()
        }

        return newId
    }

    /// True if this allocation belongs to a recurring series — including a BOUNDED series whose
    /// parent has already stopped recurring (`is_recurring = 0`) but still owns child occurrences.
    /// Without the children check, editing the first month of a bounded series would be treated as
    /// a one-off and silently skip the scope prompt.
    func isPartOfRecurringSeries(allocationId: Int) -> Bool {
        let all = allocationRepo.fetchAllAllocations()
        guard let allocation = all.first(where: { $0.dbId == allocationId }) else { return false }
        if allocation.isRecurring || allocation.parentAllocationId != nil { return true }
        return all.contains { $0.parentAllocationId == allocationId }
    }

    // MARK: - Update

    /// Updates an existing allocation's amount.
    /// - Parameters:
    ///   - id: The allocation ID to update
    ///   - newAmount: The new allocated amount in cents
    func updateAllocation(id: Int, newAmount: Int) throws {
        guard newAmount > 0 else { throw BudgetAllocationError.invalidAmount }

        // Find the existing allocation
        let allAllocations = allocationRepo.fetchAllAllocations()
        guard let existing = allAllocations.first(where: { $0.dbId == id }) else {
            throw BudgetAllocationError.allocationNotFound
        }

        let updated = BudgetAllocationModel(
            id: id,
            monthDate: existing.monthDate,
            categoryKey: existing.category.key,
            allocatedAmount: newAmount,
            isRecurring: existing.isRecurring,
            parentAllocationId: existing.parentAllocationId,
            sharedGroupId: existing.sharedGroupId
        )

        try allocationRepo.updateAllocation(updated)

        if let groupId = updated.sharedGroupId {
            let categoryName = TransactionCategory.allCases.first(where: { $0.key == updated.categoryKey })?.displayName ?? updated.categoryKey
            GroupNotificationService.shared.logActivity(
                action: .allocationEdited, groupId: groupId, detail: categoryName)
        }
    }

    /// Updates a recurring allocation with the specified option.
    /// - Parameters:
    ///   - id: The allocation ID to update
    ///   - newAmount: The new allocated amount in cents
    ///   - option: The edit option (currentOnly, futureOnly, or all)
    func updateAllocationWithOption(id: Int, newAmount: Int, option: AllocationEditOption) throws {
        guard newAmount > 0 else { throw BudgetAllocationError.invalidAmount }

        // Debug: Log the allocation being edited
        let allAllocations = allocationRepo.fetchAllAllocations()
        if let allocation = allAllocations.first(where: { $0.dbId == id }) {
            logDebug("BudgetAllocationService: Editing allocation - id: \(id), monthDate: \(allocation.monthDate), category: \(allocation.category.key), parentId: \(String(describing: allocation.parentAllocationId)), isRecurring: \(allocation.isRecurring)")
        }
        logDebug("BudgetAllocationService: Edit option: \(option), newAmount: \(newAmount)")

        let allocation = allAllocations.first(where: { $0.dbId == id })

        switch option {
        case .currentOnly:
            // Update only this specific allocation
            logDebug("BudgetAllocationService: Calling updateAllocation for id \(id) ONLY")
            try updateAllocation(id: id, newAmount: newAmount)
        case .futureOnly:
            // Update this and all future recurring allocations
            logDebug("BudgetAllocationService: Calling updateRecurringAllocationAndFuture for id \(id)")
            try allocationRepo.updateRecurringAllocationAndFuture(id: id, newAmount: newAmount)
            if let groupId = allocation?.sharedGroupId {
                let categoryName = allocation?.category.displayName ?? ""
                GroupNotificationService.shared.logActivity(
                    action: .allocationEdited, groupId: groupId, detail: categoryName)
            }
        case .throughMonth(let endMonth):
            // Update this occurrence and every later one up to (and including) endMonth
            logDebug("BudgetAllocationService: Calling updateRecurringAllocationsThrough for id \(id), endMonth \(endMonth)")
            try allocationRepo.updateRecurringAllocationsThrough(
                id: id, newAmount: newAmount, endMonth: endMonth)
            if let groupId = allocation?.sharedGroupId {
                let categoryName = allocation?.category.displayName ?? ""
                GroupNotificationService.shared.logActivity(
                    action: .allocationEdited, groupId: groupId, detail: categoryName)
            }
        case .all:
            // Update all allocations in this recurring series (past, present, future)
            logDebug("BudgetAllocationService: Calling updateAllRecurringAllocations for id \(id)")
            try allocationRepo.updateAllRecurringAllocations(id: id, newAmount: newAmount)
            if let groupId = allocation?.sharedGroupId {
                let categoryName = allocation?.category.displayName ?? ""
                GroupNotificationService.shared.logActivity(
                    action: .allocationEdited, groupId: groupId, detail: categoryName)
            }
        }
    }

    // MARK: - Delete

    /// Deletes an allocation.
    /// - Parameters:
    ///   - id: The allocation ID to delete
    ///   - deleteAllFuture: If true and allocation is recurring, deletes all future instances
    func deleteAllocation(id: Int, deleteAllFuture: Bool = false) throws {
        if deleteAllFuture {
            try allocationRepo.deleteRecurringAllocationAndFuture(id: id)
        } else {
            try allocationRepo.deleteAllocation(id: id)
        }
    }

    // MARK: - Fetch

    /// Fetches all allocations for a given month with usage calculated from transactions.
    /// Also generates any missing recurring instances for the month.
    /// - Parameter monthAnchor: The month anchor timestamp
    /// - Returns: Array of allocations with usage amounts filled in
    /// - Parameters:
    ///   - monthAnchor: The month anchor timestamp
    ///   - scope: which ledger to read — the caller's own, or a group's
    ///
    /// Until this took a scope, every one of its twelve call sites read the user-scoped set, so a
    /// group rendered the viewer's personal allocations (or nothing) regardless of context. The
    /// group-aware repository and usage queries have existed all along with no callers; this is
    /// what connects them.
    func getAllocationsWithUsage(forMonth monthAnchor: Int, in scope: LedgerScope) -> [BudgetAllocation] {
        // Generation stays deliberately user-scoped even in group scope: materialising instances
        // from a group-scoped read would pull other members' recurring series into this ledger.
        generateRecurringInstancesIfNeeded(forMonth: monthAnchor)

        // P3: fetch the full allocation set ONCE and filter locally. This method previously did
        // three separate full-table scans per call (fetchAllocations(for:) + a debug-only
        // fetchAllAllocations + …); the carousel is paged so this runs per visible card, but the
        // redundant scans within a single call were pure waste.
        let allAllocations = scope.groupId.map { allocationRepo.fetchAllocationsForGroup(groupId: $0) }
            ?? allocationRepo.fetchAllAllocations()
        var allocations = allAllocations.filter { $0.monthDate == monthAnchor }

        logDebug("BudgetAllocationService: All allocations in storage: \(allAllocations.count), for month \(monthAnchor): \(allocations.count)")
        if allocations.isEmpty && !allAllocations.isEmpty {
            logDebug("BudgetAllocationService: Stored monthDates: \(allAllocations.map { $0.monthDate })")
        }

        // Usage must come from the SAME scope as the allocations, or a group shows its own
        // allocations spent down by the viewer's personal transactions.
        let usageByCategory = usage(forMonth: monthAnchor, in: scope)

        // Fill in usage amounts
        for i in allocations.indices {
            let categoryKey = allocations[i].category.key
            allocations[i].setUsedAmount(usageByCategory[categoryKey] ?? 0)
        }

        return allocations
    }

    /// Calculates the unallocated budget summary for a month.
    /// - Parameters:
    ///   - monthAnchor: The month anchor timestamp
    ///   - scope: which ledger to read — the caller's own, or a group's
    ///
    /// Scope matters more here than anywhere else on this card: `BudgetCard.configure` gates its
    /// entire face on `totalBudget > 0`, so reading the PERSONAL budget row while rendering a group
    /// collapsed the card to the "define budget" empty state — donut, footer metrics and the
    /// projection blocks all gone — for any group whose viewer had no personal budget that month.
    func getUnallocatedSummary(forMonth monthAnchor: Int, in scope: LedgerScope) -> UnallocatedBudgetSummary {
        // Get total budget for the month, from the scope being rendered
        let budgets = scope.groupId.map { budgetRepo.fetchBudgetsForGroup(groupId: $0) }
            ?? budgetRepo.fetchBudgets()
        let budget = budgets.first { $0.monthDate == monthAnchor }
        let totalBudget = budget?.amount ?? 0

        // Get total allocated
        let allocations = allocations(forMonth: monthAnchor, in: scope)
        let totalAllocated = allocations.reduce(0) { $0 + $1.allocatedAmount }

        // Calculate spending in categories WITHOUT allocations. Usage must come from the SAME
        // scope as the allocations, or a group's unallocated spending is the viewer's own.
        let allocatedCategories = Set(allocations.map { $0.category.key })
        let usageByCategory = usage(forMonth: monthAnchor, in: scope)
        let unallocatedUsage = usageByCategory
            .filter { !allocatedCategories.contains($0.key) }
            .reduce(0) { $0 + $1.value }

        return UnallocatedBudgetSummary(
            monthDate: monthAnchor,
            totalBudget: totalBudget,
            totalAllocated: totalAllocated,
            totalUsedInUnallocatedCategories: unallocatedUsage
        )
    }

    /// Fetches transactions for a specific category in a specific month.
    /// - Parameters:
    ///   - category: The transaction category
    ///   - monthAnchor: The month anchor timestamp
    /// - Returns: Array of transactions sorted by date descending
    func getTransactions(forCategory category: TransactionCategory, monthAnchor: Int) -> [Transaction] {
        // Installments paid early stay in the list — dimmed by the cell, see
        // `TransactionCellConfiguration.isSettledEarly`. They stop consuming this month's allocation
        // through `calculateUsageByCategory`, which is where the exclusion belongs; the
        // early-payment debit spends against the Credit Card category in the month it was paid.
        return transactionRepo.fetchAllTransactions()
            .filter { transaction in
                transaction.category == category &&
                transaction.budgetMonthDate == monthAnchor &&
                transaction.type == .expense
            }
            .sorted { $0.date > $1.date }
    }

    /// Gets all available categories that don't have an allocation for the given month.
    /// - Parameter monthAnchor: The month anchor timestamp
    /// - Returns: Array of categories without allocations
    func getAvailableCategoriesForAllocation(monthAnchor: Int) -> [TransactionCategory] {
        let existingAllocations = allocationRepo.fetchAllocations(for: monthAnchor)
        let allocatedCategoryKeys = Set(existingAllocations.map { $0.category.key })

        return TransactionCategory.allCases.filter { category in
            !allocatedCategoryKeys.contains(category.key)
        }
    }

    /// Gets categories that have spending but no allocation for the given month.
    /// Only returns categories with actual spending (amount > 0).
    /// - Parameters:
    ///   - monthAnchor: The month anchor timestamp
    ///   - scope: which ledger to read — the caller's own, or a group's
    /// - Returns: Array of unallocated category spending, sorted by amount (highest first)
    func getUnallocatedCategoriesWithSpending(forMonth monthAnchor: Int, in scope: LedgerScope) -> [UnallocatedCategorySpending] {
        let existingAllocations = allocations(forMonth: monthAnchor, in: scope)
        let allocatedCategoryKeys = Set(existingAllocations.map { $0.category.key })

        let usageByCategory = usage(forMonth: monthAnchor, in: scope)

        // Find categories with spending but no allocation
        var unallocatedSpending: [UnallocatedCategorySpending] = []

        for (categoryKey, amount) in usageByCategory {
            // Skip if already allocated or no spending
            guard !allocatedCategoryKeys.contains(categoryKey), amount > 0 else { continue }

            // Find the category enum
            if let category = TransactionCategory.allCases.first(where: { $0.key == categoryKey }) {
                unallocatedSpending.append(UnallocatedCategorySpending(
                    category: category,
                    spentAmount: amount,
                    monthDate: monthAnchor
                ))
            }
        }

        // Sort by spent amount (highest first)
        return unallocatedSpending.sorted { $0.spentAmount > $1.spentAmount }
    }

    // MARK: - Deferred Card Spending

    /// Spending charged against `monthAnchor`'s allocations that the month's closing balance has not
    /// absorbed, because it sits on a credit card statement settling later.
    ///
    /// `AllocationBalanceProjection` takes this off the balance before projecting. The two figures have
    /// always bucketed a card purchase differently: `TransactionLedgerService` keeps card purchases out
    /// of the balance entirely and represents them by the statement synthetic, dated to the statement's
    /// due date, while usage below counts the purchase under its own `budgetMonthDate`. A card purchase
    /// therefore consumed the month's plan with nothing leaving the month's balance, and
    /// `base - unspentAllocations` *rose* by the amount spent.
    ///
    /// The row filter mirrors `calculateUsageByCategory` exactly - same scope, same
    /// `excludingEarlyPaidInstallments()`, same `budgetMonthDate`/`.expense` predicate - because this
    /// has to cancel that method's contribution, not approximate it. Note `budgetMonthDate` and not the
    /// transaction date: a business-day adjustment can push those into different months, and it is the
    /// allocation side this has to agree with. Change one and change both.
    func deferredCardSpending(forMonth monthAnchor: Int, in scope: LedgerScope) -> Int {
        let all = scope.groupId.map { transactionRepo.fetchTransactionsForGroup(groupId: $0) }
            ?? transactionRepo.fetchAllTransactions()

        // Only expenses, matching usage: a card refund never reduces `usedAmount`, so it must not
        // reduce what is subtracted here either.
        //
        // The cheap predicate runs first and `excludingEarlyPaidInstallments()` second - it is a
        // membership test, so the order cannot change the result, but it costs a query against
        // `DBHelper.shared`, and this runs per carousel cell. A month with no card spending now pays
        // nothing for it.
        let monthCardRows = all.filter {
            $0.budgetMonthDate == monthAnchor && $0.type == .expense
                && $0.creditCardId != nil && $0.isCreditCardStatement != true
        }
        guard !monthCardRows.isEmpty else { return 0 }

        let cardRows = monthCardRows.excludingEarlyPaidInstallments()
        guard !cardRows.isEmpty else { return 0 }

        let settlement = settlementMonths(forCards: Set(cardRows.compactMap { $0.creditCardId }))

        return cardRows.reduce(0) { total, transaction in
            guard let statementId = transaction.statementId,
                let settles = settlement[statementId]
            else {
                // Attached to no live statement, so no synthetic will ever carry this row into any
                // month's balance - deferred indefinitely rather than settled.
                return total + transaction.amount
            }
            return settles > monthAnchor ? total + transaction.amount : total
        }
    }

    // MARK: - Spend History

    /// How much of `category`'s plan this ledger's own closed months say actually gets spent.
    ///
    /// Feeds nothing monetary. `AllocationBalanceProjection` still assumes the whole plan will be
    /// spent, and this exists to tell the user what their own record says about that assumption -
    /// see `CategorySpendHistory` for why it reports a range rather than an average.
    ///
    /// A convenience over `spendHistories(for:before:in:asOf:)` for a single category. Both are read on
    /// a user-initiated screen open, never on a render path, which is why neither caches: a cache worth
    /// having here would have to be *static* (`allocationService` is a per-cell instance) and would
    /// then need locking, because `.allocationDataChanged` is posted from background threads by
    /// `SyncEngine`, `MirrorTagRestore` and `DataRepairService` while `.transactionDataChanged` is
    /// posted synchronously on the writing thread. Not paying for that.
    ///
    /// The row filter mirrors `calculateUsageByCategory` exactly - same scope, same
    /// `excludingEarlyPaidInstallments()`, same `budgetMonthDate`/`.expense` predicate. The ratio has
    /// to be a fraction of the same `usedAmount` the card displays, or the two disagree about one
    /// category in front of the user. Change one and change both.
    ///
    /// Card spending counts here, in its purchase month, exactly as the card already shows it. The
    /// statement-timing problem that `deferredCardSpending` exists for cannot arise: that one comes
    /// from the *balance* running on a cash clock while usage runs on a purchase clock, and this
    /// figure never touches the balance - it is `used / allocated` inside one month, both sides on the
    /// purchase clock. Statement synthetics are category `.creditCard`, are never persisted, and are
    /// appended only inside `TransactionLedgerService`, so they cannot reach this read at all.
    ///
    /// - Parameters:
    ///   - monthAnchor: the month being viewed. Excluded from its own history, along with everything
    ///     after it.
    ///   - reference: seam for tests, so the window is deterministic. Same convention as
    ///     `TransactionLedgerService.balanceAsOf(_:)`.
    func spendHistory(
        for category: TransactionCategory,
        before monthAnchor: Int,
        in scope: LedgerScope,
        asOf reference: Date = Date()
    ) -> CategorySpendHistory {
        spendHistories(for: [category], before: monthAnchor, in: scope, asOf: reference)[category.key]
            ?? .none
    }

    /// The same figure for several categories in **one** pass over each table.
    ///
    /// The explainer sheet lists every allocated category, and calling the single-category form per row
    /// would scan `BudgetAllocations` once per category - that table has no cache of any kind, so it
    /// would be a real full scan each time. Keyed by `TransactionCategory.key`; a category with no
    /// usable history is absent rather than present-and-empty, so a caller must fall back to `.none`.
    func spendHistories(
        for categories: [TransactionCategory],
        before monthAnchor: Int,
        in scope: LedgerScope,
        asOf reference: Date = Date()
    ) -> [String: CategorySpendHistory] {
        guard !categories.isEmpty else { return [:] }

        // Closed months only, and never past the month on screen. `closedMonthAnchors` already
        // excludes the current month; the `< monthAnchor` filter additionally keeps any month at or
        // after the one being viewed out of its own explanation - which matters on a future card,
        // whose neighbours are closed but irrelevant to it.
        //
        // Getting this wrong is the quiet way to break the feature: `generateRecurringAllocationHorizon`
        // materialises 36 months FORWARD with no spending behind them, and `fetchAllAllocations()`
        // returns every one, so a window that leaked forward would read them as 0% and report that
        // every category is never spent.
        let window = DateUtils.closedMonthAnchors(
            count: CategorySpendHistory.sampleWindow, asOf: reference
        ).filter { $0 < monthAnchor }
        guard !window.isEmpty else { return [:] }
        let months = Set(window)
        let wanted = Set(categories.map(\.key))

        let allAllocations = scope.groupId.map { allocationRepo.fetchAllocationsForGroup(groupId: $0) }
            ?? allocationRepo.fetchAllAllocations()

        // Summed, not assigned. `insertAllocation` rejects a second row for the same category, month
        // and scope, so this should be a single row - but the legacy UserDefaults-to-SQLite migration
        // above it writes straight to `db.insertBudgetAllocation` with no such check, so an old ledger
        // can hold a pair. Summing is the defensive read; picking one arbitrarily would silently
        // measure spending against half a plan.
        var allocatedByCategoryMonth: [String: [Int: Int]] = [:]
        for allocation in allAllocations
        where wanted.contains(allocation.category.key) && months.contains(allocation.monthDate)
            && allocation.allocatedAmount > 0 {
            allocatedByCategoryMonth[allocation.category.key, default: [:]][
                allocation.monthDate, default: 0] += allocation.allocatedAmount
        }
        guard !allocatedByCategoryMonth.isEmpty else { return [:] }

        // `usedAmount` on the rows above is ALWAYS zero - `BudgetAllocation.init(from:)` hard-sets it
        // and only `getAllocationsWithUsage` ever fills it in, one month at a time. Reading it here
        // would make every ratio 0 and the feature would report that nothing is ever spent, silently.
        // Usage comes from the transactions.
        let allTransactions = scope.groupId.map { transactionRepo.fetchTransactionsForGroup(groupId: $0) }
            ?? transactionRepo.fetchAllTransactions()

        let sampled = Set(allocatedByCategoryMonth.keys)
        let rows = allTransactions.filter {
            sampled.contains($0.category.key) && $0.type == .expense
                && months.contains($0.budgetMonthDate)
        }

        var usedByCategoryMonth: [String: [Int: Int]] = [:]
        // Applied after the cheap predicate: it is a membership test, so the order cannot change the
        // result, but it costs a query against `DBHelper.shared`. Skipped entirely when nothing matched.
        for transaction in rows.isEmpty ? [] : rows.excludingEarlyPaidInstallments() {
            usedByCategoryMonth[transaction.category.key, default: [:]][
                transaction.budgetMonthDate, default: 0] += transaction.amount
        }

        // A sampled month with no spending is a real 0% observation, not a gap - that is the signal
        // this whole type exists to surface.
        return allocatedByCategoryMonth.reduce(into: [String: CategorySpendHistory]()) { result, entry in
            let used = usedByCategoryMonth[entry.key] ?? [:]
            let ratios = entry.value.reduce(into: [Int: Double]()) { ratios, month in
                ratios[month.key] = Double(used[month.key] ?? 0) / Double(month.value)
            }
            result[entry.key] = CategorySpendHistory(ratiosByMonth: ratios)
        }
    }

    /// The ledger month each statement settles in.
    ///
    /// The due date, not the closing date: `CreditCardService.generateStatementTransactions` stamps the
    /// statement synthetic with `dueDate`, and `TransactionLedgerService` buckets every balance row by
    /// its own date. So the due month is the month the balance actually takes the hit.
    private func settlementMonths(forCards cardIds: Set<Int>) -> [Int: Int] {
        var months: [Int: Int] = [:]
        for cardId in cardIds {
            for statement in statementRepo.fetchStatements(forCardId: cardId) {
                guard let id = statement.id else { continue }
                months[id] = statement.dueDate.monthAnchor
            }
        }
        return months
    }

    // MARK: - Private Helpers

    /// The allocations of one month in one scope. One place the group/personal split is made, so the
    /// summary readers can't drift back apart from `getAllocationsWithUsage`.
    private func allocations(forMonth monthAnchor: Int, in scope: LedgerScope) -> [BudgetAllocation] {
        let all = scope.groupId.map { allocationRepo.fetchAllocationsForGroup(groupId: $0) }
            ?? allocationRepo.fetchAllAllocations()
        return all.filter { $0.monthDate == monthAnchor }
    }

    /// Spending by category for one month in one scope.
    private func usage(forMonth monthAnchor: Int, in scope: LedgerScope) -> [String: Int] {
        scope.groupId.map { calculateUsageByCategory(forMonth: monthAnchor, groupId: $0) }
            ?? calculateUsageByCategory(forMonth: monthAnchor)
    }

    /// Gives a generated allocation instance the identity every device derives for (series, month),
    /// replacing the random uuid the insert trigger assigned. Skipped silently when the parent has no
    /// uuid yet — the instance keeps its random one and `ConflictResolver`'s content matcher still
    /// covers it, exactly as before.
    private func assignAllocationInstanceIdentity(instanceId: Int, parentId: Int, monthDate: Int) {
        guard let parentUuid = DBHelper.shared.uuidIdentity(
            table: "BudgetAllocations", localId: parentId)?.uuid else { return }
        DBHelper.shared.assignDeterministicUuid(
            table: "BudgetAllocations", localId: instanceId,
            uuid: DeterministicIdentity.allocationInstance(
                parentUuid: parentUuid, monthDate: monthDate))
    }

    /// Calculates spending by category for a given month.
    /// Only counts expense transactions.
    private func calculateUsageByCategory(forMonth monthAnchor: Int) -> [String: Int] {
        let transactions = transactionRepo.fetchAllTransactions()
            .excludingEarlyPaidInstallments()
            .filter { $0.budgetMonthDate == monthAnchor && $0.type == .expense }

        var usage: [String: Int] = [:]
        for transaction in transactions {
            usage[transaction.category.key, default: 0] += transaction.amount
        }
        return usage
    }

    /// Group-aware version: calculates spending by category using all group members' transactions.
    func calculateUsageByCategory(forMonth monthAnchor: Int, groupId: String) -> [String: Int] {
        let transactions = transactionRepo.fetchTransactionsForGroup(groupId: groupId)
            .excludingEarlyPaidInstallments()
            .filter { $0.budgetMonthDate == monthAnchor && $0.type == .expense }

        var usage: [String: Int] = [:]
        for transaction in transactions {
            usage[transaction.category.key, default: 0] += transaction.amount
        }
        return usage
    }

    /// Generates recurring allocation instances for a month if they don't exist.
    /// Uses lazy generation pattern - instances are created on-demand when viewing a month.
    private func generateRecurringInstancesIfNeeded(forMonth monthAnchor: Int) {
        // HYDRATION GATE (mirrors recurring-transaction generation): a device that has not
        // completed a verified full pull must not materialize recurring occurrences for OTHER
        // series — it lacks the authoritative state (and tombstones) to know what was deleted
        // elsewhere, so it would resurrect deletions and diverge. Creation of a brand-new series
        // uses the ungated, series-scoped generateRecurringAllocationHorizon instead.
        guard UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2") else { return }

        // Get all recurring parent allocations
        let allAllocations = allocationRepo.fetchAllAllocations()
        let recurringParents = allAllocations.filter {
            $0.isRecurring && $0.parentAllocationId == nil
        }

        // TOMBSTONE AWARENESS: never recreate a month+category the user soft-deleted
        // (fetchAllAllocations excludes deleted rows, so we must consult deletions explicitly).
        let deletedKeys = DBHelper.shared.fetchDeletedAllocationKeys(
            userId: UIDUserDefaultsManager.shared.currentUserUID)

        logDebug("BudgetAllocationService: Found \(recurringParents.count) recurring parents")

        for parent in recurringParents {
            guard let parentId = parent.dbId else {
                logDebug("BudgetAllocationService: Skipping parent with no dbId")
                continue
            }

            // Only generate instances for months AFTER the parent was created
            guard parent.monthDate < monthAnchor else {
                logDebug("BudgetAllocationService: Skipping parent (monthDate \(parent.monthDate) >= current \(monthAnchor))")
                continue
            }

            // Don't resurrect a deleted occurrence.
            if deletedKeys.contains("\(monthAnchor)|\(parent.category.key)") {
                logDebug("BudgetAllocationService: Skipping deleted occurrence \(parent.category.key) @ \(monthAnchor)")
                continue
            }

            // Check if ANY allocation already exists for this month and category
            // This includes independent allocations (not linked to this parent) to support "ignore conflicts" flow
            let hasInstance = allAllocations.contains { allocation in
                allocation.monthDate == monthAnchor &&
                allocation.category.key == parent.category.key
            }

            if !hasInstance {
                // Inherit the amount from the occurrence "in effect" at this month — the
                // most recent occurrence (parent or an edited child) at or before the
                // target month — instead of always the parent's amount. Without this, an
                // "edit this and future" change (which updates existing rows but not the
                // earlier parent) silently reverted for months materialized later.
                let seriesOccurrences = allAllocations
                    .filter { $0.dbId == parentId || $0.parentAllocationId == parentId }
                    .sorted { $0.monthDate < $1.monthDate }
                let template = seriesOccurrences.last(where: { $0.monthDate <= monthAnchor }) ?? parent

                logDebug("BudgetAllocationService: Creating recurring instance for \(parent.category.key) in month \(monthAnchor) with amount \(template.allocatedAmount)")
                let instance = BudgetAllocationModel(
                    monthDate: monthAnchor,
                    categoryKey: parent.category.key,
                    allocatedAmount: template.allocatedAmount,
                    isRecurring: true,  // Child instances are still part of the recurring series
                    parentAllocationId: parentId,
                    sharedGroupId: parent.sharedGroupId
                )
                // Derived identity for (series, month): a month materialised independently on two
                // devices becomes ONE row instead of two that then have to be matched by content.
                if let newId = try? allocationRepo.insertAllocation(instance) {
                    assignAllocationInstanceIdentity(
                        instanceId: newId, parentId: parentId, monthDate: monthAnchor)
                }
            } else {
                logDebug("BudgetAllocationService: Instance already exists for \(parent.category.key) in month \(monthAnchor)")
            }
        }
    }

    /// EAGER, series-scoped horizon generation for a single recurring parent. Materializes every
    /// occurrence from the parent's month through `now + horizonMonths`. Unlike
    /// generateRecurringInstancesIfNeeded this is NOT hydration-gated — it only ever touches the
    /// one (brand-new) series identified by `parentId`, which has no cross-device history to
    /// conflict with — but it IS tombstone-aware and idempotent, so it never duplicates or
    /// resurrects a deleted occurrence. Called at creation so the whole series syncs up front.
    private func generateRecurringAllocationHorizon(parentId: Int, endMonth: Int? = nil) {
        let all = allocationRepo.fetchAllAllocations()
        guard let parent = all.first(where: { $0.dbId == parentId }), parent.isRecurring else { return }

        let deletedKeys = DBHelper.shared.fetchDeletedAllocationKeys(
            userId: UIDUserDefaultsManager.shared.currentUserUID)

        let seriesOccurrences = all
            .filter { $0.dbId == parentId || $0.parentAllocationId == parentId }
            .sorted { $0.monthDate < $1.monthDate }

        // Months already covered for this category (any series), so we don't duplicate.
        var existingMonths = Set(all.filter { $0.category.key == parent.category.key }.map { $0.monthDate })

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!
        let now = Date()

        // Batch all horizon inserts into one transaction (one fsync instead of ~36) AND one UI
        // change notification (each insert previously triggered a full main-thread allocation
        // re-query + table reload — 36 of them back to back).
        try? allocationRepo.performBulk {
            for offset in 1...RecurringTransactionManager.horizonMonths {
                guard let targetDate = utcCalendar.date(byAdding: .month, value: offset, to: now) else { continue }
                let anchor = targetDate.monthAnchor
                guard anchor > parent.monthDate else { continue }
                // Bounded series: never materialize past the chosen end month.
                if let endMonth = endMonth, anchor > endMonth { break }
                if existingMonths.contains(anchor) { continue }
                if deletedKeys.contains("\(anchor)|\(parent.category.key)") { continue }

                let template = seriesOccurrences.last(where: { $0.monthDate <= anchor }) ?? parent
                let instance = BudgetAllocationModel(
                    monthDate: anchor,
                    categoryKey: parent.category.key,
                    allocatedAmount: template.allocatedAmount,
                    isRecurring: true,
                    parentAllocationId: parentId,
                    sharedGroupId: parent.sharedGroupId
                )
                if let newId = try? allocationRepo.insertAllocation(instance) {
                    assignAllocationInstanceIdentity(
                        instanceId: newId, parentId: parentId, monthDate: anchor)
                    existingMonths.insert(anchor)
                }
            }
        }
        // A bounded series must stop growing: clear the parent's recurrence so the rolling
        // generator (`generateRecurringInstancesIfNeeded`) never extends it past the end month.
        // `is_recurring` is an already-synced column, so the bound is honoured on every device
        // without adding a new CloudKit field (which production schema would reject).
        if endMonth != nil {
            try? allocationRepo.updateIsRecurring(allocationId: parentId, isRecurring: false)
        }

        logWarning("[RecurringAllocationCreate] generated horizon for parent \(parentId) (\(parent.category.key)) endMonth=\(endMonth.map(String.init) ?? "always")")
    }
}
