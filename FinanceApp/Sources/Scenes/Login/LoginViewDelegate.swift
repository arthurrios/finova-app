//
//  LoginFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation

public protocol LoginViewDelegate: AnyObject {
  func sendLoginData(email: String, password: String)
  func navigateToRegister()
}
