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
    // 🔒 Save to SecureLocalDataManager for UID-isolated storage
    var budgets = SecureLocalDataManager.shared.loadBudgets()

    // Remove existing budget for this month if it exists
    budgets.removeAll { $0.monthDate == budget.monthDate }

    // Add new budget
    budgets.append(budget)

    // Save back to secure storage
    SecureLocalDataManager.shared.saveBudgets(budgets)

    // Also save to SQLite for backward compatibility during migration
    try db.insertBudget(monthDate: budget.monthDate, amount: budget.amount)
  }

  func update(budget: BudgetModel) throws {
    // 🔒 Update in SecureLocalDataManager
    var budgets = SecureLocalDataManager.shared.loadBudgets()

    if let index = budgets.firstIndex(where: { $0.monthDate == budget.monthDate }) {
      budgets[index] = budget
    } else {
      budgets.append(budget)
    }

    SecureLocalDataManager.shared.saveBudgets(budgets)

    // Also update in SQLite for backward compatibility
    try db.updateBudget(monthDate: budget.monthDate, amount: budget.amount)
  }

  func delete(monthDate: Int) throws {
    // 🔒 Delete from SecureLocalDataManager
    var budgets = SecureLocalDataManager.shared.loadBudgets()
    budgets.removeAll { $0.monthDate == monthDate }
    SecureLocalDataManager.shared.saveBudgets(budgets)

    // Also delete from SQLite
    try db.deleteBudget(monthDate: monthDate)
  }

  func fetchBudgets() -> [BudgetModel] {
    // 🔒 Use SecureLocalDataManager for UID-isolated data access ONLY
    let secureBudgets = SecureLocalDataManager.shared.loadBudgets()

    // NO fallback to SQLite - each user should only see their own data
    return secureBudgets
  }

  func exists(monthDate: Int) -> Bool {
    let budgets = fetchBudgets()
    return budgets.contains { $0.monthDate == monthDate }
  }
}
