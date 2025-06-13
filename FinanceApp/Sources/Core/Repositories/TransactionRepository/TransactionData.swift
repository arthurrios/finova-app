//
//  TransactionRepresentable.swift
//  FinanceApp
//
//  Created by Arthur Rios on 06/06/25.
//

import Foundation

struct TransactionData<C, T> {
  let id: Int?
  let title: String
  let amount: Int
  let dateTimestamp: Int
  let budgetMonthDate: Int
  let isRecurring: Bool?
  let hasInstallments: Bool?
  let parentTransactionId: Int?
  let installmentNumber: Int?
  let totalInstallments: Int?
  let originalAmount: Int?

  let category: C
  let type: T
}

enum TransactionError: Error, Equatable {
  case invalidDateFormat
  case invalidCategory
  case invalidType
  case invalidInstallmentCount
  case databaseError
  case transactionNotFound
  case notARecurringTransaction
  case parentTransactionNotFound
  case concurrentModificationError
}
