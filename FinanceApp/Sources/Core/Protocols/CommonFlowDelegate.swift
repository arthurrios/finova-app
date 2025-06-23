//
//  CommonFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 25/06/25.
//

import Foundation

/// Shared protocol for common navigation actions across different flows
public protocol CommonFlowDelegate: AnyObject {
  func navigateToDashboard()
}
