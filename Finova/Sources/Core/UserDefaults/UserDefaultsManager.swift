//
//  UserDefaultsManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

class UserDefaultsManager {
  private static let userKey = "userKey"
  private static let currentMonthIndex = "currentMonthIndexKey"
  private static let balanceDisplayModeKey = "BalanceDisplayMode"
  private static let biometricEnabledKey = "biometricEnabled"
  private static let hideValuesKey = "hideValues"

  static func saveUser(user: User) {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(user) {
      UserDefaults.standard.set(data, forKey: userKey)
      UserDefaults.standard.synchronize()
    }
  }

  static func getUser() -> User? {
    if let userData = UserDefaults.standard.data(forKey: userKey) {
      let decoder = JSONDecoder()
      if let user = try? decoder.decode(User.self, from: userData) {
        return user
      }
    }
    return nil
  }

  static func removeUser() {
    UserDefaults.standard.removeObject(forKey: userKey)
    UserDefaults.standard.synchronize()
  }

  static func getCurrentMonthIndex() -> Int {
    return UserDefaults.standard.integer(forKey: currentMonthIndex)
  }

  static func setCurrentMonthIndex(_ index: Int) {
    UserDefaults.standard.set(index, forKey: currentMonthIndex)
  }

  static func setBalanceDisplayMode(_ mode: BalanceDisplayMode) {
    let modeString: String
    switch mode {
    case .current:
      modeString = "current"
    case .final:
      modeString = "final"
    case .daySpecific:
      // Don't save day-specific mode to UserDefaults
      return
    }
    UserDefaults.standard.set(modeString, forKey: balanceDisplayModeKey)
  }

  static func getBalanceDisplayMode() -> BalanceDisplayMode {
    let modeString = UserDefaults.standard.string(forKey: balanceDisplayModeKey) ?? "final"
    return modeString == "current" ? .current : .final
  }

  static func setBiometricEnabled(_ isEnabled: Bool) {
    UserDefaults.standard.set(isEnabled, forKey: biometricEnabledKey)
    UserDefaults.standard.synchronize()
  }

  static func getBiometricEnabled() -> Bool {
    return UserDefaults.standard.bool(forKey: biometricEnabledKey)
  }

  static func setHideValues(_ isHidden: Bool) {
    UserDefaults.standard.set(isHidden, forKey: hideValuesKey)
    UserDefaults.standard.synchronize()
  }

  static func getHideValues() -> Bool {
    return UserDefaults.standard.bool(forKey: hideValuesKey)
  }

  // MARK: - Clear All Settings

  static func clearAllSettings() {
    UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
    UserDefaults.standard.removeObject(forKey: currentMonthIndex)
    UserDefaults.standard.removeObject(forKey: balanceDisplayModeKey)
    UserDefaults.standard.synchronize()
  }

  // MARK: - UID-Based User Management

  static func saveUserWithUID(user: User) {
    guard let uid = user.firebaseUID else {
      print("❌ Cannot save user: No Firebase UID")
      // Fallback to global save for non-Firebase users
      saveUser(user: user)
      return
    }

    // Set current user
    UIDUserDefaultsManager.shared.currentUserUID = uid

    // Migrate existing global settings if needed
    if let existingUser = getUser() {
      UIDUserDefaultsManager.shared.migrateGlobalSettingsToUser(uid: uid, globalUser: existingUser)
    }

    // Save user settings
    let settings = UserSettings(
      name: user.name,
      email: user.email,
      hasFaceIdEnabled: user.hasFaceIdEnabled,
      isUserSaved: user.isUserSaved,
      createdAt: user.createdAt,
      lastSignIn: Date()
    )

    UIDUserDefaultsManager.shared.saveUserSettings(for: uid, settings: settings)

    // Also maintain the global user for backward compatibility
    saveUser(user: user)
  }

  static func getUserWithUID() -> User? {
    guard let uid = UIDUserDefaultsManager.shared.currentUserUID,
      let settings = UIDUserDefaultsManager.shared.getUserSettings(for: uid)
    else {
      // Fallback to global user
      return getUser()
    }

    return User(
      firebaseUID: uid,
      name: settings.name,
      email: settings.email,
      isUserSaved: settings.isUserSaved,
      hasFaceIdEnabled: settings.hasFaceIdEnabled
    )
  }

