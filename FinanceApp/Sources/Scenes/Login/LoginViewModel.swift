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
    
    func authenticate(userName: String, userEmail: String, password: String) {
        Auth.auth().signIn(withEmail: userEmail, password: password) { [weak self] result, error in
            if let error = error {
                print("Failed to authenticate user: \(error.localizedDescription)")
            } else {
                self?.successResult?(userName, userEmail)
            }
        }
    }
}
