//
//  BudgetCellDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 22/05/25.
//

import Foundation

public protocol BudgetsCellDelegate: AnyObject {
    func budgetCellDidRequestDelete(_ cell: BudgetsCell, completion: @escaping (Bool) -> Void)
}
