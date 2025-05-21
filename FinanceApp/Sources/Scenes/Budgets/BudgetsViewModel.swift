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
}
