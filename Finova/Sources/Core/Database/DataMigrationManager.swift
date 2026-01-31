//
//  DataMigrationManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 25/06/25.
//

import Foundation

class DataMigrationManager {
  static let shared = DataMigrationManager()
  private init() {}

  // MARK: - Migration Keys

  /// Global key to track if local data has been migrated to any Firebase user
  private let globalMigrationKey = "global_local_data_migrated_to_firebase"

  /// Key to track which Firebase user owns the migrated local data
  private let migratedDataOwnerKey = "migrated_local_data_owner_uid"

  // MARK: - Public Migration Interface

  /// Checks if migration is needed and performs it if necessary
  /// This implements one-time global migration to prevent data privacy violations
  func checkAndPerformMigration(
    for firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {

    // Check if global migration has already been performed
    if UserDefaults.standard.bool(forKey: globalMigrationKey) {
      completion(true)
      return
    }

    // Check if there's existing local data to migrate
    let hasExistingData = checkForExistingData()

    if !hasExistingData {
      markGlobalMigrationComplete(for: firebaseUID)
      completion(true)
      return
    }

    performFirstUserMigration(for: firebaseUID, userEmail: userEmail, completion: completion)
  }

  /// Forces a migration regardless of previous status (for testing/debugging)
  func forceMigration(
    for firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    performMigration(for: firebaseUID, userEmail: userEmail, completion: completion)
  }

  /// Verifies that migration was successful
  func verifyMigration(for firebaseUID: String) -> MigrationVerificationResult {
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
    return SecureLocalDataManager.shared.verifyMigration()
  }

  /// Checks if a specific user owns the migrated data
  func doesUserOwnMigratedData(firebaseUID: String) -> Bool {
    guard UserDefaults.standard.bool(forKey: globalMigrationKey) else {
      return false  // No migration has occurred yet
    }

    let owner = UserDefaults.standard.string(forKey: migratedDataOwnerKey)
    return owner == firebaseUID
  }

  /// Gets the owner of migrated data (if any)
  func getMigratedDataOwner() -> String? {
    guard UserDefaults.standard.bool(forKey: globalMigrationKey) else {
      return nil
    }
    return UserDefaults.standard.string(forKey: migratedDataOwnerKey)
  }

  // MARK: - Private Methods

  private func checkForExistingData() -> Bool {
    // Check for existing transactions in SQLite DIRECTLY (not through repositories)
    let existingTransactions = (try? DBHelper.shared.getTransactions()) ?? []

    // Check for existing budgets in SQLite DIRECTLY (not through repositories)
    let existingBudgets = (try? DBHelper.shared.getBudgets()) ?? []

    // Check for existing user profile data
    let hasProfileImage = ProfileImageCleanup.shared.loadGlobalProfileImageIfExists() != nil
    let currentMonthIndex = UserDefaultsManager.getCurrentMonthIndex()

    let hasData =
      !existingTransactions.isEmpty || !existingBudgets.isEmpty || hasProfileImage
      || currentMonthIndex != 0

    return hasData
  }

  private func performFirstUserMigration(
    for firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    performMigration(for: firebaseUID, userEmail: userEmail) { [weak self] success in
      if success {
        self?.markGlobalMigrationComplete(for: firebaseUID)
      }
      completion(success)
    }
  }

  private func performMigration(
    for firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    // Use SecureLocalDataManager to perform the actual migration
    SecureLocalDataManager.shared.migrateOldDataToUser(
      firebaseUID: firebaseUID, userEmail: userEmail
    ) { [weak self] success in
      if success {
        // Verify migration
        _ = self?.verifyMigration(for: firebaseUID)
      }
      completion(success)
    }
  }

  private func markGlobalMigrationComplete(for firebaseUID: String) {
    UserDefaults.standard.set(true, forKey: globalMigrationKey)
    UserDefaults.standard.set(firebaseUID, forKey: migratedDataOwnerKey)
  }

  // MARK: - Migration Statistics

  func getMigrationStatistics(for firebaseUID: String) -> MigrationStatistics {
    // Get original data counts from SQLite DIRECTLY
    let originalTransactionCount = (try? DBHelper.shared.getTransactions())?.count ?? 0
    let originalBudgetCount = (try? DBHelper.shared.getBudgets())?.count ?? 0

    // Get migrated data counts
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
    let migratedTransactionCount = SecureLocalDataManager.shared.loadTransactions().count
    let migratedBudgetCount = SecureLocalDataManager.shared.loadBudgets().count

    return MigrationStatistics(
      originalTransactionCount: originalTransactionCount,
      migratedTransactionCount: migratedTransactionCount,
      originalBudgetCount: originalBudgetCount,
      migratedBudgetCount: migratedBudgetCount,
      migrationComplete: originalTransactionCount == migratedTransactionCount
        && originalBudgetCount == migratedBudgetCount,
      isDataOwner: doesUserOwnMigratedData(firebaseUID: firebaseUID)
    )
  }

  // MARK: - Testing & Debugging Methods

  /// Resets migration state (for testing purposes only)
  func resetMigrationState() {
    UserDefaults.standard.removeObject(forKey: globalMigrationKey)
    UserDefaults.standard.removeObject(forKey: migratedDataOwnerKey)
  }
  
  /// Reset migration state for current user only
  func resetCurrentUserMigrationState() {
    // Get current user from SecureLocalDataManager
    guard let currentUID = SecureLocalDataManager.shared.getCurrentUserUID() else {
      logError("Cannot reset migration state: No authenticated user")
      return
    }

    // Reset migration flags for current user only
    // Do not affect other users' migration states
    UserDefaults.standard.removeObject(forKey: "migration_completed_\(currentUID)")

    // Only reset global migration if current user is the data owner
    let currentDataOwner = UserDefaults.standard.string(forKey: migratedDataOwnerKey)
    if currentDataOwner == currentUID {
      UserDefaults.standard.removeObject(forKey: globalMigrationKey)
      UserDefaults.standard.removeObject(forKey: migratedDataOwnerKey)
    }
  }

  /// Gets current migration state for debugging
  func getMigrationState() -> MigrationState {
    let isGlobalMigrationComplete = UserDefaults.standard.bool(forKey: globalMigrationKey)
    let dataOwner = UserDefaults.standard.string(forKey: migratedDataOwnerKey)

    return MigrationState(
      isGlobalMigrationComplete: isGlobalMigrationComplete,
      dataOwner: dataOwner,
      hasExistingData: checkForExistingData()
    )
  }

  // MARK: - Cleanup Methods

  /// Clears old data after successful migration (use with caution!)
  func clearOldDataAfterMigration(confirmation: String) -> Bool {
    guard confirmation == "CONFIRM_DELETE_OLD_DATA" else {
      return false
    }

    // This would clear the SQLite database and UserDefaults
    // Not yet implemented for safety
    return false
  }
}

// MARK: - Supporting Data Models

struct MigrationStatistics {
  let originalTransactionCount: Int
  let migratedTransactionCount: Int
  let originalBudgetCount: Int
  let migratedBudgetCount: Int
  let migrationComplete: Bool
  let isDataOwner: Bool

  var summary: String {
    return """
      Migration Statistics:
      - Transactions: \(migratedTransactionCount)/\(originalTransactionCount) migrated
      - Budgets: \(migratedBudgetCount)/\(originalBudgetCount) migrated
      - Status: \(migrationComplete ? "Complete" : "Incomplete")
      - Data Owner: \(isDataOwner ? "Yes" : "No")
      """
  }
}

struct MigrationState {
  let isGlobalMigrationComplete: Bool
  let dataOwner: String?
  let hasExistingData: Bool

  var summary: String {
    return """
      Migration State:
      - Global Migration Complete: \(isGlobalMigrationComplete ? "Yes" : "No")
      - Data Owner: \(dataOwner ?? "None")
      - Has Existing Data: \(hasExistingData ? "Yes" : "No")
      """
  }
}
