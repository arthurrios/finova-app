//
//  RegisterViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation
import SwiftEmailValidator

final class RegisterViewModel {
    var successResult: (() -> Void)?
    var errorResult: ((String, String) -> Void)?
    
    private let authManager = AuthenticationManager.shared
    
    init() {
        authManager.delegate = self
    }
    
    func registerUser(name: String, email: String, password: String, confirmPassword: String) {
        // Enhanced validation with localized messages
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorResult?("validation.error.title".localized, "validation.error.nameRequired".localized)
            return
        }
        
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorResult?("validation.error.title".localized, "validation.error.emailRequired".localized)
            return
        }
        
        guard EmailSyntaxValidator.correctlyFormatted(email, compatibility: .ascii) else {
            errorResult?("validation.error.title".localized, "auth.error.invalidEmail".localized)
            return
        }
        
        guard !password.isEmpty else {
            errorResult?(
                "validation.error.title".localized, "validation.error.passwordRequired".localized)
            return
        }
        
        guard password.count >= 6 else {
            errorResult?("validation.error.title".localized, "auth.error.weakPassword".localized)
            return
        }
        
        guard password == confirmPassword else {
            errorResult?(
                "validation.error.title".localized, "validation.error.passwordsDoNotMatch".localized)
            return
        }
        
        // Register with Firebase
        authManager.register(name: name, email: email, password: password)
    }
}

extension RegisterViewModel: AuthenticationManagerDelegate {
    func authenticationDidComplete(user: User) {
        logInfo("RegisterViewModel received user: '\(user.name)' with UID: '\(user.firebaseUID ?? "nil")'")
        
        if let firebaseUID = user.firebaseUID {
            UIDUserDefaultsManager.shared.currentUserUID = firebaseUID
            DBHelper.shared.backfillUserIds(uid: firebaseUID)
        }
        
        // Save user locally
        logInfo("Saving user to UserDefaults: '\(user.name)'")
        UserDefaultsManager.saveUser(user: user)
        
        // Verify saved user
        if let savedUser = UserDefaultsManager.getUser() {
            logInfo("Verified saved user: '\(savedUser.name)'")
        } else {
            logError("Failed to save/retrieve user from UserDefaults")
        }
        
        DispatchQueue.main.async {
            self.successResult?()
        }
    }
    
    func authenticationDidFail(error: Error) {
        DispatchQueue.main.async {
            let title = FirebaseErrorHandler.localizedTitle(for: error)
            let message = FirebaseErrorHandler.localizedMessage(for: error)
            self.errorResult?(title, message)
        }
    }
}
