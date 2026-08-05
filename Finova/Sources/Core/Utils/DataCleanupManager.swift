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
      logInfo("Global SQLite cleanup already completed")
      return
    }

    logInfo("Starting global SQLite data cleanup...")

    // Clear all global SQLite transactions
    clearGlobalTransactions()

    // Clear all global SQLite budgets
    clearGlobalBudgets()

    // Mark cleanup as completed
    UserDefaults.standard.set(true, forKey: cleanupKey)
    UserDefaults.standard.synchronize()

    logInfo("Global SQLite data cleanup completed")
  }

  /// Clear all transactions from global SQLite database
  private func clearGlobalTransactions() {
    do {
      let allTransactions = try DBHelper.shared.getTransactions()

      if !allTransactions.isEmpty {
        logInfo("Clearing \(allTransactions.count) global transactions from SQLite...")

        // Use batch delete for better performance
        try DBHelper.shared.deleteAllTransactions()

        // The rows these exclusions point at are gone, and a later series handed a reused parent id
        // would inherit them — suppressing occurrences the user never deleted.
        RecurringTransactionManager.clearAllDeletedInstanceTracking()

        logInfo("Global transactions cleared from SQLite")
      }
    } catch {
      logError("Failed to clear global transactions: \(error)")
    }
  }

  /// Clear all budgets from global SQLite database
  private func clearGlobalBudgets() {
    do {
      let allBudgets = try DBHelper.shared.getBudgets()

      if !allBudgets.isEmpty {
        logInfo("Clearing \(allBudgets.count) global budgets from SQLite...")

        // Use batch delete for better performance
        try DBHelper.shared.deleteAllBudgets()

        logInfo("Global budgets cleared from SQLite")
      }
    } catch {
      logError("Failed to clear global budgets: \(error)")
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
