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
        
        let budgetsByAnchor: [Int: Int] = budgetRepo.fetchBudgets()
            .reduce(into: [:]) { acc, entry in
                acc[entry.monthDate] = entry.amount
        }
        
        let allTxs = transactionRepo.fetchTransactions()
        
        let expensesByAnchor = allTxs
            .filter { $0.type == .expense }
            .reduce(into: [:]) { acc, tx in
                acc[tx.budgetMonthDate, default: 0] += tx.amount
            }
        
        let incomesByAnchor = allTxs
            .filter { $0.type == .income }
            .reduce(into: [:]) { acc, tx in
                acc[tx.budgetMonthDate, default: 0] += tx.amount
            }
        
        let anchors = monthRange.map { offset in
            let dt = calendar.date(byAdding: .month, value: offset, to: today)!
            return dt.monthAnchor
        }.sorted()
        
        var runningBalance = [Int: Int]()
        var previousAvailable = 0
        
        let cards: [MonthBudgetCardType] = anchors.compactMap { anchor in
            let date = Date(timeIntervalSince1970: TimeInterval(anchor))
            let month = DateFormatter.monthFormatter.string(from: date)
            
            let expense = expensesByAnchor[anchor] ?? 0
            let income = incomesByAnchor[anchor] ?? 0
            let budgetLimit = budgetsByAnchor[anchor]
            
            let net = income - expense
            let available = previousAvailable + net
            
            previousAvailable = available
            runningBalance[anchor] = available
            
            return MonthBudgetCardType(
                date: date,
                month: "month.\(month.lowercased())".localized,
                usedValue: expense,
                budgetLimit: budgetLimit,
                availableValue: available
            )
        }
        
        return cards.sorted { $0.date < $1.date }
    }
}
