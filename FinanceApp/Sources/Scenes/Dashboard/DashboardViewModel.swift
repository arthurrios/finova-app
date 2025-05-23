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
            let date = Date(timeIntervalSince1970: TimeInterval(entry.monthDate))
            let key = DateFormatter.keyFormatter.string(from: date)
            acc[key] = entry.amount
        }
        
        let transactions = transactionRepo.fetchTransactions()
        
        let expenses = transactions
            .filter { $0.type == .expense }
            .reduce(into: [String: Int]()) { acc, tx in
                let key = DateFormatter.keyFormatter.string(from: tx.date)
                acc[key, default: 0] += tx.amount
            }
        
        let incomes = transactions
            .filter { $0.type == .income }
            .reduce(into: [String: Int]()) { acc, tx in
                let key = DateFormatter.keyFormatter.string(from: tx.date)
                acc[key, default: 0] += tx.amount
            }
        
        let sortedMonths = monthRange.map { offset in
            calendar.date(byAdding: .month, value: offset, to: today)!
        }.sorted()
        
        var runningAvailable = [String: Int]()
        var previousAvailable = 0
        
        return sortedMonths.compactMap { date in
            let key = DateFormatter.keyFormatter.string(from: date)
            let month = DateFormatter.monthFormatter.string(from: date)
            
            let expense = expenses[key] ?? 0
            let income = incomes[key] ?? 0
            let budgetLimit = budgetsByKey[key]
            
            
            let currentMonthBalance = income - expense
            let available: Int?
            
            available = previousAvailable + currentMonthBalance
            
            previousAvailable = available ?? previousAvailable + currentMonthBalance
            runningAvailable[key] = previousAvailable
            
            return MonthBudgetCardType(date: date,
                                       month: "month.\(month.lowercased())".localized,
                                       usedValue: expense,
                                       budgetLimit: budgetLimit,
                                       availableValue: available
            )
        }.sorted { $0.date < $1.date }
    }
}
