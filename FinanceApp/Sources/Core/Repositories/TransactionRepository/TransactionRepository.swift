//
//  TransactionRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class TransactionRepository: TransactionRepositoryProtocol {
  private let db = DBHelper.shared

  func fetchTransactions() -> [Transaction] {
    return ((try? db.getTransactions()) ?? [])
      .filter { transaction in
        // Filter out parent installment transactions - they should not be displayed in UI
        if transaction.hasInstallments == true {
          return false
        }
        return true
      }
  }

  func insertTransaction(_ transaction: TransactionModel) throws {
    _ = try db.insertTransaction(transaction)
  }

  func delete(id: Int) throws {
    try db.deleteTransaction(id: id)
  }

  func fetchAllTransactions() -> [Transaction] {
    // Returns ALL transactions including parent transactions (for internal operations)
    return (try? db.getTransactions()) ?? []
  }

  func fetchParentInstallmentTransactions() -> [Transaction] {
    return ((try? db.getTransactions()) ?? [])
      .filter { $0.hasInstallments == true }
  }

  func fetchRecurringTransactions() -> [Transaction] {
    return fetchAllTransactions().filter { $0.isRecurring == true }
  }

  func fetchTransactionInstancesForRecurring(_ recurringId: Int) -> [Transaction] {
    return fetchAllTransactions().filter { $0.parentTransactionId == recurringId }
  }

  func fetchAllRecurringInstances() -> [Transaction] {
    return fetchAllTransactions().filter { $0.parentTransactionId != nil }
  }

  func insertTransactionAndGetId(_ transaction: TransactionModel) throws -> Int {
    return try db.insertTransaction(transaction)
  }

  func updateParentTransactionId(transactionId: Int, parentId: Int) throws {
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)
  }

  func deleteTransactionAndRelated(id: Int) throws {
    let allTransactions = fetchAllTransactions()
    guard let transaction = allTransactions.first(where: { $0.id == id }) else {
      throw TransactionError.transactionNotFound
    }

    if transaction.isRecurring == true {
      try deleteRecurringTransactionAndInstances(transactionId: id)
      return
    }

    if let parentId = transaction.parentTransactionId {
      try deleteInstallmentTransactionAndSiblings(parentId: parentId)
      return
    }

    if transaction.hasInstallments == true {
      try deleteInstallmentTransactionAndSiblings(parentId: id)
      return
    }

    try delete(id: id)
  }

  private func deleteRecurringTransactionAndInstances(transactionId: Int) throws {
    let allTransactions = fetchAllTransactions()

    let instances = allTransactions.filter { $0.parentTransactionId == transactionId }

    for instance in instances {
      if let instanceId = instance.id {
        try delete(id: instanceId)
      }
    }

    try delete(id: transactionId)
  }

  private func deleteInstallmentTransactionAndSiblings(parentId: Int) throws {
    let allTransactions = fetchAllTransactions()

    let installments = allTransactions.filter { $0.parentTransactionId == parentId }

    for installment in installments {
      if let installmentId = installment.id {
        try delete(id: installmentId)
      }
    }

    try delete(id: parentId)
  }

  func fetchInstallmentTransactions(parentId: Int) -> [Transaction] {
    return fetchAllTransactions().filter { $0.parentTransactionId == parentId }
  }

  // MARK: - Test Helper Methods
  func clearAllTransactionsForTesting() {
    let allTransactions = fetchAllTransactions()

    // Delete in multiple passes to handle parent/child relationships
    for _ in 0..<10 {  // Try up to 10 times
      let remainingTransactions = fetchAllTransactions()
      if remainingTransactions.isEmpty { break }

      for transaction in remainingTransactions {
        if let id = transaction.id {
          try? delete(id: id)
        }
      }
    }
  }
}
