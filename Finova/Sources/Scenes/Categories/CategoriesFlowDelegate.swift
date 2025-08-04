//
//  CategoriesFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation

protocol CategoriesFlowDelegate: AnyObject {
    func navigateToSubCategoryManagement()
    func navigateToSubCategoryCreation(parentCategory: TransactionCategory?)
    func navigateToBudgetAllocation(for month: Date)
    func navigateBackToDashboard()
    func categoriesDidAppear()
}
