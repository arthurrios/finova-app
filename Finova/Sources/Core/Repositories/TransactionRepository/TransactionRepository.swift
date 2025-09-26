//
//  TransactionRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UserNotifications

final class TransactionRepository: TransactionRepositoryProtocol {
  private let db = DBHelper.shared

  func fetchTransactions() -> [Transaction] {
    // Return all transactions that should be visible in the UI
    let allTransactions = fetchAllTransactions()

    let filteredTransactions = allTransactions.filter { transaction in
      // Show all transaction instances (including recurring instances)
      // Hide only the parent recurring/installment transactions
      if transaction.isRecurring == true && transaction.parentTransactionId == nil {
        return false  // Hide parent recurring transaction
      }
      if transaction.hasInstallments == true && transaction.parentTransactionId == nil {
        return false  // Hide parent installment transaction
      }
      return true
    }

    return filteredTransactions
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

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func delete(id: Int) throws {
    // Delete from SQLite
    try db.deleteTransaction(id: id)

    // 🔒 Also delete from SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    secureTransactions.removeAll { $0.id == id }
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
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
    return fetchAllTransactions().filter {
      $0.parentTransactionId == recurringId && $0.id != recurringId
    }
  }

  func fetchAllRecurringInstances() -> [Transaction] {
    return fetchAllTransactions().filter { $0.parentTransactionId != nil }
  }

  // MARK: - Debug Methods

  /// Debug method to check for duplicate transactions in the same month
  func debugDuplicateTransactions() {
    let allTransactions = fetchAllTransactions()
    let transactionsByMonth = Dictionary(grouping: allTransactions) { $0.budgetMonthDate }

    print("🔍 Debug: Checking for duplicate transactions by month...")

    for (monthAnchor, transactions) in transactionsByMonth {
      if transactions.count > 1 {
        let date = Date(timeIntervalSince1970: TimeInterval(monthAnchor))
        print("⚠️ Month \(date): Found \(transactions.count) transactions:")

        for tx in transactions {
          let isParent = tx.isRecurring == true && tx.parentTransactionId == nil
          let isInstance = tx.parentTransactionId != nil
          let type = isParent ? "PARENT" : (isInstance ? "INSTANCE" : "REGULAR")

          print("   - \(tx.title) (ID: \(tx.id ?? -1), Type: \(type), Amount: \(tx.amount))")
        }
      }
    }
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

  func updateTransactionDirectly(_ transaction: TransactionModel) throws {
    print("🔧 DEBUG: updateTransactionDirectly called for transaction \(transaction.data.id ?? -1)")
    print(
      "🔧 DEBUG: Transaction data - title: '\(transaction.data.title)', amount: \(transaction.data.amount), dateTimestamp: \(transaction.data.dateTimestamp), budgetMonthDate: \(transaction.data.budgetMonthDate)"
    )
    print("🔧 DEBUG: Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")

    // Update SQLite directly
    try db.updateTransaction(transaction)
    print("🔧 DEBUG: SQLite update completed")

    // Also update SecureLocalDataManager to keep it in sync
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    print("🔧 DEBUG: Loaded \(secureTransactions.count) transactions from SecureLocalDataManager")

    // Debug: Log all transactions to see what we have
    for (idx, tx) in secureTransactions.enumerated() {
      if idx < 5 {  // Only log first 5 to avoid spam
        print(
          "🔧 DEBUG: Transaction \(idx): ID=\(tx.id ?? -1), Title='\(tx.title)', Category=\(tx.category)"
        )
      }
    }

    if let index = secureTransactions.firstIndex(where: { $0.id == transaction.data.id }) {
      let existingTransaction = secureTransactions[index]
      print("🔧 DEBUG: Found existing transaction at index \(index)")
      print(
        "🔧 DEBUG: Existing transaction - ID: \(existingTransaction.id ?? -1), Title: '\(existingTransaction.title)', Category: \(existingTransaction.category)"
      )

      // Debug the input values
      print(
        "🔧 DEBUG: Input values - title: '\(transaction.data.title)', category: '\(transaction.data.category)', type: '\(transaction.data.type)'"
      )

      // Convert string category and type to enum values
      let categoryEnum =
        TransactionCategory.allCases.first(where: { $0.key == transaction.data.category })
        ?? .miscellaneous
      let typeEnum =
        TransactionType.allCases.first(where: { String(describing: $0) == transaction.data.type })
        ?? .expense

      print("🔧 DEBUG: About to create updatedData with:")
      print("🔧 DEBUG: - id: \(existingTransaction.id ?? -1)")
      print("🔧 DEBUG: - title:  '\(transaction.data.title)'")
      print("🔧 DEBUG: - amount: \(transaction.data.amount)")
      print("🔧 DEBUG: - dateTimestamp: \(transaction.data.dateTimestamp)")
      print("🔧 DEBUG: - budgetMonthDate: \(transaction.data.budgetMonthDate)")
      print("🔧 DEBUG: - category: \(categoryEnum)")
      print("🔧 DEBUG: - type: \(typeEnum)")

      let updatedData = UITransactionData(
        id: existingTransaction.id,
        title: transaction.data.title,
        amount: transaction.data.amount,
        dateTimestamp: transaction.data.dateTimestamp,
        budgetMonthDate: transaction.data.budgetMonthDate,
        isRecurring: existingTransaction.isRecurring,
        hasInstallments: existingTransaction.hasInstallments,
        parentTransactionId: existingTransaction.parentTransactionId,
        installmentNumber: existingTransaction.installmentNumber,
        totalInstallments: existingTransaction.totalInstallments,
        originalAmount: existingTransaction.originalAmount,
        category: categoryEnum,
        type: typeEnum
      )

      print(
        "🔧 DEBUG: Created UITransactionData - title: '\(updatedData.title)', category: \(updatedData.category), type: \(updatedData.type)"
      )

      // Debug: Check what we're about to save
      let transactionToSave = Transaction(data: updatedData)
      print(
        "🔧 DEBUG: Transaction to save - title: '\(transactionToSave.title)', category: \(transactionToSave.category), type: \(transactionToSave.type)"
      )

      secureTransactions[index] = transactionToSave
      print("🔧 DEBUG: Updated transaction at index \(index)")
      print(
        "🔧 DEBUG: Updated transaction - ID: \(secureTransactions[index].id ?? -1), Title: '\(secureTransactions[index].title)', Category: \(secureTransactions[index].category)"
      )
      print(
        "🔧 DEBUG: About to save \(secureTransactions.count) transactions to SecureLocalDataManager")

      SecureLocalDataManager.shared.saveTransactions(secureTransactions)
      print("🔧 DEBUG: SecureLocalDataManager update completed")
    } else {
      print(
        "❌ DEBUG: Transaction \(transaction.data.id ?? -1) NOT FOUND in SecureLocalDataManager!")
    }

    // Reschedule notification for the updated transaction
    rescheduleNotificationForTransaction(transactionId: transaction.data.id)

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
    print("🔧 DEBUG: Cache invalidation notification sent")
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

  func updateTransaction(_ transaction: TransactionModel) throws {
    print("🔧 DEBUG: updateTransaction called for transaction \(transaction.data.id ?? -1)")
    print(
      "🔧 DEBUG: Transaction data - title: '\(transaction.data.title)', category: '\(transaction.data.category)', type: '\(transaction.data.type)'"
    )
    print("🔧 DEBUG: Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")

    // Update all related transactions (for recurring/installments)

    // First, find the transaction to determine its type
    let existingTransactions = SecureLocalDataManager.shared.loadTransactions()
    guard
      let existingTransaction = existingTransactions.first(where: { $0.id == transaction.data.id })
    else {
      print("❌ DEBUG: Transaction not found in SecureLocalDataManager")
      throw TransactionError.transactionNotFound
    }

    print(
      "🔧 DEBUG: Found existing transaction - isRecurring: \(existingTransaction.isRecurring ?? false), hasInstallments: \(existingTransaction.hasInstallments ?? false)"
    )

    if existingTransaction.isRecurring == true {
      print("🔧 DEBUG: Taking recurring path")
      // Update all recurring instances
      try updateAllRecurringTransactions(
        templateTransaction: transaction, existingTransaction: existingTransaction)
    } else if existingTransaction.hasInstallments == true {
      print("🔧 DEBUG: Taking installment path")
      // Update all installment instances
      try updateAllInstallmentTransactions(
        templateTransaction: transaction, existingTransaction: existingTransaction)
    } else {
      print("🔧 DEBUG: Taking normal transaction path - calling updateTransactionDirectly")
      // Normal transaction - use updateTransactionDirectly to avoid conflicts
      try updateTransactionDirectly(transaction)
    }
  }

  private func updateAllRecurringTransactions(
    templateTransaction: TransactionModel, existingTransaction: Transaction
  ) throws {
    // Find all transactions with the same recurring group
    let recurringGroupId = existingTransaction.parentTransactionId ?? existingTransaction.id
    let allTransactions = SecureLocalDataManager.shared.loadTransactions()
    let relatedTransactions = allTransactions.filter { transaction in
      transaction.id == recurringGroupId || transaction.parentTransactionId == recurringGroupId
    }

    // Get the new date from the template (this represents the new recurring day)
    let newDate = Date(timeIntervalSince1970: TimeInterval(templateTransaction.data.dateTimestamp))
    let newDay = Calendar.current.component(.day, from: newDate)

    print("🔄 RECURRING UPDATE: Updating all recurring transactions to day \(newDay) of each month")

    // Update each related transaction
    for relatedTransaction in relatedTransactions {
      // Calculate the correct date for this transaction's month
      let originalDate = Date(timeIntervalSince1970: TimeInterval(relatedTransaction.dateTimestamp))
      let originalMonth = Calendar.current.component(.month, from: originalDate)
      let originalYear = Calendar.current.component(.year, from: originalDate)

      // Create a new date with the same month/year but the new day
      var dateComponents = DateComponents()
      dateComponents.year = originalYear
      dateComponents.month = originalMonth
      dateComponents.day = newDay

      // Handle cases where the new day doesn't exist in the month (e.g., Feb 30)
      let calendar = Calendar.current
      let adjustedDate: Date
      if let newDateForMonth = calendar.date(from: dateComponents) {
        adjustedDate = newDateForMonth
      } else {
        // If the day doesn't exist in this month, use the last day of the month
        let lastDayOfMonth =
          calendar.range(of: .day, in: .month, for: originalDate)?.upperBound ?? 1
        dateComponents.day = lastDayOfMonth - 1
        adjustedDate = calendar.date(from: dateComponents) ?? originalDate
        print(
          "⚠️ Day \(newDay) doesn't exist in month \(originalMonth), using day \(lastDayOfMonth - 1)"
        )
      }

      print(
        "🔄 Updating transaction \(relatedTransaction.id ?? 0) from \(originalDate) to \(adjustedDate)"
      )

      try updateSingleTransactionOnly(
        id: relatedTransaction.id!,
        title: templateTransaction.data.title,
        category: TransactionCategory.allCases.first(where: {
          $0.key == templateTransaction.data.category
        }) ?? .miscellaneous,
        type: TransactionType.allCases.first(where: {
          String(describing: $0) == templateTransaction.data.type
        }) ?? .expense,
        amount: templateTransaction.data.amount,
        date: adjustedDate
      )

      // Reschedule notification for this updated transaction
      rescheduleNotificationForTransaction(transactionId: relatedTransaction.id)
    }
  }

  private func updateAllInstallmentTransactions(
    templateTransaction: TransactionModel, existingTransaction: Transaction
  ) throws {
    // HYBRID APPROACH: Recreate entire installment series with new parameters
    // This ensures data integrity and provides intuitive UX

    let newDate = Date(timeIntervalSince1970: TimeInterval(templateTransaction.data.dateTimestamp))
    let newTotalAmount = templateTransaction.data.amount
    let newNumberOfInstallments = templateTransaction.data.totalInstallments ?? 1

    print("🔄 INSTALLMENT UPDATE: Recreating series with:")
    print("   - Total Amount: \(newTotalAmount)")
    print("   - Number of Installments: \(newNumberOfInstallments)")
    print("   - Initial Date: \(newDate)")

    // Find the main installment transaction (the one being edited)
    let allTransactions = SecureLocalDataManager.shared.loadTransactions()

    // Determine the correct main installment transaction ID
    let mainInstallmentTransactionId: Int
    if let parentId = existingTransaction.parentTransactionId {
      // This is an individual installment, find the main installment transaction
      if let mainTransaction = allTransactions.first(where: {
        $0.hasInstallments == true && $0.parentTransactionId == nil && $0.id == parentId
      }) {
        mainInstallmentTransactionId = parentId
      } else {
        // Try fallback: find any main installment transaction in the same month
        let individualInstallmentMonth = existingTransaction.budgetMonthDate
        if let fallbackMainTransaction = allTransactions.first(where: {
          $0.hasInstallments == true && $0.parentTransactionId == nil
            && $0.budgetMonthDate == individualInstallmentMonth && $0.amount == 0
        }) {
          mainInstallmentTransactionId = fallbackMainTransaction.id ?? 0
        } else {
          mainInstallmentTransactionId = parentId  // Use original parent ID as fallback
        }
      }
    } else {
      // This is already the main installment transaction
      mainInstallmentTransactionId = existingTransaction.id ?? 0
    }

    print("   - Main installment transaction ID: \(mainInstallmentTransactionId)")

    let relatedTransactions = allTransactions.filter { transaction in
      transaction.id == mainInstallmentTransactionId
        || transaction.parentTransactionId == mainInstallmentTransactionId
    }

    // Calculate individual installment amount (total divided by number of installments)
    let individualAmount = newTotalAmount / newNumberOfInstallments

    print("   - Individual Amount: \(individualAmount)")

    // Delete all existing related transactions first
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        print("   - Deleting old installment: \(id)")
        try delete(id: id)
      }
    }

    // Create new installment series
    let calendar = Calendar.current
    let startDate = newDate

    for i in 0..<newNumberOfInstallments {
      // Calculate date for this installment (add i months to start date)
      let installmentDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate

      // Create new installment transaction
      let installmentData = UITransactionData(
        id: nil,  // Will be assigned by database
        title: templateTransaction.data.title,
        amount: individualAmount,
        dateTimestamp: Int(installmentDate.timeIntervalSince1970),
        budgetMonthDate: installmentDate.monthAnchor,
        isRecurring: false,
        hasInstallments: true,
        parentTransactionId: mainInstallmentTransactionId,
        installmentNumber: i + 1,
        totalInstallments: newNumberOfInstallments,
        originalAmount: nil,
        category: TransactionCategory.allCases.first(where: {
          $0.key == templateTransaction.data.category
        }) ?? .miscellaneous,
        type: TransactionType.allCases.first(where: {
          String(describing: $0) == templateTransaction.data.type
        }) ?? .expense
      )

      let installmentTransaction = Transaction(data: installmentData)

      // Save the new installment
      let installmentModel = TransactionModel(
        id: nil,
        title: installmentTransaction.title,
        category: installmentTransaction.category.key,
        amount: installmentTransaction.amount,
        type: String(describing: installmentTransaction.type),
        dateTimestamp: Int(installmentTransaction.date.timeIntervalSince1970),
        budgetMonthDate: installmentTransaction.budgetMonthDate,
        isRecurring: false,
        hasInstallments: true,
        parentTransactionId: mainInstallmentTransactionId,
        originalAmount: nil,
        installmentNumber: i + 1,
        totalInstallments: newNumberOfInstallments
      )

      do {
        try insertTransaction(installmentModel)
        print(
          "   - Created installment \(i + 1)/\(newNumberOfInstallments): \(installmentDate) - \(individualAmount) - monthAnchor: \(installmentDate.monthAnchor)"
        )
      } catch {
        print("❌ Failed to create installment \(i + 1): \(error)")
        throw error
      }
    }

    print("✅ INSTALLMENT UPDATE: Series recreated successfully")
  }

  func updateSingleTransactionOnly(
    id: Int,
    title: String,
    category: TransactionCategory,
    type: TransactionType,
    amount: Int,
    date: Date
  ) throws {
    // Create a transaction model with only the fields we want to update
    let updatedTransaction = TransactionModel(
      id: id,
      title: title,
      category: category.key,
      amount: amount,
      type: String(describing: type),
      dateTimestamp: Int(date.timeIntervalSince1970),
      budgetMonthDate: date.monthAnchor,
      isRecurring: false,  // Keep existing values - this will be handled by DB
      hasInstallments: false,  // Keep existing values - this will be handled by DB
      parentTransactionId: nil,  // Keep existing values
      originalAmount: amount,
      installmentNumber: nil,  // Keep existing values
      totalInstallments: nil  // Keep existing values
    )

    // Update SQLite with partial update
    try db.updateSingleTransaction(updatedTransaction)

    // 🔒 Also update SecureLocalDataManager for UID-isolated storage
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    // Find and update only the specific transaction
    if let index = secureTransactions.firstIndex(where: { $0.id == id }) {
      let existingTransaction = secureTransactions[index]

      // Create new UITransactionData with updated fields
      let updatedData = UITransactionData(
        id: existingTransaction.id,
        title: title,
        amount: amount,
        dateTimestamp: Int(date.timeIntervalSince1970),
        budgetMonthDate: date.monthAnchor,
        isRecurring: existingTransaction.isRecurring,
        hasInstallments: existingTransaction.hasInstallments,
        parentTransactionId: existingTransaction.parentTransactionId,
        installmentNumber: existingTransaction.installmentNumber,
        totalInstallments: existingTransaction.totalInstallments,
        originalAmount: existingTransaction.originalAmount,
        category: category,
        type: type
      )

      // Create new Transaction instance
      let updatedTransaction = Transaction(data: updatedData)
      secureTransactions[index] = updatedTransaction
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)

      print("🔒 Updated single transaction in secure storage: \(title)")

      // Reschedule notification for the updated transaction
      rescheduleNotificationForTransaction(transactionId: id)
    } else {
      print("⚠️ Could not find transaction \(id) in secure storage to update")
    }
  }

