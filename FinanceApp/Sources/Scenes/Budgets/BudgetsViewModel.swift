//
//  BudgetsViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation

final class BudgetsViewModel {
    let budgetRepo: BudgetRepository
    private let calendar = Calendar.current
    let selectedDate: Date?
    
    init(budgetRepo: BudgetRepository = BudgetRepository(), initialDate: Date? = nil) {
        self.budgetRepo = budgetRepo
        selectedDate = initialDate
    }
    
    func loadMonthTableViewData() -> [BudgetModel] {
        let budgets = budgetRepo.fetchBudgets()
        
        return budgets.map { entry in
            let date = Date(entry.monthKey)
            return BudgetModel(date: date, budget: entry.budget)
        }
    }
}
