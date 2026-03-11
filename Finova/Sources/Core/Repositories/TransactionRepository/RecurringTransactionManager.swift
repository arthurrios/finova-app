//
//  RecurringTransactionManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/06/25.
//

import Foundation
import NotificationCenter

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
  private let transactionRepo: TransactionRepository
  private let creditCardService: CreditCardService
  private let creditCardRepo: CreditCardRepository
  private let calendar: Calendar
  private let notificationCenter = UNUserNotificationCenter.current()

  // MARK: - Concurrency Control
  private let operationQueue = DispatchQueue(
    label: "recurring.transaction.operations", qos: .userInitiated)
  private var currentOperations: Set<String> = []
  private let operationLock = NSLock()

  // MARK: - Deleted Instance Tracking
  // Tracks instances deleted via .currentSelection to prevent lazy generation from recreating them.
  // Key: parentTransactionId, Value: set of month anchors that should NOT be regenerated.
  private var deletedInstanceAnchors: [Int: Set<Int>] = [:]

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    creditCardService: CreditCardService = CreditCardService(),
    creditCardRepo: CreditCardRepository = CreditCardRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.creditCardService = creditCardService
    self.creditCardRepo = creditCardRepo

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
    operationQueue.async { [weak self] in
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
    operationQueue.async { [weak self] in
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

          // Mirror mode: tag new instance with group ID
          if MirrorModeManager.shared.isEnabled,
             let groupId = MirrorModeManager.shared.linkedGroupId {
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
      scheduleOptimizedNotificationsForRecurringInstances(newInstances)
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
          let notifID = "transaction_\(id)"
          notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
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
  func trackDeletedInstance(parentId: Int, monthAnchor: Int) {
    operationLock.lock()
    defer { operationLock.unlock() }
    deletedInstanceAnchors[parentId, default: []].insert(monthAnchor)
  }

  /// Clear deletion tracking for a parent (called when the parent itself is deleted).
  func clearDeletedInstanceTracking(for parentId: Int) {
    operationLock.lock()
    defer { operationLock.unlock() }
    deletedInstanceAnchors.removeValue(forKey: parentId)
  }

  func cleanupRecurringInstancesFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    cleanupOption: RecurringCleanupOption,
    completion: (() -> Void)? = nil
  ) {
    let operationId = "cleanup_recurring_\(parentTransactionId)_\(cleanupOption)"

    // Prevent concurrent deletion operations on the same transaction
    operationLock.lock()
    defer { operationLock.unlock() }

    guard !currentOperations.contains(operationId) else {
      DispatchQueue.main.async { completion?() }
      return
    }

    currentOperations.insert(operationId)

    operationQueue.async { [weak self] in
      defer {
        self?.operationLock.lock()
        self?.currentOperations.remove(operationId)
        self?.operationLock.unlock()
        // Call completion on main thread
        DispatchQueue.main.async { completion?() }
      }

      guard let self = self else {
        DispatchQueue.main.async { completion?() }
        return
      }

      let selectedAnchor = selectedTransactionDate.monthAnchor
      let allInstances = self.transactionRepo.fetchAllRecurringInstances()

      let relatedInstances = allInstances.filter {
        $0.parentTransactionId == parentTransactionId
      }

      // Delete instances in a single transaction to prevent partial states
      var instancesToDelete: [Int] = []

      for instance in relatedInstances {
        let shouldDelete: Bool

        switch cleanupOption {
        case .currentSelection:
          // Only delete the current selected transaction
          shouldDelete = instance.budgetMonthDate == selectedAnchor
        case .futureOnly:
          shouldDelete = instance.budgetMonthDate >= selectedAnchor
        case .all:
          shouldDelete = true
        }

        if shouldDelete, let instanceId = instance.id {
          instancesToDelete.append(instanceId)
        }
      }

      // Perform deletions atomically
      for instanceId in instancesToDelete {
        do {
          try self.transactionRepo.delete(id: instanceId)
          let notifID = "transaction_\(instanceId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting recurring instance \(instanceId): \(error)")
        }
      }

      // Track deleted anchors so lazy generation won't recreate them
      if cleanupOption == .currentSelection && !instancesToDelete.isEmpty {
        self.trackDeletedInstance(parentId: parentTransactionId, monthAnchor: selectedAnchor)
      }

      if cleanupOption == .all {
        do {
          try self.transactionRepo.delete(id: parentTransactionId)
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting parent recurring transaction \(parentTransactionId): \(error)")
        }
        self.clearDeletedInstanceTracking(for: parentTransactionId)
      } else {
        // For non-"all" deletions, check if parent is now orphaned
        let remainingInstances = self.transactionRepo.fetchTransactionInstancesForRecurring(
          parentTransactionId)
        if remainingInstances.isEmpty {
          // Delete orphaned parent to prevent resurrection bugs
          do {
            try self.transactionRepo.delete(id: parentTransactionId)
            let notifID = "transaction_\(parentTransactionId)"
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
          } catch {
            logError("Error deleting orphaned parent transaction \(parentTransactionId): \(error)")
          }
          self.clearDeletedInstanceTracking(for: parentTransactionId)
        } else if cleanupOption == .futureOnly {
          // When deleting future instances, mark parent as no longer recurring
          // This prevents lazy generation from recreating deleted instances
          do {
            try self.transactionRepo.updateIsRecurring(
              transactionId: parentTransactionId, isRecurring: false)
          } catch {
            logError("Error updating isRecurring flag for parent \(parentTransactionId): \(error)")
          }
          self.clearDeletedInstanceTracking(for: parentTransactionId)
        }
      }
    }
  }

  func cleanupInstallmentTransactionsFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    cleanupOption: RecurringCleanupOption,
    completion: (() -> Void)? = nil
  ) {
    let operationId = "cleanup_installment_\(parentTransactionId)_\(cleanupOption)"

    // Prevent concurrent deletion operations on the same transaction
    operationLock.lock()
    defer { operationLock.unlock() }

    guard !currentOperations.contains(operationId) else {
      DispatchQueue.main.async { completion?() }
      return
    }

    currentOperations.insert(operationId)

    operationQueue.async { [weak self] in
      defer {
        self?.operationLock.lock()
        self?.currentOperations.remove(operationId)
        self?.operationLock.unlock()
        // Call completion on main thread
        DispatchQueue.main.async { completion?() }
      }

      guard let self = self else {
        DispatchQueue.main.async { completion?() }
        return
      }

      // Use the more efficient method to get only instances for this parent
      let installmentInstances = self.transactionRepo.fetchTransactionInstancesForRecurring(
        parentTransactionId)

      // Collect instances to delete first to avoid partial states
      var instancesToDelete: [Int] = []

      for instance in installmentInstances {
        let shouldDelete: Bool

        switch cleanupOption {
        case .currentSelection:
          // Only delete the current selected transaction
          shouldDelete = instance.date == selectedTransactionDate
        case .futureOnly:
          shouldDelete = instance.date >= selectedTransactionDate
        case .all:
          shouldDelete = true
        }

        if shouldDelete, let instanceId = instance.id {
          instancesToDelete.append(instanceId)
        }
      }

      // Perform deletions atomically
      for instanceId in instancesToDelete {
        do {
          try self.transactionRepo.delete(id: instanceId)
          let notifID = "transaction_\(instanceId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting installment instance: \(error)")
        }
      }

      // Track deleted anchors so lazy generation won't recreate them
      if cleanupOption == .currentSelection && !instancesToDelete.isEmpty {
        let selectedAnchor = selectedTransactionDate.monthAnchor
        self.trackDeletedInstance(parentId: parentTransactionId, monthAnchor: selectedAnchor)
      }

      if cleanupOption == .all {
        do {
          try self.transactionRepo.delete(id: parentTransactionId)
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting parent installment transaction: \(error)")
        }
        self.clearDeletedInstanceTracking(for: parentTransactionId)
      } else if cleanupOption == .futureOnly {
        // For futureOnly, also delete the parent to prevent lazy regeneration
        // This is safe because the parent is just a hidden "Installment Parent" record
        do {
          try self.transactionRepo.delete(id: parentTransactionId)
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting parent installment transaction: \(error)")
        }
        self.clearDeletedInstanceTracking(for: parentTransactionId)
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
    operationQueue.async { [weak self] in
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

    // Fetch all transactions ONCE
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

    operationQueue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion?(0) }
        return
      }

      // Fetch ALL transactions ONCE for efficiency
      let allTransactions = self.transactionRepo.fetchAllTransactions()

      // Early exit if no transactions
      guard !allTransactions.isEmpty else {
        DispatchQueue.main.async { completion?(0) }
        return
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

      // Build a set of existing (title, budgetMonthDate) to prevent duplicates
      // even when parent_transaction_id is wrong (cross-device ID mismatch)
      // or amounts differ slightly (rounding, edits on different devices).
      var existingTitleAnchors: Set<String> = []
      for tx in allTransactions {
        existingTitleAnchors.insert("\(tx.title)|\(tx.budgetMonthDate)")
      }

      // Filter recurring parents and installment parents
      let recurringParents = allTransactions.filter {
        $0.isRecurring == true && ($0.parentTransactionId == nil || $0.parentTransactionId == $0.id)
      }

      let installmentParents = allTransactions.filter {
        $0.hasInstallments == true && $0.parentTransactionId == nil
      }

      // Early exit if no parents to process
      guard !recurringParents.isEmpty || !installmentParents.isEmpty else {
        DispatchQueue.main.async { completion?(0) }
        return
      }

      var newInstancesCreated = 0

      // Process recurring transactions
      for recurringTx in recurringParents {
        guard let recurringTxId = recurringTx.id else { continue }
        guard allTransactionIds.contains(recurringTxId) else { continue }

        // Get existing anchors from pre-built lookup
        let existingAnchors = instancesByParentId[recurringTxId] ?? []

        // Get anchors of intentionally deleted instances (from .currentSelection deletion)
        self.operationLock.lock()
        let excludedAnchors = self.deletedInstanceAnchors[recurringTxId] ?? []
        self.operationLock.unlock()

        // Only generate for months that don't have instances yet and weren't intentionally deleted
        let missingAnchors = monthAnchors.subtracting(existingAnchors)
          .subtracting(excludedAnchors)
          .filter { $0 != recurringTx.budgetMonthDate }  // Don't create for parent's month
          .filter { $0 > recurringTx.budgetMonthDate }  // Only future months

        guard !missingAnchors.isEmpty else { continue }

        let originalDate = Date(timeIntervalSince1970: TimeInterval(recurringTx.dateTimestamp))

        for targetAnchor in missingAnchors {
          // Safety check: skip if a transaction with same title+month already exists
          // This prevents duplicates when parent_transaction_id is wrong (cross-device sync)
          // or amounts differ slightly between devices
          let key = "\(recurringTx.title)|\(targetAnchor)"
          guard !existingTitleAnchors.contains(key) else { continue }

          let targetDate = Date(timeIntervalSince1970: TimeInterval(targetAnchor))
          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let instanceDate = self.generateValidDateForMonth(
            originalDate: originalDate,
            targetMonth: targetMonth,
            targetYear: targetYear
          )

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
            let insertedId = try self.transactionRepo.insertTransactionAndGetId(instanceModel)
            newInstancesCreated += 1
            existingTitleAnchors.insert(key)

            // Mirror mode: tag new instance with group ID
            if MirrorModeManager.shared.isEnabled,
               let groupId = MirrorModeManager.shared.linkedGroupId {
              self.transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
            }

            // Assign to correct monthly statement if linked to a credit card
            if let cardId = recurringTx.creditCardId,
               let uid = AuthenticationManager.shared.currentUser?.uid {
              self.assignToStatement(transactionId: insertedId, creditCardId: cardId, transactionDate: instanceDate, userId: uid)
            }
          } catch {
            logError("Error creating recurring instance: \(error)")
          }
        }
      }

      // Process installment transactions
      for parent in installmentParents {
        guard let parentId = parent.id,
          let totalInstallments = parent.totalInstallments,
          totalInstallments > 1
        else { continue }

        let existingAnchors = instancesByParentId[parentId] ?? []

        // Get anchors of intentionally deleted instances (from .currentSelection deletion)
        self.operationLock.lock()
        let excludedAnchors = self.deletedInstanceAnchors[parentId] ?? []
        self.operationLock.unlock()

        // For CC installments, dates are remapped to statement due dates, so the
        // budgetMonthDate-based anchor check won't match the purchase-date-based
        // target anchor. Build a set of existing installment numbers to prevent
        // lazy gen from recreating installments that already exist at a different anchor.
        // Note: parent transactions don't have creditCardId — only children do.
        var existingInstallmentNumbers = Set<Int>()
        let childrenOfParent = allTransactions.filter { $0.parentTransactionId == parentId }
        let isCCInstallment = childrenOfParent.contains { $0.creditCardId != nil }
        if isCCInstallment {
          for tx in childrenOfParent {
            if let num = tx.installmentNumber {
              existingInstallmentNumbers.insert(num)
            }
          }
        }

        let parentDate = parent.date
        let originalAmount = parent.originalAmount ?? parent.amount
        let amountPerInstallment = originalAmount / totalInstallments
        let remainder = originalAmount % totalInstallments
        let cleanTitle = parent.title.replacingOccurrences(of: " - Installment Parent", with: "")

        for installmentNumber in 1...totalInstallments {
          guard
            let targetDate = self.calendar.date(
              byAdding: .month, value: installmentNumber - 1, to: parentDate)
          else { continue }

          let targetAnchor = targetDate.monthAnchor

          // Skip if this installment number already exists (CC installments have remapped dates)
          if isCCInstallment && existingInstallmentNumbers.contains(installmentNumber) {
            continue
          }

          // Only generate if this month is requested, doesn't exist yet, and wasn't intentionally deleted
          guard monthAnchors.contains(targetAnchor), !existingAnchors.contains(targetAnchor),
                !excludedAnchors.contains(targetAnchor) else {
            continue
          }

          let installmentAmount =
            installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

          // Safety check: skip if a transaction with same title+month already exists
          let instKey = "\(cleanTitle)|\(targetAnchor)"
          guard !existingTitleAnchors.contains(instKey) else { continue }

          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let installmentDate = self.generateValidDateForMonth(
            originalDate: parentDate,
            targetMonth: targetMonth,
            targetYear: targetYear
          )

          let installmentModel = TransactionModel(
            title: cleanTitle,
            category: parent.category.key,
            amount: installmentAmount,
            type: parent.type.key,
            dateTimestamp: Int(installmentDate.timeIntervalSince1970),
            budgetMonthDate: targetAnchor,
            parentTransactionId: parentId,
            originalAmount: originalAmount,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            creditCardId: parent.creditCardId
          )

          do {
            let insertedId = try self.transactionRepo.insertTransactionAndGetId(installmentModel)
            newInstancesCreated += 1
            existingTitleAnchors.insert(instKey)
            // Link to credit card statement if the parent is a credit card transaction
            if let cardId = parent.creditCardId,
               let uid = AuthenticationManager.shared.currentUser?.uid {
              self.assignToStatement(transactionId: insertedId, creditCardId: cardId, transactionDate: installmentDate, userId: uid, remapToStatementDueDate: true)
            }
          } catch {
            logError("Error creating installment instance: \(error)")
          }
        }
      }

      // Mirror mode: ensure all newly created instances are tagged with group ID
      if newInstancesCreated > 0 {
        MirrorModeManager.shared.reconcileMirrorData()
      }

      // Call completion on current (background) queue - callers should dispatch to main if needed
      completion?(newInstancesCreated)
    }
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
    guard let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: transactionDate, userId: userId) else { return }
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

  // MARK: - Notification Management

  /// Optimized system for scheduling recurring transaction notifications
  private func scheduleOptimizedNotificationsForRecurringInstances(_ instances: [TransactionModel])
  {
    // Group instances by month
    var instancesByMonth: [String: [TransactionModel]] = [:]

    for instance in instances {
      let date = Date(timeIntervalSince1970: TimeInterval(instance.data.dateTimestamp))
      let monthKey =
        "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"

      if instancesByMonth[monthKey] == nil {
        instancesByMonth[monthKey] = []
      }
      instancesByMonth[monthKey]?.append(instance)
    }

    // Schedule notification for each month (max 1 per month)
    for (monthKey, monthInstances) in instancesByMonth {
      scheduleMonthlyRecurringNotification(monthKey: monthKey, instances: monthInstances)
    }
  }

  /// Schedule a monthly notification for all recurring instances in a month
  private func scheduleMonthlyRecurringNotification(monthKey: String, instances: [TransactionModel])
  {
    guard let firstInstance = instances.first else { return }

    let date = Date(timeIntervalSince1970: TimeInterval(firstInstance.data.dateTimestamp))

    // Check if the date is too far in the future (more than 1 year)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow { return }

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else { return }

    let timeInterval = notificationDate.timeIntervalSinceNow

    // Check if the interval is too large (more than 30 days)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      scheduleRecurringReminderNotification(for: monthKey, instances: instances)
      return
    }

    // Create consolidated monthly notification
    let totalAmount = instances.reduce(0) { $0 + $1.data.amount }
    let instanceCount = instances.count

    let title = "notification.recurring.title".localized
    let bodyKey =
      instanceCount == 1
      ? "notification.recurring.body.singular" : "notification.recurring.body.plural"
    let body =
      instanceCount == 1
      ? String(format: bodyKey.localized, totalAmount.currencyString)
      : String(format: bodyKey.localized, instanceCount, totalAmount.currencyString)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = [
      "type": "recurring_month",
      "monthKey": monthKey,
      "instanceCount": instanceCount,
      "totalAmount": totalAmount,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(
      identifier: "recurring_month_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling recurring notification for month \(monthKey): \(error)")
      }
    }
  }

  /// Schedule a reminder notification for distant recurring instances
  private func scheduleRecurringReminderNotification(
    for monthKey: String, instances: [TransactionModel]
  ) {
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: thirtyDaysInSeconds, repeats: false)

    let content = UNMutableNotificationContent()
    content.title = "notification.recurring.reminder.title".localized
    content.body = "notification.recurring.reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["type": "recurring_reminder", "monthKey": monthKey]

    let request = UNNotificationRequest(
      identifier: "recurring_reminder_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling recurring reminder for month \(monthKey): \(error)")
      }
    }
  }
}
