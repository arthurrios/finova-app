//
//  DataRecoveryToastManager.swift
//  Finova
//
//  Created by Arthur Rios on 13/09/25.
//

import Foundation

protocol DataRecoveryToastManagerDelegate: AnyObject {
  func dataRecoveryToastManager(_ manager: DataRecoveryToastManager, shouldShowToast: Bool)
  func dataRecoveryToastManager(_ manager: DataRecoveryToastManager, didDismissToast: Bool)
}

final class DataRecoveryToastManager {
  static let shared = DataRecoveryToastManager()

  weak var delegate: DataRecoveryToastManagerDelegate?

  // MARK: - UserDefaults Keys
  private let recoveryToastDismissedKey = "recoveryToastDismissed"
  private let lastRecoveryToastDismissedKey = "lastRecoveryToastDismissed"
  private let dataRecoveryCompletedKey = "dataRecoveryCompleted"

  private init() {}

  // MARK: - Public Methods

  /// Check if recovery toast should be shown
  func shouldShowRecoveryToast() -> Bool {
    // Don't show if recovery was already completed
    if UserDefaults.standard.bool(forKey: dataRecoveryCompletedKey) {
      print("📱 Recovery already completed - not showing toast")
      return false
    }

    // Don't show if user permanently dismissed the toast
    if UserDefaults.standard.bool(forKey: recoveryToastDismissedKey) {
      print("📱 Recovery toast permanently dismissed")
      return false
    }

    // Check if we have a currently authenticated user
    guard let currentUser = AuthenticationManager.shared.currentUser else {
      print("📱 No authenticated user - not showing recovery toast")
      return false
    }

    // Check if this user might need data recovery
    let migrationKey = "data_migrated_to_firebase_\(currentUser.uid)"
    let emergencyKey = "emergency_recovery_attempted_\(currentUser.uid)"

    // If migration was never completed or failed, might need recovery
    let migrationCompleted = UserDefaults.standard.bool(forKey: migrationKey)
    let emergencyAttempted = UserDefaults.standard.bool(forKey: emergencyKey)

    if !migrationCompleted && !emergencyAttempted {
      // Check if there's actually data to recover (SQLite has data)
      let hasExistingData = checkForExistingDataInSQLite()
      if hasExistingData {
        print("📱 User has SQLite data but migration not completed - showing recovery toast")
        return true
      }
    }

    // Check if user dismissed recently (show again after 24 hours)
    if let lastDismissedDate = UserDefaults.standard.object(forKey: lastRecoveryToastDismissedKey)
      as? Date
    {
      let hoursSinceDismissal = Date().timeIntervalSince(lastDismissedDate) / 3600
      if hoursSinceDismissal < 24 {
        let hoursRemaining = 24 - hoursSinceDismissal
        print(
          "📱 Recovery toast dismissed recently. Remaining time: \(String(format: "%.1f", hoursRemaining)) hours"
        )
        return false
      } else {
        print("📱 24 hours have passed since dismissal. Showing reminder toast")
        return true
      }
    }

    print("📱 Recovery toast conditions not met")
    return false
  }

  /// Check if there's data in SQLite that could be recovered
  private func checkForExistingDataInSQLite() -> Bool {
    do {
      let transactions = try DBHelper.shared.getTransactions()
      let budgets = try DBHelper.shared.getBudgets()

      let hasData = !transactions.isEmpty || !budgets.isEmpty
      print(
        "📱 SQLite data check: \(transactions.count) transactions, \(budgets.count) budgets - hasData: \(hasData)"
      )
      return hasData
    } catch {
      print("📱 Error checking SQLite data: \(error)")
      return false
    }
  }

  /// Mark toast as dismissed temporarily (24 hours)
  func markToastAsDismissedTemporarily() {
    UserDefaults.standard.set(Date(), forKey: lastRecoveryToastDismissedKey)
    print("📱 Recovery toast dismissed temporarily")
  }

  /// Mark toast as permanently dismissed
  func markToastAsPermanentlyDismissed() {
    UserDefaults.standard.set(true, forKey: recoveryToastDismissedKey)
    UserDefaults.standard.set(Date(), forKey: lastRecoveryToastDismissedKey)
    print("📱 Recovery toast permanently dismissed")
  }

  /// Mark data recovery as completed (prevents toast from showing again)
  func markDataRecoveryAsCompleted() {
    UserDefaults.standard.set(true, forKey: dataRecoveryCompletedKey)
    print("📱 Data recovery marked as completed")
  }

  /// Reset recovery state (for testing/debugging)
  func resetRecoveryState() {
    UserDefaults.standard.removeObject(forKey: recoveryToastDismissedKey)
    UserDefaults.standard.removeObject(forKey: lastRecoveryToastDismissedKey)
    UserDefaults.standard.removeObject(forKey: dataRecoveryCompletedKey)
    print("📱 Recovery toast state reset")
  }

  /// Trigger recovery process
  func performDataRecovery(completion: @escaping (Bool, String) -> Void) {
    guard let currentUser = AuthenticationManager.shared.currentUser else {
      completion(false, "No authenticated user found")
      return
    }

    print("🚨 TOAST RECOVERY: Starting data recovery for \(currentUser.uid)")

    // Clear migration flags to force re-attempt
    let migrationKey = "data_migrated_to_firebase_\(currentUser.uid)"
    let emergencyKey = "emergency_recovery_attempted_\(currentUser.uid)"
    let globalMigrationKey = "global_local_data_migrated_to_firebase"

    UserDefaults.standard.removeObject(forKey: migrationKey)
    UserDefaults.standard.removeObject(forKey: emergencyKey)
    UserDefaults.standard.removeObject(forKey: globalMigrationKey)

    // Clear ownership restrictions
    UserDefaults.standard.removeObject(forKey: "data_owner_uid")
    UserDefaults.standard.removeObject(forKey: "data_owner_email")
    UserDefaults.standard.removeObject(forKey: "device_users")

    // Attempt migration
    SecureLocalDataManager.shared.migrateOldDataToUser(
      firebaseUID: currentUser.uid,
      userEmail: currentUser.email ?? ""
    ) { [weak self] success in
      DispatchQueue.main.async {
        if success {
          print("✅ TOAST RECOVERY: Data recovery successful!")
          self?.markDataRecoveryAsCompleted()
          completion(
            true, "Data recovery successful! Your transactions and budgets have been restored.")
        } else {
          print("❌ TOAST RECOVERY: Data recovery failed")
          completion(false, "Data recovery failed. Please try again or contact support.")
        }
      }
    }
  }
}
