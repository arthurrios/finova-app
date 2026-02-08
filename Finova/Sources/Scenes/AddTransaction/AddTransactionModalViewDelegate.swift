//
//  AddTransactionViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

enum PaymentMethod: Equatable {
  case cashDebit
  case creditCard(cardId: Int)
}

public struct AddTransactionData {
  let title: String
  let amount: Int
  let date: String
  let category: String
  let transactionType: String
  let creditCardId: Int?

  init(title: String, amount: Int, date: String, category: String, transactionType: String, creditCardId: Int? = nil) {
    self.title = title
    self.amount = amount
    self.date = date
    self.category = category
    self.transactionType = transactionType
    self.creditCardId = creditCardId
  }
}

public struct InstallmentTransactionData {
  let title: String
  let totalAmount: Int
  let date: String
  let category: String
  let transactionType: String
  let installments: Int
  let creditCardId: Int?

  init(title: String, totalAmount: Int, date: String, category: String, transactionType: String, installments: Int, creditCardId: Int? = nil) {
    self.title = title
    self.totalAmount = totalAmount
    self.date = date
    self.category = category
    self.transactionType = transactionType
    self.installments = installments
    self.creditCardId = creditCardId
  }
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
  func didTapCreateCreditCard()
  func closeModal()
}
