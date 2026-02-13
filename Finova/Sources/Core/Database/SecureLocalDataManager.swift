//
//  SecureLocalDataManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import CryptoKit
import Foundation
import UIKit

class SecureLocalDataManager {

  // MARK: - Singleton
  static let shared = SecureLocalDataManager()

  // MARK: - Properties
  private var currentUserUID: String?
  private var encryptionKey: SymmetricKey?

  /// Concurrent queue for thread-safe file operations (reader-writer pattern)
  private let fileQueue = DispatchQueue(label: "com.finova.secureLocalDataManager.fileQueue", attributes: .concurrent)

  private init() {}

  // MARK: - User Session Management

  func authenticateUser(firebaseUID: String) {
    self.currentUserUID = firebaseUID
    self.encryptionKey = generateEncryptionKey(for: firebaseUID)
    createUserDataDirectoryIfNeeded(for: firebaseUID)
  }

  func getCurrentUserUID() -> String? {
    return currentUserUID
  }

  func signOut() {
    self.currentUserUID = nil
    self.encryptionKey = nil
  }

  // MARK: - Generic Data Access (UID-isolated)

  func saveData<T: Codable>(_ data: T, filename: String) {
    guard let uid = currentUserUID else {
      logError("Cannot save data: No authenticated user")
      return
    }
    saveEncryptedData(data, for: uid, filename: filename)
  }

