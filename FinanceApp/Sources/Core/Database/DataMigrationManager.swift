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
    print(
      "🔄 DataMigrationManager: Checking migration status for user: \(firebaseUID) with email: \(userEmail)"
    )

    // Check if global migration has already been performed
    if UserDefaults.standard.bool(forKey: globalMigrationKey) {
      let existingOwner = UserDefaults.standard.string(forKey: migratedDataOwnerKey) ?? "unknown"

      if existingOwner == firebaseUID {
        print("✅ This user (\(firebaseUID)) already owns the migrated data")
      } else {
        print("ℹ️ Local data already migrated to different user (\(existingOwner))")
        print("ℹ️ User \(firebaseUID) will start with empty account (privacy protection)")
      }

      completion(true)
      return
    }

    // Check if there's existing local data to migrate
    let hasExistingData = checkForExistingData()

    if !hasExistingData {
      print("ℹ️ No existing local data found - marking global migration as complete")
      markGlobalMigrationComplete(for: firebaseUID)
      completion(true)
      return
    }

    print("📦 Existing local data found - performing one-time migration to first Firebase user...")
    performFirstUserMigration(for: firebaseUID, userEmail: userEmail, completion: completion)
  }

  /// Forces a migration regardless of previous status (for testing/debugging)
  func forceMigration(
    for firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    print(
      "🔄 DataMigrationManager: Force migration for user: \(firebaseUID) with email: \(userEmail)")
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
    let hasProfileImage = UserDefaultsManager.loadProfileImage() != nil
    let currentMonthIndex = UserDefaultsManager.getCurrentMonthIndex()

    let hasData =
      !existingTransactions.isEmpty || !existingBudgets.isEmpty || hasProfileImage
      || currentMonthIndex != 0

    print("🔍 Existing local data check (SQLite direct):")
    print("   Transactions: \(existingTransactions.count)")
    print("   Budgets: \(existingBudgets.count)")
    print("   Profile Image: \(hasProfileImage)")
    print("   Month Index: \(currentMonthIndex)")
    print("   Has Data: \(hasData)")

    return hasData
  }

  private func performFirstUserMigration(
    for firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    print("🎯 Performing first-user migration for: \(firebaseUID) with email: \(userEmail)")

    performMigration(for: firebaseUID, userEmail: userEmail) { [weak self] success in
      if success {
        print("✅ First-user migration completed successfully")
        self?.markGlobalMigrationComplete(for: firebaseUID)
      } else {
        print("❌ First-user migration failed")
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
    ) {
      [weak self] success in
      if success {
        print("✅ DataMigrationManager: Migration completed successfully")

        // Verify migration
        let verification = self?.verifyMigration(for: firebaseUID)
        print("🔍 Migration verification: \(verification?.isComplete == true ? "PASSED" : "FAILED")")
      } else {
        print("❌ DataMigrationManager: Migration failed")
      }
      completion(success)
    }
  }

  private func markGlobalMigrationComplete(for firebaseUID: String) {
    UserDefaults.standard.set(true, forKey: globalMigrationKey)
    UserDefaults.standard.set(firebaseUID, forKey: migratedDataOwnerKey)
    print("🔒 Global migration marked complete for owner: \(firebaseUID)")
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
    print("🔄 Resetting migration state (testing only)")
    UserDefaults.standard.removeObject(forKey: globalMigrationKey)
    UserDefaults.standard.removeObject(forKey: migratedDataOwnerKey)
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
      print("❌ Invalid confirmation string for data deletion")
      return false
    }

    print("🗑️ Clearing old data after migration...")

    // This would clear the SQLite database and UserDefaults
    // For now, we'll just log what would be cleared
    print("⚠️ Old data cleanup not yet implemented for safety")
    print("   Would clear: SQLite transactions, budgets, UserDefaults profile data")

    return false  // Return false until actual implementation
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
      • Transactions: \(migratedTransactionCount)/\(originalTransactionCount) migrated
      • Budgets: \(migratedBudgetCount)/\(originalBudgetCount) migrated
      • Status: \(migrationComplete ? "✅ Complete" : "⚠️ Incomplete")
      • Data Owner: \(isDataOwner ? "✅ Yes" : "❌ No")
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
      • Global Migration Complete: \(isGlobalMigrationComplete ? "✅ Yes" : "❌ No")
      • Data Owner: \(dataOwner ?? "None")
      • Has Existing Data: \(hasExistingData ? "✅ Yes" : "❌ No")
      """
  }
}
