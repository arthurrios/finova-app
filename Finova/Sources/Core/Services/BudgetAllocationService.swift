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

        // EAGER GENERATION: materialize the whole series NOW — from this month through the horizon —
        // so every occurrence exists as a real, syncable row before this call returns. Nothing
        // materializes on navigation any more, so anything skipped here would simply be missing.
        // Series-scoped, tombstone-aware and idempotent, so it only touches this brand-new series.
        if isRecurring {
            // Materialize, THEN adopt orphans, THEN materialize again.
            //
            // The order matters. The allocation linker requires an orphan to border a month the
            // series already owns (category + scope is thin evidence on its own), and at this point
            // the series owns exactly one month — so relinking first could adopt almost nothing.
            // The second pass then fills the months those newly-adopted rows had been blocking as
            // foreign. Both passes are idempotent, so on a clean create the extra one is a no-op.
            var created = allocationRepo.materializeSeries(
                parentId: newId, endMonth: recurrenceEndMonth)
            let adopted = RecurringSeriesLinker(allocationRepo: allocationRepo)
                .repairAllocationSeries(around: newId)
            if adopted > 0 {
                created += allocationRepo.materializeSeries(
                    parentId: newId, endMonth: recurrenceEndMonth)
            }
            logWarning(
                "[RecurringAllocationCreate] series \(newId) (\(category.key)) materialized \(created) occurrence(s), adopted \(adopted), endMonth=\(recurrenceEndMonth.map(String.init) ?? "always")"
            )

            // A bounded series must stop growing: clear the parent's recurrence so the rolling
            // top-up never extends it past the end month. `is_recurring` is an already-synced
            // column, so the bound is honoured on every device without a new CloudKit field.
            if recurrenceEndMonth != nil {
                try? allocationRepo.updateIsRecurring(allocationId: newId, isRecurring: false)
            }

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

    /// The LIVE row a scoped write should anchor its pre-write repair and materialization on.
    ///
    /// Both `repairAllocationSeries` and `materializeSeries` open with `first(where: { $0.id ==
    /// parentId })` and return 0 when it misses, so anchoring on a `parent_allocation_id` that no
    /// local row answers to turns the whole repair-then-materialize preamble into a silent no-op —
    /// and the write that follows reaches only the rows sharing that same dangling pointer. That is
    /// the "edit this and all future changed January and March, nothing else" report: the pointer
    /// had arrived from another device, where it addressed a different row entirely.
    ///
    /// When the pointer leads nowhere, fall back to the earliest live row that shares this series'
    /// identity — category + scope, per `RecurringSeriesLinker` — at or before the edited month, so
    /// the repair pass can adopt the edited row and its stranded siblings back into one timeline.
    /// The edited row itself is always a candidate, so this never returns an id that cannot anchor.
    private func seriesAnchor(for id: Int, in all: [BudgetAllocation]) -> Int {
        guard let target = all.first(where: { $0.dbId == id }) else { return id }
        // No pointer at all means the row IS a root — nothing to resolve. Only a pointer that leads
        // nowhere gets the search below, so the healthy path keeps its exact previous behaviour.
        guard let pointer = target.parentAllocationId else { return id }
        if all.contains(where: { $0.dbId == pointer }) { return pointer }

        let peers = all.filter { candidate in
            guard let candidateId = candidate.dbId else { return false }
            guard candidate.category.key == target.category.key,
                (candidate.sharedGroupId ?? "") == (target.sharedGroupId ?? ""),
                candidate.monthDate <= target.monthDate
            else { return false }
            // Same bound the linker applies: a genuine one-off is nobody's series root.
            return candidate.isRecurring || candidate.parentAllocationId != nil
                || all.contains { $0.parentAllocationId == candidateId }
        }

        let anchor = peers.min {
            ($0.monthDate, $0.dbId ?? 0) < ($1.monthDate, $1.dbId ?? 0)
        }
        guard let anchorId = anchor?.dbId, anchorId != id else { return id }

        logWarning(
            "[AllocationEdit] row \(id) points at parent \(pointer), which is not a local allocation — anchoring the series repair on \(anchorId) instead"
        )
        return anchorId
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

        // RELINK, THEN MATERIALIZE, THEN EDIT. A scoped edit selects siblings by parent pointer, so
        // an occurrence whose pointer is broken is invisible to it and stays outdated; and with
        // nothing generating on navigation, months that were never materialized would simply be
        // skipped. Both are repaired before the scope is applied, so the pointer filter downstream
        // is sufficient. Skipped for `.currentOnly`, which touches exactly one known row.
        if case .currentOnly = option {} else {
            let scoped = allocationRepo.fetchAllAllocations()
            if scoped.contains(where: { $0.dbId == id }) {
                let seriesParentId = seriesAnchor(for: id, in: scoped)
                let relinked = RecurringSeriesLinker(allocationRepo: allocationRepo)
                    .repairAllocationSeries(around: seriesParentId)
                let materialized = allocationRepo.materializeSeries(
                    parentId: seriesParentId, endMonth: nil)
                if relinked > 0 || materialized > 0 {
                    logWarning(
                        "[AllocationEdit] relinked \(relinked) and materialized \(materialized) occurrence(s) before edit (option=\(option))"
                    )
                }
            }
        }

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
        // Same reasoning as the edit path: a scoped delete selects siblings by parent pointer, so
        // orphaned occurrences would survive a "delete future" and reappear as strays.
        if deleteAllFuture {
            let scoped = allocationRepo.fetchAllAllocations()
            if scoped.contains(where: { $0.dbId == id }) {
                RecurringSeriesLinker(allocationRepo: allocationRepo)
                    .repairAllocationSeries(around: seriesAnchor(for: id, in: scoped))
            }
        }

        if deleteAllFuture {
            try allocationRepo.deleteRecurringAllocationAndFuture(id: id)
        } else {
            try allocationRepo.deleteAllocation(id: id)
        }

        SyncEngine.shared.pushPendingChangesNow()
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
    /// A PURE READ. It used to materialize this month's recurring occurrences first, which made it a
    /// write called once per rendered carousel card, on the main thread, from inside UIKit reloads —
    /// so a month's allocations existed only if the user had scrolled to that month. Generation now
    /// happens eagerly at CRUD time and in one rolling background pass; see `materializeAllSeries`.
    func getAllocationsWithUsage(forMonth monthAnchor: Int, in scope: LedgerScope) -> [BudgetAllocation] {
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

    /// The rolling top-up for allocations: materializes every missing occurrence of every recurring
    /// series, each from its own start month through the horizon.
    ///
    /// Replaces `generateRecurringInstancesIfNeeded(forMonth:)`, which ran from
    /// `getAllocationsWithUsage` — that is, once per RENDERED carousel card, on the main thread,
    /// with no serialization. A month therefore existed only if the user had scrolled to it, which
    /// is exactly the "stale throughout the months" behaviour. Nothing generates on render now.
    ///
    /// Runs on a serial queue and answers on it. Idempotent, so re-running costs one query.
    func materializeAllSeries(completion: ((Int) -> Void)? = nil) {
        Self.materializationQueue.async { [self] in
            // HYDRATION GATE: a device that has not completed a verified full pull lacks the
            // tombstones to know what was deleted elsewhere, so it would resurrect deletions and
            // diverge. Creation of a brand-new series is series-scoped and stays ungated.
            guard UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2") else {
                completion?(0)
                return
            }

            let created = allocationRepo.materializeAllSeries()
            if created > 0 {
                logWarning("[Materialize] created \(created) allocation occurrence(s)")
            }
            completion?(created)
        }
    }

    /// Serializes allocation materialization app-wide, mirroring
    /// `RecurringTransactionManager.operationQueue`. Static so every service instance shares it —
    /// `BudgetAllocationService` is deliberately not a singleton, so two instances could otherwise
    /// interleave reads and writes on the same series.
    private static let materializationQueue = DispatchQueue(
        label: "allocation.series.materialization", qos: .userInitiated)
}
