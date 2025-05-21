//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
    let entries: [(String, Int)] = [
        ("2024-08", 5000_00),
        ("2024-09", 5000_00),
        ("2024-10", 5000_00),
        ("2024-11", 5000_00),
        ("2024-12", 5000_00),
        ("2025-01", 5000_00),
        ("2025-02", 5000_00),
        ("2025-03", 5000_00),
        ("2025-05", 5000_00),
    ]
    
    func fetchBudgets() -> [BudgetEntry] {
        return entries.map { (monthKey, budget) in
            BudgetEntry(monthKey: monthKey, budget: budget)
        }
    }
}
