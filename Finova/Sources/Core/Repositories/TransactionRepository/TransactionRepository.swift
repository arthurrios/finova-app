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
    let allTransactions = fetchAllTransactions()

    let filteredTransactions = allTransactions.filter { transaction in
      if transaction.isRecurring == true && transaction.parentTransactionId == nil {
        return false
      }
      if transaction.hasInstallments == true && transaction.parentTransactionId == nil {
        return false
      }
      return true
    }

    return filteredTransactions
  }

  func insertTransaction(_ transaction: TransactionModel) throws {
    Self.invalidateCache()
    try db.insertTransaction(transaction)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func delete(id: Int) throws {
    Self.invalidateCache()
    logDebug("TransactionRepository: Deleting transaction with id \(id)")
    try db.deleteTransaction(id: id)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func fetchAllTransactions() -> [Transaction] {
    let currentUID = UIDUserDefaultsManager.shared.currentUserUID

    if let cached = Self.cachedTransactions, Self.cacheUserUID == currentUID {
      return cached
    }

    let transactions: [Transaction]
    if let uid = currentUID {
      transactions = (try? db.getTransactions(forUser: uid)) ?? []
    } else {
      transactions = (try? db.getTransactions()) ?? []
    }

    Self.cachedTransactions = transactions
    Self.cacheUserUID = currentUID
    return transactions
  }

  func fetchParentInstallmentTransactions() -> [Transaction] {
    return fetchAllTransactions()
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
  }

  func clearCreditCardFields(transactionId: Int) throws {
    Self.invalidateCache()
    try db.clearTransactionCreditCardFields(transactionId: transactionId)
  }

  // MARK: - Debug Methods

  func debugDuplicateTransactions() {
    // No-op in production
  }

  func insertTransactionAndGetId(_ transaction: TransactionModel) throws -> Int {
    Self.invalidateCache()
    return try db.insertTransaction(transaction)
  }

  func updateTransactionDirectly(_ transaction: TransactionModel) throws {
    Self.invalidateCache()
    try db.updateTransaction(transaction)

    rescheduleNotificationForTransaction(transactionId: transaction.data.id)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func updateParentTransactionId(transactionId: Int, parentId: Int) throws {
    Self.invalidateCache()
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)
  }

  func updateTransaction(_ transaction: TransactionModel) throws {
    let allTransactions = fetchAllTransactions()
    guard
      let existingTransaction = allTransactions.first(where: { $0.id == transaction.data.id })
    else {
      throw TransactionError.transactionNotFound
    }

    if existingTransaction.isRecurring == true {
      try updateAllRecurringTransactions(
        templateTransaction: transaction, existingTransaction: existingTransaction)
    } else if existingTransaction.hasInstallments == true {
      try updateAllInstallmentTransactions(
        templateTransaction: transaction, existingTransaction: existingTransaction)
    } else {
      try updateTransactionDirectly(transaction)
    }
  }

  private func updateAllRecurringTransactions(
    templateTransaction: TransactionModel, existingTransaction: Transaction
  ) throws {
    let recurringGroupId = existingTransaction.parentTransactionId ?? existingTransaction.id
    let allTransactions = fetchAllTransactions()
    let relatedTransactions = allTransactions.filter { transaction in
      transaction.id == recurringGroupId || transaction.parentTransactionId == recurringGroupId
    }

    let calendar = Calendar.current
    let newDate = Date(timeIntervalSince1970: TimeInterval(templateTransaction.data.dateTimestamp))
    let newDay = calendar.component(.day, from: newDate)

    for relatedTransaction in relatedTransactions {
      let originalDate = Date(timeIntervalSince1970: TimeInterval(relatedTransaction.dateTimestamp))
      let originalMonth = calendar.component(.month, from: originalDate)
      let originalYear = calendar.component(.year, from: originalDate)

      var dateComponents = DateComponents()
      dateComponents.year = originalYear
      dateComponents.month = originalMonth
      dateComponents.day = newDay

      let adjustedDate: Date
      if let newDateForMonth = calendar.date(from: dateComponents) {
        adjustedDate = newDateForMonth
      } else {
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

      rescheduleNotificationForTransaction(transactionId: relatedTransaction.id)
    }
  }

  private func updateAllInstallmentTransactions(
    templateTransaction: TransactionModel, existingTransaction: Transaction
  ) throws {
    let calendar = Calendar.current
    let newDate = Date(timeIntervalSince1970: TimeInterval(templateTransaction.data.dateTimestamp))
    let newTotalAmount = templateTransaction.data.amount
    let newNumberOfInstallments = templateTransaction.data.totalInstallments ?? 1

    let allTransactions = fetchAllTransactions()

    let mainInstallmentTransactionId: Int
    if let parentId = existingTransaction.parentTransactionId {
      if allTransactions.first(where: {
        $0.hasInstallments == true && $0.parentTransactionId == nil && $0.id == parentId
      }) != nil {
        mainInstallmentTransactionId = parentId
      } else {
        let individualInstallmentMonth = existingTransaction.budgetMonthDate
        if let fallbackMainTransaction = allTransactions.first(where: {
          $0.hasInstallments == true && $0.parentTransactionId == nil
            && $0.budgetMonthDate == individualInstallmentMonth && $0.amount == 0
        }) {
          mainInstallmentTransactionId = fallbackMainTransaction.id ?? 0
        } else {
          mainInstallmentTransactionId = parentId
        }
      }
    } else {
      mainInstallmentTransactionId = existingTransaction.id ?? 0
    }

    let relatedTransactions = allTransactions.filter { transaction in
      transaction.id == mainInstallmentTransactionId
        || transaction.parentTransactionId == mainInstallmentTransactionId
    }

    let individualAmount = newTotalAmount / newNumberOfInstallments

    let originalCreditCardId = relatedTransactions.first(where: { $0.creditCardId != nil })?.creditCardId
    let finalCreditCardId = templateTransaction.data.creditCardId ?? originalCreditCardId
    let oldStatementIds = Set(relatedTransactions.compactMap { $0.statementId })

    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }

    let startDate = newDate
    let creditCardService = CreditCardService()
    let creditCardRepo = CreditCardRepository()

    for i in 0..<newNumberOfInstallments {
      let installmentDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate

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
    let updatedTransaction = TransactionModel(
      id: id,
      title: title,
      category: category.key,
      amount: amount,
      type: String(describing: type),
      dateTimestamp: Int(date.timeIntervalSince1970),
      budgetMonthDate: date.monthAnchor,
      isRecurring: false,
      hasInstallments: false,
      parentTransactionId: nil,
      originalAmount: amount,
      installmentNumber: nil,
      totalInstallments: nil
    )

    try db.updateSingleTransaction(updatedTransaction)
    rescheduleNotificationForTransaction(transactionId: id)
  }

  func updateTransactionParentId(transactionId: Int, parentId: Int) throws {
    Self.invalidateCache()
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)
  }

  func updateIsRecurring(transactionId: Int, isRecurring: Bool) throws {
    Self.invalidateCache()
    try db.updateIsRecurring(transactionId: transactionId, isRecurring: isRecurring)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func deleteTransactionAndRelated(id: Int) throws {
    let allTransactions = fetchAllTransactions()
    guard let transaction = allTransactions.first(where: { $0.id == id }) else {
      throw TransactionError.transactionNotFound
    }

    switch transaction.mode {
    case .recurring:
      try deleteRecurringTransactionAndInstances(transactionId: id)
      return

    case .installments:
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

    let isRecurringTransaction = transaction.mode == .recurring

    switch option {
    case .currentSelection:
      try delete(id: id)

    case .futureOnly:
      if isRecurringTransaction {
        try deleteFutureRecurringInstances(transactionId: id)
      } else if transaction.mode == .installments {
        try deleteFutureInstallmentInstances(transactionId: id)
      } else {
        try delete(id: id)
      }

    case .all:
      if isRecurringTransaction {
        try deleteAllRecurringTransactionOccurrences(transactionId: id)
      } else if transaction.mode == .installments {
        let parentId = transaction.parentTransactionId ?? id
        try deleteInstallmentTransactionAndSiblings(parentId: parentId)
      } else {
        try delete(id: id)
      }
    }
  }

  private func deleteRecurringTransactionAndInstances(transactionId: Int) throws {
    try delete(id: transactionId)
  }

  private func deleteAllRecurringTransactionOccurrences(transactionId: Int) throws {
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    let recurringGroupId = current.parentTransactionId ?? current.id

    logDebug("TransactionRepository: Deleting all recurring occurrences for transaction \(transactionId), recurringGroupId: \(String(describing: recurringGroupId))")

    let relatedTransactions = allTransactions.filter { transaction in
      guard let txId = transaction.id else { return false }
      return txId == recurringGroupId || transaction.parentTransactionId == recurringGroupId
    }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) transactions to delete")

    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }
  }

  private func deleteFutureRecurringInstances(transactionId: Int) throws {
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    let recurringGroupId = current.parentTransactionId ?? current.id
    let currentDate = current.date

    logDebug("TransactionRepository: Deleting future recurring instances for transaction \(transactionId), recurringGroupId: \(String(describing: recurringGroupId)), currentDate: \(currentDate)")

    let relatedTransactions = allTransactions.filter { transaction in
      guard let txId = transaction.id else { return false }
      let isInGroup = txId == recurringGroupId || transaction.parentTransactionId == recurringGroupId
      let isFutureOrCurrent = transaction.date >= currentDate
      return isInGroup && isFutureOrCurrent
    }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) future transactions to delete")

    for relatedTransaction in relatedTransactions {
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }

    if let parentId = recurringGroupId {
      let remainingInstances = fetchTransactionInstancesForRecurring(parentId)

      if remainingInstances.isEmpty {
        let updatedTransactions = fetchAllTransactions()
        if updatedTransactions.first(where: { $0.id == parentId && $0.isRecurring == true }) != nil {
          logDebug("TransactionRepository: Deleting orphaned parent \(parentId)")
          try delete(id: parentId)
        }
      } else {
        logDebug("TransactionRepository: Stopping future recurrence for parent \(parentId)")
        try updateIsRecurring(transactionId: parentId, isRecurring: false)
      }
    }
  }

  private func deleteFutureInstallmentInstances(transactionId: Int) throws {
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    let installmentGroupId = current.parentTransactionId ?? current.id
    let currentInstallmentNumber = current.installmentNumber ?? 1

    logDebug("TransactionRepository: Deleting future installment instances for transaction \(transactionId), installmentGroupId: \(String(describing: installmentGroupId)), currentInstallment: \(currentInstallmentNumber)")

    let relatedTransactions = allTransactions.filter { transaction in
      guard let txId = transaction.id else { return false }
      let isInGroup = txId == installmentGroupId || transaction.parentTransactionId == installmentGroupId
      let isFutureOrCurrent = (transaction.installmentNumber ?? 0) >= currentInstallmentNumber
      return isInGroup && isFutureOrCurrent
    }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) future installments to delete")

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
    for _ in 0..<10 {
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

  private func rescheduleNotificationForTransaction(transactionId: Int?) {
    guard let transactionId = transactionId else { return }

    let notificationId = "transaction_\(transactionId)"
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
      notificationId
    ])

    let allTransactions = fetchAllTransactions()
    guard let updatedTransaction = allTransactions.first(where: { $0.id == transactionId }) else {
      return
    }

    scheduleNotificationForTransaction(updatedTransaction)
  }

  private func scheduleNotificationForTransaction(_ tx: Transaction) {
    guard let transactionId = tx.id else { return }

    let id = "transaction_\(transactionId)"
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    guard notificationDate > now else {
      return
    }

    let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if tx.date > oneYearFromNow {
      return
    }

    let timeInterval = notificationDate.timeIntervalSinceNow

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
         ck_record_id, sync_status, user_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?);
      """

    db.executeCloudInsert(
      query,
      transaction: transaction,
      category: category,
      type: type,
      ckRecordName: ckRecordName
    )
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
  }

  func markSyncPending(for id: Int) {
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'pending' WHERE id = ?;",
      intBindings: [id]
    )
  }

  func softDeleteByCKRecordName(_ recordName: String) {
    Self.invalidateCache()
    db.executeSyncUpdate(
      "DELETE FROM Transactions WHERE ck_record_id = ?;",
      textBindings: [recordName]
    )
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

  func removeCloudInsertedRecords() {
    Self.invalidateCache()
    db.executeSyncUpdate("DELETE FROM Transactions WHERE ck_record_id IS NOT NULL;")
    db.executeSyncUpdate("UPDATE Transactions SET sync_status = 'pending', ck_record_id = NULL, ck_modified_at = NULL;")
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
