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
      logDebug("DEBUG: Force cleaning up all global SQLite data...")

      DataCleanupManager.shared.forceCleanup()

      // Also reset migration state
      DataMigrationManager.shared.resetMigrationState()

      logInfo("DEBUG: Global data cleanup completed")
    }

    /// Show current data status for debugging
    func showDataStatus() {
      logDebug("DEBUG: Current Data Status")
      logDebug("=" * 50)

      // Check SQLite data
      let sqliteTransactions = (try? DBHelper.shared.getTransactions()) ?? []
      let sqliteBudgets = (try? DBHelper.shared.getBudgets()) ?? []

      logDebug("SQLite Data:")
      logDebug("   Transactions: \(sqliteTransactions.count)")
      logDebug("   Budgets: \(sqliteBudgets.count)")

      // Check if user is authenticated
      if let user = UserDefaultsManager.getUser() {
        logDebug("Current User: \(user.name) (\(user.firebaseUID ?? "no UID"))")

        if let uid = user.firebaseUID {
          SecureLocalDataManager.shared.authenticateUser(firebaseUID: uid)
          let secureTransactions = SecureLocalDataManager.shared.loadTransactions()
          let secureBudgets = SecureLocalDataManager.shared.loadBudgets()

          logDebug("Secure Data for \(uid):")
          logDebug("   Transactions: \(secureTransactions.count)")
          logDebug("   Budgets: \(secureBudgets.count)")
        }
      } else {
        logWarning("No user logged in")
      }

      // Check migration status
      let migrationState = DataMigrationManager.shared.getMigrationState()
      logDebug("Migration Status:")
      logDebug("   Global Migration Complete: \(migrationState.isGlobalMigrationComplete)")
      logDebug("   Data Owner: \(migrationState.dataOwner ?? "none")")
      logDebug("   Has Existing Data: \(migrationState.hasExistingData)")

      // Check cleanup status
      let cleanupCompleted = DataCleanupManager.shared.isCleanupCompleted()
      logDebug("Cleanup Status:")
      logDebug("   Global Cleanup Completed: \(cleanupCompleted)")

      logDebug("=" * 50)
    }

    /// Reset everything for clean testing
    func resetEverything() {
      logDebug("DEBUG: Resetting everything for clean testing...")

      // Force cleanup global data
      forceCleanupGlobalData()

      // Clear user data
      UserDefaultsManager.removeUser()

      // Sign out from auth systems
      AuthenticationManager.shared.signOut()
      SecureLocalDataManager.shared.signOut()

      logInfo("DEBUG: Everything reset - ready for clean testing")
    }

    /// Debug notification system comprehensively
    func debugNotificationSystem() {
      NotificationDebugManager.shared.performFullNotificationDebug()
    }

    /// Test notifications immediately
    func testNotificationNow() {
      NotificationDebugManager.shared.scheduleTestNotification()
    }

    /// Force reschedule all notifications
    func forceRescheduleNotifications() {
      NotificationDebugManager.shared.forceRescheduleAllNotifications()
    }
  }

  // Helper extension for string repetition
  extension String {
    static func * (string: String, count: Int) -> String {
      return String(repeating: string, count: count)
    }
  }
#endif
