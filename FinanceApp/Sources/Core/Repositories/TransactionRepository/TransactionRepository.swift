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
    // 🔒 Use SecureLocalDataManager for UID-isolated data access ONLY
    let secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    // Return secure data filtered for UI display
    // NO fallback to SQLite - each user should only see their own data
    return secureTransactions.filter { transaction in
      // Filter out parent installment transactions - they should not be displayed in UI
      if transaction.hasInstallments == true {
        return false
      }
      // Filter out parent recurring transactions - they should not be displayed in UI
      // Only their instances (with parentTransactionId) should be shown
      if transaction.isRecurring == true {
        return false
      }
      return true
    }
  }

  func insertTransaction(_ transaction: TransactionModel) throws {
    // Insert to SQLite first
    let insertedId = try db.insertTransaction(transaction)

    // 🔒 Also save to SecureLocalDataManager for UID-isolated storage
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    // Convert TransactionModel to Transaction for secure storage
    let dbData = transaction.data
    let uiData = try UITransactionData(from: dbData)
    var newTransaction = Transaction(data: uiData)

    // Set the ID from SQLite insertion
    let updatedData = UITransactionData(
      id: insertedId,
      title: newTransaction.title,
      amount: newTransaction.amount,
      dateTimestamp: newTransaction.dateTimestamp,
      budgetMonthDate: newTransaction.budgetMonthDate,
      isRecurring: newTransaction.isRecurring,
      hasInstallments: newTransaction.hasInstallments,
      parentTransactionId: newTransaction.parentTransactionId,
      installmentNumber: newTransaction.installmentNumber,
      totalInstallments: newTransaction.totalInstallments,
      originalAmount: newTransaction.originalAmount,
      category: newTransaction.category,
      type: newTransaction.type
    )

    secureTransactions.append(Transaction(data: updatedData))
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)
  }

  func delete(id: Int) throws {
    // Delete from SQLite
    try db.deleteTransaction(id: id)

    // 🔒 Also delete from SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    secureTransactions.removeAll { $0.id == id }
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)
  }

  func fetchAllTransactions() -> [Transaction] {
    // Returns ALL transactions including parent transactions (for internal operations)
    // 🔒 Use SecureLocalDataManager for UID-isolated data access ONLY
    let secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    // NO fallback to SQLite - each user should only see their own data
    return secureTransactions
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
    // Insert to SQLite first
    let insertedId = try db.insertTransaction(transaction)

    // 🔒 Also save to SecureLocalDataManager for UID-isolated storage
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    // Convert TransactionModel to Transaction for secure storage
    let dbData = transaction.data
    let uiData = try UITransactionData(from: dbData)

    // Set the ID from SQLite insertion
    let updatedData = UITransactionData(
      id: insertedId,
      title: uiData.title,
      amount: uiData.amount,
      dateTimestamp: uiData.dateTimestamp,
      budgetMonthDate: uiData.budgetMonthDate,
      isRecurring: uiData.isRecurring,
      hasInstallments: uiData.hasInstallments,
      parentTransactionId: uiData.parentTransactionId,
      installmentNumber: uiData.installmentNumber,
      totalInstallments: uiData.totalInstallments,
      originalAmount: uiData.originalAmount,
      category: uiData.category,
      type: uiData.type
    )

    secureTransactions.append(Transaction(data: updatedData))
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)

    return insertedId
  }

  func updateParentTransactionId(transactionId: Int, parentId: Int) throws {
    // Update SQLite first
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)

    // 🔒 Also update SecureLocalDataManager for UID-isolated storage
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    // Find and update the specific transaction
    if let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) {
      let existingTransaction = secureTransactions[index]

      // Create updated transaction data with new parent ID
      let updatedData = UITransactionData(
        id: existingTransaction.id,
        title: existingTransaction.title,
        amount: existingTransaction.amount,
        dateTimestamp: existingTransaction.dateTimestamp,
        budgetMonthDate: existingTransaction.budgetMonthDate,
        isRecurring: existingTransaction.isRecurring,
        hasInstallments: existingTransaction.hasInstallments,
        parentTransactionId: parentId,  // ✅ Update the parent ID here
        installmentNumber: existingTransaction.installmentNumber,
        totalInstallments: existingTransaction.totalInstallments,
        originalAmount: existingTransaction.originalAmount,
        category: existingTransaction.category,
        type: existingTransaction.type
      )

      // Replace the transaction in the array
      secureTransactions[index] = Transaction(data: updatedData)

      // Save back to secure storage
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)

      print(
        "🔒 Updated parent transaction ID in secure storage: \(transactionId) -> parent: \(parentId)"
      )
    } else {
      print("⚠️ Could not find transaction \(transactionId) in secure storage to update parent ID")
    }
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