  func updateTransactionParentId(transactionId: Int, parentId: Int) throws {
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)

    // Also update SecureLocalDataManager for UID-isolated storage
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    if let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) {
      let existingTransaction = secureTransactions[index]

      // Create new UITransactionData with updated parent ID
      let updatedData = UITransactionData(
        id: existingTransaction.id,
        title: existingTransaction.title,
        amount: existingTransaction.amount,
        dateTimestamp: existingTransaction.dateTimestamp,
        budgetMonthDate: existingTransaction.budgetMonthDate,
        isRecurring: existingTransaction.isRecurring,
        hasInstallments: existingTransaction.hasInstallments,
        parentTransactionId: parentId,
        installmentNumber: existingTransaction.installmentNumber,
        totalInstallments: existingTransaction.totalInstallments,
        originalAmount: existingTransaction.originalAmount,
        category: existingTransaction.category,
        type: existingTransaction.type
      )

      // Create new Transaction instance
      let updatedTransaction = Transaction(data: updatedData)
      secureTransactions[index] = updatedTransaction
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)

      print("🔒 Updated transaction \(transactionId) parent ID to \(parentId) in secure storage")
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

  func deleteTransactionWithOption(id: Int, option: RecurringCleanupOption) throws {
    let transaction = fetchAllTransactions().first { $0.id == id }

    guard let transaction = transaction else {
      throw TransactionError.transactionNotFound
    }

    switch option {
    case .currentSelection:
      // Delete only the current transaction instance
      try delete(id: id)

    case .futureOnly:
      // For recurring transactions, delete future instances only
      if transaction.isRecurring == true {
        try deleteFutureRecurringInstances(transactionId: id)
      } else {
        // For non-recurring, just delete current
        try delete(id: id)
      }

    case .all:
      // Delete all related transactions
      if transaction.isRecurring == true {
        try deleteAllRecurringTransactionOccurrences(transactionId: id)
      } else if transaction.mode == .installments {
        try deleteInstallmentTransactionAndSiblings(parentId: id)
      } else {
        try delete(id: id)
      }
    }
  }

  private func deleteRecurringTransactionAndInstances(transactionId: Int) throws {
    // For recurring transactions, only delete the current instance
    // Do not delete all future instances as that would be destructive
    try delete(id: transactionId)
  }

  private func deleteAllRecurringTransactionOccurrences(transactionId: Int) throws {
    // Find all transactions with the same recurring group
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    // Get the recurring group ID (either the transaction's own ID or its parentTransactionId)
    let recurringGroupId = current.parentTransactionId ?? current.id

    // Find all related transactions in this recurring group
    let relatedTransactions = allTransactions.filter { transaction in
      transaction.id == recurringGroupId || transaction.parentTransactionId == recurringGroupId
    }

    print(
      "🔄 RECURRING DELETE: Deleting \(relatedTransactions.count) occurrences of recurring transaction group \(recurringGroupId ?? 0)"
    )

    // Delete all related transactions
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
        print("   - Deleted transaction \(id): \(relatedTransaction.title)")
      }
    }

    print("✅ RECURRING DELETE: All occurrences deleted successfully")
  }

  private func deleteFutureRecurringInstances(transactionId: Int) throws {
    // Find all transactions with the same recurring group
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    // Get the recurring group ID (either the transaction's own ID or its parentTransactionId)
    let recurringGroupId = current.parentTransactionId ?? current.id
    let currentDate = current.date

    // Find all related transactions in this recurring group that are in the future
    let relatedTransactions = allTransactions.filter { transaction in
      let isInGroup =
        transaction.id == recurringGroupId || transaction.parentTransactionId == recurringGroupId
      let isInFuture = transaction.date > currentDate
      return isInGroup && isInFuture
    }

    print(
      "🔄 RECURRING DELETE: Deleting \(relatedTransactions.count) future occurrences of recurring transaction group \(recurringGroupId ?? 0)"
    )

    // Delete all future related transactions
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
        print("   - Deleted future transaction \(id): \(relatedTransaction.title)")
      }
    }

    print("✅ RECURRING DELETE: Future occurrences deleted successfully")
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

  // MARK: - Notification Management

  /// Reschedules notification for a specific transaction after it has been updated
  private func rescheduleNotificationForTransaction(transactionId: Int?) {
    guard let transactionId = transactionId else { return }

    print("🔔 Rescheduling notification for transaction \(transactionId)")

    // Remove existing notification for this transaction
    let notificationId = "transaction_\(transactionId)"
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
      notificationId
    ])
    print("🔔 🧹 Removed existing notification for transaction \(transactionId)")

    // Get the updated transaction data
    let allTransactions = fetchAllTransactions()
    guard let updatedTransaction = allTransactions.first(where: { $0.id == transactionId }) else {
      print("🔔 ❌ Could not find updated transaction \(transactionId) for notification rescheduling")
      return
    }

    // Schedule new notification using the same logic as AppDelegate
    scheduleNotificationForTransaction(updatedTransaction)
  }

  /// Schedules a notification for a single transaction (reused from AppDelegate logic)
  private func scheduleNotificationForTransaction(_ tx: Transaction) {
    guard let transactionId = tx.id else { return }

    let id = "transaction_\(transactionId)"
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > now else {
      print("🔔 ⚠️ Skipping notification for \(tx.title) - date is in the past")
      return
    }

    // Check if date is too far in the future (more than 1 year)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if tx.date > oneYearFromNow {
      print("🔔 ⚠️ Skipping notification for \(tx.title) - date too far in future")
      return
    }

    // Calculate time interval from now to notification date
    let timeInterval = notificationDate.timeIntervalSinceNow

    // Check if interval is too large (more than 30 days)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      print("🔔 ⚠️ Skipping notification for \(tx.title) - more than 30 days away")
      return
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

    let titleKey =
      tx.type == .income
      ? "notification.transaction.title.income"
      : "notification.transaction.title.expense"
    let bodyKey =
      tx.type == .income
      ? "notification.transaction.body.income"
      : "notification.transaction.body.expense"

    let amountString = tx.amount.currencyString
    let title = titleKey.localized
    let body = String(format: bodyKey.localized, amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["transactionId": transactionId, "date": tx.date.timeIntervalSince1970]

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("🔔 ❌ Error rescheduling notification for \(tx.title): \(error)")
      } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        print(
          "🔔 ✅ Rescheduled notification for \(tx.title) at \(formatter.string(from: notificationDate))"
        )
      }
    }
  }
}
