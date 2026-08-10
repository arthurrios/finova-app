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

  /// Guards the secure store and the cache that shadows it. Recursive because a `mutateSecureStore`
  /// body may reach back into a read on the same thread.
  private static let storeLock = NSRecursiveLock()

  private static var cachedTransactions: [Transaction]?
  private static var cacheUserUID: String?

  static func invalidateCache() {
    storeLock.lock()
    defer { storeLock.unlock() }
    cachedTransactions = nil
    cacheUserUID = nil
  }

  /// Runs one read-modify-write of the secure store as a single atomic step: loads it, hands it to
  /// `body`, and — if `body` reports a change — writes it back and drops the cache, all before any
  /// other thread can read or write. Returns whether anything was written.
  ///
  /// Every mutating method here used to do this by hand, unsynchronized, and that leaked
  /// duplicate recurring occurrences two ways. The dashboard ledger reads on the main thread while
  /// recurring generation runs on a background queue, so:
  ///
  ///   - LOST UPDATE. Two writers each load the same array, each append their own row, and each save
  ///     the whole thing. The second save has no idea the first happened, so the first writer's row
  ///     is gone from the store even though it is still in SQLite. Generation dedups against the
  ///     store, does not see the row, and creates the occurrence a second time.
  ///   - STALE CACHE. Invalidating before the write is not enough, and neither is invalidating after
  ///     it: a reader can miss the cache, load the PRE-write store, and only then publish that
  ///     snapshot into `cachedTransactions` — landing after the writer's invalidation and surviving
  ///     it. The next generation pass reads that snapshot and re-creates what it cannot see.
  ///
  /// Holding one lock across load-mutate-save-invalidate closes both: a reader either sees the store
  /// entirely before the write or entirely after it, and can never publish a snapshot into the cache
  /// mid-write. Serializing the generators (see `RecurringTransactionManager`) stops two passes
  /// overlapping but does nothing about a store or cache that is already wrong.
  @discardableResult
  private static func mutateSecureStore(_ body: (inout [Transaction]) throws -> Bool) rethrows
    -> Bool
  {
    storeLock.lock()
    defer { storeLock.unlock() }

    var transactions = SecureLocalDataManager.shared.loadTransactions()
    guard try body(&transactions) else { return false }

    SecureLocalDataManager.shared.saveTransactions(transactions)
    cachedTransactions = nil
    cacheUserUID = nil
    return true
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
      // Carried explicitly, and taken from `uiData` rather than `newTransaction`: this rebuild exists
      // only to stamp the SQLite id, but every field it forgets is silently DROPPED from the secure
      // store. `fetchAllTransactions` reads the secure store, and recurring generation dedups against
      // `seriesPeriod` from it — so losing that here makes the generator fall back to
      // budgetMonthDate, miss occurrences whose date a rule moved into an adjacent month, and create
      // them a second time.
      businessDayRule: uiData.businessDayRule,
      unadjustedDateTimestamp: uiData.unadjustedDateTimestamp,
      seriesPeriod: uiData.seriesPeriod,
      category: newTransaction.category,
      type: newTransaction.type
    )

    // 🔒 Also save to SecureLocalDataManager for UID-isolated storage
    Self.mutateSecureStore { secureTransactions in
      secureTransactions.append(Transaction(data: updatedData))
      return true
    }

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func delete(id: Int) throws {
    try deleteBatch(ids: [id])
  }

  /// Deletes several transactions as one unit.
  ///
  /// Series deletions ("this and remaining", "all occurrences") remove tens of rows at once, and the
  /// per-row cost here is not small: every single delete reloaded the ENTIRE secure store, filtered
  /// it, wrote it all back, invalidated the cache and broadcast `transactionDataChanged`. A 36-month
  /// series meant 36 full load/filter/save cycles and 36 UI refreshes, each re-reading the whole
  /// ledger, with the screen showing a half-deleted series in between.
  ///
  /// The secure store is now read once, stripped of every doomed id, and written once.
  func deleteBatch(ids: [Int]) throws {
    guard !ids.isEmpty else { return }
    Self.invalidateCache()

    let doomed = Set(ids)

    for id in ids {
      try deleteRow(id: id)
    }

    // 🔒 One pass over SecureLocalDataManager for the whole batch.
    Self.mutateSecureStore { secureTransactions in
      let countBefore = secureTransactions.count
      secureTransactions.removeAll { transaction in
        guard let transactionId = transaction.id else { return false }
        return doomed.contains(transactionId)
      }
      logDebug(
        "TransactionRepository: Removed \(countBefore - secureTransactions.count) transactions from SecureLocalDataManager"
      )
      return true
    }

    // Notify that data has changed (for cache invalidation)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  /// Removes one row and the bookkeeping that belongs to it alone. Callers are responsible for the
  /// shared aftermath — see `deleteBatch`.
  private func deleteRow(id: Int) throws {
    logDebug("TransactionRepository: Deleting transaction with id \(id)")

    // If this row is an early-payment debit, put the installments it covered back on their own
    // statements FIRST. Deleting it while their `settled_by_transaction_id` still pointed here would
    // erase the amount from the ledger entirely — the installments stay excluded from every total,
    // and nothing charges for them any more. Done here rather than in each caller so removal by any
    // route (details screen, statement list, swipe-to-delete, cleanup option) is covered.
    if db.isEarlyPayment(transactionId: id) {
      EarlyPaymentService(transactionRepo: self).releaseInstallments(settledBy: id)
    }

    // Same reasoning for a cancellation credit: deleting it while the installments still pointed at it
    // would leave the purchase permanently flagged as cancelled with no refund backing it, and the
    // user could never cancel it again.
    if db.isCancellationRefund(transactionId: id) {
      InstallmentCancellationService(transactionRepo: self).releaseInstallments(cancelledBy: id)
    }

    // A statement payment is a pair — the debit that moved the money and the credit that reduced the
    // invoice — and neither half makes sense alone. Deleting the debit while its credit stood would
    // leave the invoice discounted by a payment nobody made; deleting the credit while its debit stood
    // would charge for a payment the invoice no longer records. Either half taken removes the other,
    // and the statement is reopened if it owes money again. The service holds a cascade guard so the
    // partner's own delete does not come back round here.
    if db.isStatementPayment(transactionId: id) || db.statementPaymentId(transactionId: id) != nil {
      StatementPaymentService(transactionRepo: self).handleDeletion(of: id)
    }

    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: ["transaction_\(id)"])

    try db.deleteTransaction(id: id)
  }

  func fetchAllTransactions() -> [Transaction] {
    // Returns ALL transactions including parent transactions (for internal operations)
    // 🔒 Use SecureLocalDataManager for UID-isolated data access ONLY
    let currentUID = AuthenticationManager.shared.currentUser?.uid

    // Under the same lock as every write: the miss, the load and the publish have to be one step, or
    // this is exactly where a pre-write snapshot gets published over a writer's invalidation.
    Self.storeLock.lock()
    defer { Self.storeLock.unlock() }

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

  // MARK: - Date / Budget Month

  /// Re-anchors a transaction onto a new date AND the budget month it counts toward.
  ///
  /// Mirrored into `SecureLocalDataManager` for the same reason `updateCreditCardFields` is: the
  /// secure store is the source of truth this release reads statements and dashboard rows from, so a
  /// DB-only write would leave the two disagreeing.
  func updateDateAndBudgetMonth(transactionId: Int, newDateTimestamp: Int, newBudgetMonthDate: Int) {
    Self.invalidateCache()
    db.updateTransactionDateAndBudgetMonth(
      transactionId: transactionId,
      newDateTimestamp: newDateTimestamp,
      newBudgetMonthDate: newBudgetMonthDate
    )
    mirrorToSecureStore(transactionId: transactionId) { existing in
      (dateTimestamp: newDateTimestamp, budgetMonthDate: newBudgetMonthDate)
    }
  }

  /// Moves only the budget month, leaving the transaction's own date alone.
  func updateBudgetMonthDate(transactionId: Int, newBudgetMonthDate: Int) {
    Self.invalidateCache()
    db.updateTransactionBudgetMonthDate(
      transactionId: transactionId,
      newBudgetMonthDate: newBudgetMonthDate
    )
    mirrorToSecureStore(transactionId: transactionId) { existing in
      (dateTimestamp: existing.dateTimestamp, budgetMonthDate: newBudgetMonthDate)
    }
  }

  /// Rewrites just the date fields of one row in the secure store, leaving everything else as-is.
  private func mirrorToSecureStore(
    transactionId: Int,
    newDates: (Transaction) -> (dateTimestamp: Int, budgetMonthDate: Int)
  ) {
    Self.mutateSecureStore { secureTransactions in
      guard let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) else {
        return false
      }
      let existing = secureTransactions[index]
      let dates = newDates(existing)
      let updatedData = UITransactionData(
        id: existing.id,
        title: existing.title,
        amount: existing.amount,
        dateTimestamp: dates.dateTimestamp,
        budgetMonthDate: dates.budgetMonthDate,
        isRecurring: existing.isRecurring,
        hasInstallments: existing.hasInstallments,
        parentTransactionId: existing.parentTransactionId,
        installmentNumber: existing.installmentNumber,
        totalInstallments: existing.totalInstallments,
        originalAmount: existing.originalAmount,
        creditCardId: existing.creditCardId,
        statementId: existing.statementId,
        isCreditCardStatement: existing.isCreditCardStatement,
        category: existing.category,
        type: existing.type
      )
      secureTransactions[index] = Transaction(data: updatedData)
      return true
    }
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
    Self.mutateSecureStore { secureTransactions in
      guard let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) else {
        return false
      }
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
      return true
    }
  }

  func clearCreditCardFields(transactionId: Int) throws {
    Self.invalidateCache()
    try db.clearTransactionCreditCardFields(transactionId: transactionId)

    // Also update SecureLocalDataManager
    Self.mutateSecureStore { secureTransactions in
      guard let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) else {
        return false
      }
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
      return true
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
      // See the note in `insertTransaction` — omitting these drops them from the secure store, which
      // is what recurring generation dedups against.
      businessDayRule: uiData.businessDayRule,
      unadjustedDateTimestamp: uiData.unadjustedDateTimestamp,
      seriesPeriod: uiData.seriesPeriod,
      category: uiData.category,
      type: uiData.type
    )

    // 🔒 Also save to SecureLocalDataManager for UID-isolated storage
    Self.mutateSecureStore { secureTransactions in
      secureTransactions.append(Transaction(data: updatedData))
      return true
    }

    return insertedId
  }

  func updateTransactionDirectly(_ transaction: TransactionModel) throws {
    Self.invalidateCache()
    // Update SQLite directly
    try db.updateTransaction(transaction)

    // Also update SecureLocalDataManager to keep it in sync
    let didUpdate = Self.mutateSecureStore { secureTransactions -> Bool in
      guard let index = secureTransactions.firstIndex(where: { $0.id == transaction.data.id })
      else {
        return false
      }
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

      return true
    }

    if !didUpdate {
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
    Self.mutateSecureStore { secureTransactions in
      // Find and update the specific transaction
      guard let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) else {
        return false
      }
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
      return true
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

    // Carried across iterations so installment N+1 is chained one billing cycle after N rather than
    // re-derived from its own date — see the routing note in AddTransactionModalViewModel.
    var previousStatement: CreditCardStatement?

    // The rule the series was created with is carried into every rebuilt child: without this, a
    // rebuild — changing the amount, say — would silently reset the whole series to `.exact`.
    let seriesRule = templateTransaction.data.businessDayRule

    for i in 0..<newNumberOfInstallments {
      // Through `OccurrenceDateCalculator` rather than raw `byAdding: .month`, so a rebuilt series
      // lands on the same dates a freshly created one would: the same day clamping for months that
      // are too short, and the same noon anchoring that keeps a date from drifting across midnight.
      // Raw month arithmetic here silently produced a different day for a series anchored on the
      // 29th–31st, walking it further on every edit.
      let targetDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
      let occurrence = OccurrenceDateCalculator.occurrencePair(
        from: startDate,
        targetMonth: calendar.component(.month, from: targetDate),
        targetYear: calendar.component(.year, from: targetDate),
        rule: seriesRule,
        calendar: calendar
      )

      // Resolve the statement before inserting, so the row is written once with the date it will
      // actually be charged on. Routed by the unadjusted date, as on the creation path.
      var statement: CreditCardStatement?
      if let cardId = finalCreditCardId, let card = creditCardRepo.fetchCard(byId: cardId),
        let uid = AuthenticationManager.shared.currentUser?.uid
      {
        if let previous = previousStatement {
          statement = creditCardService.nextStatement(after: previous, for: card, userId: uid)
        } else {
          statement = creditCardService.getOrCreateStatement(
            for: card, transactionDate: occurrence.unadjusted, userId: uid)
        }
      }

      let effectiveDate = statement?.dueDate ?? occurrence.adjusted

      // Save the new installment
      let installmentModel = TransactionModel(
        id: nil,
        title: templateTransaction.data.title,
        category: templateTransaction.data.category,
        amount: individualAmount,
        type: templateTransaction.data.type,
        dateTimestamp: Int(effectiveDate.timeIntervalSince1970),
        budgetMonthDate: effectiveDate.monthAnchor,
        isRecurring: false,
        hasInstallments: true,
        parentTransactionId: mainInstallmentTransactionId,
        originalAmount: nil,
        installmentNumber: i + 1,
        totalInstallments: newNumberOfInstallments,
        businessDayRule: seriesRule,
        unadjustedDateTimestamp: Int(occurrence.unadjusted.timeIntervalSince1970),
        seriesPeriod: occurrence.unadjusted.monthAnchor
      )

      do {
        let insertedId = try insertTransactionAndGetId(installmentModel)

        // Assign credit card statement if installments are on a card
        if let cardId = finalCreditCardId, let statement = statement, let statementId = statement.id {
          try updateCreditCardFields(
            transactionId: insertedId,
            creditCardId: cardId,
            statementId: statementId,
            isCreditCardStatement: false
          )
          creditCardService.recalculateStatementTotal(statementId: statementId)
          previousStatement = statement
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
    let didUpdate = Self.mutateSecureStore { secureTransactions -> Bool in
      // Find and update only the specific transaction
      guard let index = secureTransactions.firstIndex(where: { $0.id == id }) else { return false }
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
      secureTransactions[index] = Transaction(data: updatedData)
      return true
    }

    // Outside the lock: notification work has no business holding the store.
    if didUpdate {
      // Reschedule notification for the updated transaction
      rescheduleNotificationForTransaction(transactionId: id)
    }
  }

  func updateTransactionParentId(transactionId: Int, parentId: Int) throws {
    Self.invalidateCache()
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)

    // Also update SecureLocalDataManager for UID-isolated storage
    Self.mutateSecureStore { secureTransactions in
      guard let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) else {
        return false
      }
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
      secureTransactions[index] = Transaction(data: updatedData)
      return true
    }
  }

  /// Updates the isRecurring flag for a transaction (used when stopping future recurrence)
  func updateIsRecurring(transactionId: Int, isRecurring: Bool) throws {
    Self.invalidateCache()
    try db.updateIsRecurring(transactionId: transactionId, isRecurring: isRecurring)

    // Also update SecureLocalDataManager for UID-isolated storage
    Self.mutateSecureStore { secureTransactions in
      guard let index = secureTransactions.firstIndex(where: { $0.id == transactionId }) else {
        return false
      }
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
      secureTransactions[index] = Transaction(data: updatedData)
      return true
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

      // Record the month so lazy generation doesn't immediately put it back. Without this the row
      // reappeared the next time the user browsed onto that month — the delete looked like it had
      // silently failed. Recurring only: installments are all created upfront and are deleted by
      // scope rather than by occurrence, so they never need an exclusion.
      if isRecurringTransaction {
        let parentId = transaction.parentTransactionId ?? id
        RecurringTransactionManager.trackDeletedInstance(
          parentId: parentId, monthAnchor: transaction.budgetMonthDate)
      }

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
        // The series is going away entirely, so its per-month exclusions are dead weight — and a
        // stale entry would suppress generation for a later series that reused the parent's row id.
        RecurringTransactionManager.clearDeletedInstanceTracking(
          for: transaction.parentTransactionId ?? id)
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

  /// Removes a recurring transaction together with every occurrence of its series.
  ///
  /// This used to delete only the row it was handed, on the grounds that removing the rest would be
  /// destructive. But it is the branch `deleteTransactionAndRelated` routes recurring transactions
  /// to — the plain "Delete" on the transaction details, statement and allocation screens — so the
  /// user asked to delete a recurring transaction, was given no choice of scope, and got one month
  /// removed with the rest of the series silently left behind. Callers that genuinely want a single
  /// occurrence have `deleteTransactionWithOption(id:option: .currentSelection)` for exactly that.
  ///
  /// Aligned with release/v1.6.0 and the installment-payment branch, where the same method already
  /// removes the whole series.
  private func deleteRecurringTransactionAndInstances(transactionId: Int) throws {
    try deleteAllRecurringTransactionOccurrences(transactionId: transactionId)
  }

  /// Every row of `transaction`'s recurring series, resilient to a parent that has gone missing.
  ///
  /// A series is normally found through `parentTransactionId`. But instances are regenerated (their
  /// ids change) and parents get deleted, leaving siblings that point at an id nothing else shares.
  /// Filtering on that id then matches only the row the user opened, so "this and remaining" removed
  /// exactly one occurrence and looked like it had done nothing.
  ///
  /// The broadened match is deliberately narrow: same title, amount AND category, and recurring. For a
  /// delete, matching too much is far worse than matching too little, so it only kicks in when the
  /// parent row genuinely is not there.
  private func recurringSeriesMembers(of transaction: Transaction, in all: [Transaction])
    -> [Transaction]
  {
    let groupId = transaction.parentTransactionId ?? transaction.id
    let byParent = all.filter { tx in
      guard let txId = tx.id else { return false }
      return txId == groupId || tx.parentTransactionId == groupId
    }

    let parentExists = all.contains { $0.id == groupId }
    guard !parentExists else { return byParent }

    let siblings = all.filter { tx in
      tx.mode == .recurring && tx.title == transaction.title
        && tx.amount == transaction.amount && tx.category == transaction.category
    }

    var byId: [Int: Transaction] = [:]
    for tx in byParent + siblings {
      if let id = tx.id { byId[id] = tx }
    }

    logDebug(
      "TransactionRepository: recurring parent \(groupId.map(String.init) ?? "nil") is missing — "
        + "resolved \(byId.count) series row(s) by title+amount+category instead of \(byParent.count)")

    return Array(byId.values)
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
    let relatedTransactions = recurringSeriesMembers(of: current, in: allTransactions)

    logDebug("TransactionRepository: Found \(relatedTransactions.count) transactions to delete")

    try deleteBatch(ids: relatedTransactions.compactMap { $0.id })
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
    let relatedTransactions = recurringSeriesMembers(of: current, in: allTransactions)
      .filter { $0.date >= currentDate }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) future transactions to delete")

    try deleteBatch(ids: relatedTransactions.compactMap { $0.id })

    // IMPORTANT: stop EVERY parent the deleted rows belonged to from generating new future
    // instances, not just the group id the opened instance pointed at. Future months are generated
    // lazily from the parent, so any parent left with is_recurring = 1 recreates the months that were
    // just deleted — which is what made this look like nothing had been deleted. A drifted series has
    // more than one parent, so stopping only one leaves the rest generating.
    let parentIds = Set(
      relatedTransactions.compactMap { $0.parentTransactionId ?? $0.id }
        + [recurringGroupId].compactMap { $0 })

    for parentId in parentIds {
      let remainingInstances = fetchTransactionInstancesForRecurring(parentId)

      if remainingInstances.isEmpty {
        // No instances left - delete the parent entirely
        let updatedTransactions = fetchAllTransactions()
        if updatedTransactions.first(where: { $0.id == parentId && $0.isRecurring == true }) != nil {
          logDebug("TransactionRepository: Deleting orphaned parent \(parentId)")
          try delete(id: parentId)
        }
      } else if fetchAllTransactions().contains(where: { $0.id == parentId }) {
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

    try deleteBatch(ids: relatedTransactions.compactMap { $0.id })
  }

  private func deleteInstallmentTransactionAndSiblings(parentId: Int) throws {
    let allTransactions = fetchAllTransactions()

    logDebug("TransactionRepository: Deleting installment transaction and siblings for parentId \(parentId)")

    let installments = allTransactions.filter { transaction in
      guard let txParentId = transaction.parentTransactionId else { return false }
      return txParentId == parentId
    }

    logDebug("TransactionRepository: Found \(installments.count) installments to delete")

    // Children and the parent placeholder go together, in one batch — a partial series deletion
    // leaves orphaned children pointing at a parent that no longer exists.
    try deleteBatch(ids: installments.compactMap { $0.id } + [parentId])
  }

  func fetchInstallmentTransactions(parentId: Int) -> [Transaction] {
    return fetchAllTransactions().filter { $0.parentTransactionId == parentId }
  }

  // MARK: - Test Helper Methods
  func clearAllTransactionsForTesting() {
    // Deleted-occurrence exclusions are keyed by parent row id, so they outlive the rows they refer
    // to. Emptying the store without clearing them lets the next series created under a reused id
    // inherit them, and occurrences the user never deleted go silently ungenerated.
    RecurringTransactionManager.clearAllDeletedInstanceTracking()

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

  /// Reconciles the reminder for a transaction whose state changed outside the normal write paths.
  ///
  /// Early payment and cancellation change what a row MEANS without editing the row itself, so they
  /// have no other way in. Without this an installment paid ahead would go on reminding the user to
  /// pay it, and reversing the payment would leave it with no reminder at all.
  func reconcileNotification(transactionId: Int) {
    rescheduleNotificationForTransaction(transactionId: transactionId)
  }

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

    // An installment paid ahead of schedule gets no reminder — the money already left the account on
    // the early-payment debit, and reminding the user to pay it again is worse than saying nothing.
    guard DBHelper.shared.settledByTransactionId(transactionId: transactionId) == nil else { return }

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
}
