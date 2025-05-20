//
//  DashboardViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

final class DashboardViewModel {
    let budgetRepo: BudgetRepository
    let transactionRepo: TransactionRepository
    private let calendar = Calendar.current
    
    private let monthRange: ClosedRange<Int>
    
    init(budgetRepo: BudgetRepository = BudgetRepository(), transactionRepo: TransactionRepository = TransactionRepository(), monthRange: ClosedRange<Int> = -12...24) { // 3 years
        self.budgetRepo = budgetRepo
        self.transactionRepo = transactionRepo
        self.monthRange = monthRange
    }
    
    func loadMonthlyCards() -> [MonthBudgetCardType] {
        let today = Date()
        
        let budgetsArray = budgetRepo.fetchBudgets()
        let budgetsByKey = budgetsArray.reduce(into: [String: Int]()) { acc, entry in
            acc[entry.monthKey] = entry.budget
        }
                
        let spendings = transactionRepo.fetchTransactions()
            .filter { $0.type == .outcome }
            .reduce(into: [String: Int]()) { acc, tx in
                let key = DateFormatter.keyFormatter.string(from: tx.date)
                acc[key, default: 0] += tx.amount
            }
        
        return monthRange.compactMap { offset in
            let date = calendar.date(byAdding: .month, value: offset, to: today)!
            let key = DateFormatter.keyFormatter.string(from: date)
            let used = spendings[key] ?? 0
            let month = DateFormatter.monthFormatter.string(from: date)
            
            let budgetLimit = budgetsByKey[key]
            let available = budgetLimit.map { $0 - used }
                        
            return MonthBudgetCardType(date: date,
                                       month: "month.\(month.lowercased())".localized, 
                                       usedValue: used, 
                                       budgetLimit: budgetLimit,
                                       availableValue: available
            )
        }
    }
}
