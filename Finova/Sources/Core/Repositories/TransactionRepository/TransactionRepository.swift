//
//  TransactionRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class TransactionRepository: TransactionRepositoryProtocol {
  /// Injectable so tests can point two repositories at two genuinely separate databases.
  /// Production always uses `.shared`.
  private let db: DBHelper

  init(db: DBHelper = .shared) { self.db = db }

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
    try deleteBatch(ids: [id])
  }

  /// Deletes several transactions as one unit.
  ///
  /// Series deletions ("this and remaining", "all occurrences") remove tens of rows at once. Doing
  /// that through repeated single deletes meant one cache invalidation, one statement recalculation
  /// and one `transactionDataChanged` broadcast *per row* — so a 36-month series fired 36 UI
  /// refreshes, each re-reading the whole ledger, and left the screen showing a half-deleted series
  /// in between.
  ///
  /// The per-row work is identical to `delete(id:)`; only the shared aftermath is hoisted out and run
  /// once.
  ///
  /// Deliberately NOT wrapped in `db.inTransaction`. That was the obvious next step — a partial
  /// failure would roll the whole batch back — but it silently lost deletes: rows that had been
  /// removed reappeared. The per-row writes go through `executeSyncUpdate`, which pokes
  /// `SyncChangeTracker` and wakes the sync engine on another thread mid-transaction, so an outer
  /// BEGIN/COMMIT around them is not currently safe. Losing a delete is far worse than not having
  /// atomicity here, so this stays a plain loop until that interaction is untangled.
  func deleteBatch(ids: [Int]) throws {
    guard !ids.isEmpty else { return }
    Self.invalidateCache()

    // Statement links have to be read before the rows go.
    let doomed = Set(ids)
    let affectedStatementIds = Set(
      fetchAllTransactions()
        .filter { $0.id.map(doomed.contains) ?? false }
        .compactMap { $0.statementId }
    )

    for id in ids {
      try deleteRow(id: id)
    }

    Self.invalidateCache()

    for stmtId in affectedStatementIds {
      CreditCardService().recalculateStatementTotal(statementId: stmtId)
    }

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

    // Cancel any scheduled notification for this transaction
    TransactionNotificationManager.shared.cancelNotification(for: id)

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

    if let txId = transaction.data.id {
      TransactionNotificationManager.shared.rescheduleNotification(for: txId)
    }
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  func updateParentTransactionId(transactionId: Int, parentId: Int) throws {
    Self.invalidateCache()
    try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)
  }

  func updateDateAndBudgetMonth(transactionId: Int, newDateTimestamp: Int, newBudgetMonthDate: Int) {
    Self.invalidateCache()
    db.updateTransactionDateAndBudgetMonth(
      transactionId: transactionId,
      newDateTimestamp: newDateTimestamp,
      newBudgetMonthDate: newBudgetMonthDate
    )
  }

  func updateBudgetMonthDate(transactionId: Int, newBudgetMonthDate: Int) {
    Self.invalidateCache()
    db.updateTransactionBudgetMonthDate(
      transactionId: transactionId,
      newBudgetMonthDate: newBudgetMonthDate
    )
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

      if let txId = relatedTransaction.id {
        TransactionNotificationManager.shared.rescheduleNotification(for: txId)
      }
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

    // Even split with the remainder added to installment #1, matching the creation
    // path (AddTransactionModalViewModel). A plain `total / count` silently dropped
    // the remainder, which made installment #1 change while the rest looked untouched.
    let baseAmount = newTotalAmount / newNumberOfInstallments
    let remainder = newTotalAmount % newNumberOfInstallments

    let originalCreditCardId = relatedTransactions.first(where: { $0.creditCardId != nil })?.creditCardId
    let finalCreditCardId = templateTransaction.data.creditCardId ?? originalCreditCardId
    let oldStatementIds = Set(relatedTransactions.compactMap { $0.statementId })

    // Update the parent placeholder in place (never delete it — children would then
    // point at a soft-deleted parent). Keep its amount at 0 so it never affects totals,
    // matching how the parent is created.
    let parentModel = TransactionModel(
      id: mainInstallmentTransactionId,
      title: templateTransaction.data.title,
      category: templateTransaction.data.category,
      amount: 0,
      type: templateTransaction.data.type,
      dateTimestamp: Int(newDate.timeIntervalSince1970),
      budgetMonthDate: newDate.monthAnchor,
      isRecurring: false,
      hasInstallments: true,
      parentTransactionId: nil,
      originalAmount: newTotalAmount,
      installmentNumber: nil,
      totalInstallments: newNumberOfInstallments,
      creditCardId: finalCreditCardId,
      isCreditCardStatement: finalCreditCardId != nil ? false : nil
    )
    try updateTransactionDirectly(parentModel)
    markSyncPending(for: mainInstallmentTransactionId)

    let startDate = newDate
    let creditCardService = CreditCardService()
    let creditCardRepo = CreditCardRepository()
    let uid = AuthenticationManager.shared.currentUser?.uid

    // Build & insert ALL new children FIRST. Only after every child is created do we
    // delete the old ones — so a mid-loop failure can be rolled back, never leaving a
    // half-rebuilt series (the old "delete all, then recreate one-by-one" order left a
    // partial set when any insert/statement step threw).
    var insertedChildIds: [Int] = []
    var newStatementIds: Set<Int> = []
    // Track the previous installment's statement so each installment lands in the
    // billing cycle right after the previous one (consecutive cycles), matching the
    // creation path. Per-installment date routing could collapse two into one cycle.
    var previousStatement: CreditCardStatement? = nil

    do {
      for i in 0..<newNumberOfInstallments {
        let installmentDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
        let installmentAmount = i == 0 ? baseAmount + remainder : baseAmount

        let installmentModel = TransactionModel(
          id: nil,
          title: templateTransaction.data.title,
          category: templateTransaction.data.category,
          amount: installmentAmount,
          type: templateTransaction.data.type,
          dateTimestamp: Int(installmentDate.timeIntervalSince1970),
          budgetMonthDate: installmentDate.monthAnchor,
          isRecurring: false,
          hasInstallments: false,
          parentTransactionId: mainInstallmentTransactionId,
          originalAmount: newTotalAmount,
          installmentNumber: i + 1,
          totalInstallments: newNumberOfInstallments
        )

        let insertedId = try insertTransactionAndGetId(installmentModel)
        insertedChildIds.append(insertedId)

        if let cardId = finalCreditCardId, let card = creditCardRepo.fetchCard(byId: cardId), let uid = uid {
          let statement: CreditCardStatement?
          if let prev = previousStatement {
            statement = creditCardService.nextStatement(after: prev, for: card, userId: uid)
          } else {
            statement = creditCardService.getOrCreateStatement(for: card, transactionDate: installmentDate, userId: uid)
          }
          if let statement = statement, let stmtId = statement.id {
            try updateCreditCardFields(
              transactionId: insertedId,
              creditCardId: cardId,
              statementId: stmtId,
              isCreditCardStatement: false
            )
            newStatementIds.insert(stmtId)

            // Remap installment date to statement due date
            let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
            let dueDateBudgetMonth = statement.dueDate.monthAnchor
            updateDateAndBudgetMonth(
              transactionId: insertedId,
              newDateTimestamp: dueDateTimestamp,
              newBudgetMonthDate: dueDateBudgetMonth
            )

            previousStatement = statement
          }
        }
      }
    } catch {
      // Roll back the children we just created so the original series stays intact.
      for newId in insertedChildIds {
        try? delete(id: newId)
      }
      logError("Failed to rebuild installments, rolled back \(insertedChildIds.count) new children: \(error)")
      throw error
    }

    // All new children created successfully — now remove the old individual children.
    for relatedTransaction in relatedTransactions {
      guard relatedTransaction.parentTransactionId != nil else { continue }
      if let id = relatedTransaction.id {
        try delete(id: id)
      }
    }

    // Recalculate totals for every affected statement (old that lost children + new).
    for stmtId in oldStatementIds.union(newStatementIds) {
      creditCardService.recalculateStatementTotal(statementId: stmtId)
    }

    // Reschedule consolidated installment notifications after editing
    InstallmentNotificationManager.shared.rescheduleNotifications(parentTransactionId: mainInstallmentTransactionId)
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
    TransactionNotificationManager.shared.rescheduleNotification(for: id)
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
      // For a recurring instance, record the deleted month so lazy generation
      // doesn't immediately recreate it.
      if isRecurringTransaction {
        let parentId = transaction.parentTransactionId ?? id
        RecurringTransactionManager.trackDeletedInstance(
          parentId: parentId, monthAnchor: transaction.budgetMonthDate)
      }

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

  /// Removes a recurring transaction together with every occurrence of its series.
  ///
  /// This used to delete the single row it was handed, despite the name and despite being the branch
  /// `deleteTransactionAndRelated` routes recurring transactions to — so "delete" from the details,
  /// statement and allocation screens removed one month and silently left the rest of the series
  /// behind.
  private func deleteRecurringTransactionAndInstances(transactionId: Int) throws {
    try deleteAllRecurringTransactionOccurrences(transactionId: transactionId)
  }

  /// Every row of `transaction`'s recurring series, resilient to a parent that has gone missing.
  ///
  /// A series is normally found through `parentTransactionId`. But instances are regenerated (their
  /// ids change), parents get deleted or soft-deleted, and cross-device sync can land instances whose
  /// parent row never arrived — leaving siblings that point at an id nothing else shares. Filtering on
  /// that id then matches only the row the user opened, so "this and remaining" removed exactly one
  /// occurrence and looked like it had done nothing.
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
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    let recurringGroupId = current.parentTransactionId ?? current.id

    logDebug("TransactionRepository: Deleting all recurring occurrences for transaction \(transactionId), recurringGroupId: \(String(describing: recurringGroupId))")

    let relatedTransactions = recurringSeriesMembers(of: current, in: allTransactions)

    logDebug("TransactionRepository: Found \(relatedTransactions.count) transactions to delete")

    try deleteBatch(ids: relatedTransactions.compactMap { $0.id })

    // The whole series is gone — clear its consolidated recurring reminders (per-tx cancels
    // above don't touch the month-bucketed notifications).
    if let gid = recurringGroupId {
      RecurringNotificationManager.shared.cancelNotifications(forParent: gid)
    }
  }

  private func deleteFutureRecurringInstances(transactionId: Int) throws {
    let allTransactions = fetchAllTransactions()
    let currentTransaction = allTransactions.first { $0.id == transactionId }

    guard let current = currentTransaction else {
      throw TransactionError.transactionNotFound
    }

    let recurringGroupId = current.parentTransactionId ?? current.id
    // Compare on the month anchor, NOT the full timestamp. `date` and `budgetMonthDate`
    // are stored independently (and a CC-linked instance's `date` can be remapped to a
    // due date in a different calendar month), so a raw-Date compare would miss or
    // over-include instances. The month anchor matches how the app groups months and
    // how the recurring EDIT path selects "future" instances.
    let currentAnchor = current.budgetMonthDate

    logDebug("TransactionRepository: Deleting future recurring instances for transaction \(transactionId), recurringGroupId: \(String(describing: recurringGroupId)), currentAnchor: \(currentAnchor)")

    // Before we stop the parent's recurrence below, materialize any months between the
    // parent and the cutoff that were never lazily generated — otherwise disabling
    // recurrence would prevent those (legitimately pre-cutoff) months from ever existing.
    if let groupId = recurringGroupId {
      RecurringTransactionManager().backfillRecurringMonths(
        parentTransactionId: groupId, cutoffAnchor: currentAnchor)
    }

    let relatedTransactions = recurringSeriesMembers(of: current, in: allTransactions)
      .filter { $0.budgetMonthDate >= currentAnchor }

    logDebug("TransactionRepository: Found \(relatedTransactions.count) future transactions to delete")

    try deleteBatch(ids: relatedTransactions.compactMap { $0.id })

    // Stop recurrence on EVERY parent the deleted rows belonged to, not just the group id the user's
    // instance happened to point at. Future months are generated lazily from the parent, so a parent
    // left with `is_recurring = 1` simply recreates the months that were just deleted — which is what
    // made this look like nothing had been deleted at all. A drifted series has more than one parent,
    // so stopping only one of them leaves the rest generating.
    let parentIds = Set(
      relatedTransactions.compactMap { $0.parentTransactionId ?? $0.id }
        + [recurringGroupId].compactMap { $0 })

    for parentId in parentIds {
      let remainingInstances = fetchTransactionInstancesForRecurring(parentId)

      if remainingInstances.isEmpty {
        let updatedTransactions = fetchAllTransactions()
        if updatedTransactions.first(where: { $0.id == parentId && $0.isRecurring == true }) != nil {
          logDebug("TransactionRepository: Deleting orphaned parent \(parentId)")
          try delete(id: parentId)
        }
      } else if fetchAllTransactions().contains(where: { $0.id == parentId }) {
        logDebug("TransactionRepository: Stopping future recurrence for parent \(parentId)")
        try updateIsRecurring(transactionId: parentId, isRecurring: false)
      }
    }

    // Recompute the recurring series' consolidated reminders from the REMAINING instances.
    if let gid = recurringGroupId {
      RecurringNotificationManager.shared.rescheduleNotifications(parentTransactionId: gid)
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

    try deleteBatch(ids: relatedTransactions.compactMap { $0.id })

    // If no installment children remain, remove the orphaned parent placeholder so it
    // doesn't linger invisibly (the parent has installmentNumber == nil, so the loop
    // above never covers it).
    if let groupId = installmentGroupId {
      let remainingChildren = fetchAllTransactions().filter {
        $0.parentTransactionId == groupId && $0.installmentNumber != nil
      }
      if remainingChildren.isEmpty,
         fetchAllTransactions().first(where: { $0.id == groupId && $0.hasInstallments == true }) != nil {
        logDebug("TransactionRepository: Deleting orphaned installment parent \(groupId)")
        try delete(id: groupId)
      }
      // Recompute the installment series' consolidated reminders from the REMAINING children.
      InstallmentNotificationManager.shared.rescheduleNotifications(parentTransactionId: groupId)
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

    // Children and the parent placeholder go together, in one batch — a partial series deletion
    // leaves orphaned children pointing at a parent that no longer exists.
    try deleteBatch(ids: installments.compactMap { $0.id } + [parentId])

    // The whole installment series is gone — clear its consolidated reminders.
    InstallmentNotificationManager.shared.cancelNotifications(forParent: parentId)
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

  func fetchSharedGroupId(for transactionId: Int) -> String? {
    return db.fetchSingleString(
      "SELECT shared_group_id FROM Transactions WHERE id = ?;",
      intBinding: transactionId
    )
  }

  // MARK: - CloudKit Sync Methods

  /// Rows awaiting a CloudKit push.
  ///
  /// `updated_at` MUST be selected here: it is the ordering key for conflict resolution on the
  /// receiving device. Without it `Transaction.updatedAt` was nil and the CK adapter stamped every
  /// pushed record with `Date()` — the *push* time — while the receiving device compared that
  /// against its own real *edit* time. Any bulk re-push that doesn't represent a user edit (mirror
  /// reconcile, credit-card repair, force re-push, group-zone migration) therefore looked newer
  /// than a genuine edit on the other device and silently reverted it.
  func fetchPendingSync() -> [Transaction] {
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      let query = """
        SELECT id, title, category, type, amount, date, budget_month_date,
               is_recurring, has_installments, parent_transaction_id,
               installment_number, total_installments, original_amount,
               credit_card_id, statement_id, is_credit_card_statement, created_by_uid,
               updated_at
        FROM Transactions WHERE sync_status = 'pending' AND user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
        """
      return (try? db.executeTransactionQueryPublicText(query, textBindings: [uid])) ?? []
    }
    let query = """
      SELECT id, title, category, type, amount, date, budget_month_date,
             is_recurring, has_installments, parent_transaction_id,
             installment_number, total_installments, original_amount,
             credit_card_id, statement_id, is_credit_card_statement, created_by_uid,
             updated_at
      FROM Transactions WHERE sync_status = 'pending' AND (is_deleted IS NULL OR is_deleted = 0);
      """
    return (try? db.executeTransactionQueryPublic(query)) ?? []
  }

  /// Clears the pending flag after a successful push.
  ///
  /// `pushedUpdatedAt` is the `updated_at` of the snapshot that was actually sent. If the row has
  /// been edited since (its `updated_at` is now newer), the flag is LEFT pending so the newer
  /// version is pushed on the next cycle. Clearing unconditionally — the old behaviour — silently
  /// destroyed any edit the user made while the push was in flight: the row was marked 'synced'
  /// while holding values CloudKit had never seen, so it was never pushed again.
  func markAsSynced(ckRecordName: String, pushedUpdatedAt: Date? = nil) {
    Self.invalidateCache()
    // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
    guard let pushedUpdatedAt = pushedUpdatedAt else {
      db.executeSyncUpdate(
        "UPDATE Transactions SET sync_status = 'synced' WHERE ck_record_id = ?;",
        textBindings: [ckRecordName]
      )
      return
    }
    // COALESCE so legacy rows with no updated_at still settle instead of looping forever.
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'synced' WHERE ck_record_id = ? AND COALESCE(updated_at, 0) <= ?;",
      textBindings: [ckRecordName],
      intBindings: [Int(pushedUpdatedAt.timeIntervalSince1970)]
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

    // A transaction created on another device must get a local notification here — the
    // inbound sync path previously scheduled nothing, so cross-device additions never reminded.
    if let inserted = fetchTransaction(byCKRecordName: ckRecordName), let insertedId = inserted.id {
      reconcileNotifications(forLocalId: insertedId)
    }
  }

  func updateFromCloud(_ transaction: Transaction, ckRecordName: String, sharedGroupId: String? = nil) {
    Self.invalidateCache()
    let category = transaction.category.key
    let type = String(describing: transaction.type)

    // Preserve a non-null local `shared_group_id` when the inbound value is nil (COALESCE):
    // an inbound pull with mirror mode off (or a record read from the plain private zone without
    // zone-name tag injection) must NOT strip a record's group tag — that hides it from the group
    // view. A real re-tag/un-share still arrives as a non-null value and overwrites correctly.
    let query = """
      UPDATE Transactions SET
        title = ?, category = ?, type = ?, amount = ?, date = ?,
        budget_month_date = ?, is_recurring = ?, has_installments = ?,
        parent_transaction_id = ?, installment_number = ?,
        total_installments = ?, original_amount = ?,
        credit_card_id = ?, statement_id = ?, is_credit_card_statement = ?,
        sync_status = 'synced', ck_modified_at = ?,
        shared_group_id = COALESCE(?, shared_group_id),
        updated_at = ?,
        created_by_uid = COALESCE(?, created_by_uid)
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

    // A transaction edited on another device (amount/date/title) must update its local
    // notification content and fire date, instead of firing stale.
    if let updated = fetchTransaction(byCKRecordName: ckRecordName), let updatedId = updated.id {
      reconcileNotifications(forLocalId: updatedId)
    }
  }

  func markSyncPending(for id: Int) {
    let now = Int(Date().timeIntervalSince1970)
    db.executeSyncUpdate(
      "UPDATE Transactions SET sync_status = 'pending', ck_modified_at = ? WHERE id = ?;",
      intBindings: [now, id]
    )
  }

  /// Single entry point to (re)schedule the correct notification(s) for a transaction after it
  /// was created or changed — including changes arriving FROM the cloud (another device). Routes
  /// to the right manager by the transaction's kind so the identifier scheme stays consistent:
  /// installment/recurring children recompute their parent's consolidated notification (so an
  /// edited/added/removed item is reflected), one-off transactions reschedule their own, and
  /// parent placeholders (which never carry a user-facing notification) are skipped.
  func reconcileNotifications(forLocalId id: Int) {
    guard let tx = fetchTransaction(byId: id) else { return }
    if let parentId = tx.parentTransactionId, tx.installmentNumber != nil {
      InstallmentNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
    } else if let parentId = tx.parentTransactionId, tx.isRecurring == true {
      RecurringNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
    } else if tx.hasInstallments == true || tx.isRecurring == true {
      // Parent placeholder — no standalone notification of its own.
      return
    } else {
      TransactionNotificationManager.shared.rescheduleNotification(for: id)
    }
  }

  func deleteFromCloud(ckRecordName recordName: String) {
    Self.invalidateCache()
    // Capture the row (and its parent, if a child) BEFORE deleting so we can update the right
    // notification afterward — a transaction deleted on another device must clear/recompute its
    // reminder here (the inbound path previously only cancelled a per-tx id, missing the
    // consolidated installment/recurring month buckets).
    let doomed = fetchTransaction(byCKRecordName: recordName)

    // RECREATION-WINS — the delete-vs-edit policy, applied identically in all five repositories.
    //
    // If the local row has unpushed edits (sync_status = 'pending'), do NOT apply the remote delete:
    // the local change re-pushes and the record comes back. 'pendingDelete' still deletes (we agreed
    // to delete it too); 'synced' deletes normally.
    //
    // Why this is not ordered by `rev` like every other conflict: a CloudKit deletion carries no
    // record. `recordDeletedBlock` hands over a record ID and nothing else, so there is no version to
    // compare an edit against. Ordering the two would require tombstones on the wire — `isDeleted`
    // pushed as a field update instead of a delete — which only CreditCard currently has.
    //
    // So the choice is made under genuine ambiguity, on which failure is recoverable: a resurrected
    // row is visible and the user can delete it again, whereas a swallowed edit is money that
    // silently is not there. DeleteVsEditTests pins the behaviour AND that it converges — a rule that
    // kept the row on one device and dropped it on the other would be worse than either answer.
    if let localId = doomed?.id,
       db.fetchSingleString("SELECT sync_status FROM Transactions WHERE id = ?;", intBinding: localId) == "pending" {
      logWarning("[Sync] Skipping inbound delete of transaction \(localId) — unpushed local edit exists (recreation wins)")
      return
    }

    if let localId = doomed?.id {
      TransactionNotificationManager.shared.cancelNotification(for: localId)
    }
    db.executeSyncUpdate(
      "DELETE FROM Transactions WHERE ck_record_id = ?;",
      textBindings: [recordName]
    )
    // Recompute the parent's consolidated notification from the REMAINING children.
    if let parentId = doomed?.parentTransactionId {
      if doomed?.installmentNumber != nil {
        InstallmentNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
      } else if doomed?.isRecurring == true {
        RecurringNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
      }
    }
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
    // Cancel any scheduled notification before deleting the row
    if let localId = db.fetchSingleInt(
      "SELECT id FROM Transactions WHERE ck_record_id = ?;",
      textBinding: recordName
    ) {
      TransactionNotificationManager.shared.cancelNotification(for: localId)
    }
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

  /// DISABLED (data-safety): this deleted every cloud-linked transaction and stripped
  /// `ck_record_id` from the survivors, which destroyed data on a freshly-synced device and
  /// caused survivors to re-upload as duplicates. It is intentionally a no-op now — removing
  /// cloud-linked rows or detaching their CK identity can never be safe as a blanket operation.
  /// (No caller remains; kept neutered as a guard against reintroduction.)
  func removeCloudInsertedRecords() {
    logWarning("[TransactionRepository] removeCloudInsertedRecords is disabled (non-destructive)")
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
