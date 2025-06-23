//
//  RegisterViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation

final class RegisterViewModel {
    var successResult: (() -> Void)?
    var errorResult: ((String, String) -> Void)?
    
    private let authManager = AuthenticationManager.shared
    
    init() {
        authManager.delegate = self
    }
    
    func registerUser(name: String, email: String, password: String, confirmPassword: String) {
        // Validation
        guard password == confirmPassword else {
            errorResult?("Registration Error", "Passwords do not match")
            return
        }
        
        guard password.count >= 6 else {
            errorResult?("Registration Error", "Password must be at least 6 characters")
            return
        }
        
        guard isValidEmail(email) else {
            errorResult?("Registration Error", "Please enter a valid email address")
            return
        }
        
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorResult?("Registration Error", "Name is required")
            return
        }
        
        // Register with Firebase
        authManager.register(name: name, email: email, password: password)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

extension RegisterViewModel: AuthenticationManagerDelegate {
    func authenticationDidComplete(user: User) {
        // Migrate old data if this is first Firebase registration
        if let firebaseUID = user.firebaseUID {
            SecureLocalDataManager.shared.migrateOldDataToUser(firebaseUID: firebaseUID) { success in
                if success {
                    print("✅ Data migration completed for new user")
                }
            }
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
        }
        
        // Save user locally
        UserDefaultsManager.saveUser(user: user)
        
        DispatchQueue.main.async {
            self.successResult?()
        }
    }
    
    func authenticationDidFail(error: Error) {
        DispatchQueue.main.async {
            if let authError = error as? AuthError {
                self.errorResult?("Registration Error", authError.localizedDescription)
            } else {
                self.errorResult?("Registration Error", error.localizedDescription)
            }
        }
    }
}
