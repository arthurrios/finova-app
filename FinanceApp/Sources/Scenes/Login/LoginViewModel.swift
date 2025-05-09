//
//  LoginViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import Firebase

class LoginViewModel {
    var successResult: ((String, String) -> Void)?
    var errorResult: ((String) -> Void)?
    
    func authenticate(userName: String, userEmail: String, password: String) {
        Auth.auth().signIn(withEmail: userEmail, password: password) { [weak self] result, error in
            if let error = error as NSError? {
                if let errorCode = AuthErrorCode(rawValue: error.code) {
                    switch errorCode {
                    case .invalidCredential:
                        self?.errorResult?("login.error.message.invalidCredentials".localized)
                    default:
                        self?.errorResult?("login.error.message.unexpectedError".localized)
                    }
                }
            } else {
                self?.successResult?(userName, userEmail)
            }
        }
    }
}
