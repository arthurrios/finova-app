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
        
    init(budgetRepo: BudgetRepository = BudgetRepository()) { // 3 years
        self.budgetRepo = budgetRepo
    }
    
    func loadMonthTableViewData() -> [String] {
        return []
    }
}
