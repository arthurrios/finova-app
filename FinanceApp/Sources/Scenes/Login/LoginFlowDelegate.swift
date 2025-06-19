//
//  LoginFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

public protocol LoginFlowDelegate: AnyObject {
    func navigateToDashboard()
    func navigateToRegister()
}
