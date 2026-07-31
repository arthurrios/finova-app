//
//  RecurringTransactionManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/06/25.
//

import Foundation

enum RecurringCleanupOption {
  case currentSelection
  case futureOnly
  case all
}

enum RecurringEditOption {
  case currentSelection
  case futureOnly
  case all
}

final class RecurringTransactionManager {
  /// EAGER BOUNDED GENERATION: a recurring series always materializes its occurrences as real
  /// rows from its start month through `now + horizonMonths`. Occurrences are created at
  /// creation time (full horizon, pushed immediately) and kept rolling forward by an
  /// idempotent, forward-only, tombstone-aware, hydration-gated top-up on dashboard load —
  /// never reactively per-navigation. This is what makes recurring sync cleanly: every
  /// occurrence is a first-class synced row created once, not regenerated independently on
  /// each device (which produced duplicates and resurrected deletions).
  static let horizonMonths = 36

  private let transactionRepo: TransactionRepository
  private let creditCardService: CreditCardService
  private let creditCardRepo: CreditCardRepository
  private let calendar: Calendar
  /// Needed to derive generated rows' identities. Injectable for the same reason the repositories
  /// are: a two-device test drives two databases.
  private let db: DBHelper

  // MARK: - Concurrency Control
  // Static so ALL manager instances share one serial queue. Recurring generation,
  // edits and deletes are then mutually serialized across the whole app — previously
  // each instance had its own queue, so (for example) an "edit future" on the
  // AddTransaction screen's manager could run concurrently with lazy generation on the
  // Dashboard's manager and interleave reads/writes on the same series.
  private static let operationQueue = DispatchQueue(
    label: "recurring.transaction.operations", qos: .userInitiated)
  private static var currentOperations: Set<String> = []
  private static let operationLock = NSLock()

