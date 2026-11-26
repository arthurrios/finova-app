//
//  BudgetsViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation

public protocol BudgetsViewDelegate: AnyObject {
    func didTapAddBudgetButton(monthYearDate: String, budgetAmount: Int)
    /// Save the same amount from the typed month through `endMonth` (a month anchor).
    func didTapAddBudgets(monthYearDate: String, budgetAmount: Int, endMonth: Int)
    func didTapBackButton()
    func didTapManageTags()
}
