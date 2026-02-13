//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
  private let db = DBHelper.shared

  func insert(budget: BudgetModel) throws {
    try db.insertBudget(monthDate: budget.monthDate, amount: budget.amount)
  }

  func update(budget: BudgetModel) throws {
    try db.updateBudget(monthDate: budget.monthDate, amount: budget.amount)
  }

  func delete(monthDate: Int) throws {
    try db.deleteBudget(monthDate: monthDate)
  }

  func fetchBudgets() -> [BudgetModel] {
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      return (try? db.getBudgets(forUser: uid)) ?? []
    }
    return (try? db.getBudgets()) ?? []
  }

  func exists(monthDate: Int) -> Bool {
    let budgets = fetchBudgets()
    return budgets.contains { $0.monthDate == monthDate }
  }

  // MARK: - Group Queries

  func fetchBudgetsForGroup(groupId: String) -> [BudgetModel] {
    do {
      return try db.fetchBudgetsForGroup(groupId: groupId)
    } catch {
      logError("Failed to fetch budgets for group: \(error)")
      return []
    }
  }
}
