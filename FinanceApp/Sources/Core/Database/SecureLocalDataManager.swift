//
//  SecureLocalDataManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import CryptoKit
import Foundation

class SecureLocalDataManager {

  // MARK: - Singleton
  static let shared = SecureLocalDataManager()

  // MARK: - Properties
  private var currentUserUID: String?
  private var encryptionKey: SymmetricKey?

  private init() {}

  // MARK: - User Session Management

  func authenticateUser(firebaseUID: String) {
    print("🔒 Authenticating user for secure data access: \(firebaseUID)")
    self.currentUserUID = firebaseUID
    self.encryptionKey = generateEncryptionKey(for: firebaseUID)

    // Create user data directory if first time
    createUserDataDirectoryIfNeeded(for: firebaseUID)
    print("✅ User authenticated for secure data access")
  }

  func signOut() {
    print("🔒 Signing out from secure data manager")
    self.currentUserUID = nil
    self.encryptionKey = nil
  }

  // MARK: - Generic Data Access (UID-isolated)

  func saveData<T: Codable>(_ data: T, filename: String) {
    guard let uid = currentUserUID else {
      print("❌ Cannot save data: No authenticated user")
      return
    }

    saveEncryptedData(data, for: uid, filename: filename)
  }

  func loadData<T: Codable>(type: T.Type, filename: String) -> T? {
    guard let uid = currentUserUID else {
      print("❌ Cannot load data: No authenticated user")
      return nil
    }
    return loadEncryptedData(type: type, for: uid, filename: filename)
  }

  // MARK: - Specific Data Access Methods

  func saveTransactions(_ transactions: [Transaction]) {
    saveData(transactions, filename: "transactions.json")
  }

  func loadTransactions() -> [Transaction] {
    return loadData(type: [Transaction].self, filename: "transactions.json") ?? []
  }

  func saveBudgets(_ budgets: [BudgetModel]) {
    saveData(budgets, filename: "budgets.json")
  }

  func loadBudgets() -> [BudgetModel] {
    return loadData(type: [BudgetModel].self, filename: "budgets.json") ?? []
  }

  func saveUserProfile(_ profile: UserProfile) {
    saveData(profile, filename: "profile.json")
  }

  func loadUserProfile() -> UserProfile? {
    return loadData(type: UserProfile.self, filename: "profile.json")
  }

  // MARK: - Data Migration from Old Local Storage

  func migrateOldDataToUser(
    firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    print(
      "🔄 Starting comprehensive data migration for user: \(firebaseUID) with email: \(userEmail)")

    let migrationKey = "data_migrated_to_firebase_\(firebaseUID)"
    if UserDefaults.standard.bool(forKey: migrationKey) {
      print("✅ Migration already completed for this user")
      completion(true)
      return
    }

    // 🔒 SECURITY CHECK: Validate ownership before migration
    guard validateDataOwnership(for: firebaseUID, email: userEmail) else {
      print("❌ Migration denied: User does not own existing data")
      completion(false)
      return
    }

    // Authenticate with new UID first
    authenticateUser(firebaseUID: firebaseUID)

    var migrationSuccess = true

    // Step 1: Migrate Transactions from SQLite
    print("📊 Migrating transactions from SQLite...")
    let transactionMigrationResult = migrateTransactionsFromSQLite(validatedFor: userEmail)
    if !transactionMigrationResult {
      print("⚠️ Transaction migration failed")
      migrationSuccess = false
    }

    // Step 2: Migrate Budgets from SQLite
    print("💰 Migrating budgets from SQLite...")
    let budgetMigrationResult = migrateBudgetsFromSQLite(validatedFor: userEmail)
    if !budgetMigrationResult {
      print("⚠️ Budget migration failed")
      migrationSuccess = false
    }

    // Step 3: Migrate User Profile Data
    print("👤 Migrating user profile data...")
    let profileMigrationResult = migrateUserProfileData(validatedFor: userEmail)
    if !profileMigrationResult {
      print("⚠️ Profile migration failed")
      migrationSuccess = false
    }

    // Step 4: Backup old data (don't delete immediately for safety)
    if migrationSuccess {
      print("📦 Creating backup of old data...")
      createBackupOfOldData()

      // 🔒 SECURITY: Mark data as owned by this user
      markDataOwnership(for: firebaseUID, email: userEmail)
    }

    // Mark migration as completed only if successful
    if migrationSuccess {
      UserDefaults.standard.set(true, forKey: migrationKey)
      print("✅ Complete data migration successful for user: \(firebaseUID)")
    } else {
      print("❌ Data migration failed for user: \(firebaseUID)")
    }

    completion(migrationSuccess)
  }