  static func updateCurrentUserFaceID(enabled: Bool) {
    guard let uid = UIDUserDefaultsManager.shared.currentUserUID else {
      print("❌ Cannot update Face ID: No current user UID")
      return
    }

    // Try to get existing settings, or create new ones if they don't exist
    var settings = UIDUserDefaultsManager.shared.getUserSettings(for: uid)

    if settings == nil {
      // Create new settings for this user
      print("🆕 Creating new user settings for Face ID update, UID: \(uid)")

      // Try to get user info from Firebase or global settings
      var userName = "User"
      var userEmail = ""
      var isUserSaved = false

      if let firebaseUser = AuthenticationManager.shared.currentUser {
        userName = firebaseUser.displayName ?? "User"
        userEmail = firebaseUser.email ?? ""
        isUserSaved = true  // Firebase users are considered saved
      } else if let globalUser = getUser() {
        userName = globalUser.name
        userEmail = globalUser.email
        isUserSaved = globalUser.isUserSaved
      }

      settings = UserSettings(
        name: userName,
        email: userEmail,
        hasFaceIdEnabled: false,
        isUserSaved: isUserSaved,
        createdAt: Date(),
        lastSignIn: Date()
      )
    }

    guard var userSettings = settings else {
      print("❌ Failed to create or retrieve user settings for Face ID update")
      return
    }

    userSettings.hasFaceIdEnabled = enabled
    userSettings.lastSignIn = Date()
    UIDUserDefaultsManager.shared.saveUserSettings(for: uid, settings: userSettings)

    // Update global user as well for backward compatibility
    if var globalUser = getUser() {
      let updatedUser = User(
        firebaseUID: globalUser.firebaseUID,
        name: globalUser.name,
        email: globalUser.email,
        isUserSaved: globalUser.isUserSaved,
        hasFaceIdEnabled: enabled
      )
      saveUser(user: updatedUser)
    }

    print("✅ Updated Face ID setting for user: \(uid) to \(enabled)")
  }

  static func updateCurrentUserSavedStatus(saved: Bool) {
    guard let uid = UIDUserDefaultsManager.shared.currentUserUID else {
      print("❌ Cannot update saved status: No current user UID")
      return
    }

    // Try to get existing settings, or create new ones if they don't exist
    var settings = UIDUserDefaultsManager.shared.getUserSettings(for: uid)

    if settings == nil {
      // Create new settings for this user
      print("🆕 Creating new user settings for UID: \(uid)")

      // Try to get user info from Firebase or global settings
      var userName = "User"
      var userEmail = ""

      if let firebaseUser = AuthenticationManager.shared.currentUser {
        userName = firebaseUser.displayName ?? "User"
        userEmail = firebaseUser.email ?? ""
      } else if let globalUser = getUser() {
        userName = globalUser.name
        userEmail = globalUser.email
      }

      settings = UserSettings(
        name: userName,
        email: userEmail,
        hasFaceIdEnabled: false,
        isUserSaved: false,
        createdAt: Date(),
        lastSignIn: Date()
      )
    }

    guard var userSettings = settings else {
      print("❌ Failed to create or retrieve user settings")
      return
    }

    userSettings.isUserSaved = saved
    userSettings.lastSignIn = Date()
    UIDUserDefaultsManager.shared.saveUserSettings(for: uid, settings: userSettings)

    // Update global user as well
    if var globalUser = getUser() {
      let updatedUser = User(
        firebaseUID: globalUser.firebaseUID,
        name: globalUser.name,
        email: globalUser.email,
        isUserSaved: saved,
        hasFaceIdEnabled: globalUser.hasFaceIdEnabled
      )
      saveUser(user: updatedUser)
    }

    print("✅ Updated saved status for user: \(uid) to \(saved)")
  }

  static func getCurrentUserFaceIDSetting() -> Bool {
    guard let uid = UIDUserDefaultsManager.shared.currentUserUID,
      let settings = UIDUserDefaultsManager.shared.getUserSettings(for: uid)
    else {
      // Fallback to global setting
      return getUser()?.hasFaceIdEnabled ?? false
    }

    return settings.hasFaceIdEnabled
  }

  static func signOutCurrentUser() {
    UIDUserDefaultsManager.shared.signOut()
    removeUser()
  }
}
