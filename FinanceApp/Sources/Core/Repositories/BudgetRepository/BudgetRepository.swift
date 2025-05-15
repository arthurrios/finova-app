//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
    let entries: [(String, Int)] = [
        ("2025-03-01", 2000_00),
        ("2025-05-01", 5000_00)
    ]
    
    func fetchBudgets() -> [BudgetEntry] {
        return entries.compactMap{ (dateString, budget) -> BudgetEntry? in
            guard let date = DateFormatter.yyyyMMdd.date(from: dateString) else {
                print("⚠️ Failed to parse date: \(dateString)")
                
                return nil
            }
            return BudgetEntry(monthTimestamp: date.timeIntervalSince1970, budget: budget)
        }
    }
}
