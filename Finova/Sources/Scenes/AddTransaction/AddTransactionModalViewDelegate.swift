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

protocol AddTransactionModalViewDelegate: AnyObject {
  func handleError(title: String, message: String)
  func sendTransactionData(_ data: AddTransactionData)
  func sendRecurringTransactionData(_ data: AddTransactionData)
  func sendInstallmentTransactionData(_ data: InstallmentTransactionData)
  func updateTransactionData(id: Int, _ data: AddTransactionData)
  func updateRecurringTransactionData(id: Int, _ data: AddTransactionData)
  func updateInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData)
  func updateSingleRecurringTransactionData(id: Int, _ data: AddTransactionData)
  func updateSingleInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData)
  func updateRecurringTransactionDataWithOption(
    id: Int, _ data: AddTransactionData, editOption: RecurringEditOption)
  func closeModal()
}
