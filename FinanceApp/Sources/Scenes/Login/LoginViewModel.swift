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
}

extension LoginViewModel: AuthenticationManagerDelegate {
    func authenticationDidComplete(user: User) {
        // Authenticate local data manager with Firebase UID
        if let firebaseUID = user.firebaseUID {
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            
            // Migrate existing data if needed
            SecureLocalDataManager.shared.migrateOldDataToUser(firebaseUID: firebaseUID) { success in
                if success {
                    print("✅ Data migration completed successfully")
                } else {
                    print("⚠️ Data migration had issues")
                }
            }
        }
        
        // Save user locally
        UserDefaultsManager.saveUser(user: user)
        
        DispatchQueue.main.async {
            self.successResult?()
        }
    }
    
    func authenticationDidFail(error: any Error) {
        DispatchQueue.main.async {
            if let authError = error as? AuthError {
                self.errorResult?(
                    "Authentication Error",
                    authError.localizedDescription
                )
            } else {
                self.errorResult?(
                    "login.error.unexpectedError.title".localized,
                    error.localizedDescription
                )
            }
        }
    }
}