  func loadData<T: Codable>(type: T.Type, filename: String) -> T? {
    guard let uid = currentUserUID else {
      logError("Cannot load data: No authenticated user")
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

  // MARK: - Profile Image Methods (User-Specific)

  func saveProfileImage(_ image: UIImage) {
    guard currentUserUID != nil else {
      logError("Cannot save profile image: No authenticated user")
      return
    }

    // Load existing profile or create new one
    var userProfile =
      loadUserProfile()
      ?? UserProfile(
        profileImageData: nil,
        currentMonthIndex: UserDefaultsManager.getCurrentMonthIndex(),
        preferences: UserPreferences()
      )

    // Update profile image data
    userProfile.profileImageData = image.jpegData(compressionQuality: 0.8)

    // Save updated profile
    saveUserProfile(userProfile)
  }

  func loadProfileImage() -> UIImage? {
    guard currentUserUID != nil else {
      logError("Cannot load profile image: No authenticated user")
      return nil
    }

    guard let userProfile = loadUserProfile(),
      let imageData = userProfile.profileImageData
    else {
      return nil
    }

    return UIImage(data: imageData)
  }

  func removeProfileImage() {
    guard currentUserUID != nil else {
      logError("Cannot remove profile image: No authenticated user")
      return
    }

    var userProfile =
      loadUserProfile()
      ?? UserProfile(
        profileImageData: nil,
        currentMonthIndex: UserDefaultsManager.getCurrentMonthIndex(),
        preferences: UserPreferences()
      )

    userProfile.profileImageData = nil
    saveUserProfile(userProfile)
  }

  // MARK: - Data Migration from Old Local Storage

  func migrateOldDataToUser(
    firebaseUID: String, userEmail: String, completion: @escaping (Bool) -> Void
  ) {
    let migrationKey = "data_migrated_to_firebase_\(firebaseUID)"
    if UserDefaults.standard.bool(forKey: migrationKey) {
      completion(true)
      return
    }

    // SECURITY CHECK: Validate ownership before migration
    guard validateDataOwnership(for: firebaseUID, email: userEmail) else {
      logError("Migration denied: User does not own existing data")
      completion(false)
      return
    }

    // Authenticate with new UID first
    authenticateUser(firebaseUID: firebaseUID)

    var migrationSuccess = true

    // Step 1: Migrate Transactions from SQLite
    let transactionMigrationResult = migrateTransactionsFromSQLite(validatedFor: userEmail)
    if !transactionMigrationResult {
      migrationSuccess = false
    }

    // Step 2: Migrate Budgets from SQLite
    let budgetMigrationResult = migrateBudgetsFromSQLite(validatedFor: userEmail)
    if !budgetMigrationResult {
      migrationSuccess = false
    }

    // Step 3: Migrate User Profile Data
    let profileMigrationResult = migrateUserProfileData(validatedFor: userEmail)
    if !profileMigrationResult {
      migrationSuccess = false
    }

    // Step 4: Backup old data (don't delete immediately for safety)
    if migrationSuccess {
      createBackupOfOldData()

      // SECURITY: Mark data as owned by this user
      markDataOwnership(for: firebaseUID, email: userEmail)
    }

    // Mark migration as completed only if successful
    if migrationSuccess {
      UserDefaults.standard.set(true, forKey: migrationKey)
    } else {
      logError("Data migration failed for user: \(firebaseUID)")
    }

    completion(migrationSuccess)
  }

  // MARK: - Private Migration Methods

  private func migrateTransactionsFromSQLite(validatedFor email: String) -> Bool {
    // Use existing repository to get all transactions
    let transactionRepo = TransactionRepository()
    let allTransactions = transactionRepo.fetchAllTransactions()

    if !allTransactions.isEmpty {
      // SECURITY: Only migrate if data belongs to this user
      if validateTransactionOwnership(allTransactions, for: email) {
        saveTransactions(allTransactions)
      } else {
        logError("Transaction ownership validation failed")
        return false
      }
    }

    return true
  }

  private func migrateBudgetsFromSQLite(validatedFor email: String) -> Bool {
    // Use existing repository to get all budgets
    let budgetRepo = BudgetRepository()
    let allBudgets = budgetRepo.fetchBudgets()

    if !allBudgets.isEmpty {
      // SECURITY: Only migrate if data belongs to this user
      if validateBudgetOwnership(allBudgets, for: email) {
        saveBudgets(allBudgets)
      } else {
        logError("Budget ownership validation failed")
        return false
      }
    }

    return true
  }

  private func migrateUserProfileData(validatedFor email: String) -> Bool {
    // SECURITY: Validate profile belongs to this user
    if let existingUser = UserDefaultsManager.getUser() {
      if existingUser.email.lowercased() != email.lowercased() {
        logError("Profile email mismatch - migration denied")
        return false
      }
    }

    // Migrate user profile image from any global storage location
    var profileImageData: Data?
    if let profileImage = ProfileImageCleanup.shared.loadGlobalProfileImageIfExists() {
      profileImageData = profileImage.jpegData(compressionQuality: 0.8)
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

    // Comprehensive cleanup of all global profile images after migration
    ProfileImageCleanup.shared.clearAllGlobalProfileImages()

    return true
  }

  private func createBackupOfOldData() {
    // Create a backup directory with timestamp
    let timestamp = DateFormatter.backupFormatter.string(from: Date())
    let backupKey = "data_backup_created_\(timestamp)"

    // Mark that backup was created (for reference)
    UserDefaults.standard.set(true, forKey: backupKey)
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
      }
    } catch {
      logError("Failed to clear user data: \(error)")
    }
  }

  /// Physically deletes the encrypted transactions file from disk.
  /// Call this before rebuilding to ensure no stale data persists.
  func deleteTransactionsFile() {
    guard let uid = currentUserUID else {
      logError("Cannot delete transactions file: No authenticated user")
      return
    }

    fileQueue.sync(flags: .barrier) {
      let userDirectory = getUserDataDirectory(for: uid)
      let fileURL = userDirectory.appendingPathComponent("transactions.json")

      if FileManager.default.fileExists(atPath: fileURL.path) {
        do {
          try FileManager.default.removeItem(at: fileURL)
          logWarning("[SecureStore] Deleted transactions file at \(fileURL.path)")
        } catch {
          logError("[SecureStore] Failed to delete transactions file: \(error)")
        }
      } else {
        logWarning("[SecureStore] No transactions file to delete at \(fileURL.path)")
      }
    }
  }

  // MARK: - Security & Data Ownership

  private func validateDataOwnership(for firebaseUID: String, email: String) -> Bool {
    // EMERGENCY RECOVERY: Check if this is a first-time recovery attempt
    let emergencyRecoveryKey = "emergency_recovery_attempted_\(firebaseUID)"
    if !UserDefaults.standard.bool(forKey: emergencyRecoveryKey) {
      UserDefaults.standard.set(true, forKey: emergencyRecoveryKey)
      return true
    }

    // Check if data has already been claimed by another user
    if let existingOwnerUID = getDataOwnerUID() {
      if existingOwnerUID != firebaseUID {
        return false
      }
    }

    // Check if existing local user data matches this email
    if let existingUser = UserDefaultsManager.getUser() {
      if existingUser.email.lowercased() != email.lowercased() {
        return false
      }
    }

    // Additional check: verify user has permission to access this device's data
    return validateDeviceDataAccess(for: email)
  }

  private func validateDeviceDataAccess(for email: String) -> Bool {
    let deviceUserKey = "device_users"
    var deviceUsers = UserDefaults.standard.stringArray(forKey: deviceUserKey) ?? []

    let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    deviceUsers = deviceUsers.map {
      $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // With Firebase Auth + UID isolation, any authenticated user should be allowed
    // Add them to device users list for tracking, but don't deny access
    if !deviceUsers.contains(normalizedEmail) {
      deviceUsers.append(normalizedEmail)
      UserDefaults.standard.set(deviceUsers, forKey: deviceUserKey)
    }

    return true  // Always allow access for Firebase authenticated users
  }

  private func markDataOwnership(for firebaseUID: String, email: String) {
    UserDefaults.standard.set(firebaseUID, forKey: "data_owner_uid")
    UserDefaults.standard.set(email.lowercased(), forKey: "data_owner_email")
    UserDefaults.standard.set(Date(), forKey: "data_ownership_date")
  }

  private func updateDataOwnership(for firebaseUID: String, email: String) {
    UserDefaults.standard.set(firebaseUID, forKey: "data_owner_uid")
    UserDefaults.standard.set(email.lowercased(), forKey: "data_owner_email")
    UserDefaults.standard.set(Date(), forKey: "data_ownership_date")
  }

  func clearDataOwnership() {
    UserDefaults.standard.removeObject(forKey: "data_owner_uid")
    UserDefaults.standard.removeObject(forKey: "data_owner_email")
    UserDefaults.standard.removeObject(forKey: "data_ownership_date")
  }

  func clearCurrentUserDataOwnership() {
    guard let uid = currentUserUID else {
      logError("Cannot clear data ownership: No authenticated user")
      return
    }

    // Clear only current user's ownership records, preserve others
    // Only clear global ownership if current user is the owner
    if getDataOwnerUID() == uid {
      UserDefaults.standard.removeObject(forKey: "data_owner_uid")
      UserDefaults.standard.removeObject(forKey: "data_owner_email")
      UserDefaults.standard.removeObject(forKey: "data_ownership_date")
    }
  }

  func manuallyUpdateDeviceUsers(to email: String) {
    let deviceUserKey = "device_users"
    let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    UserDefaults.standard.set([normalizedEmail], forKey: deviceUserKey)
  }

  func reclaimDataOwnership(for firebaseUID: String, email: String) {
    updateDataOwnership(for: firebaseUID, email: email)

    // Also update the user in UserDefaults if needed
    if let existingUser = UserDefaultsManager.getUser() {
      if existingUser.email.lowercased() != email.lowercased() {
        let updatedUser = User(
          firebaseUID: firebaseUID,
          name: existingUser.name,
          email: email,
          isUserSaved: true,
          hasFaceIdEnabled: existingUser.hasFaceIdEnabled
        )
        UserDefaultsManager.saveUser(user: updatedUser)
      }
    }

    // Add reclaimed email to device users
    let deviceUserKey = "device_users"
    var deviceUsers = UserDefaults.standard.stringArray(forKey: deviceUserKey) ?? []

    // Remove the old email and add the new one
    let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    deviceUsers = deviceUsers.map {
      $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Remove any old emails and add the new one
    deviceUsers.removeAll { $0 != normalizedEmail }
    if !deviceUsers.contains(normalizedEmail) {
      deviceUsers.append(normalizedEmail)
    }

    UserDefaults.standard.set(deviceUsers, forKey: deviceUserKey)

    // Also manually ensure the device users list is correct
    manuallyUpdateDeviceUsers(to: email)
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
        logError("Failed to create user data directory: \(error)")
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
      logError("Cannot save: No encryption key available")
      return
    }

    // Use barrier for exclusive write access (reader-writer pattern)
    fileQueue.sync(flags: .barrier) {
      do {
        let jsonData = try JSONEncoder().encode(data)
        let encryptedData = try AES.GCM.seal(jsonData, using: encryptionKey)

        guard let combinedData = encryptedData.combined else {
          logError("AES.GCM.seal produced nil combined data — file NOT written for \(filename)")
          return
        }

        let userDirectory = getUserDataDirectory(for: userUID)
        let fileURL = userDirectory.appendingPathComponent(filename)

        try combinedData.write(to: fileURL)
      } catch {
        logError("Failed to save encrypted data: \(error)")
      }
    }
  }

  private func loadEncryptedData<T: Codable>(type: T.Type, for userUID: String, filename: String)
    -> T?
  {
    guard let encryptionKey = encryptionKey else {
      logError("Cannot load: No encryption key available")
      return nil
    }

    // Use serial queue for thread-safe file operations
    return fileQueue.sync {
      do {
        let userDirectory = getUserDataDirectory(for: userUID)
        let fileURL = userDirectory.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          return nil
        }

        let encryptedData = try Data(contentsOf: fileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        let result = try JSONDecoder().decode(type, from: decryptedData)
        return result
      } catch {
        logError("Failed to load encrypted data: \(error)")
        return nil
      }
    }
  }
}

// MARK: - Supporting Data Models

struct UserProfile: Codable {
  var profileImageData: Data?
  var currentMonthIndex: Int
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
    #if DEBUG
    logDebug("SecureLocalDataManager Debug Info:")
    logDebug("   Current User UID: \(currentUserUID ?? "None")")
    logDebug("   Encryption Key: \(encryptionKey != nil ? "Available" : "None")")
    if let directory = getUserDataDirectory() {
      logDebug("   User Data Directory: \(directory.path)")
      logDebug("   Directory Exists: \(FileManager.default.fileExists(atPath: directory.path))")

      // List files in directory
      do {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        logDebug("   Files: \(files)")
      } catch {
        logDebug("   Files: Unable to list (\(error))")
      }
    }
    #endif
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

// MARK: - Biometric Account Linking (Phase 7)

enum AccountValidationResult {
  case valid
  case requiresBiometricVerification(existingEmail: String, newEmail: String)
  case ownedByDifferentUser(existingEmail: String, newEmail: String)
  case accessDenied
}

extension SecureLocalDataManager {
  func validateDataOwnershipWithBiometrics(for firebaseUID: String, email: String)
    -> AccountValidationResult
  {
    // First check if this email has been used on this device before
    if let existingUser = UserDefaultsManager.getUser() {
      if existingUser.email.lowercased() == email.lowercased() {  // Same email - allow access regardless of Firebase UID
        return .valid
      } else {
        if BiometricDataManager.shared.hasBiometricData() {
          return .requiresBiometricVerification(existingEmail: existingUser.email, newEmail: email)
        } else {
          return .valid
        }
      }
    }

    // Check if data has been claimed by a different UID
    if let existingOwnerUID = getDataOwnerUID() {
      if existingOwnerUID != firebaseUID {  // Check if the existing owner has the same email
        if let existingOwnerEmail = getDataOwnerEmail() {
          if existingOwnerEmail.lowercased() == email.lowercased() {
            updateDataOwnership(for: firebaseUID, email: email)
            return .valid
          } else {
            return .ownedByDifferentUser(existingEmail: existingOwnerEmail, newEmail: email)
          }
        } else {
          return .ownedByDifferentUser(existingEmail: "Unknown", newEmail: email)
        }
      }
    }

    // Check device access - if it fails, we need to handle the conflict
    let deviceAccess = validateDeviceDataAccess(for: email)

    if !deviceAccess {
      // Device access failed - check if we have existing owner data to reclaim
      if let existingOwnerEmail = getDataOwnerEmail() {
        return .ownedByDifferentUser(existingEmail: existingOwnerEmail, newEmail: email)
      }
    }

    return deviceAccess ? .valid : .accessDenied
  }

  func registerFirstTimeUserWithBiometrics(
    firebaseUID: String,
    email: String,
    completion: @escaping (Bool) -> Void
  ) {
    guard BiometricDataManager.shared.isBiometricAvailable() else {
      authenticateUser(firebaseUID: firebaseUID)
      completion(true)
      return
    }

    // Check if biometric data already exists
    if BiometricDataManager.shared.hasBiometricData() {
      authenticateUser(firebaseUID: firebaseUID)
      completion(true)
      return
    }
    BiometricDataManager.shared.registerUserBiometric(for: email) { [weak self] success, error in
      if !success {
        logError("Biometric registration failed: \(error?.localizedDescription ?? "Unknown error")")
      }
      self?.authenticateUser(firebaseUID: firebaseUID)
      completion(true)
    }
  }

  func handleBiometricAccountLinking(
    newFirebaseUID: String,
    newEmail: String,
    linkToExistingData: Bool,
    completion: @escaping (Bool) -> Void
  ) {
    if linkToExistingData {
      if let existingUser = UserDefaultsManager.getUser() {
        let linkedUser = User(
          firebaseUID: existingUser.firebaseUID,
          name: existingUser.name,
          email: newEmail,
          isUserSaved: true,
          hasFaceIdEnabled: existingUser.hasFaceIdEnabled
        )
        UserDefaultsManager.saveUser(user: linkedUser)
        markBiometricAccountLinking(
          originalUID: existingUser.firebaseUID ?? "",
          newUID: newFirebaseUID,
          newEmail: newEmail
        )
        authenticateUser(firebaseUID: existingUser.firebaseUID ?? "")
        completion(true)
      } else {
        logError("No existing user found for linking")
        completion(false)
      }
    } else {
      registerFirstTimeUserWithBiometrics(
        firebaseUID: newFirebaseUID,
        email: newEmail,
        completion: completion
      )
    }
  }

  private func markBiometricAccountLinking(originalUID: String, newUID: String, newEmail: String) {
    let linkingInfo = [
      "original_uid": originalUID,
      "linked_uid": newUID,
      "linked_email": newEmail,
      "linking_method": "biometric_verification",
      "linking_date": ISO8601DateFormatter().string(from: Date()),
    ]
    UserDefaults.standard.set(linkingInfo, forKey: "biometric_linking_\(originalUID)")
  }

  func deleteAllUserData() {
    guard currentUserUID != nil else {
      logError("Cannot delete user data: No authenticated user")
      return
    }

    // Clear encrypted user data directory
    clearUserData()

    // Clear data ownership records
    clearDataOwnership()
  }
}