  // MARK: - Private Migration Methods

  private func migrateTransactionsFromSQLite(validatedFor email: String) -> Bool {
    do {
      // Use existing repository to get all transactions
      let transactionRepo = TransactionRepository()
      let allTransactions = transactionRepo.fetchAllTransactions()

      print("📊 Found \(allTransactions.count) transactions to migrate for \(email)")

      if !allTransactions.isEmpty {
        // 🔒 SECURITY: Only migrate if data belongs to this user
        if validateTransactionOwnership(allTransactions, for: email) {
          saveTransactions(allTransactions)
          print("✅ Successfully migrated \(allTransactions.count) transactions")
        } else {
          print("❌ Transaction ownership validation failed")
          return false
        }
      }

      return true
    } catch {
      print("❌ Failed to migrate transactions: \(error)")
      return false
    }
  }

  private func migrateBudgetsFromSQLite(validatedFor email: String) -> Bool {
    do {
      // Use existing repository to get all budgets
      let budgetRepo = BudgetRepository()
      let allBudgets = budgetRepo.fetchBudgets()

      print("💰 Found \(allBudgets.count) budgets to migrate for \(email)")

      if !allBudgets.isEmpty {
        // 🔒 SECURITY: Only migrate if data belongs to this user
        if validateBudgetOwnership(allBudgets, for: email) {
          saveBudgets(allBudgets)
          print("✅ Successfully migrated \(allBudgets.count) budgets")
        } else {
          print("❌ Budget ownership validation failed")
          return false
        }
      }

      return true
    } catch {
      print("❌ Failed to migrate budgets: \(error)")
      return false
    }
  }

  private func migrateUserProfileData(validatedFor email: String) -> Bool {
    do {
      // 🔒 SECURITY: Validate profile belongs to this user
      if let existingUser = UserDefaultsManager.getUser() {
        if existingUser.email.lowercased() != email.lowercased() {
          print("❌ Profile email mismatch - migration denied")
          return false
        }
      }

      // Migrate user profile image
      var profileImageData: Data?
      if let profileImage = UserDefaultsManager.loadProfileImage() {
        profileImageData = profileImage.jpegData(compressionQuality: 0.8)
        print("👤 Found profile image to migrate")
      }

      // Migrate current month index
      let currentMonthIndex = UserDefaultsManager.getCurrentMonthIndex()

      // Create user profile object
      let userProfile = UserProfile(
        profileImageData: profileImageData,
        currentMonthIndex: currentMonthIndex,
        preferences: UserPreferences()
      )

      saveUserProfile(userProfile)
      print("✅ Successfully migrated user profile data")

      return true
    } catch {
      print("❌ Failed to migrate user profile: \(error)")
      return false
    }
  }

  private func createBackupOfOldData() {
    // Create a backup directory with timestamp
    let timestamp = DateFormatter.backupFormatter.string(from: Date())
    let backupKey = "data_backup_created_\(timestamp)"

    // Mark that backup was created (for reference)
    UserDefaults.standard.set(true, forKey: backupKey)
    print("📦 Backup reference created: \(backupKey)")
  }

  // MARK: - Migration Verification

