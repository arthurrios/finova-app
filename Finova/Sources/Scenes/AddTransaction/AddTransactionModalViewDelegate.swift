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
  /// Defaulted so every existing construction site compiles unchanged.
  let businessDayRule: BusinessDayRule

  init(title: String, amount: Int, date: String, category: String, transactionType: String, creditCardId: Int? = nil, businessDayRule: BusinessDayRule = .exact) {
    self.title = title
    self.amount = amount
    self.date = date
    self.category = category
    self.transactionType = transactionType
    self.creditCardId = creditCardId
    self.businessDayRule = businessDayRule
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
  /// The rule every installment in the series is created with, and keeps.
  let businessDayRule: BusinessDayRule

  init(title: String, totalAmount: Int, date: String, category: String, transactionType: String, installments: Int, creditCardId: Int? = nil, businessDayRule: BusinessDayRule = .exact) {
    self.title = title
    self.totalAmount = totalAmount
    self.date = date
    self.category = category
    self.transactionType = transactionType
    self.installments = installments
    self.creditCardId = creditCardId
    self.businessDayRule = businessDayRule
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
  /// The view is a `UIView` and cannot present, so the picker is raised through the controller.
  func didRequestBusinessDayRulePicker(
    current: BusinessDayRule, completion: @escaping (BusinessDayRule) -> Void)
  func closeModal()
}
