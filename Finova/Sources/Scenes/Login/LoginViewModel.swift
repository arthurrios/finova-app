//
//  LoginViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Firebase
import Foundation

class LoginViewModel {
    var successResult: (() -> Void)?
    var errorResult: ((String, String) -> Void)?
    
    private let authManager = AuthenticationManager.shared
    
    init() {
        authManager.delegate = self
    }
    
    func authenticate(userEmail: String, password: String) {
        authManager.signIn(email: userEmail, password: password)
    }
    
    func signInWithGoogle() {
        authManager.signInWithGoogle()
    }
    
    func signInWithApple() {
        authManager.signInWithApple()
    }
}

extension LoginViewModel: AuthenticationManagerDelegate {
    func authenticationDidComplete(user: User) {
        if let firebaseUID = user.firebaseUID {
            // Set current user UID for settings lookup
            UIDUserDefaultsManager.shared.currentUserUID = firebaseUID
            // Auto-enable sync on fresh installs (key never set).
            // InitialSync screen now guarantees pull-first, so auto-sync is safe.
            if UserDefaults.standard.object(forKey: "syncEnabled") == nil {
                UserDefaultsManager.setSyncEnabled(true)
            }
            // Backfill syncFullPullVerified_v2 for existing devices that already synced
            // successfully before this flag was introduced.
            if !UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2"),
               SyncStateManager.shared.changeToken(for: "privateDB", database: "private") != nil {
                UserDefaults.standard.set(true, forKey: "syncFullPullVerified_v2")
            }
            DBHelper.shared.backfillUserIds(uid: firebaseUID)

            // Check if this user has existing settings
            let existingSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUID)

            var finalUser: User

            if let settings = existingSettings {
                // Returning user - use their saved settings but update sign-in time
                logInfo("Welcome back user: \(settings.name)")

                // Smart name preservation: if current login has a better name, use it
                var bestName = settings.name
                if !user.name.isEmpty && user.name != "User" && (settings.name.isEmpty || settings.name == "User") {
                    bestName = user.name
                    logInfo("Updating saved name from '\(settings.name)' to '\(user.name)'")
                } else if settings.name.isEmpty || settings.name == "User" {
                    bestName = user.name.isEmpty ? "User" : user.name
                }

                var updatedSettings = settings
                updatedSettings.name = bestName // Update with best available name
                updatedSettings.lastSignIn = Date()
                UIDUserDefaultsManager.shared.saveUserSettings(for: firebaseUID, settings: updatedSettings)

                finalUser = User(
                    firebaseUID: firebaseUID,
                    name: bestName, // Use best available name
                    email: settings.email,
                    isUserSaved: settings.isUserSaved,
                    hasFaceIdEnabled: settings.hasFaceIdEnabled // Use saved Face ID setting
                )

                logInfo("Restored user settings - name: '\(bestName)', faceId: \(settings.hasFaceIdEnabled)")
            } else {
                // New user - create fresh settings
                logInfo("New user detected: \(user.name)")

                finalUser = User(
                    firebaseUID: firebaseUID,
                    name: user.name,
                    email: user.email,
                    isUserSaved: false, // New user is not saved initially
                    hasFaceIdEnabled: false // New user starts with Face ID disabled
                )

                logInfo("Created new user settings - name: '\(user.name)', faceId: false")
            }

            // Save user with UID-based system
            UserDefaultsManager.saveUserWithUID(user: finalUser)

            // Force full fetch to pull ALL data from CloudKit on login
            // Only auto-sync if user hasn't disabled sync (allows safe login for recovery scenarios)
            // On new devices, InitialSyncViewController will trigger the sync instead
            let isNewDevice = !UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2")
            if UserDefaultsManager.getSyncEnabled() && !isNewDevice {
                SyncEngine.shared.performFullSync(forceFullFetch: true)
            }
        }

        DispatchQueue.main.async {
            self.successResult?()
        }
    }
    
    func authenticationDidFail(error: any Error) {
        DispatchQueue.main.async {
            let title = FirebaseErrorHandler.localizedTitle(for: error)
            let message = FirebaseErrorHandler.localizedMessage(for: error)
            self.errorResult?(title, message)
        }
    }
}
