//
//  MonthBudgetCardDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

public protocol MonthBudgetCardDelegate: AnyObject {
    func didTapConfigButton()
    func didTapDefineBudgetButton(budgetDate: Date)
}
