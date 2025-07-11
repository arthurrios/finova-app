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
  func delete(id: Int) throws
}
