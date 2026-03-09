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

    // Check if this record has been synced to CloudKit
    let ckName = fetchCKRecordName(for: id)
    if ckName != nil {
      // Soft-delete: mark as deleted and pendingDelete so SyncEngine can delete from CK
      db.executeSyncUpdate(
        "UPDATE Transactions SET is_deleted = 1, sync_status = 'pendingDelete' WHERE id = ?;",
        intBindings: [id]
      )
    } else {
      // Not synced — safe to hard-delete
      try db.deleteTransaction(id: id)
    }
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

    // Update the parent installment record in place rather than deleting it.
    // Deleting the parent causes newly-created children to point to a soft-deleted
    // (invisible) parent, making the edit appear as a "new set" of transactions.
    try updateTransactionDirectly(templateTransaction)
    markSyncPending(for: mainInstallmentTransactionId)

    // Delete only the individual installment children, not the parent.
    for relatedTransaction in relatedTransactions {
      guard relatedTransaction.parentTransactionId != nil else { continue }
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

  func fetchSharedGroupId(for transactionId: Int) -> String? {
    return db.fetchSingleString(
      "SELECT shared_group_id FROM Transactions WHERE id = ?;",
      intBinding: transactionId
    )
  }

  // MARK: - CloudKit Sync Methods

  func fetchPendingSync() -> [Transaction] {
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      let query = """
        SELECT id, title, category, type, amount, date, budget_month_date,
               is_recurring, has_installments, parent_transaction_id,
               installment_number, total_installments, original_amount,
               credit_card_id, statement_id, is_credit_card_statement, created_by_uid
        FROM Transactions WHERE sync_status = 'pending' AND user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
        """
      return (try? db.executeTransactionQueryPublicText(query, textBindings: [uid])) ?? []
    }
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions WHERE sync_status = 'pending' AND (is_deleted IS NULL OR is_deleted = 0);
      """
    return (try? db.executeTransactionQueryPublic(query)) ?? []
  }

  func markAsSynced(ckRecordName: String) {
    Self.invalidateCache()
    // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'synced' WHERE ck_record_id = ?;",
      textBindings: [ckRecordName]
    )
  }

  func setCKRecordId(for localId: Int, ckRecordName: String) {
    db.executeSyncUpdate(
      "UPDATE Transactions SET ck_record_id = ? WHERE id = ? AND ck_record_id IS NULL;",
      textBindings: [ckRecordName],
      intBindings: [localId]
    )
  }

  func overwriteCKRecordId(for localId: Int, ckRecordName: String) {
    db.executeSyncUpdate(
      "UPDATE Transactions SET ck_record_id = ? WHERE id = ?;",
      textBindings: [ckRecordName],
      intBindings: [localId]
    )
  }

  /// Deletes only soft-deleted rows (is_deleted=1) with the given CK record name.
  /// Used before re-linking a live record to a group-zone CK name, to avoid
  /// two rows sharing the same ck_record_id (stale duplicate + live re-linked).
  func deleteSoftDeletedByCKRecordName(_ recordName: String) {
    Self.invalidateCache()
    db.executeSyncUpdate(
      "DELETE FROM Transactions WHERE ck_record_id = ? AND is_deleted = 1;",
      textBindings: [recordName]
    )
  }

  func insertFromCloud(_ transaction: Transaction, ckRecordName: String, parentCKRecordName: String? = nil, sharedGroupId: String? = nil) {
    Self.invalidateCache()
    let category = transaction.category.key
    let type = String(describing: transaction.type)

    // Remove any existing row with this ck_record_id to prevent duplicates
    db.executeSyncUpdate(
      "DELETE FROM Transactions WHERE ck_record_id = ?;",
      textBindings: [ckRecordName]
    )

    let query = """
      INSERT INTO Transactions
        (title, category, type, amount, date, budget_month_date,
         is_recurring, has_installments, parent_transaction_id,
         installment_number, total_installments, original_amount,
         credit_card_id, statement_id, is_credit_card_statement,
         ck_record_id, sync_status, user_id, ck_modified_at, ck_parent_record_name,
         shared_group_id, updated_at, created_by_uid)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?, ?, ?, ?);
      """

    db.executeCloudInsert(
      query,
      transaction: transaction,
      category: category,
      type: type,
      ckRecordName: ckRecordName,
      parentCKRecordName: parentCKRecordName,
      sharedGroupId: sharedGroupId,
      updatedAt: transaction.updatedAt,
      createdByUid: transaction.createdByUid
    )

    // Phase 4D: Remap parent ID via CK record name
    if let parentCKName = parentCKRecordName,
       let localParent = fetchTransaction(byCKRecordName: parentCKName) {
      // Find the newly inserted row by ck_record_id and update its parent_transaction_id
      if let insertedRow = fetchTransaction(byCKRecordName: ckRecordName),
         let insertedId = insertedRow.id,
         let parentId = localParent.id {
        db.executeSyncUpdate(
          "UPDATE Transactions SET parent_transaction_id = ? WHERE id = ?;",
          intBindings: [parentId, insertedId]
        )
      }
    }
  }

  func updateFromCloud(_ transaction: Transaction, ckRecordName: String, sharedGroupId: String? = nil) {
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
        sync_status = 'synced', ck_modified_at = ?,
        shared_group_id = ?,
        updated_at = ?,
        created_by_uid = ?
      WHERE ck_record_id = ?;
      """

    db.executeCloudUpdate(
      query,
      transaction: transaction,
      category: category,
      type: type,
      ckRecordName: ckRecordName,
      sharedGroupId: sharedGroupId,
      updatedAt: transaction.updatedAt,
      createdByUid: transaction.createdByUid
    )
  }

  func markSyncPending(for id: Int) {
    let now = Int(Date().timeIntervalSince1970)
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'pending', ck_modified_at = ? WHERE id = ?;",
      intBindings: [now, id]
    )
  }

  func deleteFromCloud(ckRecordName recordName: String) {
    Self.invalidateCache()
    db.executeSyncUpdate(
      "DELETE FROM Transactions WHERE ck_record_id = ?;",
      textBindings: [recordName]
    )
  }

  func fetchPendingDeletes() -> [(ckRecordName: String, localId: Int)] {
    var results: [(ckRecordName: String, localId: Int)] = []
    let query = "SELECT id, ck_record_id FROM Transactions WHERE sync_status = 'pendingDelete' AND ck_record_id IS NOT NULL;"
    if let rows = db.fetchIdAndCKRecordName(query) {
      results = rows
    }
    return results
  }

  func hardDeleteByCKRecordName(_ recordName: String) {
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
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions WHERE id = ?;
      """
    return (try? db.executeTransactionQueryPublic(query, bindValues: [id]))?.first
  }

  func fetchCKRecordName(for id: Int) -> String? {
    return db.fetchSingleString(
      "SELECT ck_record_id FROM Transactions WHERE id = ?;",
      intBinding: id
    )
  }

  func fetchMatchingRecurringInstance(title: String, amount: Int, budgetMonthDate: Int) -> Transaction? {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions
      WHERE title = ? AND amount = ? AND budget_month_date = ?
        AND parent_transaction_id IS NOT NULL AND is_deleted = 0
      LIMIT 1;
      """
    return (try? db.executeTransactionQueryMixed(
      query, textBindings: [title], intBindings: [amount, budgetMonthDate]
    ))?.first
  }

  /// Matches any transaction (parent, instance, or normal) by title + amount + budget_month_date.
  /// Used as a last-resort fallback in ConflictResolver to prevent duplicate inserts.
  func fetchMatchingTransaction(title: String, amount: Int, budgetMonthDate: Int) -> Transaction? {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions
      WHERE title = ? AND amount = ? AND budget_month_date = ?
        AND (is_deleted IS NULL OR is_deleted = 0)
      LIMIT 1;
      """
    return (try? db.executeTransactionQueryMixed(
      query, textBindings: [title], intBindings: [amount, budgetMonthDate]
    ))?.first
  }

  func fetchRecurringInstance(parentId: Int, budgetMonthDate: Int) -> Transaction? {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions
      WHERE parent_transaction_id = ? AND budget_month_date = ? AND is_deleted = 0
      LIMIT 1;
      """
    return (try? db.executeTransactionQueryPublic(query, bindValues: [parentId, budgetMonthDate]))?.first
  }

  func fetchTransaction(byCKRecordName recordName: String) -> Transaction? {
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions WHERE ck_record_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
      """
    return (try? db.executeTransactionQueryPublicText(query, textBindings: [recordName]))?.first
  }

  /// Returns a mapping of parentTransactionId → Set<budgetMonthDate> for all soft-deleted
  /// (is_deleted=1) installment and recurring instances.
  /// Used by lazy generation to prevent recreating instances the user intentionally deleted.
  func fetchDeletedChildAnchors() -> [Int: Set<Int>] {
    let pairs = db.fetchIntIntPairs(
      "SELECT parent_transaction_id, budget_month_date FROM Transactions WHERE is_deleted = 1 AND parent_transaction_id IS NOT NULL;"
    )
    var result: [Int: Set<Int>] = [:]
    for (parentId, anchor) in pairs {
      result[parentId, default: []].insert(anchor)
    }
    return result
  }

  /// If a soft-deleted record with this CK name exists (is_deleted=1), restores its sync_status
  /// to 'pendingDelete' so the next push cycle will remove it from CloudKit.
  /// Returns true if such a record was found (caller should skip re-insertion).
  func restorePendingDeleteIfNeeded(ckRecordName: String) -> Bool {
    let check = "SELECT id FROM Transactions WHERE ck_record_id = ? AND is_deleted = 1;"
    guard db.fetchSingleInt(check, textBinding: ckRecordName) != nil else { return false }
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'pendingDelete' WHERE ck_record_id = ? AND is_deleted = 1;",
      textBindings: [ckRecordName]
    )
    return true
  }

  /// If a tombstone (is_deleted=1, ck_record_id=NULL) exists for this parent+month,
  /// re-links it to the incoming CK record name and re-queues it as pendingDelete.
  /// Called by ConflictResolver when CloudKit re-sends a record whose local row was
  /// tombstoned by hardDeleteLocal (ck_record_id cleared), preventing re-insertion.
  func restoreTombstoneForInstance(parentId: Int, budgetMonthDate: Int, ckRecordName: String) -> Bool {
    let check = """
      SELECT id FROM Transactions
      WHERE parent_transaction_id = ? AND budget_month_date = ? AND is_deleted = 1
      LIMIT 1;
      """
    guard db.fetchSingleInt(check, intBindings: [parentId, budgetMonthDate]) != nil else { return false }
    // Do NOT re-link the tombstone (i.e. don't assign ck_record_id or mark pendingDelete).
    // Re-linking caused an infinite delete loop: after a successful CK delete hardDeleteLocal
    // clears ck_record_id, a stale-token pull re-delivers the live record, this function
    // re-queues it as pendingDelete, the next push deletes it again, and so on forever.
    // Returning true is enough: it prevents insertFromCloud from resurrecting the instance.
    // The tombstone remains (is_deleted=1, ck_record_id=NULL) to block lazy regeneration.
    // When CK's change token advances past our delete, the next pull will deliver it as a
    // deletion and processDeletedRecord will confirm the tombstone state.
    return true
  }

  func lastModifiedDate(for id: Int) -> Date? {
    let query = "SELECT updated_at FROM Transactions WHERE id = ?;"
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
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid
      FROM Transactions WHERE shared_group_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
      """
    return (try? db.executeTransactionQueryPublicText(query, textBindings: [groupId])) ?? []
  }

  /// Fetches group transactions filtered for display — hides parent recurring/installment templates.
  /// Matches the same filtering as fetchTransactions() for personal view.
  func fetchDisplayTransactionsForGroup(groupId: String) -> [Transaction] {
    return fetchTransactionsForGroup(groupId: groupId).filter { tx in
      if tx.isRecurring == true && tx.parentTransactionId == nil { return false }
      if tx.hasInstallments == true && tx.parentTransactionId == nil { return false }
      return true
    }
  }

  func removeCloudInsertedRecords() {
    Self.invalidateCache()
    db.executeSyncUpdate("DELETE FROM Transactions WHERE ck_record_id IS NOT NULL;")
    db.executeSyncUpdate("UPDATE Transactions SET sync_status = 'pending', ck_record_id = NULL, ck_modified_at = NULL;")
  }

  /// Fixes orphaned parent_transaction_id references, then deduplicates recurring instances.
  /// Must be called after processing all incoming CloudKit records.
  func fixAndDeduplicateAfterSync() {
    Self.invalidateCache()
    db.fixOrphanedParentTransactionIds()
    db.deduplicateRecurringTransactions()
    Self.invalidateCache()
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
