//
//  BudgetAllocationDetailsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import Foundation
import UIKit

// MARK: - Allocation Delete Option

enum AllocationDeleteOption {
    case currentOnly   // Delete only this month's allocation
    case futureOnly    // Delete this month and all future allocations
    case all           // Delete all occurrences (past, present, future)
}

// MARK: - Details Mode

enum AllocationDetailsMode {
    case allocated(BudgetAllocation)
    case unallocated(UnallocatedCategorySpending)
}

final class BudgetAllocationDetailsViewModel {

    // MARK: - Properties

    private let transactionRepository: TransactionRepositoryProtocol
    private let allocationRepository: BudgetAllocationRepositoryProtocol
    private let allocationService: BudgetAllocationService
    private(set) var allocation: BudgetAllocation?
    private(set) var unallocatedSpending: UnallocatedCategorySpending?
    let mode: AllocationDetailsMode

    /// Returns true if this is an unallocated category (no allocation set yet)
    var isUnallocatedMode: Bool {
        if case .unallocated = mode { return true }
        return false
    }

    // MARK: - Initialization

    /// Initializer for allocated mode (existing allocation)
    init(
        allocation: BudgetAllocation,
        transactionRepository: TransactionRepositoryProtocol = TransactionRepository(),
        allocationRepository: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        allocationService: BudgetAllocationService = BudgetAllocationService()
    ) {
        self.mode = .allocated(allocation)
        self.allocation = allocation
        self.unallocatedSpending = nil
        self.transactionRepository = transactionRepository
        self.allocationRepository = allocationRepository
        self.allocationService = allocationService
    }

    /// Initializer for unallocated mode (category with spending but no allocation)
    init(
        unallocatedSpending: UnallocatedCategorySpending,
        transactionRepository: TransactionRepositoryProtocol = TransactionRepository(),
        allocationRepository: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        allocationService: BudgetAllocationService = BudgetAllocationService()
    ) {
        self.mode = .unallocated(unallocatedSpending)
        self.allocation = nil
        self.unallocatedSpending = unallocatedSpending
        self.transactionRepository = transactionRepository
        self.allocationRepository = allocationRepository
        self.allocationService = allocationService
    }

    // MARK: - Computed Properties
    // Note: These properties use `self.allocation` when available to support refresh after edits.
    // The `mode` is only used for unallocated mode or as fallback.

    var category: TransactionCategory {
        if let allocation = allocation {
            return allocation.category
        }
        if case .unallocated(let spending) = mode {
            return spending.category
        }
        fatalError("Invalid state: no allocation or unallocated spending")
    }

    var monthDate: Int {
        if let allocation = allocation {
            return allocation.monthDate
        }
        if case .unallocated(let spending) = mode {
            return spending.monthDate
        }
        fatalError("Invalid state: no allocation or unallocated spending")
    }

    var allocatedAmount: Int {
        if let allocation = allocation {
            return allocation.allocatedAmount
        }
        return 0  // Unallocated mode - no allocation set
    }

    var usedAmount: Int {
        if let allocation = allocation {
            return allocation.usedAmount
        }
        if case .unallocated(let spending) = mode {
            return spending.spentAmount
        }
        return 0
    }

    var remainingAmount: Int {
        if let allocation = allocation {
            return allocation.remainingAmount
        }
        if case .unallocated(let spending) = mode {
            return -spending.spentAmount  // All spending is "over" since no budget
        }
        return 0
    }

    var usagePercentage: Int {
        if let allocation = allocation {
            return Int(allocation.usagePercentage)
        }
        return 100  // Unallocated: 100% over budget (or show as full)
    }

    var status: AllocationStatus {
        if let allocation = allocation {
            return allocation.status
        }
        return .overBudget  // Unallocated: always over since no budget set
    }