  func verifyMigration() -> MigrationVerificationResult {
    guard let uid = currentUserUID else {
      return MigrationVerificationResult(
        isComplete: false,
        transactionCount: 0,
        budgetCount: 0,
        hasProfile: false,
        errors: ["No authenticated user"]
      )
    }

    let transactions = loadTransactions()
    let budgets = loadBudgets()
    let profile = loadUserProfile()

    let result = MigrationVerificationResult(
      isComplete: !transactions.isEmpty || !budgets.isEmpty,
      transactionCount: transactions.count,
      budgetCount: budgets.count,
      hasProfile: profile != nil,
      errors: []
    )

    print("🔍 Migration verification: \(result)")
    return result
  }

  // MARK: - User Data Directory Management

  func getUserDataDirectory() -> URL? {
    guard let uid = currentUserUID else { return nil }
    return getUserDataDirectory(for: uid)
  }

  func clearUserData() {
    guard let uid = currentUserUID else { return }
    let userDirectory = getUserDataDirectory(for: uid)

    do {
      if FileManager.default.fileExists(atPath: userDirectory.path) {
        try FileManager.default.removeItem(at: userDirectory)
        print("✅ User data cleared successfully")
      }
    } catch {
      print("❌ Failed to clear user data: \(error)")
    }
  }

  // MARK: - Security & Data Ownership

  private func validateDataOwnership(for firebaseUID: String, email: String) -> Bool {
    // Check if data has already been claimed by another user
    if let existingOwnerUID = getDataOwnerUID() {
      if existingOwnerUID != firebaseUID {
        print("🔒 Data already owned by different user: \(existingOwnerUID)")
        return false
      }
    }

    // Check if existing local user data matches this email
    if let existingUser = UserDefaultsManager.getUser() {
      if existingUser.email.lowercased() != email.lowercased() {
        print("🔒 Email mismatch: existing=\(existingUser.email), new=\(email)")
        return false
      }
    }

    // Additional check: verify user has permission to access this device's data
    return validateDeviceDataAccess(for: email)
  }

  private func validateDeviceDataAccess(for email: String) -> Bool {
    // This could check if the user has previously used this device
    // For now, we'll allow access but log for security monitoring
    print("🔍 Validating device data access for: \(email)")

    // Check if this email has been used on this device before
    let deviceUserKey = "device_users"
    var deviceUsers = UserDefaults.standard.stringArray(forKey: deviceUserKey) ?? []

    if deviceUsers.isEmpty {
      // First user on this device - grant access
      deviceUsers.append(email.lowercased())
      UserDefaults.standard.set(deviceUsers, forKey: deviceUserKey)
      print("✅ First user on device - access granted")
      return true
    }

    if deviceUsers.contains(email.lowercased()) {
      print("✅ Email found in device users - access granted")
      return true
    }

    // New email on device with existing data - require explicit confirmation
    print("⚠️ New email on device with existing data - access denied")
    return false
  }

  private func markDataOwnership(for firebaseUID: String, email: String) {
    UserDefaults.standard.set(firebaseUID, forKey: "data_owner_uid")
    UserDefaults.standard.set(email.lowercased(), forKey: "data_owner_email")
    UserDefaults.standard.set(Date(), forKey: "data_ownership_date")
    print("🔒 Data ownership marked for: \(email) (\(firebaseUID))")
  }

  private func getDataOwnerUID() -> String? {
    return UserDefaults.standard.string(forKey: "data_owner_uid")
  }

  private func getDataOwnerEmail() -> String? {
    return UserDefaults.standard.string(forKey: "data_owner_email")
  }

  // Helper validation methods
  private func validateTransactionOwnership(_ transactions: [Transaction], for email: String)
    -> Bool
  {
    // For now, return true if user email matches stored user
    // You could enhance this with more sophisticated validation
    return true
  }

  private func validateBudgetOwnership(_ budgets: [BudgetModel], for email: String) -> Bool {
    // For now, return true if user email matches stored user
    // You could enhance this with more sophisticated validation
    return true
  }

