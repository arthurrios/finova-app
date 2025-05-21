//
//  BudgetRepositoryProtocol.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

protocol BudgetRepositoryProtocol {
    func fetchBudgets() -> [BudgetModel]
    func exists(monthDate: Int) -> Bool
    func insert(budget: BudgetModel) throws
    func update(budget: BudgetModel) throws
    func delete(monthDate: Int) throws
}
