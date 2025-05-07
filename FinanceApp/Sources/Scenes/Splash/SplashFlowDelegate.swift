//
//  SplashFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation

public protocol SplashFlowDelegate: AnyObject {
    func navigateToLogin()
    func navigateToDashboard()
}
