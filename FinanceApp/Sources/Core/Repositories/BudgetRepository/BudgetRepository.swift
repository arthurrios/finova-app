//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
    private let db = DBHelper.shared
    
    func insert(budget: BudgetModel) throws {
        try db.insertBudget(monthDate: budget.monthDate, amount: budget.amount)
    }
    
    func update(budget: BudgetModel) throws {
        try db.updateBudget(monthDate: budget.monthDate, amount: budget.amount)
    }
    
    func delete(monthDate: Int) throws {
        try db.deleteBudget(monthDate: monthDate)
    }
    
    func fetchBudgets() -> [BudgetModel] {
        (try? db.getBudgets()) ?? []
    }
    
    func exists(monthDate: Int) -> Bool {
        (try? db.exists(monthDate: monthDate)) ?? false
    }
}
