//
//  UIDUserDefaultsManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 27/01/25.
//

import Foundation

/// Manages user-specific settings linked to Firebase UID
class UIDUserDefaultsManager {
    
    // MARK: - Singleton
    static let shared = UIDUserDefaultsManager()
    private init() {}
    
    // MARK: - Private Keys
    private static let userSettingsPrefix = "userSettings_"
    private static let currentUserUIDKey = "currentUserUID"
    private static let globalCurrentMonthIndex = "currentMonthIndexKey"
    private static let globalBalanceDisplayMode = "BalanceDisplayMode"
    
    // MARK: - Current User Management
    
    var currentUserUID: String? {
        get {
            return UserDefaults.standard.string(forKey: Self.currentUserUIDKey)
        }
        set {
            if let uid = newValue {
                UserDefaults.standard.set(uid, forKey: Self.currentUserUIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentUserUIDKey)
            }
            UserDefaults.standard.synchronize()
        }
    }
    
    // MARK: - User-Specific Settings
    
    func saveUserSettings(for uid: String, settings: UserSettings) {
        let key = Self.userSettingsPrefix + uid
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize()
            print("✅ Saved settings for user: \(uid)")
        }
    }
    
    func getUserSettings(for uid: String) -> UserSettings? {
        let key = Self.userSettingsPrefix + uid
        if let data = UserDefaults.standard.data(forKey: key) {
            let decoder = JSONDecoder()
            if let settings = try? decoder.decode(UserSettings.self, from: data) {
                return settings
            }
        }
        return nil
    }
    
    func removeUserSettings(for uid: String) {
        let key = Self.userSettingsPrefix + uid
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
        print("🗑️ Removed settings for user: \(uid)")
    }
    
    // MARK: - Current User Convenience Methods
    
    func saveCurrentUserSettings(_ settings: UserSettings) {
        guard let uid = currentUserUID else {
            print("❌ Cannot save settings: No current user UID")
            return
        }
        saveUserSettings(for: uid, settings: settings)
    }
    
    func getCurrentUserSettings() -> UserSettings? {
        guard let uid = currentUserUID else {
            print("❌ Cannot get settings: No current user UID")
            return nil
        }
        return getUserSettings(for: uid)
    }
    
    // MARK: - Migration from Global Settings
    
    func migrateGlobalSettingsToUser(uid: String, globalUser: User) {
        // Check if user already has settings
        if getUserSettings(for: uid) != nil {
            print("ℹ️ User \(uid) already has settings, skipping migration")
            return
        }
        
        // Create settings from global user data
        let settings = UserSettings(
            name: globalUser.name,
            email: globalUser.email,
            hasFaceIdEnabled: globalUser.hasFaceIdEnabled,
            isUserSaved: globalUser.isUserSaved,
            createdAt: globalUser.createdAt,
            lastSignIn: Date()
        )
        
        saveUserSettings(for: uid, settings: settings)
        print("✅ Migrated global settings to user: \(uid)")
    }
    
    // MARK: - Global Settings (Non-User Specific)
    
    func getCurrentMonthIndex() -> Int {
        return UserDefaults.standard.integer(forKey: Self.globalCurrentMonthIndex)
    }
    
    func setCurrentMonthIndex(_ index: Int) {
        UserDefaults.standard.set(index, forKey: Self.globalCurrentMonthIndex)
    }
    
    func getBalanceDisplayMode() -> BalanceDisplayMode {
        let modeString = UserDefaults.standard.string(forKey: Self.globalBalanceDisplayMode) ?? "final"
        return modeString == "current" ? .current : .final
    }
    
    func setBalanceDisplayMode(_ mode: BalanceDisplayMode) {
        let modeString = mode == .current ? "current" : "final"
        UserDefaults.standard.set(modeString, forKey: Self.globalBalanceDisplayMode)
    }
    
    // MARK: - Cleanup Methods
    
    func signOut() {
        currentUserUID = nil
        print("🔒 UIDUserDefaultsManager signed out")
    }
    
    func clearAllUserSettings() {
        // Get all UserDefaults keys and remove user-specific ones
        if let keys = UserDefaults.standard.dictionaryRepresentation().keys as? [String] {
            for key in keys {
                if key.hasPrefix(Self.userSettingsPrefix) {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        UserDefaults.standard.synchronize()
        print("🗑️ Cleared all user settings")
    }
}

// MARK: - UserSettings Model

struct UserSettings: Codable {
    var name: String  // Made mutable to allow name updates from different login methods
    let email: String
    var hasFaceIdEnabled: Bool
    var isUserSaved: Bool
    let createdAt: Date
    var lastSignIn: Date
    
    init(name: String, email: String, hasFaceIdEnabled: Bool = false, isUserSaved: Bool = false, createdAt: Date = Date(), lastSignIn: Date = Date()) {
        self.name = name
        self.email = email
        self.hasFaceIdEnabled = hasFaceIdEnabled
        self.isUserSaved = isUserSaved
        self.createdAt = createdAt
        self.lastSignIn = lastSignIn
    }
    
    var displayName: String {
        return name.isEmpty ? "User" : name
    }
} 