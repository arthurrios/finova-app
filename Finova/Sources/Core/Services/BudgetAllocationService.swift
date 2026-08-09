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

    // MARK: - Initialization

    init(
        allocationRepo: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository()
    ) {
        self.allocationRepo = allocationRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
    }

    // MARK: - Create

    /// Creates a new budget allocation for a category in a given month.
    /// - Parameters:
    ///   - category: The transaction category to allocate budget for
    ///   - amount: The allocated amount in cents
    ///   - monthAnchor: The month anchor timestamp
    ///   - isRecurring: Whether this allocation should recur monthly
    /// - Returns: The ID of the created allocation
    @discardableResult
    func createAllocation(
        category: TransactionCategory,
        amount: Int,
        monthAnchor: Int,
        isRecurring: Bool
    ) throws -> Int {
        guard amount > 0 else { throw BudgetAllocationError.invalidAmount }

        let model = BudgetAllocationModel(
            monthDate: monthAnchor,
            categoryKey: category.key,
            allocatedAmount: amount,
            isRecurring: isRecurring
        )

        let newId = try allocationRepo.insertAllocation(model)

        // EAGER GENERATION: materialize the whole series NOW, so every occurrence exists before this
        // call returns. Nothing materializes on navigation any more, so a month skipped here would
        // simply be missing until some later pass happened to cover it.
        if isRecurring {
            let created = materializeSeries(parentId: newId, startMonth: monthAnchor)
            logWarning(
                "[RecurringAllocationCreate] series \(newId) (\(category.key)) materialized \(created) occurrence(s)")
        }

        return newId
    }

    /// Materializes every missing occurrence of ONE allocation series, from its own start month
    /// through the horizon. Returns how many were created.
    ///
    /// Series-anchored: `SeriesMonths.seriesAnchors` anchors the horizon on `max(now, start)`, so a
    /// series created while scrolled back to a past month fills the gap between its start and today
    /// rather than leaving it permanently empty.
    ///
    /// Idempotent and tombstone-aware, so it is safe to call on every CRUD and from the rolling
    /// top-up.
    @discardableResult
    func materializeSeries(parentId: Int, startMonth: Int) -> Int {
        let all = allocationRepo.fetchAllAllocations()
        guard let parent = all.first(where: { $0.dbId == parentId }) else { return 0 }

        let tombstoned = allocationRepo.deletedMonthsBySeries()[parentId] ?? []

        // Occurrences of THIS series, ascending, for the in-effect template.
        let series = all
            .filter { $0.dbId == parentId || $0.parentAllocationId == parentId }
            .sorted { $0.monthDate < $1.monthDate }
        var ownMonths = Set(series.map { $0.monthDate })

        // Months held by a DIFFERENT allocation in the same category. We cannot insert there (one
        // live allocation per month+category), but it is not this series' row — treating every
        // same-category row as "already covered" is what let an unrelated one-off punch a hole.
        let foreignMonths = Set(
            all.filter { $0.category.key == parent.category.key && !ownMonths.contains($0.monthDate) }
                .map { $0.monthDate })

        var created = 0
        for anchor in SeriesMonths.seriesAnchors(start: startMonth) {
            guard anchor > parent.monthDate else { continue }
            if ownMonths.contains(anchor) { continue }
            if tombstoned.contains(anchor) {
                logWarning(
                    "[Materialize] allocation month \(anchor) for '\(parent.category.key)' was deleted from series \(parentId) — not recreating")
                continue
            }
            if foreignMonths.contains(anchor) {
                logWarning(
                    "[Materialize] allocation month \(anchor) for '\(parent.category.key)' is held by a row outside series \(parentId) — skipping")
                continue
            }

            let template = series.last(where: { $0.monthDate <= anchor }) ?? parent
            let instance = BudgetAllocationModel(
                monthDate: anchor,
                categoryKey: parent.category.key,
                allocatedAmount: template.allocatedAmount,
                isRecurring: true,
                parentAllocationId: parentId
            )
            if (try? allocationRepo.insertAllocation(instance)) != nil {
                ownMonths.insert(anchor)
                created += 1
            }
        }

        return created
    }

    /// The rolling top-up: materializes every missing occurrence of every recurring series, each
    /// from its own start month through the horizon.
    ///
    /// Replaces generation-on-render. `getAllocationsWithUsage` used to materialize the month it was
    /// asked for — once per RENDERED carousel card, on the main thread — so a month existed only if
    /// the user had scrolled to it.
    @discardableResult
    func materializeAllSeries() -> Int {
        let all = allocationRepo.fetchAllAllocations()
        // Ongoing series, and bounded ones whose parent stopped recurring but still owns children —
        // excluding the latter meant a gap inside a bounded series could never heal.
        let parents = all.filter { candidate in
            guard candidate.parentAllocationId == nil, let id = candidate.dbId else { return false }
            return candidate.isRecurring || all.contains { $0.parentAllocationId == id }
        }

        var created = 0
        for parent in parents {
            guard let parentId = parent.dbId else { continue }
            created += materializeSeries(parentId: parentId, startMonth: parent.monthDate)
        }
        return created
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
            parentAllocationId: existing.parentAllocationId
        )

        try allocationRepo.updateAllocation(updated)
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

        switch option {
        case .currentOnly:
            // Update only this specific allocation
            logDebug("BudgetAllocationService: Calling updateAllocation for id \(id) ONLY")
            try updateAllocation(id: id, newAmount: newAmount)
        case .futureOnly:
            // Update this and all future recurring allocations
            logDebug("BudgetAllocationService: Calling updateRecurringAllocationAndFuture for id \(id)")
            try allocationRepo.updateRecurringAllocationAndFuture(id: id, newAmount: newAmount)
        case .all:
            // Update all allocations in this recurring series (past, present, future)
            logDebug("BudgetAllocationService: Calling updateAllRecurringAllocations for id \(id)")
            try allocationRepo.updateAllRecurringAllocations(id: id, newAmount: newAmount)
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
    /// A PURE READ. It used to materialize this month's recurring occurrences first, which made it a
    /// write called once per rendered carousel card, on the main thread — so a month's allocations
    /// existed only if the user had scrolled to that month. Generation now happens eagerly at CRUD
    /// time and in one rolling pass; see `materializeAllSeries`.
    func getAllocationsWithUsage(forMonth monthAnchor: Int) -> [BudgetAllocation] {
        // Fetch allocations for the month
        var allocations = allocationRepo.fetchAllocations(for: monthAnchor)

        // Debug: Log all allocations in storage vs filtered
        let allAllocations = allocationRepo.fetchAllAllocations()
        logDebug("BudgetAllocationService: All allocations in storage: \(allAllocations.count), for month \(monthAnchor): \(allocations.count)")
        if allocations.isEmpty && !allAllocations.isEmpty {
            logDebug("BudgetAllocationService: Stored monthDates: \(allAllocations.map { $0.monthDate })")
        }

        // Calculate usage by category from transactions
        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)

        // Fill in usage amounts
        for i in allocations.indices {
            let categoryKey = allocations[i].category.key
            allocations[i].setUsedAmount(usageByCategory[categoryKey] ?? 0)
        }

        return allocations
    }

    /// Calculates the unallocated budget summary for a month.
    /// - Parameter monthAnchor: The month anchor timestamp
    /// - Returns: Summary of unallocated budget and spending
    func getUnallocatedSummary(forMonth monthAnchor: Int) -> UnallocatedBudgetSummary {
        // Get total budget for the month
        let budgets = budgetRepo.fetchBudgets()
        let budget = budgets.first { $0.monthDate == monthAnchor }
        let totalBudget = budget?.amount ?? 0

        // Get total allocated
        let allocations = allocationRepo.fetchAllocations(for: monthAnchor)
        let totalAllocated = allocations.reduce(0) { $0 + $1.allocatedAmount }

        // Calculate spending in categories WITHOUT allocations
        let allocatedCategories = Set(allocations.map { $0.category.key })
        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)
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
    /// - Parameter monthAnchor: The month anchor timestamp
    /// - Returns: Array of unallocated category spending, sorted by amount (highest first)
    func getUnallocatedCategoriesWithSpending(forMonth monthAnchor: Int) -> [UnallocatedCategorySpending] {
        let existingAllocations = allocationRepo.fetchAllocations(for: monthAnchor)
        let allocatedCategoryKeys = Set(existingAllocations.map { $0.category.key })

        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)

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

    // MARK: - Private Helpers

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

    /// Generates recurring allocation instances for a month if they don't exist.
    /// Uses lazy generation pattern - instances are created on-demand when viewing a month.
    private func generateRecurringInstancesIfNeeded(forMonth monthAnchor: Int) {
        // Get all recurring parent allocations
        let allAllocations = allocationRepo.fetchAllAllocations()
        let recurringParents = allAllocations.filter {
            $0.isRecurring && $0.parentAllocationId == nil
        }

        // TOMBSTONES: a month the user deleted must never be recreated. Series-keyed, so a deletion
        // in one series does not punch a permanent hole in every later series for the same category.
        let deletedMonths = allocationRepo.deletedMonthsBySeries()

        logDebug("BudgetAllocationService: Found \(recurringParents.count) recurring parents")

        for parent in recurringParents {
            guard let parentId = parent.dbId else {
                logDebug("BudgetAllocationService: Skipping parent with no dbId")
                continue
            }

            if deletedMonths[parentId]?.contains(monthAnchor) == true {
                logDebug("BudgetAllocationService: month \(monthAnchor) was deleted from series \(parentId) — not recreating")
                continue
            }

            // Only generate instances for months AFTER the parent was created
            guard parent.monthDate < monthAnchor else {
                logDebug("BudgetAllocationService: Skipping parent (monthDate \(parent.monthDate) >= current \(monthAnchor))")
                continue
            }

            // Check if ANY allocation already exists for this month and category
            // This includes independent allocations (not linked to this parent) to support "ignore conflicts" flow
            let hasInstance = allAllocations.contains { allocation in
                allocation.monthDate == monthAnchor &&
                allocation.category.key == parent.category.key
            }

            if !hasInstance {
                logDebug("BudgetAllocationService: Creating recurring instance for \(parent.category.key) in month \(monthAnchor)")
                let instance = BudgetAllocationModel(
                    monthDate: monthAnchor,
                    categoryKey: parent.category.key,
                    allocatedAmount: parent.allocatedAmount,
                    isRecurring: true,  // Child instances are still part of the recurring series
                    parentAllocationId: parentId
                )
                _ = try? allocationRepo.insertAllocation(instance)
            } else {
                logDebug("BudgetAllocationService: Instance already exists for \(parent.category.key) in month \(monthAnchor)")
            }
        }
    }
}
