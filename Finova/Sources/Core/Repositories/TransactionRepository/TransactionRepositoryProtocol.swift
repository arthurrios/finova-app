//
//  TransactionRepositoryProtocol.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

protocol TransactionRepositoryProtocol {
  func fetchTransactions() -> [Transaction]
  func fetchAllTransactions() -> [Transaction]
  func fetchParentInstallmentTransactions() -> [Transaction]
  func insertTransaction(_ transaction: TransactionModel) throws
  func updateTransaction(_ transaction: TransactionModel) throws
  func updateSingleTransactionOnly(
    id: Int,
    title: String,
    category: TransactionCategory,
    type: TransactionType,
    amount: Int,
    date: Date
  ) throws
  func updateTransactionParentId(transactionId: Int, parentId: Int) throws
  func delete(id: Int) throws
  func deleteTransactionAndRelated(id: Int) throws
  func deleteTransactionWithOption(id: Int, option: RecurringCleanupOption) throws
}
