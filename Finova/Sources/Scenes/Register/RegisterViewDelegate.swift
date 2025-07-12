//
//  RegisterViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation

protocol RegisterViewDelegate: AnyObject {
    func sendRegisterData(name: String, email: String, password: String, confirmPassword: String)
    func navigateBackToLogin()
}
