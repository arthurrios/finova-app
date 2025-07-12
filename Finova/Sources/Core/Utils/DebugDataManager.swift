//
//  DebugDataManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 25/06/25.
//

import Foundation

#if DEBUG
  /// Debug utility to help test and cleanup data isolation issues
  class DebugDataManager {

    static let shared = DebugDataManager()

    private init() {}

    /// Force cleanup all global SQLite data (for testing)
    func forceCleanupGlobalData() {
      print("🧪 DEBUG: Force cleaning up all global SQLite data...")

      DataCleanupManager.shared.forceCleanup()

      // Also reset migration state
      DataMigrationManager.shared.resetMigrationState()

      print("✅ DEBUG: Global data cleanup completed")
    }

    /// Show current data status for debugging
    func showDataStatus() {
      print("🔍 DEBUG: Current Data Status")
      print("=" * 50)

      // Check SQLite data
      let sqliteTransactions = (try? DBHelper.shared.getTransactions()) ?? []
      let sqliteBudgets = (try? DBHelper.shared.getBudgets()) ?? []

      print("📊 SQLite Data:")
      print("   Transactions: \(sqliteTransactions.count)")
      print("   Budgets: \(sqliteBudgets.count)")

      // Check if user is authenticated
      if let user = UserDefaultsManager.getUser() {
        print("👤 Current User: \(user.name) (\(user.firebaseUID ?? "no UID"))")

        if let uid = user.firebaseUID {
          SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
          let secureTransactions = SecureLocalDataManager.shared.loadTransactions()
          let secureBudgets = SecureLocalDataManager.shared.loadBudgets()

          print("🔒 Secure Data for \(uid):")
          print("   Transactions: \(secureTransactions.count)")
          print("   Budgets: \(secureBudgets.count)")
        }
      } else {
        print("❌ No user logged in")
      }

      // Check migration status
      let migrationState = DataMigrationManager.shared.getMigrationState()
      print("🔄 Migration Status:")
      print("   Global Migration Complete: \(migrationState.isGlobalMigrationComplete)")
      print("   Data Owner: \(migrationState.dataOwner ?? "none")")
      print("   Has Existing Data: \(migrationState.hasExistingData)")

      // Check cleanup status
      let cleanupCompleted = DataCleanupManager.shared.isCleanupCompleted()
      print("🧹 Cleanup Status:")
      print("   Global Cleanup Completed: \(cleanupCompleted)")

      print("=" * 50)
    }

    /// Reset everything for clean testing
    func resetEverything() {
      print("🧪 DEBUG: Resetting everything for clean testing...")

      // Force cleanup global data
      forceCleanupGlobalData()

      // Clear user data
      UserDefaultsManager.removeUser()

      // Sign out from auth systems
      AuthenticationManager.shared.signOut()
      SecureLocalDataManager.shared.signOut()

      print("✅ DEBUG: Everything reset - ready for clean testing")
    }
  }

  // Helper extension for string repetition
  extension String {
    static func * (string: String, count: Int) -> String {
      return String(repeating: string, count: count)
    }
  }
#endif
