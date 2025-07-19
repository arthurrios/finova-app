//
//  DashboardFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

public protocol DashboardFlowDelegate: AnyObject {
    func logout()
    func navigateToBudgets(date: Date?)
    func openAddTransactionModal()
    func navigateToSettings()
}
