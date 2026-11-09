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
  /// The debits that paid a statement. See `excludingStatementPayments`.
  func statementPaymentDebitIds() -> Set<Int>
  func insertTransaction(_ transaction: TransactionModel) throws
  func updateTransaction(_ transaction: TransactionModel) throws
  func updateTransactionDirectly(_ transaction: TransactionModel) throws
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

extension TransactionRepositoryProtocol {
  /// A stand-in repository with no database has no statement payments.
  func statementPaymentDebitIds() -> Set<Int> { [] }
}