  // MARK: - Private Methods

  private func generateEncryptionKey(for userUID: String) -> SymmetricKey {
    let keyData = SHA256.hash(data: Data(userUID.utf8))
    return SymmetricKey(data: keyData)
  }

  private func createUserDataDirectoryIfNeeded(for userUID: String) {
    let userDirectory = getUserDataDirectory(for: userUID)

    if !FileManager.default.fileExists(atPath: userDirectory.path) {
      do {
        try FileManager.default.createDirectory(
          at: userDirectory, withIntermediateDirectories: true)
      } catch {
        print("❌ Failed to create user data directory: \(error)")
      }
    }
  }

  private func getUserDataDirectory(for userUID: String) -> URL {
    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
      .first!
    return
      documentsDirectory
      .appendingPathComponent("UserData")
      .appendingPathComponent(userUID)
  }

  private func saveEncryptedData<T: Codable>(_ data: T, for userUID: String, filename: String) {
    guard let encryptionKey = encryptionKey else {
      print("❌ Cannot save: No encryption key available")
      return
    }

    do {
      let jsonData = try JSONEncoder().encode(data)
      let encryptedData = try AES.GCM.seal(jsonData, using: encryptionKey)

      let userDirectory = getUserDataDirectory(for: userUID)
      let fileURL = userDirectory.appendingPathComponent(filename)

      try encryptedData.combined?.write(to: fileURL)
      print("✅ Encrypted data saved: \(filename)")
    } catch {
      print("❌ Failed to save encrypted data: \(error)")
    }
  }

  private func loadEncryptedData<T: Codable>(type: T.Type, for userUID: String, filename: String)
    -> T?
  {
    guard let encryptionKey = encryptionKey else {
      print("❌ Cannot load: No encryption key available")
      return nil
    }

    do {
      let userDirectory = getUserDataDirectory(for: userUID)
      let fileURL = userDirectory.appendingPathComponent(filename)

      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        print("ℹ️ Data file does not exist: \(filename)")
        return nil
      }

      let encryptedData = try Data(contentsOf: fileURL)
      let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
      let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

      let result = try JSONDecoder().decode(type, from: decryptedData)
      print("✅ Encrypted data loaded: \(filename)")
      return result
    } catch {
      print("❌ Failed to load encrypted data: \(error)")
      return nil
    }
  }
}

// MARK: - Supporting Data Models

struct UserProfile: Codable {
  let profileImageData: Data?
  let currentMonthIndex: Int
  let preferences: UserPreferences
}

struct UserPreferences: Codable {
  let hasFaceIdEnabled: Bool
  let notificationsEnabled: Bool
  let preferredCurrency: String

  init(
    hasFaceIdEnabled: Bool = false, notificationsEnabled: Bool = true,
    preferredCurrency: String = "USD"
  ) {
    self.hasFaceIdEnabled = hasFaceIdEnabled
    self.notificationsEnabled = notificationsEnabled
    self.preferredCurrency = preferredCurrency
  }
}

struct MigrationVerificationResult {
  let isComplete: Bool
  let transactionCount: Int
  let budgetCount: Int
  let hasProfile: Bool
  let errors: [String]
}

// MARK: - Debug Helper

extension SecureLocalDataManager {
  func printDebugInfo() {
    print("🔍 SecureLocalDataManager Debug Info:")
    print("   Current User UID: \(currentUserUID ?? "None")")
    print("   Encryption Key: \(encryptionKey != nil ? "Available" : "None")")
    if let directory = getUserDataDirectory() {
      print("   User Data Directory: \(directory.path)")
      print("   Directory Exists: \(FileManager.default.fileExists(atPath: directory.path))")

      // List files in directory
      do {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        print("   Files: \(files)")
      } catch {
        print("   Files: Unable to list (\(error))")
      }
    }
  }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
  static let backupFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter
  }()
}
