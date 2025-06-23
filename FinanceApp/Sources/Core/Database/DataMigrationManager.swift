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
    
    // MARK: - Public Migration Interface
    
    /// Checks if migration is needed and performs it if necessary
    func checkAndPerformMigration(for firebaseUID: String, completion: @escaping (Bool) -> Void) {
        print("🔄 DataMigrationManager: Checking migration status for user: \(firebaseUID)")
        
        let migrationKey = "data_migrated_to_firebase_\(firebaseUID)"
        
        // Check if migration already completed for this user
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("✅ Migration already completed for this user")
            completion(true)
            return
        }
        
        // Check if there's existing data to migrate
        let hasExistingData = checkForExistingData()
        
        if !hasExistingData {
            print("ℹ️ No existing data found to migrate - marking as migrated")
            UserDefaults.standard.set(true, forKey: migrationKey)
            completion(true)
            return
        }
        
        print("📦 Existing data found - performing migration...")
        performMigration(for: firebaseUID, completion: completion)
    }
    
    /// Forces a migration regardless of previous status (for testing/debugging)
    func forceMigration(for firebaseUID: String, completion: @escaping (Bool) -> Void) {
        print("🔄 DataMigrationManager: Force migration for user: \(firebaseUID)")
        performMigration(for: firebaseUID, completion: completion)
    }
    
    /// Verifies that migration was successful
    func verifyMigration(for firebaseUID: String) -> MigrationVerificationResult {
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
        return SecureLocalDataManager.shared.verifyMigration()
    }
    
    // MARK: - Private Methods
    
    private func checkForExistingData() -> Bool {
        // Check for existing transactions in SQLite
        let transactionRepo = TransactionRepository()
        let existingTransactions = transactionRepo.fetchAllTransactions()
        
        // Check for existing budgets in SQLite
        let budgetRepo = BudgetRepository()
        let existingBudgets = budgetRepo.fetchBudgets()
        
        // Check for existing user profile data
        let hasProfileImage = UserDefaultsManager.loadProfileImage() != nil
        let currentMonthIndex = UserDefaultsManager.getCurrentMonthIndex()
        
        let hasData =
        !existingTransactions.isEmpty || !existingBudgets.isEmpty || hasProfileImage
        || currentMonthIndex != 0
        
        print("🔍 Existing data check:")
        print("   Transactions: \(existingTransactions.count)")
        print("   Budgets: \(existingBudgets.count)")
        print("   Profile Image: \(hasProfileImage)")
        print("   Month Index: \(currentMonthIndex)")
        print("   Has Data: \(hasData)")
        
        return hasData
    }
    
    private func performMigration(for firebaseUID: String, completion: @escaping (Bool) -> Void) {
        // Use SecureLocalDataManager to perform the actual migration
        SecureLocalDataManager.shared.migrateOldDataToUser(firebaseUID: firebaseUID) {
            [weak self] success in
            if success {
                print("✅ DataMigrationManager: Migration completed successfully")
                
                // Verify migration
                let verification = self?.verifyMigration(for: firebaseUID)
                print("🔍 Migration verification: \(verification?.isComplete == true ? "PASSED" : "FAILED")")
                
                completion(success)
            } else {
                print("❌ DataMigrationManager: Migration failed")
                completion(false)
            }
        }
    }
    
    // MARK: - Migration Statistics
    
    func getMigrationStatistics(for firebaseUID: String) -> MigrationStatistics {
        // Get original data counts
        let transactionRepo = TransactionRepository()
        let budgetRepo = BudgetRepository()
        
        let originalTransactionCount = transactionRepo.fetchAllTransactions().count
        let originalBudgetCount = budgetRepo.fetchBudgets().count
        
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
            && originalBudgetCount == migratedBudgetCount
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
    
    var summary: String {
        return """
      Migration Statistics:
      • Transactions: \(migratedTransactionCount)/\(originalTransactionCount) migrated
      • Budgets: \(migratedBudgetCount)/\(originalBudgetCount) migrated
      • Status: \(migrationComplete ? "✅ Complete" : "⚠️ Incomplete")
      """
    }
}
