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
    func didUpdateAllocation()
    func didDeleteAllocation()
}
