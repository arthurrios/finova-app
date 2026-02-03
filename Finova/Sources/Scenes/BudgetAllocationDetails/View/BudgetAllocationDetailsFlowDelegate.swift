//
//  BudgetAllocationDetailsFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 01/02/26.
//

import UIKit

protocol BudgetAllocationDetailsFlowDelegate: AnyObject {
    func dismissAllocationDetails()
    func navigateToTransactionDetails(transaction: Transaction)
    func editAllocation(_ allocation: BudgetAllocation)
    func createAllocation(forCategory category: TransactionCategory, monthAnchor: Int)
    func didUpdateAllocation()
    func didDeleteAllocation()
}
