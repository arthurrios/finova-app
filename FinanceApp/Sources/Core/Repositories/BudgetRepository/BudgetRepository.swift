//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
    let entries: [(String, Int)] = [
        ("2025-03", 2000_00),
        ("2025-05", 5000_00)
    ]
    
    func fetchBudgets() -> [BudgetEntry] {
        return entries.map { (monthKey, budget) in
            BudgetEntry(monthKey: monthKey, budget: budget)
        }
    }
}
