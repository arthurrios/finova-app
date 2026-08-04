//
//  DashboardFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

protocol DashboardFlowDelegate: AnyObject {
    func logout()
    func navigateToBudgets(date: Date?)
    func openAddTransactionModal()
    func openAddAllocationModal(forMonth monthAnchor: Int, preselectedCategory: TransactionCategory?)
    func navigateToProfile()
    func navigateToNotificationHistory()
    func navigateToTransactionDetails(transaction: Transaction)
    func navigateToAllocationDetails(allocation: BudgetAllocation)
    func navigateToUnallocatedDetails(unallocatedSpending: UnallocatedCategorySpending)
    func navigateToStatementDetails(card: CreditCard, statement: CreditCardStatement)
    func openAdjustBalanceModal(currentBalance: Int)
    func navigateToAllocationTags()
    /// Creates a tag from the dashboard and goes straight to linking its categories - the same flow the
    /// Tags list uses, so the two entry points cannot drift apart.
    func presentCreateAllocationTag()
}
