//
//  RegisterFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation

public protocol RegisterFlowDelegate: AnyObject {
    func navigateToDashboard()
    func navigateBackToLogin()
}
