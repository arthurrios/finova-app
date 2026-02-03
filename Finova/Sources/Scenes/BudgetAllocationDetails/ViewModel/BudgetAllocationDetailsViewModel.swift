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

final class BudgetAllocationDetailsViewModel {

    // MARK: - Properties

    private let transactionRepository: TransactionRepositoryProtocol
    private let allocationRepository: BudgetAllocationRepositoryProtocol
    private let allocationService: BudgetAllocationService
    private(set) var allocation: BudgetAllocation

    // MARK: - Initialization

    init(
        allocation: BudgetAllocation,
        transactionRepository: TransactionRepositoryProtocol = TransactionRepository(),
        allocationRepository: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        allocationService: BudgetAllocationService = BudgetAllocationService()
    ) {
        self.allocation = allocation
        self.transactionRepository = transactionRepository
        self.allocationRepository = allocationRepository
        self.allocationService = allocationService
    }

    // MARK: - Computed Properties

    var category: TransactionCategory { allocation.category }
    var allocatedAmount: Int { allocation.allocatedAmount }
    var usedAmount: Int { allocation.usedAmount }
    var remainingAmount: Int { allocation.remainingAmount }
    var usagePercentage: Int { Int(allocation.usagePercentage) }
    var status: AllocationStatus { allocation.status }

    /// Returns true if this allocation is part of a recurring series.
    /// This includes both parent allocations (isRecurring=true) and child allocations (parentAllocationId != nil)
    var isRecurring: Bool {
        allocation.isRecurring || allocation.parentAllocationId != nil
    }

    // MARK: - Formatted Strings

    var formattedAllocated: String {
        allocatedAmount.currencyString
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
        let date = Date(timeIntervalSince1970: TimeInterval(allocation.monthDate))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var overBudgetWarningMessage: String? {
        guard status == .overBudget else { return nil }
        let overAmount = abs(remainingAmount)
        return String(
            format: "allocation.details.summary.warning.over".localized,
            overAmount.currencyString
        )
    }

    // MARK: - Transactions

    func getFilteredTransactions() -> [Transaction] {
        let allTransactions = transactionRepository.fetchAllTransactions()

        // Filter transactions by:
        // 1. Category matches allocation category
        // 2. budgetMonthDate matches allocation month (same as how usage is calculated)
        // 3. Type is expense (allocations track expenses)
        return allTransactions.filter { transaction in
            transaction.category == allocation.category &&
            transaction.type == .expense &&
            transaction.budgetMonthDate == allocation.monthDate
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
        guard let dbId = allocation.dbId else {
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
        guard let dbId = allocation.dbId else {
            logError("BudgetAllocationDetailsVM: Cannot delete - allocation dbId is nil")
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
        // Reload allocation data from service (which calculates usage amounts)
        guard let dbId = allocation.dbId else { return }

        // Use the service to get allocations with usage calculated
        let allocations = allocationService.getAllocationsWithUsage(
            forMonth: allocation.monthDate
        )

        if let updatedAllocation = allocations.first(where: { $0.dbId == dbId }) {
            self.allocation = updatedAllocation
        }
    }
}