    /// Returns true if this allocation is part of a recurring series.
    /// This includes both parent allocations (isRecurring=true) and child allocations (parentAllocationId != nil)
    var isRecurring: Bool {
        if let allocation = allocation {
            return allocation.isRecurring || allocation.parentAllocationId != nil
        }
        return false  // Unallocated mode
    }

    // MARK: - Formatted Strings

    var formattedAllocated: String {
        if isUnallocatedMode {
            return "allocation.unallocated.label".localized
        }
        return allocatedAmount.currencyString
    }

    var formattedUsed: String {
        usedAmount.currencyString
    }

    var formattedRemaining: String {
        let remaining = remainingAmount
        if remaining < 0 {
            return "-" + abs(remaining).currencyString
        }
        return remaining.currencyString
    }

    var formattedPercentage: String {
        "\(usagePercentage)%"
    }

    var monthYearString: String {
        let date = Date(timeIntervalSince1970: TimeInterval(monthDate))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var overBudgetWarningMessage: String? {
        // For unallocated mode, show a different message
        if isUnallocatedMode {
            return "allocation.details.unallocated.warning".localized
        }
        guard status == .overBudget else { return nil }
        let overAmount = abs(remainingAmount)
        return String(
            format: "allocation.details.summary.warning.over".localized,
            overAmount.currencyString
        )
    }

    // MARK: - Transactions

    func getFilteredTransactions() -> [Transaction] {
        // `fetchTransactions()` rather than `fetchAllTransactions()`: installment and recurring
        // parents are zero-amount template rows carrying the series' category and month, so the
        // unfiltered fetch listed a bogus "<title> - Installment Parent · 0" entry in the purchase
        // month. The explicit guard below repeats that exclusion, so a path that reintroduces a
        // parent — the installment edit flow rebuilds them — cannot put one back on screen.
        let transactions = transactionRepository.fetchTransactions()

        // Filter transactions by:
        // 1. Category matches allocation/spending category
        // 2. budgetMonthDate matches the month (same as how usage is calculated)
        // 3. Type is expense (allocations track expenses)
        return transactions.filter { transaction in
            let isParentTemplate =
                transaction.parentTransactionId == nil
                && (transaction.hasInstallments == true || transaction.isRecurring == true)
            if isParentTemplate { return false }

            return transaction.category == category &&
                transaction.type == .expense &&
                transaction.budgetMonthDate == monthDate
        }.sorted { $0.date > $1.date } // Most recent first
    }

    var transactionCount: Int {
        getFilteredTransactions().count
    }

    // MARK: - Transaction Deletion

    func getTransactionType(for transaction: Transaction) -> TransactionComplexityType {
        guard let transactionId = transaction.id else { return .simple }

        // Check if this is a recurring transaction instance
        if let parentId = transaction.parentTransactionId {
            // Special case: if parentTransactionId points to itself, treat it as a parent transaction
            if parentId == transactionId {
                // Continue to parent transaction checks below
            } else {
                let allTransactions = transactionRepository.fetchAllTransactions()
                let parentTransaction = allTransactions.first(where: { $0.id == parentId })

                if parentTransaction?.isRecurring == true {
                    return .recurringInstance
                } else {
                    return .installmentInstance
                }
            }
        }

        // Check if this is a parent recurring transaction
        if transaction.isRecurring == true {
            return .recurringParent
        }

        // Special case: if mode is recurring but isRecurring is false (data corruption), treat as recurring parent
        if transaction.mode == .recurring && transaction.isRecurring != true {
            return .recurringParent
        }

        // Check if this is a parent installment transaction (only if not recurring)
        if transaction.hasInstallments == true && transaction.isRecurring != true {
            return .installmentParent
        }

        return .simple
    }

    func deleteTransaction(_ transaction: Transaction) -> Result<Void, Error> {
        guard let transactionId = transaction.id else {
            return .failure(
                NSError(
                    domain: "BudgetAllocationDetails", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid transaction ID"]))
        }

        do {
            try transactionRepository.deleteTransactionAndRelated(id: transactionId)
            refreshAllocation()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Async variants of the two deletes.
    ///
    /// Both are batch operations — "all occurrences" removes tens of rows, each with its own
    /// statement recalculation — so running them inline blocked the main thread for the whole series.
    func deleteTransactionAsync(
        _ transaction: Transaction, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.deleteTransaction(transaction)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func deleteTransactionWithOptionAsync(
        transactionId: Int,
        option: RecurringCleanupOption,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.deleteTransactionWithOption(
                transactionId: transactionId, option: option)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func deleteTransactionWithOption(
        transactionId: Int,
        option: RecurringCleanupOption
    ) -> Result<Void, Error> {
        do {
            let allTransactions = transactionRepository.fetchAllTransactions()
            guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
                return .failure(TransactionError.transactionNotFound)
            }

            // Handle simple transactions directly
            if transaction.isRecurring != true && transaction.parentTransactionId == nil
                && transaction.hasInstallments != true
            {
                try transactionRepository.delete(id: transactionId)
                refreshAllocation()
                return .success(())
            }

            // For complex transactions, use the repository method that handles cleanup properly
            try transactionRepository.deleteTransactionWithOption(id: transactionId, option: option)
            refreshAllocation()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Allocation Actions

    func deleteAllocation() -> Result<Void, Error> {
        guard let allocation = allocation, let dbId = allocation.dbId else {
            return .failure(BudgetAllocationError.allocationNotFound)
        }

        do {
            try allocationRepository.deleteAllocation(id: dbId)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func deleteRecurringAllocation(option: AllocationDeleteOption) -> Result<Void, Error> {
        guard let allocation = allocation, let dbId = allocation.dbId else {
            logError("BudgetAllocationDetailsVM: Cannot delete - allocation is nil or dbId is nil")
            return .failure(BudgetAllocationError.allocationNotFound)
        }

        logDebug("BudgetAllocationDetailsVM: Deleting allocation with dbId: \(dbId), option: \(option), isRecurring: \(allocation.isRecurring), parentId: \(String(describing: allocation.parentAllocationId))")

        do {
            switch option {
            case .currentOnly:
                // Delete only this specific allocation
                logDebug("BudgetAllocationDetailsVM: Calling deleteAllocation for id: \(dbId)")
                try allocationRepository.deleteAllocation(id: dbId)
            case .futureOnly:
                // Delete this and all future recurring allocations
                logDebug("BudgetAllocationDetailsVM: Calling deleteRecurringAllocationAndFuture for id: \(dbId)")
                try allocationRepository.deleteRecurringAllocationAndFuture(id: dbId)
            case .all:
                // Delete all allocations in this recurring series (past, present, future)
                logDebug("BudgetAllocationDetailsVM: Calling deleteAllRecurringAllocations for id: \(dbId)")
                try allocationRepository.deleteAllRecurringAllocations(id: dbId)
            }
            logDebug("BudgetAllocationDetailsVM: Deletion successful for option: \(option)")
            return .success(())
        } catch {
            logError("BudgetAllocationDetailsVM: Deletion failed with error: \(error)")
            return .failure(error)
        }
    }

    func refreshAllocation() {
        // For unallocated mode, recalculate the spent amount
        if case .unallocated(var spending) = mode {
            // Recalculate spent amount from transactions
            let transactions = getFilteredTransactions()
            let newSpentAmount = transactions.reduce(0) { $0 + $1.amount }
            // Note: We can't mutate the mode directly, but the transactions will be refetched
            // The spending amount is derived from transactions anyway
            return
        }

        // Reload allocation data from service (which calculates usage amounts)
        guard let allocation = allocation, let dbId = allocation.dbId else { return }

        // Use the service to get allocations with usage calculated
        let allocations = allocationService.getAllocationsWithUsage(
            forMonth: allocation.monthDate
        )

        if let updatedAllocation = allocations.first(where: { $0.dbId == dbId }) {
            self.allocation = updatedAllocation
        }
    }
}