  // MARK: - Deleted Instance Tracking
  // Tracks instances deleted via .currentSelection to prevent lazy generation from recreating them.
  // Key: parentTransactionId, Value: set of month anchors that should NOT be regenerated.
  // Static + lock-guarded so every manager instance AND the repository's delete path
  // share the same view (previously each instance had its own copy, so a delete on one
  // instance didn't stop regeneration driven by another).
  private static var deletedInstanceAnchors: [Int: Set<Int>] = [:]
  private static let deletedAnchorsLock = NSLock()

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    creditCardService: CreditCardService = CreditCardService(),
    creditCardRepo: CreditCardRepository = CreditCardRepository(),
    db: DBHelper = .shared
  ) {
    self.transactionRepo = transactionRepo
    self.creditCardService = creditCardService
    self.creditCardRepo = creditCardRepo
    self.db = db

    // Usar calendar com fuso horário UTC para consistência com monthAnchor
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!
    self.calendar = utcCalendar
  }

  func generateRecurringTransactionsForRange(
    _ monthRange: ClosedRange<Int>,
    referenceDate: Date = Date(),
    transactionStartDate: Date? = nil
  ) {
    // Use async queue to prevent blocking the main thread
    Self.operationQueue.async { [weak self] in
      guard let self = self else { return }

      let recurringTransactions = self.transactionRepo.fetchRecurringTransactions()

      // Fetch all transactions once instead of per-transaction
      let allTransactions = self.transactionRepo.fetchAllTransactions()
      let allTransactionIds = Set(allTransactions.compactMap { $0.id })

      for recurringTx in recurringTransactions {
        guard let recurringTxId = recurringTx.id else { continue }

        // Use the pre-fetched set for efficient existence check
        guard allTransactionIds.contains(recurringTxId) else { continue }

        self.generateInstancesForTransaction(
          recurringTx,
          in: monthRange,
          referenceDate: referenceDate,
          transactionStartDate: transactionStartDate
        )
      }
    }
  }

  /// Generate instances for a newly created recurring transaction (optimized for single transaction)
  func generateInstancesForNewRecurringTransaction(
    _ recurringTx: Transaction,
    in monthRange: ClosedRange<Int>,
    referenceDate: Date,
    transactionStartDate: Date? = nil,
    completion: (() -> Void)? = nil
  ) {
    guard recurringTx.id != nil else {
      completion?()
      return
    }

    // Use async queue to prevent blocking the main thread
    Self.operationQueue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion?() }
        return
      }

      self.performInstanceGeneration(
        for: recurringTx,
        in: monthRange,
        referenceDate: referenceDate,
        transactionStartDate: transactionStartDate
      )

      // Call completion on main thread
      DispatchQueue.main.async { completion?() }
    }
  }

  func generateInstancesForTransaction(
    _ recurringTx: Transaction,
    in monthRange: ClosedRange<Int>,
    referenceDate: Date,
    transactionStartDate: Date? = nil
  ) {
    performInstanceGeneration(
      for: recurringTx,
      in: monthRange,
      referenceDate: referenceDate,
      transactionStartDate: transactionStartDate
    )
  }

  // MARK: - Private Instance Generation Logic

  private func performInstanceGeneration(
    for recurringTx: Transaction,
    in monthRange: ClosedRange<Int>,
    referenceDate: Date,
    transactionStartDate: Date? = nil
  ) {
    guard let recurringTxId = recurringTx.id else { return }

    // Get existing instances for this specific recurring transaction
    let existingInstances = transactionRepo.fetchTransactionInstancesForRecurring(recurringTxId)
    let existingAnchors = Set(existingInstances.map { $0.budgetMonthDate })

    // Determine the effective start anchor
    let effectiveStartAnchor: Int
    if let startDate = transactionStartDate {
      effectiveStartAnchor = startDate.monthAnchor
    } else {
      effectiveStartAnchor = recurringTx.budgetMonthDate
    }

    var newInstances: [TransactionModel] = []

    for monthOffset in monthRange {
      guard let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: referenceDate)
      else { continue }

      let targetAnchor = targetDate.monthAnchor

      // Skip if an instance already exists for this period
      if existingAnchors.contains(targetAnchor) { continue }

      // Never create an instance for the same month as the parent transaction
      if targetAnchor == recurringTx.budgetMonthDate { continue }

      // Create instances for the effective start anchor and all future periods
      if targetAnchor >= effectiveStartAnchor {
        let originalDate = Date(timeIntervalSince1970: TimeInterval(recurringTx.dateTimestamp))

        // Generate a valid date for the target month
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)
        let instanceDate = generateValidDateForMonth(
          originalDate: originalDate,
          targetMonth: targetMonth,
          targetYear: targetYear
        )

        // Create the instance, preserving credit card association from parent
        let instanceModel = TransactionModel(
          title: recurringTx.title,
          category: recurringTx.category.key,
          amount: recurringTx.amount,
          type: recurringTx.type.key,
          dateTimestamp: Int(instanceDate.timeIntervalSince1970),
          budgetMonthDate: targetAnchor,
          parentTransactionId: recurringTxId,
          creditCardId: recurringTx.creditCardId
        )

        do {
          let insertedId = try transactionRepo.insertTransactionAndGetId(instanceModel)
          newInstances.append(instanceModel)

          // Derived identity: both devices compute the same uuid for (series, month), so a month
          // materialised independently on two devices is ONE row rather than two that
          // ConflictResolver then has to guess are the same by title + amount + month.
          if let parentId = recurringTx.id,
             let parentUuid = db.uuidIdentity(table: "Transactions", localId: parentId)?.uuid {
            db.assignDeterministicUuid(
              table: "Transactions", localId: insertedId,
              uuid: DeterministicIdentity.recurringInstance(
                parentUuid: parentUuid, monthDate: targetAnchor))
          }

          // An instance belongs to whatever ledger its SERIES belongs to. Mirror mode used to
          // stamp the mirrored group here instead, so instances of a personal series were born
          // tagged to a group the series itself was not in.
          if let parentId = recurringTx.id,
             let groupId = transactionRepo.fetchSharedGroupId(for: parentId) {
            transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
          }

          // Assign to correct monthly statement if linked to a credit card
          if let cardId = recurringTx.creditCardId,
             let uid = AuthenticationManager.shared.currentUser?.uid {
            assignToStatement(transactionId: insertedId, creditCardId: cardId, transactionDate: instanceDate, userId: uid)
          }
        } catch {
          logError("Error creating recurring transaction instance: \(error)")
        }
      }
    }

    // Schedule notifications for all newly created instances
    if !newInstances.isEmpty {
      RecurringNotificationManager.shared.scheduleNotifications(for: newInstances)
    }
  }

  func cleanupRecurringInstancesOutsideRange(
    _ monthRange: ClosedRange<Int>, referenceDate: Date, cleanupOption: RecurringCleanupOption
  ) {

    let validAnchors = Set(
      monthRange.compactMap { offset in
        calendar.date(byAdding: .month, value: offset, to: referenceDate)?.monthAnchor
      })

    let allInstances = transactionRepo.fetchAllRecurringInstances()
    let recurringTransactions = transactionRepo.fetchRecurringTransactions()
    let recurringStartAnchors = Dictionary(
      uniqueKeysWithValues: recurringTransactions.map { ($0.id, $0.budgetMonthDate) })

    let currentAnchor = referenceDate.monthAnchor

    for instance in allInstances {
      let shouldDelete: Bool

      switch cleanupOption {
      case .currentSelection:
        // For general cleanup, currentSelection behaves like futureOnly
        let isOutsideRange = !validAnchors.contains(instance.budgetMonthDate)
        let isFutureInstance = instance.budgetMonthDate > currentAnchor
        let isBeforeRecurringStart =
          instance.parentTransactionId.map { parentId in
            instance.budgetMonthDate <= (recurringStartAnchors[parentId] ?? 0)
          } ?? false
        shouldDelete = (isOutsideRange && isFutureInstance) || isBeforeRecurringStart

      case .futureOnly:
        let isOutsideRange = !validAnchors.contains(instance.budgetMonthDate)
        let isFutureInstance = instance.budgetMonthDate > currentAnchor
        let isBeforeRecurringStart =
          instance.parentTransactionId.map { parentId in
            instance.budgetMonthDate <= (recurringStartAnchors[parentId] ?? 0)
          } ?? false
        shouldDelete = (isOutsideRange && isFutureInstance) || isBeforeRecurringStart

      case .all:
        shouldDelete =
          !validAnchors.contains(instance.budgetMonthDate)
          || (instance.parentTransactionId.map { parentId in
            instance.budgetMonthDate <= (recurringStartAnchors[parentId] ?? 0)
          } ?? false)
      }

      guard let id = instance.id else { return }

      if shouldDelete {
        do {
          try transactionRepo.delete(id: id)

          // Clean up notification for deleted recurring instance
          TransactionNotificationManager.shared.cancelNotification(for: id)
        } catch {
          logError("Error deleting outdated recurring instance: \(error)")
        }
      }
    }
  }

  func cleanupRecurringInstancesWithUserChoice(
    _ monthRange: ClosedRange<Int>,
    referenceDate: Date,
    onCleanupChoiceNeeded: @escaping (RecurringCleanupOption) -> Void
  ) {
    onCleanupChoiceNeeded(.futureOnly)
  }

  /// Record that a specific instance was intentionally deleted so lazy generation won't recreate it.
  static func trackDeletedInstance(parentId: Int, monthAnchor: Int) {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    deletedInstanceAnchors[parentId, default: []].insert(monthAnchor)
  }

  /// Clear deletion tracking for a parent (called when the parent itself is deleted).
  static func clearDeletedInstanceTracking(for parentId: Int) {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    deletedInstanceAnchors.removeValue(forKey: parentId)
  }

  /// Month anchors intentionally deleted for a parent (read by lazy generation so it
  /// won't recreate a month the user explicitly removed).
  static func excludedAnchors(for parentId: Int) -> Set<Int> {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    return deletedInstanceAnchors[parentId] ?? []
  }

  /// Single serialized entry point for deleting a recurring OR installment transaction
  /// with a scope option (this / future / all).
  ///
  /// Runs on the same serial `operationQueue` as lazy generation (so a delete never
  /// races an in-flight generation) and delegates the actual row selection to
  /// `TransactionRepository.deleteTransactionWithOption` — the ONE canonical
  /// implementation now shared by every screen (Dashboard, Transaction Details,
  /// Statement Details, Allocation Details). Previously the Dashboard used bespoke
  /// month/exact-date-keyed cleanup methods while the detail screens used the
  /// repository, so the same action deleted different rows depending on the screen
  /// (e.g. installment "delete this" over-deleted siblings that shared a due date).
  func deleteWithOption(
    transactionId: Int,
    option: RecurringCleanupOption,
    completion: ((Result<Void, Error>) -> Void)? = nil
  ) {
    let operationId = "delete_\(transactionId)_\(option)"

    Self.operationLock.lock()
    guard !Self.currentOperations.contains(operationId) else {
      Self.operationLock.unlock()
      DispatchQueue.main.async { completion?(.success(())) }
      return
    }
    Self.currentOperations.insert(operationId)
    Self.operationLock.unlock()

    Self.operationQueue.async { [weak self] in
      var result: Result<Void, Error> = .success(())
      defer {
        Self.operationLock.lock()
        Self.currentOperations.remove(operationId)
        Self.operationLock.unlock()
        DispatchQueue.main.async { completion?(result) }
      }

      guard let self = self else { return }

      do {
        try self.transactionRepo.deleteTransactionWithOption(id: transactionId, option: option)
      } catch {
        logError("Error deleting transaction \(transactionId) with option \(option): \(error)")
        result = .failure(error)
      }
    }
  }

  // MARK: - Recurring Transaction Editing

  /// Edit recurring transactions based on the selected option (async version)
  /// Runs on background queue and calls completion when done
  func editRecurringTransactionsFromDateAsync(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    editOption: RecurringEditOption,
    newData: TransactionModel,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    Self.operationQueue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion(.failure(TransactionError.repositoryUnavailable)) }
        return
      }
      do {
        try self.editRecurringTransactionsFromDateSync(
          parentTransactionId: parentTransactionId,
          selectedTransactionDate: selectedTransactionDate,
          editOption: editOption,
          newData: newData
        )
        DispatchQueue.main.async { completion(.success(())) }
      } catch {
        DispatchQueue.main.async { completion(.failure(error)) }
      }
    }
  }

  /// Edit recurring transactions based on the selected option (sync version)
  /// Optimized to minimize database calls and remove excessive logging
  func editRecurringTransactionsFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    editOption: RecurringEditOption,
    newData: TransactionModel
  ) throws {
    try editRecurringTransactionsFromDateSync(
      parentTransactionId: parentTransactionId,
      selectedTransactionDate: selectedTransactionDate,
      editOption: editOption,
      newData: newData
    )
  }

  /// Internal sync implementation
  private func editRecurringTransactionsFromDateSync(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    editOption: RecurringEditOption,
    newData: TransactionModel
  ) throws {
    let selectedAnchor = selectedTransactionDate.monthAnchor

    // DETERMINISTIC EDIT: "this and future" / "all" must affect the whole series — not only the
    // months that happen to be materialized right now. Recurring occurrences are created lazily,
    // so a device that never navigated forward (or whose lazy generation was gated) has no future
    // rows to update, and the edit would silently touch only the current one. Materialize the
    // forward horizon (matching creation's 24-month window) first, so every future occurrence
    // exists as a row. performLazyGeneration skips intentionally-deleted months, so this never
    // resurrects a deleted occurrence. Runs inline on operationQueue (the Async caller already
    // serialized us; performLazyGeneration is documented safe to call inline here).
    if editOption != .currentSelection {
      var horizonAnchors = Set<Int>()
      for offset in 0...Self.horizonMonths {
        if let d = calendar.date(byAdding: .month, value: offset, to: selectedTransactionDate) {
          horizonAnchors.insert(d.monthAnchor)
        }
      }
      let materialized = performLazyGeneration(horizonAnchors)
      if materialized > 0 {
        logWarning("[RecurringEdit] Materialized \(materialized) missing future instance(s) before edit (option=\(editOption))")
      }
    }

    // Fetch all transactions ONCE (now includes any just-materialized future rows)
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Filter to related instances
    let relatedInstances = allTransactions.filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }

    guard !relatedInstances.isEmpty else { return }

    // Build list of instances to update based on edit option
    // Store the original timestamp and budgetMonthDate to preserve them
    var instancesToUpdate: [(id: Int, originalTimestamp: Int, originalBudgetMonthDate: Int, originalIsRecurring: Bool?, originalParentId: Int?, originalCreditCardId: Int?, originalStatementId: Int?)] = []

    for instance in relatedInstances {
      guard let instanceId = instance.id else { continue }

      let instanceDate = Date(timeIntervalSince1970: TimeInterval(instance.dateTimestamp))
      let instanceMonthAnchor = instanceDate.monthAnchor

      let shouldUpdate: Bool
      switch editOption {
      case .currentSelection:
        shouldUpdate = instanceMonthAnchor == selectedAnchor
      case .futureOnly:
        shouldUpdate = instanceMonthAnchor >= selectedAnchor
      case .all:
        shouldUpdate = true
      }

      if shouldUpdate {
        instancesToUpdate.append((
          id: instanceId,
          originalTimestamp: instance.dateTimestamp,
          originalBudgetMonthDate: instance.budgetMonthDate,
          originalIsRecurring: instance.isRecurring,
          originalParentId: instance.parentTransactionId,
          originalCreditCardId: instance.creditCardId,
          originalStatementId: instance.statementId
        ))
      }
    }

    guard !instancesToUpdate.isEmpty else { return }

    // Get the new day from the selected transaction date using local calendar
    var localCalendar = Calendar(identifier: .gregorian)
    localCalendar.timeZone = TimeZone.current
    let newDay = localCalendar.component(.day, from: selectedTransactionDate)

    // Track old statement IDs that need recalculation
    var oldStatementIdsToRecalculate: Set<Int> = []

    // Perform all updates
    for (instanceId, originalTimestamp, originalBudgetMonthDate, originalIsRecurring, originalParentId, originalCreditCardId, originalStatementId) in instancesToUpdate {
      let originalDate = Date(timeIntervalSince1970: TimeInterval(originalTimestamp))
      let originalDay = localCalendar.component(.day, from: originalDate)

      // Only recalculate date if the day actually changed
      let finalTimestamp: Int
      let finalBudgetMonthDate: Int
      let dateChanged: Bool

      if newDay == originalDay {
        // Day didn't change - preserve original timestamp and budgetMonthDate exactly
        finalTimestamp = originalTimestamp
        finalBudgetMonthDate = originalBudgetMonthDate
        dateChanged = false
      } else {
        // Day changed - need to recalculate the date
        let originalYear = localCalendar.component(.year, from: originalDate)
        let originalMonth = localCalendar.component(.month, from: originalDate)

        var dateComponents = DateComponents()
        dateComponents.year = originalYear
        dateComponents.month = originalMonth
        dateComponents.day = newDay
        // Preserve the original hour/minute/second to avoid timestamp drift
        dateComponents.hour = localCalendar.component(.hour, from: originalDate)
        dateComponents.minute = localCalendar.component(.minute, from: originalDate)
        dateComponents.second = localCalendar.component(.second, from: originalDate)

        var newDate = localCalendar.date(from: dateComponents)

        // If the date is invalid (e.g., Feb 31), adjust to the last valid day of the month
        if newDate == nil {
          let lastDayOfMonth =
            localCalendar.range(of: .day, in: .month, for: originalDate)?.upperBound ?? 31
          let actualLastDay = lastDayOfMonth - 1
          dateComponents.day = actualLastDay
          newDate = localCalendar.date(from: dateComponents)
        }

        guard let calculatedDate = newDate else { continue }

        finalTimestamp = Int(calculatedDate.timeIntervalSince1970)
        finalBudgetMonthDate = calculatedDate.monthAnchor
        dateChanged = true
      }

      // Determine the correct isRecurring value
      // Parent (id == parentTransactionId) should keep isRecurring = true
      // Children should keep their original isRecurring value (usually nil or false)
      let isParent = instanceId == parentTransactionId
      let finalIsRecurring = isParent ? true : originalIsRecurring

      // Determine the correct parentTransactionId value
      // Parent points to itself, children point to parent
      let finalParentId = isParent ? parentTransactionId : originalParentId

      // Use the credit card ID from the edit data directly — nil means cash/debit
      let finalCreditCardId = newData.data.creditCardId
      let creditCardChanged = finalCreditCardId != originalCreditCardId
      let creditCardRemoved = originalCreditCardId != nil && finalCreditCardId == nil

      let updatedTransaction = TransactionModel(
        id: instanceId,
        title: newData.data.title,
        category: newData.data.category,
        amount: newData.data.amount,
        type: newData.data.type,
        dateTimestamp: finalTimestamp,
        budgetMonthDate: finalBudgetMonthDate,
        isRecurring: finalIsRecurring,
        hasInstallments: newData.data.hasInstallments,
        parentTransactionId: finalParentId,
        originalAmount: newData.data.originalAmount,
        installmentNumber: newData.data.installmentNumber,
        totalInstallments: newData.data.totalInstallments,
        creditCardId: finalCreditCardId,
        isCreditCardStatement: finalCreditCardId != nil ? false : nil
      )

      try transactionRepo.updateTransactionDirectly(updatedTransaction)

      // Handle credit card field changes
      if creditCardRemoved {
        // Card was removed: clear all credit card fields
        try transactionRepo.clearCreditCardFields(transactionId: instanceId)
        if let oldStmtId = originalStatementId {
          oldStatementIdsToRecalculate.insert(oldStmtId)
        }
      } else if (dateChanged || creditCardChanged), let cardId = finalCreditCardId,
         let uid = AuthenticationManager.shared.currentUser?.uid {
        // Card changed or date changed: reassign to correct statement
        let newDate = Date(timeIntervalSince1970: TimeInterval(finalTimestamp))
        assignToStatement(transactionId: instanceId, creditCardId: cardId, transactionDate: newDate, userId: uid)

        // Mark old statement for recalculation
        if let oldStmtId = originalStatementId {
          oldStatementIdsToRecalculate.insert(oldStmtId)
        }
      }
    }

    // Recalculate totals for old statements that lost transactions
    for oldStmtId in oldStatementIdsToRecalculate {
      creditCardService.recalculateStatementTotal(statementId: oldStmtId)
    }

    // Recompute the recurring series' consolidated notifications so an "edit this/future"
    // change to amount/day is reflected (this bulk edit previously rescheduled nothing).
    RecurringNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentTransactionId)
  }

  // MARK: - Recurring Transaction Linking

  /// Find existing recurring transactions with the same characteristics
  func findSimilarRecurringTransaction(
    title: String,
    category: String,
    amount: Int,
    type: String
  ) -> Transaction? {
    let recurringTransactions = transactionRepo.fetchRecurringTransactions()

    // A parent recurring transaction is identified by:
    // 1. isRecurring == true
    // 2. parentTransactionId == nil OR parentTransactionId == self.id (self-referencing)
    // 3. Has instances linked to it (not orphaned)
    return recurringTransactions.first { transaction in
      let isSameDetails = transaction.title.lowercased() == title.lowercased()
        && transaction.category.key == category
        && transaction.amount == amount
        && transaction.type.key == type

      // Parent transactions either have no parent or point to themselves
      let isParent = transaction.parentTransactionId == nil
        || transaction.parentTransactionId == transaction.id

      // Make sure this parent transaction actually has active instances
      // to avoid linking to orphaned parents from partial deletions
      let hasActiveInstances: Bool
      if isParent, let txId = transaction.id {
        let instances = transactionRepo.fetchTransactionInstancesForRecurring(txId)
        hasActiveInstances = !instances.isEmpty
      } else {
        hasActiveInstances = false
      }

      return isSameDetails && isParent && hasActiveInstances
    }
  }

  /// Link a new recurring transaction to an existing similar one
  func linkToExistingRecurringTransaction(
    newTransactionId: Int,
    existingParentId: Int
  ) throws {
    // Update the new transaction to be a child of the existing parent
    try transactionRepo.updateParentTransactionId(
      transactionId: newTransactionId,
      parentId: existingParentId
    )
  }

  // MARK: - Lazy Generation Methods

  /// Lazily generates recurring transaction instances only for the specified month anchors.
  /// This method is optimized to minimize database calls and skip unnecessary work.
  /// - Parameters:
  ///   - monthAnchors: Set of month anchors to generate instances for
  ///   - completion: Optional completion handler called when generation is complete
  func generateInstancesLazilyForMonths(
    _ monthAnchors: Set<Int>,
    completion: ((_ newInstancesCreated: Int) -> Void)? = nil
  ) {
    guard !monthAnchors.isEmpty else {
      DispatchQueue.main.async { completion?(0) }
      return
    }

    Self.operationQueue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion?(0) }
        return
      }
      let created = self.performLazyGeneration(monthAnchors)
      completion?(created)
    }
  }

  /// Synchronous core of lazy generation. Materializes any missing recurring instances
  /// for the given month anchors and returns how many were created.
  ///
  /// Safe to call inline while already serialized on `operationQueue` — used both by the
  /// async `generateInstancesLazilyForMonths` above and by the "delete future" backfill,
  /// which needs to materialize pre-cutoff months synchronously before the parent's
  /// recurrence is disabled.
  private func performLazyGeneration(_ monthAnchors: Set<Int>) -> Int {
      // Fetch ALL transactions ONCE for efficiency
      let allTransactions = self.transactionRepo.fetchAllTransactions()

      // Early exit if no transactions
      guard !allTransactions.isEmpty else {
        return 0
      }

      // Build lookup tables ONCE
      let allTransactionIds = Set(allTransactions.compactMap { $0.id })

      // Group transactions by parent ID for efficient instance lookup
      var instancesByParentId: [Int: Set<Int>] = [:]  // parentId -> Set of monthAnchors
      for tx in allTransactions {
        if let parentId = tx.parentTransactionId {
          if instancesByParentId[parentId] == nil {
            instancesByParentId[parentId] = []
          }
          instancesByParentId[parentId]?.insert(tx.budgetMonthDate)
        }
      }

      // Group full occurrences per series (parent + its instances), sorted by month.
      // New instances inherit from the occurrence "in effect" at their target month — the
      // most recent occurrence at or before it — instead of always the original parent.
      // This makes "edit this and future occurrences" changes (amount, title, category, type,
      // card) propagate to months that are materialized lazily later, while months before an
      // edit keep their original values.
      var occurrencesBySeriesId: [Int: [Transaction]] = [:]
      for tx in allTransactions {
        guard let seriesId = tx.parentTransactionId ?? tx.id else { continue }
        occurrencesBySeriesId[seriesId, default: []].append(tx)
      }
      for (seriesId, occurrences) in occurrencesBySeriesId {
        occurrencesBySeriesId[seriesId] = occurrences.sorted {
          $0.budgetMonthDate < $1.budgetMonthDate
        }
      }

      // Also include soft-deleted (is_deleted=1) instances so lazy generation never recreates
      // an instance the user intentionally deleted, even if the active row was removed.
      // This covers both in-session deletions (row still soft-deleted) and post-CK-delete
      // tombstones left by hardDeleteLocal (ck_record_id cleared but is_deleted=1 remains).
      let deletedChildAnchors = self.transactionRepo.fetchDeletedChildAnchors()
      for (parentId, anchors) in deletedChildAnchors {
        for anchor in anchors {
          instancesByParentId[parentId, default: []].insert(anchor)
        }
      }

      // Build a set of existing (title, budgetMonthDate, DAY) to prevent duplicates even when
      // parent_transaction_id is wrong (cross-device ID mismatch). The DAY is part of the key so
      // two same-title recurring series that fall on DIFFERENT days of the month can coexist —
      // keying on title+month alone wrongly blocked a new series when another same-title one
      // already occupied every month (it generated 0 instances, leaving only a stray parent).
      var existingTitleAnchors: Set<String> = []
      for tx in allTransactions {
        let txDay = calendar.component(.day, from: Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp)))
        existingTitleAnchors.insert("\(tx.title)|\(tx.budgetMonthDate)|\(txDay)")
      }

      // Filter recurring parents only — installments are now generated upfront at creation time
      let recurringParents = allTransactions.filter {
        $0.isRecurring == true && ($0.parentTransactionId == nil || $0.parentTransactionId == $0.id)
      }

      // Early exit if no recurring parents to process
      guard !recurringParents.isEmpty else {
        return 0
      }

      var newInstancesCreated = 0

      // Batch every insert/update in this generation pass into ONE transaction (one fsync)
      // instead of one per row. Inner per-row do/catch still logs and continues, so a single
      // bad row doesn't roll back the whole batch. (See DBHelper.inTransaction — re-entrant safe.)
      try? DBHelper.shared.inTransaction {
      // Process recurring transactions
      for recurringTx in recurringParents {
        guard let recurringTxId = recurringTx.id else { continue }
        guard allTransactionIds.contains(recurringTxId) else { continue }

        // Get existing anchors from pre-built lookup
        let existingAnchors = instancesByParentId[recurringTxId] ?? []

        // Get anchors of intentionally deleted instances (from .currentSelection deletion)
        let excludedAnchors = Self.excludedAnchors(for: recurringTxId)

        // Only generate for months that don't have instances yet and weren't intentionally deleted
        let missingAnchors = monthAnchors.subtracting(existingAnchors)
          .subtracting(excludedAnchors)
          .filter { $0 != recurringTx.budgetMonthDate }  // Don't create for parent's month
          .filter { $0 > recurringTx.budgetMonthDate }  // Only future months

        guard !missingAnchors.isEmpty else { continue }

        // Occurrences of this series, ascending by month (for picking the in-effect template).
        let seriesOccurrences = occurrencesBySeriesId[recurringTxId] ?? [recurringTx]

        for targetAnchor in missingAnchors {
          // Inherit from the most recent occurrence at or before this month, so a prior
          // "edit this and future" change carries forward. Falls back to the parent.
          let template = seriesOccurrences.last(where: { $0.budgetMonthDate <= targetAnchor })
            ?? recurringTx

          // Safety check: skip only if a same-title row on the SAME day already exists in this
          // month (cross-device duplicate protection). A same-title series on a different day is
          // legitimately distinct and must still generate.
          let templateDay = calendar.component(.day, from: Date(timeIntervalSince1970: TimeInterval(template.dateTimestamp)))
          let key = "\(template.title)|\(targetAnchor)|\(templateDay)"
          guard !existingTitleAnchors.contains(key) else { continue }

          let targetDate = Date(timeIntervalSince1970: TimeInterval(targetAnchor))
          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let originalDate = Date(timeIntervalSince1970: TimeInterval(template.dateTimestamp))
          let instanceDate = self.generateValidDateForMonth(
            originalDate: originalDate,
            targetMonth: targetMonth,
            targetYear: targetYear
          )

          let instanceModel = TransactionModel(
            title: template.title,
            category: template.category.key,
            amount: template.amount,
            type: template.type.key,
            dateTimestamp: Int(instanceDate.timeIntervalSince1970),
            budgetMonthDate: targetAnchor,
            parentTransactionId: recurringTxId,
            creditCardId: template.creditCardId
          )

          do {
            let insertedId = try self.transactionRepo.insertTransactionAndGetId(instanceModel)
            newInstancesCreated += 1
            existingTitleAnchors.insert(key)

            // Derived identity for (series, month) — see the note at the other generation site.
            if let parentId = template.id,
               let parentUuid = self.db.uuidIdentity(table: "Transactions", localId: parentId)?.uuid {
              self.db.assignDeterministicUuid(
                table: "Transactions", localId: insertedId,
                uuid: DeterministicIdentity.recurringInstance(
                  parentUuid: parentUuid, monthDate: targetAnchor))
            }

            // Inherit the series' scope, not the device's mirror setting (see above).
            if let parentId = template.id,
               let groupId = self.transactionRepo.fetchSharedGroupId(for: parentId) {
              self.transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
            }

            // Assign to correct monthly statement if linked to a credit card
            if let cardId = template.creditCardId,
               let uid = AuthenticationManager.shared.currentUser?.uid {
              self.assignToStatement(transactionId: insertedId, creditCardId: cardId, transactionDate: instanceDate, userId: uid)
            }
          } catch {
            logError("Error creating recurring instance: \(error)")
          }
        }
      }
      } // end inTransaction

      // Installment lazy generation removed — all installments are now created upfront at creation time

      return newInstancesCreated
  }

  /// Materializes any missing recurring instances for months strictly between the
  /// parent's own month and `cutoffAnchor`. Called by "delete future" BEFORE the
  /// parent's recurrence is disabled, so pre-cutoff months that were never lazily
  /// generated aren't silently lost (disabling recurrence stops all future generation).
  /// Runs synchronously/inline — the caller is responsible for serialization if needed.
  func backfillRecurringMonths(parentTransactionId: Int, cutoffAnchor: Int) {
    let all = transactionRepo.fetchAllTransactions()
    guard let parent = all.first(where: { $0.id == parentTransactionId }) else { return }
    let startAnchor = parent.budgetMonthDate
    guard startAnchor < cutoffAnchor else { return }

    // Enumerate month anchors strictly between the parent's month and the cutoff, using
    // the same (current-timezone) month-anchor convention instances were created with.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    var anchors: Set<Int> = []
    var date = Date(timeIntervalSince1970: TimeInterval(startAnchor))
    var steps = 0
    while steps < 600 {  // safety bound (~50 years)
      steps += 1
      guard let next = cal.date(byAdding: .month, value: 1, to: date) else { break }
      date = next
      let anchor = next.monthAnchor
      if anchor >= cutoffAnchor { break }
      anchors.insert(anchor)
    }

    guard !anchors.isEmpty else { return }
    _ = performLazyGeneration(anchors)
  }

  /// Check if lazy generation is needed for the given month anchors (lightweight check)
  /// Note: This is now only used for debugging - the generation method handles its own checks
  func needsLazyGeneration(for monthAnchors: Set<Int>) -> Bool {
    // This is intentionally a fast approximate check
    // The actual generation method will do the detailed check
    let recurringCount = transactionRepo.fetchRecurringTransactions().count
    let allTransactions = transactionRepo.fetchAllTransactions()
    let installmentParentCount = allTransactions.filter {
      $0.hasInstallments == true && $0.parentTransactionId == nil
    }.count

    return recurringCount > 0 || installmentParentCount > 0
  }

  // MARK: - Credit Card Statement Assignment

  /// Assigns a transaction to the correct credit card statement based on its date.
  /// When `remapToStatementDueDate` is true (for CC installments), the transaction's
  /// dateTimestamp and budgetMonthDate are updated to the statement's due date so that
  /// the installment appears in the month money is actually debited.
  private func assignToStatement(transactionId: Int, creditCardId: Int, transactionDate: Date, userId: String, remapToStatementDueDate: Bool = false) {
    guard let card = creditCardRepo.fetchCard(byId: creditCardId) else { return }
    // On non-original devices, only link to existing statements (never create new ones).
    // Statements should already exist from cloud sync.
    let isOriginalDevice = UserDefaults.standard.bool(forKey: "hasCompletedInitialCloudPush_v1")
    let statement: CreditCardStatement?
    if isOriginalDevice {
        statement = creditCardService.getOrCreateStatement(for: card, transactionDate: transactionDate, userId: userId)
    } else {
        statement = creditCardService.getExistingStatement(for: card, transactionDate: transactionDate)
    }
    guard let statement = statement else { return }
    do {
      try transactionRepo.updateCreditCardFields(
        transactionId: transactionId,
        creditCardId: creditCardId,
        statementId: statement.id!,
        isCreditCardStatement: false
      )
      creditCardService.recalculateStatementTotal(statementId: statement.id!)

      if remapToStatementDueDate {
        let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
        let dueDateBudgetMonth = statement.dueDate.monthAnchor
        transactionRepo.updateDateAndBudgetMonth(
          transactionId: transactionId,
          newDateTimestamp: dueDateTimestamp,
          newBudgetMonthDate: dueDateBudgetMonth
        )
      }
    } catch {
      logError("Error assigning transaction \(transactionId) to statement: \(error)")
    }
  }

  // MARK: - Helper Methods

  /// Gera uma data válida para o mês especificado, lidando com dias que não existem
  /// - Parameters:
  ///   - originalDate: Data original da transação recorrente
  ///   - targetMonth: Mês para o qual gerar a data
  ///   - targetYear: Ano para o qual gerar a data
  /// - Returns: Data válida para o mês especificado
  private func generateValidDateForMonth(
    originalDate: Date,
    targetMonth: Int,
    targetYear: Int
  ) -> Date {
    let originalDay = calendar.component(.day, from: originalDate)

    // Calculate the last day of the specific month
    let lastDayOfMonth: Int
    switch targetMonth {
    case 2:  // February
      let isLeapYear = (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0)
      lastDayOfMonth = isLeapYear ? 29 : 28
    case 4, 6, 9, 11:  // April, June, September, November
      lastDayOfMonth = 30
    default:  // January, March, May, July, August, October, December
      lastDayOfMonth = 31
    }

    // Determine the day to use
    let dayToUse = min(originalDay, lastDayOfMonth)

    // Create the date
    var dateComponents = DateComponents()
    dateComponents.year = targetYear
    dateComponents.month = targetMonth
    dateComponents.day = dayToUse
    dateComponents.hour = 12  // Use noon to avoid timezone issues
    dateComponents.minute = 0
    dateComponents.second = 0

    guard let validDate = calendar.date(from: dateComponents) else {
      // Fallback: use the first day of the month
      dateComponents.day = 1
      return calendar.date(from: dateComponents) ?? Date()
    }

    return validDate
  }

}
