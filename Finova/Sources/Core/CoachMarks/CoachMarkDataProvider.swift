//
//  CoachMarkDataProvider.swift
//  Finova
//

import Foundation

protocol CoachMarkDataProviding {
    func currentFacts() -> CoachMarkFacts
}

/// Reads through the repositories, so it sees the current user's rows and nothing else.
/// Read-only: this type and everything above it never write to the ledger.
struct CoachMarkDataProvider: CoachMarkDataProviding {
    func currentFacts() -> CoachMarkFacts {
        let thisMonth = Date().monthAnchor
        let budgets = BudgetRepository().fetchBudgets()
        let allocations = BudgetAllocationRepository().fetchAllAllocations()
        let transactionRepository = TransactionRepository()
        let uid = UserDefaultsManager.getUser()?.firebaseUID
            ?? UIDUserDefaultsManager.shared.currentUserUID

        return CoachMarkFacts(
            hasAnyBudget: !budgets.isEmpty,
            hasBudgetThisMonth: budgets.contains { $0.monthDate == thisMonth },
            hasAnyAllocation: !allocations.isEmpty,
            hasAllocationThisMonth: allocations.contains { $0.monthDate == thisMonth },
            hasRecurringTransaction: !transactionRepository.fetchRecurringTransactions().isEmpty,
            hasAnyTransaction: !transactionRepository.fetchAllTransactions().isEmpty,
            hasCreditCard: uid.map { !CreditCardRepository().fetchAllCards(userId: $0).isEmpty } ?? false
        )
    }
}
