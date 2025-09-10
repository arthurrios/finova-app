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
        print("🧹 Skipping parent deletion for \(cleanupOption) cleanup")
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

  /// Edit recurring transactions based on the selected option
  func editRecurringTransactionsFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    editOption: RecurringEditOption,
    newData: TransactionModel
  ) throws {
    print(
      "✏️ Starting edit for recurring transaction \(parentTransactionId) with option: \(editOption)"
    )

    // Debug the input data
    print(
      "✏️ DEBUG: Input newData - title: '\(newData.data.title)', category: '\(newData.data.category)', type: '\(newData.data.type)'"
    )

    let selectedAnchor = selectedTransactionDate.monthAnchor
    let allInstances = transactionRepo.fetchAllRecurringInstances()

    let relatedInstances = allInstances.filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }

    print("✏️ Found \(relatedInstances.count) related instances for parent \(parentTransactionId)")
    print("✏️ DEBUG: Related instances:")
    for instance in relatedInstances {
      let instanceDate = Date(timeIntervalSince1970: TimeInterval(instance.dateTimestamp))
      let isParent = instance.id == parentTransactionId
      let isChild = instance.parentTransactionId == parentTransactionId
      print(
        "✏️ DEBUG: - Instance \(instance.id ?? -1): Date=\(instanceDate), IsParent=\(isParent), IsChild=\(isChild)"
      )
    }

    // Update instances based on edit option
    var instancesToUpdate: [Int] = []

    for instance in relatedInstances {
      // Calculate the month anchor from the actual transaction date
      // This fixes the issue where budgetMonthDate might contain transaction timestamps instead of month anchors
      let instanceDate = Date(timeIntervalSince1970: TimeInterval(instance.dateTimestamp))
      let instanceMonthAnchor = instanceDate.monthAnchor

      let shouldUpdate: Bool

      switch editOption {
      case .currentSelection:
        // Only update the current selected transaction
        shouldUpdate = instanceMonthAnchor == selectedAnchor
        print(
          "✏️ DEBUG: Current selection - instance anchor: \(instanceMonthAnchor), selected anchor: \(selectedAnchor), shouldUpdate: \(shouldUpdate)"
        )
      case .futureOnly:
        shouldUpdate = instanceMonthAnchor >= selectedAnchor
        print(
          "✏️ DEBUG: Future only - instance anchor: \(instanceMonthAnchor), selected anchor: \(selectedAnchor), shouldUpdate: \(shouldUpdate)"
        )
      case .all:
        shouldUpdate = true
        print(
          "✏️ DEBUG: All - instance anchor: \(instanceMonthAnchor), shouldUpdate: \(shouldUpdate)"
        )
      }

      if shouldUpdate, let instanceId = instance.id {
        instancesToUpdate.append(instanceId)
        print("✏️ DEBUG: Added instance \(instanceId) to update list")
      }
    }

    // Get the new day from the selected transaction date
    // Use local calendar to extract day to avoid timezone issues
    let localCalendar = Calendar.current
    let newDay = localCalendar.component(.day, from: selectedTransactionDate)
    print("✏️ DEBUG: Selected transaction date: \(selectedTransactionDate)")
    print("✏️ DEBUG: Extracted new day (local): \(newDay)")
    print("✏️ DEBUG: Instances to update: \(instancesToUpdate.count)")

    // Parent transaction is now included in relatedInstances, so no need for separate logic

    // Perform updates atomically
    print("✏️ DEBUG: Starting to update \(instancesToUpdate.count) instances")
    for instanceId in instancesToUpdate {
      print("✏️ DEBUG: Processing instance \(instanceId)")
      // Find the original instance to get its month/year
      guard let originalInstance = relatedInstances.first(where: { $0.id == instanceId }) else {
        print("❌ Could not find original instance \(instanceId)")
        continue
      }
      print("✏️ DEBUG: Found original instance \(instanceId) with date: \(originalInstance.date)")

      // Calculate the new date for this instance (same day, same month/year as original)
      let originalDate = originalInstance.date
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

      print(
        "✏️ DEBUG: Creating date for instance \(instanceId) - Year: \(originalYear), Month: \(originalMonth), Day: \(newDay)"
      )
      print("✏️ DEBUG: Original date was: \(originalDate)")
      print("✏️ DEBUG: Date components: \(dateComponents)")

      // Try to create the date with the new day using local calendar
      var newDate = localCalendar.date(from: dateComponents)

      // If the date is invalid (e.g., Feb 31), adjust to the last valid day of the month
      if newDate == nil {
        let lastDayOfMonth =
          localCalendar.range(of: .day, in: .month, for: originalDate)?.upperBound ?? 31
        let actualLastDay = lastDayOfMonth - 1  // upperBound is exclusive
        dateComponents.day = actualLastDay
        newDate = localCalendar.date(from: dateComponents)
        print("✏️ DEBUG: Invalid date, adjusted to last day of month: \(actualLastDay)")
      }

      guard let finalDate = newDate else {
        print("❌ Could not create new date for instance \(instanceId)")
        continue
      }

      print("✏️ DEBUG: Final date created: \(finalDate)")
      print("✏️ DEBUG: Final day component (UTC): \(calendar.component(.day, from: finalDate))")
      print(
        "✏️ DEBUG: Final day component (local): \(localCalendar.component(.day, from: finalDate))")

      let newTimestamp = Int(finalDate.timeIntervalSince1970)
      let newBudgetMonthDate = finalDate.monthAnchor

      // Create updated transaction model with new data and updated date
      let updatedModel = TransactionModel(
        id: instanceId,
        title: newData.data.title,
        category: newData.data.category,
        amount: newData.data.amount,
        type: newData.data.type,
        dateTimestamp: newTimestamp,
        budgetMonthDate: newBudgetMonthDate,
        parentTransactionId: parentTransactionId
      )

      print(
        "✏️ DEBUG: About to update transaction \(instanceId) with new timestamp: \(newTimestamp)")
      print(
        "✏️ DEBUG: Updated model data - title: '\(updatedModel.data.title)', amount: \(updatedModel.data.amount), dateTimestamp: \(updatedModel.data.dateTimestamp), budgetMonthDate: \(updatedModel.data.budgetMonthDate)"
      )

      do {
        // Use updateSingleTransactionOnly to avoid TransactionRepository's recurring logic
        let category =
          TransactionCategory.allCases.first(where: { $0.key == updatedModel.data.category })
          ?? .miscellaneous
        let type =
          TransactionType.allCases.first(where: { String(describing: $0) == updatedModel.data.type }
          ) ?? .expense

        // Create a custom update that preserves the correct budgetMonthDate
        let updatedTransaction = TransactionModel(
          id: instanceId,
          title: updatedModel.data.title,
          category: updatedModel.data.category,
          amount: updatedModel.data.amount,
          type: updatedModel.data.type,
          dateTimestamp: Int(finalDate.timeIntervalSince1970),
          budgetMonthDate: finalDate.monthAnchor,  // Use proper month anchor calculation
          isRecurring: updatedModel.data.isRecurring,
          hasInstallments: updatedModel.data.hasInstallments,
          parentTransactionId: updatedModel.data.parentTransactionId,
          originalAmount: updatedModel.data.originalAmount,
          installmentNumber: updatedModel.data.installmentNumber,
          totalInstallments: updatedModel.data.totalInstallments
        )

        // Use the new direct update method that preserves correct budgetMonthDate
        try transactionRepo.updateTransactionDirectly(updatedTransaction)

        // Verify the update was successful by fetching the transaction
        let allTransactions = transactionRepo.fetchAllTransactions()
        if let updatedTransaction = allTransactions.first(where: { $0.id == instanceId }) {
          let updatedDate = Date(
            timeIntervalSince1970: TimeInterval(updatedTransaction.dateTimestamp))
          print(
            "✅ VERIFICATION: Transaction \(instanceId) updated successfully - Date: \(updatedDate), Day: \(Calendar.current.component(.day, from: updatedDate)), BudgetMonthDate: \(updatedTransaction.budgetMonthDate)"
          )
        } else {
          print("❌ VERIFICATION: Transaction \(instanceId) NOT FOUND after update!")
        }

        print(
          "✅ Successfully updated instance \(instanceId) for parent \(parentTransactionId) (updated date from \(originalDate) to \(finalDate))"
        )
      } catch {
        print("❌ Failed to update instance \(instanceId): \(error)")
        throw error
      }
    }

    // Parent transaction is now handled in the main update loop above

    print("✏️ Completed edit for recurring transaction \(parentTransactionId)")

    // Verify the updates were successful
    let updatedInstances = transactionRepo.fetchAllRecurringInstances().filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }
    print("✏️ DEBUG: Verification - Found \(updatedInstances.count) instances after update")
    for instance in updatedInstances {
      let instanceDate = Date(timeIntervalSince1970: TimeInterval(instance.dateTimestamp))
      print(
        "✏️ DEBUG: Instance \(instance.id ?? -1) - Date: \(instanceDate), Day: \(Calendar.current.component(.day, from: instanceDate))"
      )
    }

    // Additional verification: Check if all instances are still in the main transaction list
    let allTransactions = transactionRepo.fetchAllTransactions()
    let relatedTransactionsInMainList = allTransactions.filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }
    print(
      "✏️ DEBUG: Verification - Found \(relatedTransactionsInMainList.count) related transactions in main list"
    )
    for tx in relatedTransactionsInMainList {
      let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
      print(
        "✏️ DEBUG: Main list transaction \(tx.id ?? -1) - Date: \(txDate), Day: \(Calendar.current.component(.day, from: txDate))"
      )
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

    return recurringTransactions.first { transaction in
      transaction.title.lowercased() == title.lowercased() && transaction.category.key == category
        && transaction.amount == amount && transaction.type.key == type
        && transaction.parentTransactionId == nil  // Only parent transactions
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
