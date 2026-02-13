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
    func openAddTransactionModal(context: DataContext)
    func openAddAllocationModal(forMonth monthAnchor: Int, preselectedCategory: TransactionCategory?)
    func navigateToProfile()
    func navigateToNotificationHistory()
    func navigateToTransactionDetails(transaction: Transaction)
    func navigateToAllocationDetails(allocation: BudgetAllocation)
    func navigateToUnallocatedDetails(unallocatedSpending: UnallocatedCategorySpending)
    func navigateToStatementDetails(card: CreditCard, statement: CreditCardStatement)
    func openAdjustBalanceModal(currentBalance: Int, context: DataContext)
}
