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
    
    let followIncome: BudgetFollowsIncomeService

    init(
        budgetRepo: BudgetRepository = BudgetRepository(), initialDate: Date? = nil,
        followIncome: BudgetFollowsIncomeService = .shared
    ) {
        self.budgetRepo = budgetRepo
        selectedDate = initialDate
        self.followIncome = followIncome
    }

    /// The note under a month in the list: its percent of income, or the hint when it has none.
    func note(forMonth anchor: Int, amount: Int) -> String? {
        guard followIncome.follows(month: anchor) else { return nil }
        if amount == 0 { return "budgets.followIncome.noIncome".localized }
        return String(format: "budgets.followIncome.rowNote".localized, followIncome.settings.percent)
    }

    /// A budget typed by hand while the switch is on keeps that month fixed.
    func keepFixed(months: [Int]) {
        months.forEach { followIncome.optOut(month: $0) }
    }

    static func monthAnchor(of monthYearDate: String) -> Int? {
        DateFormatter.monthYearFormatter.date(from: monthYearDate)?.monthAnchor
    }
    
    /// What comes in during a month: the amount a budget is suggested to match. Card rows are left
    /// out because a card refund is not money received. Callers pass rows without the early-paid
    /// installments, as the ledger does, so this cannot disagree with the month the user sees.
    static func monthlyIncome(of transactions: [Transaction], monthAnchor: Int) -> Int {
        transactions
            .filter { $0.budgetMonthDate == monthAnchor && $0.type == .income && $0.creditCardId == nil }
            .reduce(0) { $0 + $1.amount }
    }

    func suggestedBudget(monthYearDate: String) -> Int {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else { return 0 }
        return Self.monthlyIncome(
            of: TransactionRepository().fetchAllTransactions().excludingEarlyPaidInstallments(),
            monthAnchor: date.monthAnchor)
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
    
    // MARK: - Many months at once

    /// Month anchors from `start` through `end`, both included, one per calendar month. Empty when
    /// `end` is before `start`.
    static func monthAnchors(from start: Int, through end: Int) -> [Int] {
        guard end >= start else { return [] }
        let cal = Calendar.current
        let startDate = Date(timeIntervalSince1970: TimeInterval(start))
        var anchors: [Int] = []
        var offset = 0
        while let date = cal.date(byAdding: .month, value: offset, to: startDate) {
            let anchor = date.monthAnchor
            if anchor > end { break }
            anchors.append(anchor)
            offset += 1
        }
        return anchors
    }

    /// The month anchor `count` months after `start` (0 is `start` itself).
    static func monthAnchor(_ start: Int, plusMonths count: Int) -> Int {
        let startDate = Date(timeIntervalSince1970: TimeInterval(start))
        return Calendar.current.date(byAdding: .month, value: count, to: startDate)?.monthAnchor ?? start
    }

    /// The months in the range that already hold a budget, in calendar order.
    func existingBudgetMonths(monthYearDate: String, endMonth: Int) -> [Int] {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else { return [] }
        let taken = Set(budgetRepo.fetchBudgets().map(\.monthDate))
        return Self.monthAnchors(from: date.monthAnchor, through: endMonth).filter(taken.contains)
    }

    /// Writes `amount` to every month from the typed month through `endMonth`, all or nothing.
    /// `replaceExisting` false keeps the months that already have a budget.
    func addBudgets(
        amount: Int, monthYearDate: String, endMonth: Int, replaceExisting: Bool
    ) -> Result<[Int], Error> {
        guard let date = DateFormatter.monthYearFormatter.date(from: monthYearDate) else {
            return .failure(BudgetError.invalidDateFormat)
        }
        let months = Self.monthAnchors(from: date.monthAnchor, through: endMonth)
        do {
            let written = try budgetRepo.upsertBudgets(
                monthDates: months, amount: amount, replaceExisting: replaceExisting)
            return .success(written)
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
