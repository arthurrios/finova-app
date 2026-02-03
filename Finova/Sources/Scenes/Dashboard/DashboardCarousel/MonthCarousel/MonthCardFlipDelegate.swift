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
    func didTapAllocation(_ allocation: BudgetAllocation)
    func didTapBudgetsConfig(forMonth monthAnchor: Int)
    func didTapDefineBudget(forMonth monthAnchor: Int)
}
