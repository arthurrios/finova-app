//
//  BudgetsViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation

final class BudgetsViewModel {
    let budgetRepo: BudgetRepository
    let selectedDate: Date?
    
    enum BudgetError: Error {
        case invalidDateFormat
        case budgetAlreadyExists
    }
    
    init(budgetRepo: BudgetRepository = BudgetRepository(), initialDate: Date? = nil) {
        self.budgetRepo = budgetRepo
        selectedDate = initialDate
    }
    
    /// What comes in during a month: the amount a budget is suggested to match. Card rows are left
    /// out because a card refund is not money received, the same rule the ledger uses for cash.
    static func monthlyIncome(of transactions: [Transaction], monthAnchor: Int) -> Int {
        transactions
            .filter { $0.budgetMonthDate == monthAnchor && $0.type == .income && $0.creditCardId == nil }
            .reduce(0) { $0 + $1.amount }
    }

    func suggestedBudget(monthYearDate: String) -> Int {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else { return 0 }
        return Self.monthlyIncome(
            of: TransactionRepository().fetchAllTransactions(), monthAnchor: date.monthAnchor)
    }

    func loadMonthTableViewData() -> [DisplayBudgetModel] {
        return budgetRepo.fetchBudgets().map { entry in
            let date = Date(timeIntervalSince1970: TimeInterval(entry.monthDate))
            return DisplayBudgetModel(date: date, amount: entry.amount)
        }
    }
    
    func addBudget(amount: Int, monthYearDate: String) -> Result<Void, Error> {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else {
            return .failure(BudgetError.invalidDateFormat)
        }
        
        let anchor = date.monthAnchor
        let model = BudgetModel(monthDate: anchor, amount: amount)
        
        do {
            if budgetRepo.exists(monthDate: anchor) {
                return .failure(BudgetError.budgetAlreadyExists)
            } else {
                try budgetRepo.insert(budget: model)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    func forceUpdateBudget(amount: Int, monthYearDate: String) -> Result<Void, Error> {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else {
            return .failure(BudgetError.invalidDateFormat)
        }
        
        let anchor = date.monthAnchor
        let model = BudgetModel(monthDate: anchor, amount: amount)
        
        do {
            try budgetRepo.update(budget: model)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    func deleteBudget(monthYearDate: String) -> Result<Void, Error> {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else {
            return .failure(BudgetError.invalidDateFormat)
        }
        
        let anchor = date.monthAnchor
        
        do {
            try budgetRepo.delete(monthDate: anchor)
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
