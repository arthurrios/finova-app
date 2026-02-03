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
    func navigateToSettings()
    func navigateToNotificationHistory()
    func navigateToTransactionDetails(transaction: Transaction)
    func navigateToAllocationDetails(allocation: BudgetAllocation)
    func navigateToUnallocatedDetails(unallocatedSpending: UnallocatedCategorySpending)
}
