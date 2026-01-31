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
  private let calendar: Calendar
  private let notificationCenter = UNUserNotificationCenter.current()

  // MARK: - Concurrency Control
  private let operationQueue = DispatchQueue(
    label: "recurring.transaction.operations", qos: .userInitiated)
  private var currentOperations: Set<String> = []
  private let operationLock = NSLock()

  init(transactionRepo: TransactionRepository = TransactionRepository()) {
    self.transactionRepo = transactionRepo

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
    print("🔄 Generating recurring transactions for range \(monthRange)")

    // Use async queue to prevent blocking the main thread
    operationQueue.async { [weak self] in
      guard let self = self else { return }

      let recurringTransactions = self.transactionRepo.fetchRecurringTransactions()
      print("📊 Found \(recurringTransactions.count) recurring transactions")

      // Fetch all transactions once instead of per-transaction
      let allTransactions = self.transactionRepo.fetchAllTransactions()
      let allTransactionIds = Set(allTransactions.compactMap { $0.id })

      for recurringTx in recurringTransactions {
        guard let recurringTxId = recurringTx.id else {
          print("⚠️ Skipping recurring transaction without ID: \(recurringTx.title)")
          continue
        }

        // Use the pre-fetched set for efficient existence check
        guard allTransactionIds.contains(recurringTxId) else {
          print("⚠️ Skipping deleted recurring transaction: \(recurringTx.title)")
          continue
        }

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
    guard let recurringTxId = recurringTx.id else {
      completion?()
      return
    }

    print(
      "🔄 Generating instances for NEW recurring transaction: '\(recurringTx.title)' (ID: \(recurringTxId))"
    )

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

    print(
      "🔄 Generating instances for recurring transaction: '\(recurringTx.title)' (ID: \(recurringTxId))"
    )
    print("📅 Range: \(monthRange), Reference date: \(referenceDate)")
    print("📅 Parent transaction month anchor: \(recurringTx.budgetMonthDate)")
    print(
      "📅 Parent transaction date: \(Date(timeIntervalSince1970: TimeInterval(recurringTx.dateTimestamp)))"
    )

    // Get existing instances for this specific recurring transaction
    let existingInstances = transactionRepo.fetchTransactionInstancesForRecurring(recurringTxId)
    let existingAnchors = Set(existingInstances.map { $0.budgetMonthDate })

    print("📊 Existing instances: \(existingInstances.count)")
    print("📊 Existing anchors: \(existingAnchors)")

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
      if existingAnchors.contains(targetAnchor) {
        print("⏭️ Skipping month \(targetAnchor) - instance already exists")
        continue
      }

      // IMPORTANT: Never create an instance for the same month as the parent transaction
      if targetAnchor == recurringTx.budgetMonthDate {
        print("⏭️ Skipping month \(targetAnchor) - same as parent transaction month")
        continue
      }

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

        print("✅ Creating instance for anchor: \(targetAnchor) (month offset: \(monthOffset))")

        // Create the instance
        let instanceModel = TransactionModel(
          title: recurringTx.title,
          category: recurringTx.category.key,
          amount: recurringTx.amount,
          type: recurringTx.type.key,
          dateTimestamp: Int(instanceDate.timeIntervalSince1970),
          budgetMonthDate: targetAnchor,
          parentTransactionId: recurringTxId
        )

        do {
          try transactionRepo.insertTransaction(instanceModel)
          print("✅ Created recurring instance: \(recurringTx.title) for \(instanceDate)")
          newInstances.append(instanceModel)
        } catch {
          print("❌ Error creating recurring transaction instance: \(error)")
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
          print("Error deleting outdated recurring instance: \(error)")
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
      print("🧹 ⚠️ Cleanup already in progress for transaction \(parentTransactionId), skipping")
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

      print(
        "🧹 Starting cleanup for recurring transaction \(parentTransactionId) with option: \(cleanupOption)"
      )

      let selectedAnchor = selectedTransactionDate.monthAnchor
      let allInstances = self.transactionRepo.fetchAllRecurringInstances()

      let relatedInstances = allInstances.filter {
        $0.parentTransactionId == parentTransactionId
      }

      print("🧹 Found \(relatedInstances.count) related instances for parent \(parentTransactionId)")

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
          print("🧹 Deleted instance \(instanceId) for parent \(parentTransactionId)")

          let notifID = "transaction_\(instanceId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          print("❌ Error deleting recurring instance \(instanceId): \(error)")
        }
      }

      if cleanupOption == .all {
        do {
          // Try to delete the parent transaction directly - the repository will handle verification
          try self.transactionRepo.delete(id: parentTransactionId)
          print("🧹 Successfully deleted parent recurring transaction \(parentTransactionId)")

          // Clean up notification for deleted parent transaction
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
          print(
            "🔔 🗑️ Removed notification for deleted parent recurring transaction: \(parentTransactionId)"
          )
        } catch {
          print("❌ Error deleting parent recurring transaction \(parentTransactionId): \(error)")
        }
      } else {
        // For non-"all" deletions, check if parent is now orphaned (no remaining instances)
        let remainingInstances = self.transactionRepo.fetchTransactionInstancesForRecurring(
          parentTransactionId)
        if remainingInstances.isEmpty {
          print(
            "🧹 Parent \(parentTransactionId) has no remaining instances after \(cleanupOption) deletion"
          )
          // Delete orphaned parent to prevent resurrection bugs
          do {
            try self.transactionRepo.delete(id: parentTransactionId)
            print("🧹 Deleted orphaned parent recurring transaction \(parentTransactionId)")

            let notifID = "transaction_\(parentTransactionId)"
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
          } catch {
            print("❌ Error deleting orphaned parent transaction \(parentTransactionId): \(error)")
          }
        } else {
          print(
            "🧹 Parent \(parentTransactionId) still has \(remainingInstances.count) instances, keeping it"
          )
        }
      }

      print("🧹 Completed cleanup for recurring transaction \(parentTransactionId)")
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
      print(
        "🧹 ⚠️ Installment cleanup already in progress for transaction \(parentTransactionId), skipping"
      )
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
          print("Error deleting installment instance: \(error)")
        }
      }

      if cleanupOption == .all {
        do {
          try self.transactionRepo.delete(id: parentTransactionId)

          // Clean up notification for deleted parent transaction
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
          print(
            "🔔 🗑️ Removed notification for deleted parent installment transaction: \(parentTransactionId)"
          )
        } catch {
          print("Error deleting parent installment transaction: \(error)")
        }
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
    print(
      "✏️ Editing recurring transaction \(parentTransactionId) with option: \(editOption)"
    )

    let selectedAnchor = selectedTransactionDate.monthAnchor

    // Fetch all transactions ONCE
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Filter to related instances
    let relatedInstances = allTransactions.filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }

    guard !relatedInstances.isEmpty else {
      print("❌ No related instances found for parent \(parentTransactionId)")
      return
    }

    // Build list of instances to update based on edit option
    var instancesToUpdate: [(id: Int, originalDate: Date)] = []

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
        instancesToUpdate.append((id: instanceId, originalDate: instanceDate))
      }
    }

    guard !instancesToUpdate.isEmpty else {
      print("✏️ No instances matched the edit criteria")
      return
    }

    print("✏️ Updating \(instancesToUpdate.count) instances")

    // Get the new day from the selected transaction date
    let localCalendar = Calendar.current
    let newDay = localCalendar.component(.day, from: selectedTransactionDate)

    // Perform all updates
    for (instanceId, originalDate) in instancesToUpdate {
      let originalYear = calendar.component(.year, from: originalDate)
      let originalMonth = calendar.component(.month, from: originalDate)

      // Create new date with the updated day but same month/year
      var dateComponents = DateComponents()
      dateComponents.year = originalYear
      dateComponents.month = originalMonth
      dateComponents.day = newDay
      dateComponents.hour = 0
      dateComponents.minute = 0
      dateComponents.second = 0

      var newDate = localCalendar.date(from: dateComponents)

      // If the date is invalid (e.g., Feb 31), adjust to the last valid day of the month
      if newDate == nil {
        let lastDayOfMonth =
          localCalendar.range(of: .day, in: .month, for: originalDate)?.upperBound ?? 31
        let actualLastDay = lastDayOfMonth - 1
        dateComponents.day = actualLastDay
        newDate = localCalendar.date(from: dateComponents)
      }

      guard let finalDate = newDate else { continue }

      let updatedTransaction = TransactionModel(
        id: instanceId,
        title: newData.data.title,
        category: newData.data.category,
        amount: newData.data.amount,
        type: newData.data.type,
        dateTimestamp: Int(finalDate.timeIntervalSince1970),
        budgetMonthDate: finalDate.monthAnchor,
        isRecurring: newData.data.isRecurring,
        hasInstallments: newData.data.hasInstallments,
        parentTransactionId: parentTransactionId,
        originalAmount: newData.data.originalAmount,
        installmentNumber: newData.data.installmentNumber,
        totalInstallments: newData.data.totalInstallments
      )

      try transactionRepo.updateTransactionDirectly(updatedTransaction)
    }

    print("✏️ Completed editing \(instancesToUpdate.count) recurring instances")
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

    print(
      "🔗 Linked new recurring transaction \(newTransactionId) to existing parent \(existingParentId)"
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
    completion: (() -> Void)? = nil
  ) {
    guard !monthAnchors.isEmpty else {
      DispatchQueue.main.async { completion?() }
      return
    }

    operationQueue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion?() }
        return
      }

      // Fetch ALL transactions ONCE for efficiency
      let allTransactions = self.transactionRepo.fetchAllTransactions()

      // Early exit if no transactions
      guard !allTransactions.isEmpty else {
        DispatchQueue.main.async { completion?() }
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

      // Filter recurring parents and installment parents
      let recurringParents = allTransactions.filter {
        $0.isRecurring == true && ($0.parentTransactionId == nil || $0.parentTransactionId == $0.id)
      }

      let installmentParents = allTransactions.filter {
        $0.hasInstallments == true && $0.parentTransactionId == nil
      }

      // Early exit if no parents to process
      guard !recurringParents.isEmpty || !installmentParents.isEmpty else {
        DispatchQueue.main.async { completion?() }
        return
      }

      var newInstancesCreated = 0

      // Process recurring transactions
      for recurringTx in recurringParents {
        guard let recurringTxId = recurringTx.id else { continue }
        guard allTransactionIds.contains(recurringTxId) else { continue }

        // Get existing anchors from pre-built lookup
        let existingAnchors = instancesByParentId[recurringTxId] ?? []

        // Only generate for months that don't have instances yet
        let missingAnchors = monthAnchors.subtracting(existingAnchors)
          .filter { $0 != recurringTx.budgetMonthDate }  // Don't create for parent's month
          .filter { $0 > recurringTx.budgetMonthDate }  // Only future months

        guard !missingAnchors.isEmpty else { continue }

        let originalDate = Date(timeIntervalSince1970: TimeInterval(recurringTx.dateTimestamp))

        for targetAnchor in missingAnchors {
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
            parentTransactionId: recurringTxId
          )

          do {
            try self.transactionRepo.insertTransaction(instanceModel)
            newInstancesCreated += 1
          } catch {
            print("❌ LAZY: Error creating recurring instance: \(error)")
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

          // Only generate if this month is requested AND doesn't exist yet
          guard monthAnchors.contains(targetAnchor), !existingAnchors.contains(targetAnchor) else {
            continue
          }

          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let installmentDate = self.generateValidDateForMonth(
            originalDate: parentDate,
            targetMonth: targetMonth,
            targetYear: targetYear
          )

          let installmentAmount =
            installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

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
            totalInstallments: totalInstallments
          )

          do {
            try self.transactionRepo.insertTransaction(installmentModel)
            newInstancesCreated += 1
          } catch {
            print("❌ LAZY: Error creating installment instance: \(error)")
          }
        }
      }

      if newInstancesCreated > 0 {
        print("🔄 LAZY: Created \(newInstancesCreated) new instances")
      }

      // Call completion on current (background) queue - callers should dispatch to main if needed
      completion?()
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

    print(
      "🔧 generateValidDateForMonth: originalDay=\(originalDay), targetMonth=\(targetMonth), targetYear=\(targetYear)"
    )

    // Calcular o último dia do mês específico primeiro
    let lastDayOfMonth: Int

    switch targetMonth {
    case 2:  // Fevereiro
      let isLeapYear = (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0)
      lastDayOfMonth = isLeapYear ? 29 : 28
    case 4, 6, 9, 11:  // Abril, Junho, Setembro, Novembro
      lastDayOfMonth = 30
    default:  // Janeiro, Março, Maio, Julho, Agosto, Outubro, Dezembro
      lastDayOfMonth = 31
    }

    print("📅 Last day of month \(targetMonth)/\(targetYear): \(lastDayOfMonth)")

    // Determinar o dia a usar
    let dayToUse = min(originalDay, lastDayOfMonth)
    print("📅 Using day: \(dayToUse) (original: \(originalDay), last day: \(lastDayOfMonth))")

    // Criar a data com o dia determinado
    var dateComponents = DateComponents()
    dateComponents.year = targetYear
    dateComponents.month = targetMonth
    dateComponents.day = dayToUse
    dateComponents.hour = 12  // Usar meio-dia para evitar problemas de fuso horário
    dateComponents.minute = 0
    dateComponents.second = 0

    // Criar a data
    guard let validDate = calendar.date(from: dateComponents) else {
      print("❌ Failed to create date for \(dayToUse)/\(targetMonth)/\(targetYear), using fallback")
      // Fallback: usar o primeiro dia do mês
      dateComponents.day = 1
      let fallbackDate = calendar.date(from: dateComponents) ?? Date()
      print("⚠️ Using fallback date (1st day) for month \(targetMonth)/\(targetYear)")
      return fallbackDate
    }

    if dayToUse != originalDay {
      print(
        "📅 Adjusted date for month \(targetMonth)/\(targetYear): original day \(originalDay) → adjusted day \(dayToUse)"
      )
    } else {
      print("✅ Original day \(originalDay) works for month \(targetMonth)/\(targetYear)")
    }

    return validDate
  }

  // MARK: - Notification Management

  /// Sistema otimizado para agendar notificações de transações recorrentes
  private func scheduleOptimizedNotificationsForRecurringInstances(_ instances: [TransactionModel])
  {
    print("🔔 🔄 Scheduling optimized notifications for \(instances.count) recurring instances")

    // Agrupar instâncias por mês
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

    print("🔔 📅 Grouped recurring instances into \(instancesByMonth.count) months")

    // Agendar notificação para cada mês (máximo 1 por mês)
    for (monthKey, monthInstances) in instancesByMonth {
      scheduleMonthlyRecurringNotification(monthKey: monthKey, instances: monthInstances)
    }
  }

  /// Agenda uma notificação mensal para todas as instâncias recorrentes do mês
  private func scheduleMonthlyRecurringNotification(monthKey: String, instances: [TransactionModel])
  {
    guard let firstInstance = instances.first else { return }

    let date = Date(timeIntervalSince1970: TimeInterval(firstInstance.data.dateTimestamp))

    // Verificar se a data é muito no futuro (mais de 1 ano)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow {
      print(
        "🔔 ⚠️ Recurring month \(monthKey) is more than 1 year in the future, skipping notification")
      return
    }

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      print("🔔 ⚠️ Recurring notification time is in the past, skipping")
      return
    }

    let timeInterval = notificationDate.timeIntervalSinceNow

    // Verificar se o intervalo é muito grande (mais de 30 dias)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      print("🔔 ⚠️ Recurring month \(monthKey) is more than 30 days away, scheduling reminder")
      scheduleRecurringReminderNotification(for: monthKey, instances: instances)
      return
    }

    // Criar notificação mensal consolidada
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
        print("🔔 ❌ Error scheduling recurring notification for month \(monthKey): \(error)")
      } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        print(
          "🔔 ✅ Scheduled recurring notification for month \(monthKey) at \(formatter.string(from: notificationDate))"
        )
      }
    }
  }

  /// Agenda uma notificação de lembrete para instâncias recorrentes distantes
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
        print("🔔 ❌ Error scheduling recurring reminder for month \(monthKey): \(error)")
      } else {
        print("🔔 ✅ Scheduled recurring reminder for month \(monthKey)")
      }
    }
  }
}
