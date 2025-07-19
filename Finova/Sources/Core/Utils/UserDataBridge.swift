//
//  UserDataBridge.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import Foundation

class UserDataBridge {
    static let shared = UserDataBridge()
    
    private init() {}
    
    /// Call this after user authentication to ensure data is properly set up
    func setupUserData(for firebaseUID: String, userEmail: String) {
        // Authenticate secure local data manager
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
        
        // Perform migration if needed
        SecureLocalDataManager.shared.migrateOldDataToUser(
            firebaseUID: firebaseUID, userEmail: userEmail
        ) { success in
            if success {
                print("✅ User data setup completed successfully")
            } else {
                print("⚠️ User data setup had issues")
            }
        }
    }
    
    /// Call this when user logs out to clean up all data
    func cleanupUserData() {
        AuthenticationManager.shared.signOut()
        SecureLocalDataManager.shared.signOut()
        UserDefaultsManager.removeUser()
        
        print("✅ User data cleanup completed")
    }
    
    /// Check if user is properly authenticated for both Firebase and local data
    func isUserFullyAuthenticated() -> Bool {
        guard AuthenticationManager.shared.isAuthenticated else {
            print("❌ Firebase authentication missing")
            return false
        }
        
        guard UserDefaultsManager.getUser() != nil else {
            print("❌ Local user data missing")
            return false
        }
        
        return true
    }
}
