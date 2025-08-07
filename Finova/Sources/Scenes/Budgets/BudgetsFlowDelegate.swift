//
//  BudgetsFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation

public protocol BudgetsFlowDelegate: AnyObject {
    func navBackToDashboard()
    func budgetsDidAppear()
}
