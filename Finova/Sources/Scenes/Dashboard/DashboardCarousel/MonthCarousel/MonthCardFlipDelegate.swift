//
//  MonthCardFlipDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 01/02/26.
//

import UIKit

protocol MonthCardFlipDelegate: AnyObject {
    func didRequestFlip(isShowingBudgetView: Bool)
    func didSelectAllocationCategory(_ category: TransactionCategory)
    /// A tag arc on the donut was tapped. `nil` clears the selection.
    func didSelectAllocationTag(_ tagId: String?)
    func didTapAllocation(_ allocation: BudgetAllocation)
    func didTapUnallocatedSpending(_ spending: UnallocatedCategorySpending)
    func didTapBudgetsConfig(forMonth monthAnchor: Int)
    func didTapDefineBudget(forMonth monthAnchor: Int)
}
