//
//  Notification+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/06/25.
//

import Foundation

extension Notification.Name {
  static let transactionDataChanged = Notification.Name("transactionDataChanged")
  static let appDidEnterForeground = Notification.Name("appDidEnterForeground")
  static let navigateToTransactionDetails = Notification.Name("navigateToTransactionDetails")
  static let currencyDidChange = Notification.Name("currencyDidChange")
}
