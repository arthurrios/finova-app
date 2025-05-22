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
    private lazy var monthCardsCache: [MonthBudgetCardType] = buildMonthlyCards()
    
    private let monthRange: ClosedRange<Int>
    
    init(budgetRepo: BudgetRepository = BudgetRepository(), transactionRepo: TransactionRepository = TransactionRepository(), monthRange: ClosedRange<Int> = -12...24) { // 3 years
        self.budgetRepo = budgetRepo
        self.transactionRepo = transactionRepo
        self.monthRange = monthRange
    }
    
    func loadMonthlyCards() -> [MonthBudgetCardType] {
      return monthCardsCache
    }
    
    func refreshMonthlyCards() {
        monthCardsCache = buildMonthlyCards()
    }
    
    private func buildMonthlyCards() -> [MonthBudgetCardType] {
        let today = Date()
        let budgets = budgetRepo.fetchBudgets()
            .reduce(into: [String:Int]()) { acc, e in
                let key = DateFormatter.keyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(e.monthDate)))
                acc[key] = e.amount
            }
        let allTx = transactionRepo.fetchTransactions()
        let expenses = allTx.filter{ $0.type == .expense }
            .reduce(into:[String:Int]()){ $0[DateFormatter.keyFormatter.string(from:$1.date), default:0] += $1.amount }
        let incomes  = allTx.filter{ $0.type == .income }
            .reduce(into:[String:Int]()){ $0[DateFormatter.keyFormatter.string(from:$1.date), default:0] += $1.amount }
        
        let monthData = monthRange
            .map { calendar.date(byAdding:.month, value:$0, to:today)! }
            .sorted()
        
        var runningAvailable = 0
        return monthData.map { date in
            let key    = DateFormatter.keyFormatter.string(from: date)
            let used   = expenses[key] ?? 0
            let earned = incomes[key]  ?? 0
            runningAvailable += earned - used
            
            let monthName = DateFormatter.monthFormatter.string(from: date)
            return MonthBudgetCardType(
                date: date,
                month: "month.\(monthName.lowercased())".localized,
                usedValue: used,
                budgetLimit: budgets[key],
                availableValue: runningAvailable
            )
        }
    }
}
