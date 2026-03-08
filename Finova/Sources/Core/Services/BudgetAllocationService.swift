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

        return try allocationRepo.insertAllocation(model)
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
            GroupNotificationService.shared.logActivity(
                action: .allocationEdited, groupId: groupId, detail: updated.categoryKey)
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
                GroupNotificationService.shared.logActivity(
                    action: .allocationEdited, groupId: groupId, detail: allocation?.category.key ?? "")
            }
        case .all:
            // Update all allocations in this recurring series (past, present, future)
            logDebug("BudgetAllocationService: Calling updateAllRecurringAllocations for id \(id)")
            try allocationRepo.updateAllRecurringAllocations(id: id, newAmount: newAmount)
            if let groupId = allocation?.sharedGroupId {
                GroupNotificationService.shared.logActivity(
                    action: .allocationEdited, groupId: groupId, detail: allocation?.category.key ?? "")
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
    func getAllocationsWithUsage(forMonth monthAnchor: Int) -> [BudgetAllocation] {
        // First, generate any missing recurring instances
        generateRecurringInstancesIfNeeded(forMonth: monthAnchor)

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
        return transactionRepo.fetchAllTransactions().filter { transaction in
            transaction.category == category &&
            transaction.budgetMonthDate == monthAnchor &&
            transaction.type == .expense
        }.sorted { $0.date > $1.date }
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
                    parentAllocationId: parentId,
                    sharedGroupId: parent.sharedGroupId
                )
                _ = try? allocationRepo.insertAllocation(instance)
            } else {
                logDebug("BudgetAllocationService: Instance already exists for \(parent.category.key) in month \(monthAnchor)")
            }
        }
    }
}
