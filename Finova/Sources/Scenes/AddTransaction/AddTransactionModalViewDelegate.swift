//
//  AddTransactionViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

public struct AddTransactionData {
  let title: String
  let amount: Int
  let date: String
  let category: String
  let transactionType: String
}

public struct InstallmentTransactionData {
  let title: String
  let totalAmount: Int
  let date: String
  let category: String
  let transactionType: String
  let installments: Int
}

public protocol AddTransactionModalViewDelegate: AnyObject {
  func handleError(title: String, message: String)
  func sendTransactionData(_ data: AddTransactionData)
  func sendRecurringTransactionData(_ data: AddTransactionData)
  func sendInstallmentTransactionData(_ data: InstallmentTransactionData)
  func closeModal()
}
