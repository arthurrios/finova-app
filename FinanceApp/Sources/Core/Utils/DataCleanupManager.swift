//
//  DataCleanupManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 25/06/25.
//

import Foundation

/// Utility to clean up global SQLite data and ensure proper UID-based isolation
class DataCleanupManager {

  static let shared = DataCleanupManager()

  private init() {}

  /// One-time cleanup to remove global SQLite data after UID-based migration
  /// This should be called during app startup to ensure data isolation
  func performGlobalDataCleanup() {
    let cleanupKey = "global_sqlite_cleanup_completed"

    // Check if cleanup already performed
    if UserDefaults.standard.bool(forKey: cleanupKey) {
      print("✅ Global SQLite cleanup already completed")
      return
    }

    print("🧹 Starting global SQLite data cleanup...")

    // Clear all global SQLite transactions
    clearGlobalTransactions()

    // Clear all global SQLite budgets
    clearGlobalBudgets()

    // Mark cleanup as completed
    UserDefaults.standard.set(true, forKey: cleanupKey)
    UserDefaults.standard.synchronize()

    print("✅ Global SQLite data cleanup completed")
  }

  /// Clear all transactions from global SQLite database
  private func clearGlobalTransactions() {
    do {
      let transactionRepo = TransactionRepository()
      let allTransactions = try DBHelper.shared.getTransactions()

      print("🗑️ Clearing \(allTransactions.count) global transactions from SQLite...")

      for transaction in allTransactions {
        if let id = transaction.id {
          try DBHelper.shared.deleteTransaction(id: id)
        }
      }

      print("✅ Global transactions cleared from SQLite")
    } catch {
      print("❌ Failed to clear global transactions: \(error)")
    }
  }

  /// Clear all budgets from global SQLite database
  private func clearGlobalBudgets() {
    do {
      let allBudgets = try DBHelper.shared.getBudgets()

      print("🗑️ Clearing \(allBudgets.count) global budgets from SQLite...")

      for budget in allBudgets {
        try DBHelper.shared.deleteBudget(monthDate: budget.monthDate)
      }

      print("✅ Global budgets cleared from SQLite")
    } catch {
      print("❌ Failed to clear global budgets: \(error)")
    }
  }

  /// Force cleanup (for testing or manual cleanup)
  func forceCleanup() {
    UserDefaults.standard.removeObject(forKey: "global_sqlite_cleanup_completed")
    performGlobalDataCleanup()
  }

  /// Check if cleanup has been performed
  func isCleanupCompleted() -> Bool {
    return UserDefaults.standard.bool(forKey: "global_sqlite_cleanup_completed")
  }
}
