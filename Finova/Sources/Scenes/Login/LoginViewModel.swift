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
        // Authenticate local data manager with Firebase UID
        if let firebaseUID = user.firebaseUID {
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            
            // Set current user UID for settings lookup
            UIDUserDefaultsManager.shared.currentUserUID = firebaseUID
            
            // Check if this user has existing settings
            let existingSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUID)
            let isReturningUser = existingSettings != nil
            
            var finalUser: User
            
            if let settings = existingSettings {
                // Returning user - use their saved settings but update sign-in time
                print("👋 Welcome back user: \(settings.name)")
                
                // Smart name preservation: if current login has a better name, use it
                var bestName = settings.name
                if !user.name.isEmpty && user.name != "User" && (settings.name.isEmpty || settings.name == "User") {
                    bestName = user.name
                    print("📝 Updating saved name from '\(settings.name)' to '\(user.name)'")
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
                
                print("✅ Restored user settings - name: '\(bestName)', faceId: \(settings.hasFaceIdEnabled)")
            } else {
                // New user - create fresh settings
                print("🆕 New user detected: \(user.name)")
                
                finalUser = User(
                    firebaseUID: firebaseUID,
                    name: user.name,
                    email: user.email,
                    isUserSaved: false, // New user is not saved initially
                    hasFaceIdEnabled: false // New user starts with Face ID disabled
                )
                
                print("✅ Created new user settings - name: '\(user.name)', faceId: false")
            }
            
            // Save user with UID-based system
            UserDefaultsManager.saveUserWithUID(user: finalUser)
            
            // Migrate existing data if needed
            SecureLocalDataManager.shared.migrateOldDataToUser(
                firebaseUID: firebaseUID, userEmail: finalUser.email
            ) { success in
                if success {
                    print("✅ Data migration completed successfully")
                } else {
                    print("⚠️ Data migration had issues")
                }
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
