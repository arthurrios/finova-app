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

  // MARK: - In-Memory Cache
  private static var cachedTransactions: [Transaction]?
  private static var cacheUserUID: String?

  static func invalidateCache() {
    cachedTransactions = nil
    cacheUserUID = nil
  }

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
    Self.invalidateCache()
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
      creditCardId: newTransaction.creditCardId,
      statementId: newTransaction.statementId,
      isCreditCardStatement: newTransaction.isCreditCardStatement,
      category: newTransaction.category,
      type: newTransaction.type
    )

    secureTransactions.append(Transaction(data: updatedData))
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func delete(id: Int) throws {
    Self.invalidateCache()
    logDebug("TransactionRepository: Deleting transaction with id \(id)")

    // Delete from SQLite
    try db.deleteTransaction(id: id)

    // 🔒 Also delete from SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    let countBefore = secureTransactions.count

    // Explicitly unwrap optional ID for comparison
    secureTransactions.removeAll { transaction in
      guard let transactionId = transaction.id else { return false }
      return transactionId == id
    }

    let countAfter = secureTransactions.count
    logDebug("TransactionRepository: Removed \(countBefore - countAfter) transactions from SecureLocalDataManager")

    SecureLocalDataManager.shared.saveTransactions(secureTransactions)

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func fetchAllTransactions() -> [Transaction] {
    // Returns ALL transactions including parent transactions (for internal operations)
    // 🔒 Use SecureLocalDataManager for UID-isolated data access ONLY
    let currentUID = AuthenticationManager.shared.currentUser?.uid

    if let cached = Self.cachedTransactions, Self.cacheUserUID == currentUID {
      return cached
    }

    let secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    Self.cachedTransactions = secureTransactions
    Self.cacheUserUID = currentUID

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

  // MARK: - Credit Card Fields

  func updateCreditCardFields(transactionId: Int, creditCardId: Int, statementId: Int, isCreditCardStatement: Bool) throws {
    Self.invalidateCache()
    try db.updateTransactionCreditCardFields(
      transactionId: transactionId,
      creditCardId: creditCardId,
      statementId: statementId,
      isCreditCardStatement: isCreditCardStatement
    )

    // Also update SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    if let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) {
      let existing = secureTransactions[index]
      let updatedData = UITransactionData(
        id: existing.id,
        title: existing.title,
        amount: existing.amount,
        dateTimestamp: existing.dateTimestamp,
        budgetMonthDate: existing.budgetMonthDate,
        isRecurring: existing.isRecurring,
        hasInstallments: existing.hasInstallments,
        parentTransactionId: existing.parentTransactionId,
        installmentNumber: existing.installmentNumber,
        totalInstallments: existing.totalInstallments,
        originalAmount: existing.originalAmount,
        creditCardId: creditCardId,
        statementId: statementId,
        isCreditCardStatement: isCreditCardStatement,
        category: existing.category,
        type: existing.type
      )
      secureTransactions[index] = Transaction(data: updatedData)
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)
    }
  }

  func clearCreditCardFields(transactionId: Int) throws {
    Self.invalidateCache()
    try db.clearTransactionCreditCardFields(transactionId: transactionId)

    // Also update SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    if let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) {
      let existing = secureTransactions[index]
      let updatedData = UITransactionData(
        id: existing.id,
        title: existing.title,
        amount: existing.amount,
        dateTimestamp: existing.dateTimestamp,
        budgetMonthDate: existing.budgetMonthDate,
        isRecurring: existing.isRecurring,
        hasInstallments: existing.hasInstallments,
        parentTransactionId: existing.parentTransactionId,
        installmentNumber: existing.installmentNumber,
        totalInstallments: existing.totalInstallments,
        originalAmount: existing.originalAmount,
        creditCardId: nil,
        statementId: nil,
        isCreditCardStatement: nil,
        category: existing.category,
        type: existing.type
      )
      secureTransactions[index] = Transaction(data: updatedData)
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)
    }
  }

  // MARK: - Debug Methods

  /// Debug method to check for duplicate transactions in the same month
  func debugDuplicateTransactions() {
    // No-op in production
  }

  func insertTransactionAndGetId(_ transaction: TransactionModel) throws -> Int {
    Self.invalidateCache()
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
      creditCardId: uiData.creditCardId,
      statementId: uiData.statementId,
      isCreditCardStatement: uiData.isCreditCardStatement,
      category: uiData.category,
      type: uiData.type
    )

    secureTransactions.append(Transaction(data: updatedData))
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)

    return insertedId
  }

  func updateTransactionDirectly(_ transaction: TransactionModel) throws {
    Self.invalidateCache()
    // Update SQLite directly
    try db.updateTransaction(transaction)

    // Also update SecureLocalDataManager to keep it in sync
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    if let index = secureTransactions.firstIndex(where: { $0.id == transaction.data.id }) {
      let existingTransaction = secureTransactions[index]

      // Convert string category and type to enum values
      let categoryEnum =
        TransactionCategory.allCases.first(where: { $0.key == transaction.data.category })
        ?? .miscellaneous
      let typeEnum =
        TransactionType.allCases.first(where: { String(describing: $0) == transaction.data.type })
        ?? .expense

      // Use the model's credit card fields directly — the caller (ViewModel) is
      // responsible for setting them correctly, including nil when clearing a card.
      let finalCreditCardId = transaction.data.creditCardId
      let finalStatementId = transaction.data.statementId
      let finalIsCreditCardStatement = transaction.data.isCreditCardStatement

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
        creditCardId: finalCreditCardId,
        statementId: finalStatementId,
        isCreditCardStatement: finalIsCreditCardStatement,
        category: categoryEnum,
        type: typeEnum
      )

      let transactionToSave = Transaction(data: updatedData)
      secureTransactions[index] = transactionToSave

      SecureLocalDataManager.shared.saveTransactions(secureTransactions)
    } else {
      logError("Transaction \(transaction.data.id ?? -1) NOT FOUND in SecureLocalDataManager")
    }

    // Reschedule notification for the updated transaction
    rescheduleNotificationForTransaction(transactionId: transaction.data.id)

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func updateParentTransactionId(transactionId: Int, parentId: Int) throws {
    Self.invalidateCache()
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

    }
  }

  func updateTransaction(_ transaction: TransactionModel) throws {
    // Update all related transactions (for recurring/installments)

    // First, find the transaction to determine its type
    let existingTransactions = SecureLocalDataManager.shared.loadTransactions()
    guard
      let existingTransaction = existingTransactions.first(where: { $0.id == transaction.data.id })
    else {
      throw TransactionError.transactionNotFound
    }

    if existingTransaction.isRecurring == true {
      // Update all recurring instances
      try updateAllRecurringTransactions(
        templateTransaction: transaction, existingTransaction: existingTransaction)
    } else if existingTransaction.hasInstallments == true {
      // Update all installment instances
      try updateAllInstallmentTransactions(
        templateTransaction: transaction, existingTransaction: existingTransaction)
    } else {
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
    let calendar = Calendar.current
    let newDate = Date(timeIntervalSince1970: TimeInterval(templateTransaction.data.dateTimestamp))
    let newDay = calendar.component(.day, from: newDate)

    // Update each related transaction
    for relatedTransaction in relatedTransactions {
      // Calculate the correct date for this transaction's month
      let originalDate = Date(timeIntervalSince1970: TimeInterval(relatedTransaction.dateTimestamp))
      let originalMonth = calendar.component(.month, from: originalDate)
      let originalYear = calendar.component(.year, from: originalDate)

      // Create a new date with the same month/year but the new day
      var dateComponents = DateComponents()
      dateComponents.year = originalYear
      dateComponents.month = originalMonth
      dateComponents.day = newDay

      // Handle cases where the new day doesn't exist in the month (e.g., Feb 30)
      let adjustedDate: Date
      if let newDateForMonth = calendar.date(from: dateComponents) {
        adjustedDate = newDateForMonth
      } else {
        // If the day doesn't exist in this month, use the last day of the month
        let lastDayOfMonth =
          calendar.range(of: .day, in: .month, for: originalDate)?.upperBound ?? 1
        dateComponents.day = lastDayOfMonth - 1
        adjustedDate = calendar.date(from: dateComponents) ?? originalDate
      }

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

    let calendar = Calendar.current
    let newDate = Date(timeIntervalSince1970: TimeInterval(templateTransaction.data.dateTimestamp))
    let newTotalAmount = templateTransaction.data.amount
    let newNumberOfInstallments = templateTransaction.data.totalInstallments ?? 1

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

    let relatedTransactions = allTransactions.filter { transaction in
      transaction.id == mainInstallmentTransactionId
        || transaction.parentTransactionId == mainInstallmentTransactionId
    }

    // Calculate individual installment amount (total divided by number of installments)
    let individualAmount = newTotalAmount / newNumberOfInstallments

    // Use new credit card from template if provided, otherwise preserve from existing installments
    let originalCreditCardId = relatedTransactions.first(where: { $0.creditCardId != nil })?.creditCardId
    let finalCreditCardId = templateTransaction.data.creditCardId ?? originalCreditCardId
    let oldStatementIds = Set(relatedTransactions.compactMap { $0.statementId })

    // Delete all existing related transactions first
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }

    // Create new installment series
    let startDate = newDate
    let creditCardService = CreditCardService()
    let creditCardRepo = CreditCardRepository()

    for i in 0..<newNumberOfInstallments {
      // Calculate date for this installment (add i months to start date)
      let installmentDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate

      // Save the new installment
      let installmentModel = TransactionModel(
        id: nil,
        title: templateTransaction.data.title,
        category: templateTransaction.data.category,
        amount: individualAmount,
        type: templateTransaction.data.type,
        dateTimestamp: Int(installmentDate.timeIntervalSince1970),
        budgetMonthDate: installmentDate.monthAnchor,
        isRecurring: false,
        hasInstallments: true,
        parentTransactionId: mainInstallmentTransactionId,
        originalAmount: nil,
        installmentNumber: i + 1,
        totalInstallments: newNumberOfInstallments
      )

      do {
        let insertedId = try insertTransactionAndGetId(installmentModel)

        // Assign credit card statement if installments are on a card
        if let cardId = finalCreditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
          if let uid = AuthenticationManager.shared.currentUser?.uid,
             let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: installmentDate, userId: uid) {
            try updateCreditCardFields(
              transactionId: insertedId,
              creditCardId: cardId,
              statementId: statement.id!,
              isCreditCardStatement: false
            )
            creditCardService.recalculateStatementTotal(statementId: statement.id!)
          }
        }
      } catch {
        logError("Failed to create installment \(i + 1): \(error)")
        throw error
      }
    }

    // Recalculate old statement totals that may no longer have these installments
    if !oldStatementIds.isEmpty {
      let creditCardSvc = CreditCardService()
      for oldStmtId in oldStatementIds {
        creditCardSvc.recalculateStatementTotal(statementId: oldStmtId)
      }
    }
  }

  func updateSingleTransactionOnly(
    id: Int,
    title: String,
    category: TransactionCategory,
    type: TransactionType,
    amount: Int,
    date: Date
  ) throws {
    Self.invalidateCache()
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
        creditCardId: existingTransaction.creditCardId,
        statementId: existingTransaction.statementId,
        isCreditCardStatement: existingTransaction.isCreditCardStatement,
        category: category,
        type: type
      )

      // Create new Transaction instance
      let updatedTransaction = Transaction(data: updatedData)
      secureTransactions[index] = updatedTransaction
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)

      // Reschedule notification for the updated transaction
      rescheduleNotificationForTransaction(transactionId: id)
    }
  }

  func updateTransactionParentId(transactionId: Int, parentId: Int) throws {
    Self.invalidateCache()
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
    }
  }

  /// Updates the isRecurring flag for a transaction (used when stopping future recurrence)
  func updateIsRecurring(transactionId: Int, isRecurring: Bool) throws {
    Self.invalidateCache()
    try db.updateIsRecurring(transactionId: transactionId, isRecurring: isRecurring)

    // Also update SecureLocalDataManager for UID-isolated storage
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()

    if let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) {
      let existingTransaction = secureTransactions[index]

      // Create new UITransactionData with updated isRecurring flag
      let updatedData = UITransactionData(
        id: existingTransaction.id,
        title: existingTransaction.title,
        amount: existingTransaction.amount,
        dateTimestamp: existingTransaction.dateTimestamp,
        budgetMonthDate: existingTransaction.budgetMonthDate,
        isRecurring: isRecurring,
        hasInstallments: existingTransaction.hasInstallments,
        parentTransactionId: existingTransaction.parentTransactionId,
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
    }

    // Notify that data has changed
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func deleteTransactionAndRelated(id: Int) throws {
    let allTransactions = fetchAllTransactions()
    guard let transaction = allTransactions.first(where: { $0.id == id }) else {
      throw TransactionError.transactionNotFound
    }

    // Use mode property to correctly identify transaction type
    // This handles both parent transactions AND their instances
    switch transaction.mode {
    case .recurring:
      // For recurring transactions (parent or instance), delete only this instance
      try deleteRecurringTransactionAndInstances(transactionId: id)
      return

    case .installments:
      // For installment transactions, delete all siblings
      let parentId = transaction.parentTransactionId ?? id
      try deleteInstallmentTransactionAndSiblings(parentId: parentId)
      return

    case .normal:
      try delete(id: id)
    }
  }

  func deleteTransactionWithOption(id: Int, option: RecurringCleanupOption) throws {
    let transaction = fetchAllTransactions().first { $0.id == id }

    guard let transaction = transaction else {
      throw TransactionError.transactionNotFound
    }

    // Use mode property to correctly identify recurring transactions
    // (both parent transactions with isRecurring=true AND instances with parentTransactionId)
    let isRecurringTransaction = transaction.mode == .recurring

    switch option {
    case .currentSelection:
      // Delete only the current transaction instance
      try delete(id: id)

    case .futureOnly:
      // For recurring transactions, delete future instances only (including current)
      if isRecurringTransaction {
        try deleteFutureRecurringInstances(transactionId: id)
      } else if transaction.mode == .installments {
        // For installment transactions, delete future installments
        try deleteFutureInstallmentInstances(transactionId: id)
      } else {
        // For non-recurring, just delete current
        try delete(id: id)
      }

    case .all:
      // Delete all related transactions
      if isRecurringTransaction {
        try deleteAllRecurringTransactionOccurrences(transactionId: id)
      } else if transaction.mode == .installments {
        // For installment transactions, get the correct parent ID
        let parentId = transaction.parentTransactionId ?? id
        try deleteInstallmentTransactionAndSiblings(parentId: parentId)
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

    logDebug("TransactionRepository: Deleting all recurring occurrences for transaction \(transactionId), recurringGroupId: \(String(describing: recurringGroupId))")

    // Find all related transactions in this recurring group
    let relatedTransactions = allTransactions.filter { transaction in
      guard let txId = transaction.id else { return false }
      return txId == recurringGroupId || transaction.parentTransactionId == recurringGroupId
    }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) transactions to delete")

    // Delete all related transactions
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }
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

    logDebug("TransactionRepository: Deleting future recurring instances for transaction \(transactionId), recurringGroupId: \(String(describing: recurringGroupId)), currentDate: \(currentDate)")

    // Find all related transactions in this recurring group that are in the future (including current)
    let relatedTransactions = allTransactions.filter { transaction in
      guard let txId = transaction.id else { return false }
      let isInGroup = txId == recurringGroupId || transaction.parentTransactionId == recurringGroupId
      // Include current transaction and all future ones (>= instead of >)
      let isFutureOrCurrent = transaction.date >= currentDate
      return isInGroup && isFutureOrCurrent
    }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) future transactions to delete")

    // Delete all future related transactions (including current)
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }

    // IMPORTANT: Stop the parent from generating new future instances
    // Set isRecurring = false on the parent so no new instances are created
    if let parentId = recurringGroupId {
      let remainingInstances = fetchTransactionInstancesForRecurring(parentId)

      if remainingInstances.isEmpty {
        // No instances left - delete the parent entirely
        let updatedTransactions = fetchAllTransactions()
        if updatedTransactions.first(where: { $0.id == parentId && $0.isRecurring == true }) != nil {
          logDebug("TransactionRepository: Deleting orphaned parent \(parentId)")
          try delete(id: parentId)
        }
      } else {
        // Past instances still exist - just stop future generation by setting isRecurring = false
        logDebug("TransactionRepository: Stopping future recurrence for parent \(parentId)")
        try updateIsRecurring(transactionId: parentId, isRecurring: false)
      }
    }
  }

  private func deleteFutureInstallmentInstances(transactionId: Int) throws {
    // Find all transactions with the same installment group
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    // Get the installment group ID (either the transaction's own ID or its parentTransactionId)
    let installmentGroupId = current.parentTransactionId ?? current.id
    let currentInstallmentNumber = current.installmentNumber ?? 1

    logDebug("TransactionRepository: Deleting future installment instances for transaction \(transactionId), installmentGroupId: \(String(describing: installmentGroupId)), currentInstallment: \(currentInstallmentNumber)")

    // Find all related transactions in this installment group that are current or future
    let relatedTransactions = allTransactions.filter { transaction in
      guard let txId = transaction.id else { return false }
      let isInGroup = txId == installmentGroupId || transaction.parentTransactionId == installmentGroupId
      // Include current installment and all future ones
      let isFutureOrCurrent = (transaction.installmentNumber ?? 0) >= currentInstallmentNumber
      return isInGroup && isFutureOrCurrent
    }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) future installments to delete")

    // Delete all future related transactions (including current)
    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }
  }

  private func deleteInstallmentTransactionAndSiblings(parentId: Int) throws {
    let allTransactions = fetchAllTransactions()

    logDebug("TransactionRepository: Deleting installment transaction and siblings for parentId \(parentId)")

    let installments = allTransactions.filter { transaction in
      guard let txParentId = transaction.parentTransactionId else { return false }
      return txParentId == parentId
    }

    logDebug("TransactionRepository: Found \(installments.count) installments to delete")

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

    // Remove existing notification for this transaction
    let notificationId = "transaction_\(transactionId)"
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
      notificationId
    ])

    // Get the updated transaction data
    let allTransactions = fetchAllTransactions()
    guard let updatedTransaction = allTransactions.first(where: { $0.id == transactionId }) else {
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
      return
    }

    // Check if date is too far in the future (more than 1 year)
    let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if tx.date > oneYearFromNow {
      return
    }

    // Calculate time interval from now to notification date
    let timeInterval = notificationDate.timeIntervalSinceNow

    // Check if interval is too large (more than 30 days)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
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
        logError("Error rescheduling notification for \(tx.title): \(error)")
      }
    }
  }

  // MARK: - CloudKit Sync Methods

  func fetchPendingSync() -> [Transaction] {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement
      FROM Transactions WHERE sync_status = 'pending';
      """
    return (try? db.executeTransactionQueryPublic(query)) ?? []
  }

  func markAsSynced(ckRecordName: String) {
    Self.invalidateCache()
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'synced', ck_record_id = ? WHERE ck_record_id = ?;",
      textBindings: [ckRecordName, ckRecordName]
    )
  }

  func insertFromCloud(_ transaction: Transaction, ckRecordName: String) {
    Self.invalidateCache()
    let category = transaction.category.key
    let type = String(describing: transaction.type)

    let query = """
      INSERT OR REPLACE INTO Transactions
        (title, category, type, amount, date, budget_month_date,
         is_recurring, has_installments, parent_transaction_id,
         installment_number, total_installments, original_amount,
         credit_card_id, statement_id, is_credit_card_statement,
         ck_record_id, sync_status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced');
      """

    db.executeCloudInsert(
      query,
      transaction: transaction,
      category: category,
      type: type,
      ckRecordName: ckRecordName
    )

    // Also update SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    secureTransactions.append(transaction)
    SecureLocalDataManager.shared.saveTransactions(secureTransactions)
  }

  func updateFromCloud(_ transaction: Transaction, ckRecordName: String) {
    Self.invalidateCache()
    let category = transaction.category.key
    let type = String(describing: transaction.type)

    let query = """
      UPDATE Transactions SET
        title = ?, category = ?, type = ?, amount = ?, date = ?,
        budget_month_date = ?, is_recurring = ?, has_installments = ?,
        parent_transaction_id = ?, installment_number = ?,
        total_installments = ?, original_amount = ?,
        credit_card_id = ?, statement_id = ?, is_credit_card_statement = ?,
        sync_status = 'synced'
      WHERE ck_record_id = ?;
      """

    db.executeCloudUpdate(
      query,
      transaction: transaction,
      category: category,
      type: type,
      ckRecordName: ckRecordName
    )

    // Also update SecureLocalDataManager
    var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
    if let txId = transaction.id,
       let index = secureTransactions.firstIndex(where: { $0.id == txId }) {
      secureTransactions[index] = transaction
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)
    }
  }

  func markSyncPending(for id: Int) {
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'pending' WHERE id = ?;",
      intBindings: [id]
    )
  }

  func softDeleteByCKRecordName(_ recordName: String) {
    Self.invalidateCache()
    // Get the transaction id before deleting for SecureLocalDataManager cleanup
    let fetchQuery = "SELECT id FROM Transactions WHERE ck_record_id = ?;"
    if let txId = db.fetchSingleInt(fetchQuery, textBinding: recordName) {
      db.executeSyncUpdate(
        "DELETE FROM Transactions WHERE ck_record_id = ?;",
        textBindings: [recordName]
      )
      // Also remove from SecureLocalDataManager
      var secureTransactions = SecureLocalDataManager.shared.loadTransactions()
      secureTransactions.removeAll { $0.id == txId }
      SecureLocalDataManager.shared.saveTransactions(secureTransactions)
    }
  }

  func fetchTransaction(byId id: Int) -> Transaction? {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement
      FROM Transactions WHERE id = ?;
      """
    return (try? db.executeTransactionQueryPublic(query, bindValues: [id]))?.first
  }

  func lastModifiedDate(for id: Int) -> Date? {
    let query = "SELECT ck_modified_at FROM Transactions WHERE id = ?;"
    guard let timestamp = db.fetchSingleInt(query, intBinding: id), timestamp > 0 else {
      return nil
    }
    return Date(timeIntervalSince1970: TimeInterval(timestamp))
  }

  func fetchTransactionsForGroup(groupId: String) -> [Transaction] {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement
      FROM Transactions WHERE shared_group_id = ?;
      """
    return (try? db.executeTransactionQueryPublicText(query, textBindings: [groupId])) ?? []
  }

  /// Removes all transactions that were inserted from CloudKit sync (ghost records).
  /// Original local transactions (ck_record_id IS NULL) are preserved.
  /// Also rebuilds SecureLocalDataManager from the clean SQLite data.
  func removeCloudInsertedRecords() {
    Self.invalidateCache()

    // Delete ghost records from SQLite
    db.executeSyncUpdate("DELETE FROM Transactions WHERE ck_record_id IS NOT NULL;")

    // Also reset sync columns on remaining local transactions
    db.executeSyncUpdate("UPDATE Transactions SET sync_status = 'pending', ck_record_id = NULL, ck_modified_at = NULL;")

    rebuildSecureStoreFromSQLite()
  }

  /// Reads all transactions from SQLite and overwrites SecureLocalDataManager.
  func rebuildSecureStoreFromSQLite() {
    Self.invalidateCache()

    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement
      FROM Transactions ORDER BY id;
      """
    let sqliteTransactions = (try? db.executeTransactionQueryPublic(query)) ?? []
    logWarning("[GhostCleanup] SQLite rows: \(sqliteTransactions.count)")

    SecureLocalDataManager.shared.saveTransactions(sqliteTransactions)

    // Verify the round-trip: load back and compare counts + sample titles
    let rebuilt = SecureLocalDataManager.shared.loadTransactions()
    logWarning("[GhostCleanup] SecureStore after rebuild: \(rebuilt.count)")

    if rebuilt.count != sqliteTransactions.count {
      logError("[GhostCleanup] MISMATCH — SQLite=\(sqliteTransactions.count) vs SecureStore=\(rebuilt.count)")
    }

    // Log a few samples so we can verify data integrity
    for tx in rebuilt.prefix(3) {
      logWarning("[GhostCleanup] Sample: id=\(tx.id ?? -1) title='\(tx.title)' cat=\(tx.category.key)")
    }
  }

  func updateSharedGroupId(transactionId: Int, groupId: String?) {
    Self.invalidateCache()
    if let groupId = groupId {
      db.executeSyncUpdate(
        "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE id = ?;",
        textBindings: [groupId],
        intBindings: [transactionId]
      )
    } else {
      db.executeSyncUpdate(
        "UPDATE Transactions SET shared_group_id = NULL, sync_status = 'pending' WHERE id = ?;",
        intBindings: [transactionId]
      )
    }
  }
}
