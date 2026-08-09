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
  // Static so ALL manager instances share one serial queue. Recurring generation,
  // edits and deletes are then mutually serialized across the whole app — previously
  // each instance had its own queue, so (for example) an "edit future" on the
  // AddTransaction screen's manager could run concurrently with lazy generation on the
  // Dashboard's manager and interleave reads/writes on the same series. That race
  // produced exact duplicate occurrences: both managers read their own snapshot of the
  // series, both computed the same month as missing, and both inserted it.
  private static let operationQueue = DispatchQueue(
    label: "recurring.transaction.operations", qos: .userInitiated)
  private static var currentOperations: Set<String> = []
  private static let operationLock = NSLock()

  // MARK: - Deleted Instance Tracking
  // Tracks instances deleted via .currentSelection to prevent lazy generation from recreating them.
  // Key: parentTransactionId, Value: set of month anchors that should NOT be regenerated.
  //
  // STATIC, and not per-instance: managers are created per view model — DashboardViewModel and
  // AddTransactionModalViewModel each own one — so an anchor recorded by the manager that performed
  // the delete was invisible to whichever manager next ran lazy generation, and the occurrence the
  // user had just removed came straight back. The set belongs to the series, not to a manager.
  private static var deletedInstanceAnchors: [Int: Set<Int>] = [:]
  /// The installment equivalent, keyed by installment number rather than month — see
  /// `trackDeletedInstallments`.
  private static var deletedInstallmentNumbers: [Int: Set<Int>] = [:]
  private static let deletedAnchorsLock = NSLock()

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
    // Keyed on seriesPeriod — the occurrence an instance IS — not budgetMonthDate, the month it
    // is accounted FOR. A rule that pushes a date into an adjacent month moves budgetMonthDate,
    // which would leave the occurrence's own slot looking empty and have us recreate it.
    let existingAnchors = Set(existingInstances.map { $0.seriesPeriod })

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
        // The series' canonical date, not its stored one — see `unadjustedDate`.
        let originalDate = recurringTx.unadjustedDate

        // Generate a valid date for the target month
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)
        let occurrence = OccurrenceDateCalculator.occurrencePair(
          from: originalDate,
          targetMonth: targetMonth,
          targetYear: targetYear,
          rule: recurringTx.businessDayRule,
          calendar: calendar
        )
        let instanceDate = occurrence.adjusted

        // Create the instance, preserving credit card association from parent
        let instanceModel = TransactionModel(
          title: recurringTx.title,
          category: recurringTx.category.key,
          amount: recurringTx.amount,
          type: recurringTx.type.key,
          dateTimestamp: Int(occurrence.adjusted.timeIntervalSince1970),
          budgetMonthDate: targetAnchor,
          parentTransactionId: recurringTxId,
          creditCardId: recurringTx.creditCardId,
          businessDayRule: recurringTx.businessDayRule,
          unadjustedDateTimestamp: Int(occurrence.unadjusted.timeIntervalSince1970),
          seriesPeriod: targetAnchor
        )

        do {
          let insertedId = try transactionRepo.insertTransactionAndGetId(instanceModel)
          newInstances.append(instanceModel)

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

    // CHILDREN ONLY. `fetchAllRecurringInstances` filters on `parentTransactionId != nil`, and a
    // series parent SELF-links — so the parent is in that list, and the `isBeforeRecurringStart`
    // test below ("month <= this series' start month") is trivially true for it. Cleanup would
    // therefore delete the parent of every series it looked at, taking the whole series with it.
    //
    // This is masked today only because the loop `return`s on the first row with a nil id, which
    // aborts the whole pass. That `return` is a bug in its own right (one bad row silently stops
    // cleanup for every remaining sibling) and is fixed to `continue` below — so the two changes
    // MUST land together: fixing the `continue` alone makes the parent deletion reachable.
    let allInstances = transactionRepo.fetchAllRecurringInstances()
      .filter { $0.id != $0.parentTransactionId }
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

      // `continue`, not `return`: a single row with a nil id used to abort cleanup for every
      // remaining sibling in the ledger.
      guard let id = instance.id else { continue }

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
    deletedInstallmentNumbers.removeValue(forKey: parentId)
  }

  /// Month anchors intentionally deleted for a parent, read by lazy generation so it won't recreate
  /// a month the user explicitly removed.
  static func excludedAnchors(for parentId: Int) -> Set<Int> {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    return deletedInstanceAnchors[parentId] ?? []
  }

  /// Record installment occurrences the user removed one at a time.
  ///
  /// Kept separate from the recurring anchor set because installments are identified by number: a
  /// card installment is re-anchored onto its statement's due date, so its month is not its identity.
  static func trackDeletedInstallments(parentId: Int, numbers: Set<Int>) {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    deletedInstallmentNumbers[parentId, default: []].formUnion(numbers)
  }

  static func excludedInstallmentNumbers(for parentId: Int) -> Set<Int> {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    return deletedInstallmentNumbers[parentId] ?? []
  }

  /// Drops every exclusion, for when the rows they refer to are gone.
  ///
  /// Both sets are keyed by parent row id, which only identifies a series for as long as that series
  /// exists. Wipe the transaction store and the next series to be created can be handed the same id,
  /// inheriting exclusions that suppress occurrences the user never deleted. Called wherever the
  /// store is emptied wholesale.
  static func clearAllDeletedInstanceTracking() {
    deletedAnchorsLock.lock()
    defer { deletedAnchorsLock.unlock() }
    deletedInstanceAnchors.removeAll()
    deletedInstallmentNumbers.removeAll()
  }

  func cleanupRecurringInstancesFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    cleanupOption: RecurringCleanupOption,
    completion: (() -> Void)? = nil
  ) {
    let operationId = "cleanup_recurring_\(parentTransactionId)_\(cleanupOption)"

    // Prevent concurrent deletion operations on the same transaction.
    // Unlocked explicitly rather than by `defer`: the lock is now shared by every manager
    // instance, so holding it across the dispatch below would serialize unrelated work,
    // and NSLock is not recursive.
    Self.operationLock.lock()
    guard !Self.currentOperations.contains(operationId) else {
      Self.operationLock.unlock()
      DispatchQueue.main.async { completion?() }
      return
    }
    Self.currentOperations.insert(operationId)
    Self.operationLock.unlock()

    Self.operationQueue.async { [weak self] in
      defer {
        Self.operationLock.lock()
        Self.currentOperations.remove(operationId)
        Self.operationLock.unlock()
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
        Self.trackDeletedInstance(parentId: parentTransactionId, monthAnchor: selectedAnchor)
      }

      if cleanupOption == .all {
        do {
          try self.transactionRepo.delete(id: parentTransactionId)
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting parent recurring transaction \(parentTransactionId): \(error)")
        }
        Self.clearDeletedInstanceTracking(for: parentTransactionId)
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
          Self.clearDeletedInstanceTracking(for: parentTransactionId)
        } else if cleanupOption == .futureOnly {
          // When deleting future instances, mark parent as no longer recurring
          // This prevents lazy generation from recreating deleted instances
          do {
            try self.transactionRepo.updateIsRecurring(
              transactionId: parentTransactionId, isRecurring: false)
          } catch {
            logError("Error updating isRecurring flag for parent \(parentTransactionId): \(error)")
          }
          Self.clearDeletedInstanceTracking(for: parentTransactionId)
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

    // Prevent concurrent deletion operations on the same transaction. Explicit unlock —
    // see the note on the recurring cleanup path above.
    Self.operationLock.lock()
    guard !Self.currentOperations.contains(operationId) else {
      Self.operationLock.unlock()
      DispatchQueue.main.async { completion?() }
      return
    }
    Self.currentOperations.insert(operationId)
    Self.operationLock.unlock()

    Self.operationQueue.async { [weak self] in
      defer {
        Self.operationLock.lock()
        Self.currentOperations.remove(operationId)
        Self.operationLock.unlock()
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
      var numbersDeleted: Set<Int> = []

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
          if let number = instance.installmentNumber { numbersDeleted.insert(number) }
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

      // Track the deleted occurrences so lazy generation won't recreate them. Recorded by
      // installment NUMBER, which is what generation matches on — the month a card installment sits
      // in is its statement's due month, so it is not a stable identity for the occurrence.
      if cleanupOption == .currentSelection && !numbersDeleted.isEmpty {
        Self.trackDeletedInstallments(parentId: parentTransactionId, numbers: numbersDeleted)
      }

      if cleanupOption == .all {
        do {
          try self.transactionRepo.delete(id: parentTransactionId)
          let notifID = "transaction_\(parentTransactionId)"
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          logError("Error deleting parent installment transaction: \(error)")
        }
        Self.clearDeletedInstanceTracking(for: parentTransactionId)
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
        Self.clearDeletedInstanceTracking(for: parentTransactionId)
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

    // RELINK FIRST. "This and future" / "all" select siblings by parent pointer, and that pointer is
    // a local autoincrement id — a row that predates a repair can point at a row that no longer
    // exists. Those rows were silently skipped and stayed stale forever. Re-attaching them by
    // content BEFORE the selection runs is what makes the plain pointer filter below sufficient.
    let relinked = RecurringSeriesLinker(transactionRepo: transactionRepo)
      .repairTransactionSeries(around: parentTransactionId)
    if relinked > 0 {
      logWarning("[RecurringEdit] Relinked \(relinked) orphaned occurrence(s) before edit")
    }

    // Fetch all transactions ONCE (now includes any just-relinked rows)
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Filter to related instances
    let relatedInstances = allTransactions.filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }

    guard !relatedInstances.isEmpty else { return }

    // Build list of instances to update based on edit option
    // Store the original timestamp and budgetMonthDate to preserve them
    var instancesToUpdate: [(id: Int, originalTimestamp: Int, originalBudgetMonthDate: Int, originalSeriesPeriod: Int, originalIsRecurring: Bool?, originalParentId: Int?, originalCreditCardId: Int?, originalStatementId: Int?)] = []

    for instance in relatedInstances {
      guard let instanceId = instance.id else { continue }

      // The occurrence's own slot, read from the row rather than recomputed from its timestamp. Those
      // agree only while nothing shifts a date across a month boundary; with a business-day rule in
      // play, deriving it from the stored (already adjusted) date puts an occurrence in the wrong
      // month and "this and future occurrences" then edits the wrong set.
      let instanceMonthAnchor = instance.seriesPeriod

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
          originalSeriesPeriod: instanceMonthAnchor,
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
    // The series' own anchor row, for the un-clamped anchor day.
    let seriesParent = relatedInstances.first(where: { $0.id == parentTransactionId })

    for (instanceId, originalTimestamp, originalBudgetMonthDate, originalSeriesPeriod, originalIsRecurring, originalParentId, originalCreditCardId, originalStatementId) in instancesToUpdate {
      // Compare against the SERIES' anchor day, never this row's own day.
      //
      // A row's day is clamped to its month: a day-31 series is day 28 in February. Comparing the
      // picked day against the clamped one reported "changed" for February on every single edit.
      let seriesAnchorDay =
        seriesParent.map {
          localCalendar.component(
            .day, from: Date(timeIntervalSince1970: TimeInterval($0.dateTimestamp)))
        }
        ?? localCalendar.component(
          .day, from: Date(timeIntervalSince1970: TimeInterval(originalTimestamp)))

      // Legacy rows whose accounting month drifted away from their slot get repaired on any edit.
      let slotDrifted = originalBudgetMonthDate != originalSeriesPeriod

      let finalTimestamp: Int
      let finalBudgetMonthDate: Int
      let dateChanged: Bool

      if newDay == seriesAnchorDay && !slotDrifted {
        // Day didn't change - preserve original timestamp and budgetMonthDate exactly
        finalTimestamp = originalTimestamp
        finalBudgetMonthDate = originalBudgetMonthDate
        dateChanged = false
      } else {
        // Rebuild from the SLOT, through the same helper generation uses.
        //
        // This used to build `DateComponents` from the ROW's own date with the new day, which is
        // wrong twice over. Day 31 in February does not fail — Foundation rolls it forward to 3
        // March — so `finalBudgetMonthDate` became March: the February occurrence vanished from
        // February and landed on top of March's, which is where "a missing month plus a duplicate in
        // a later month" came from. And deriving the month from an already business-day-shifted date
        // put the occurrence in the neighbouring month for the same reason.
        //
        // `OccurrenceDateCalculator.occurrence` clamps properly (min(day, lastDayOfMonth)), and the
        // slot is authoritative about which month this occurrence is FOR.
        let slotDate = Date(timeIntervalSince1970: TimeInterval(originalSeriesPeriod))
        let targetYear = localCalendar.component(.year, from: slotDate)
        let targetMonth = localCalendar.component(.month, from: slotDate)

        let calculatedDate = OccurrenceDateCalculator.occurrence(
          anchorDay: newDay, targetMonth: targetMonth, targetYear: targetYear,
          calendar: localCalendar)

        finalTimestamp = Int(calculatedDate.timeIntervalSince1970)
        // Pinned to the slot, exactly as generation does. An occurrence can no longer leave the
        // month it is scheduled for, whatever a rule did to its date.
        finalBudgetMonthDate = originalSeriesPeriod
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

    Self.operationQueue.async { [weak self] in
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

      // Which occurrences of each series already exist. Two maps, because the two kinds of series
      // identify an occurrence differently:
      //
      //  - RECURRING by `seriesPeriod`, the month it was SCHEDULED for. Deliberately not
      //    `budgetMonthDate`: a business-day rule can push the date into an adjacent month, and keying
      //    on where it landed empties the scheduled month's slot — so the loop below sees a missing
      //    occurrence and creates a duplicate, once per generation pass.
      //  - INSTALLMENTS by `installmentNumber`. A card installment is additionally re-anchored onto
      //    its statement's due date, so neither of its month fields is a stable identity; the ordinal
      //    is, and it never moves.
      var instancesByParentId: [Int: Set<Int>] = [:]  // parentId -> Set of occurrence slots
      var installmentNumbersByParentId: [Int: Set<Int>] = [:]
      for tx in allTransactions {
        if let parentId = tx.parentTransactionId {
          instancesByParentId[parentId, default: []].insert(tx.seriesPeriod)
          if let number = tx.installmentNumber {
            installmentNumbersByParentId[parentId, default: []].insert(number)
          }
        }
      }

      // Cross-device duplicate protection: which SLOTS are already occupied, per series identity.
      //
      // This used to be keyed on `title | slot | day` over EVERY row in the ledger, so a one-off
      // transaction — or a row in a different category or type that merely shared a title and a day
      // — silently blocked that month for a genuine series. That is the "some months are skipped"
      // bug. The key is now the full series fingerprint, and only rows that are part of a recurring
      // series contribute to it.
      //
      // The day used is the SERIES' canonical day: for a child, the day its parent is anchored on,
      // not the child's own, which `OccurrenceDateCalculator` may have clamped in a short month.
      let parentsById = Dictionary(
        uniqueKeysWithValues: allTransactions.compactMap { tx -> (Int, Transaction)? in
          guard let id = tx.id else { return nil }
          return (id, tx)
        })

      func fingerprint(of tx: Transaction) -> SeriesFingerprint? {
        guard tx.id != nil else { return nil }
        let anchorSource = tx.parentTransactionId.flatMap { parentsById[$0] } ?? tx
        return SeriesFingerprint(
          scope: nil,  // no group ledgers on this branch
          title: tx.title,
          category: tx.category.key,
          type: tx.type.key,
          anchorDay: SeriesDay.anchorDay(of: anchorSource))
      }

      var occupiedSlots: [SeriesFingerprint: Set<Int>] = [:]
      for tx in allTransactions where tx.mode == .recurring {
        guard let key = fingerprint(of: tx) else { continue }
        occupiedSlots[key, default: []].insert(tx.seriesPeriod)
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

        // Get anchors of intentionally deleted instances (from .currentSelection deletion).
        // `excludedAnchors` takes `deletedAnchorsLock` itself; wrapping it in operationLock as
        // well would hold the now app-wide lock inside this loop and stall every other manager.
        let excludedAnchors = Self.excludedAnchors(for: recurringTxId)

        // Compared against the parent's SLOT, not its accounting month. Once a business-day rule can
        // push a date across a month boundary the two disagree, and comparing the wrong one either
        // skipped a legitimate month or re-created one the parent already holds.
        let parentSlot = recurringTx.seriesPeriod
        let missingAnchors = monthAnchors.subtracting(existingAnchors)
          .subtracting(excludedAnchors)
          .filter { $0 > parentSlot }  // Forward-only; the parent occupies its own slot

        // A tombstone is the one thing that silently removes months from a series. Say so.
        let suppressed = monthAnchors.intersection(excludedAnchors).filter { $0 > parentSlot }
        if !suppressed.isEmpty {
          logWarning(
            "[Materialize] series \(recurringTxId) ('\(recurringTx.title)'): \(suppressed.count) month(s) suppressed by an earlier delete")
        }

        guard !missingAnchors.isEmpty else { continue }

        let seriesKey = fingerprint(of: recurringTx)

        // The series' canonical date, NOT its stored one. Re-deriving the anchor day from a date the
        // rule has already shifted would walk the series a little further every generation pass.
        let originalDate = recurringTx.unadjustedDate

        for targetAnchor in missingAnchors.sorted() {
          // A row matching this series' full fingerprint already holds the slot but is not linked to
          // this parent — its parent pointer is broken. Creating a second row would duplicate the
          // month; the repair belongs to RecurringSeriesLinker, which runs ahead of every CRUD.
          if let seriesKey = seriesKey, occupiedSlots[seriesKey]?.contains(targetAnchor) == true {
            logWarning(
              "[Materialize] slot \(targetAnchor) for series \(recurringTxId) ('\(recurringTx.title)') is held by an unlinked row — skipping")
            continue
          }

          // Which month this slot IS, read in the same timezone the anchor was written in.
          //
          // `targetAnchor` is local midnight on the 1st (`Date.monthAnchor` is `TimeZone.current`).
          // Reading it back through this type's UTC calendar lands in the PREVIOUS month for any
          // zone ahead of UTC, so the occurrence was generated for the wrong month while
          // `budgetMonthDate` still said the right one. The date is still CONSTRUCTED with
          // `self.calendar` below, so existing rows' timestamps keep their convention.
          let targetDate = Date(timeIntervalSince1970: TimeInterval(targetAnchor))
          var anchorCalendar = Calendar(identifier: .gregorian)
          anchorCalendar.timeZone = TimeZone.current
          let targetYear = anchorCalendar.component(.year, from: targetDate)
          let targetMonth = anchorCalendar.component(.month, from: targetDate)

          let occurrence = OccurrenceDateCalculator.occurrencePair(
            from: originalDate,
            targetMonth: targetMonth,
            targetYear: targetYear,
            rule: recurringTx.businessDayRule,
            calendar: self.calendar
          )

          if let seriesKey = seriesKey {
            occupiedSlots[seriesKey, default: []].insert(targetAnchor)
          }

          // `budgetMonthDate` is where the money actually moves, so it follows the ADJUSTED date;
          // `seriesPeriod` is which occurrence this is, so it stays on the scheduled month. They
          // differ exactly when the rule crossed a month boundary, and that is the case this whole
          // split exists for.
          let instanceModel = TransactionModel(
            title: recurringTx.title,
            category: recurringTx.category.key,
            amount: recurringTx.amount,
            type: recurringTx.type.key,
            dateTimestamp: Int(occurrence.adjusted.timeIntervalSince1970),
            budgetMonthDate: targetAnchor,
            parentTransactionId: recurringTxId,
            creditCardId: recurringTx.creditCardId,
            businessDayRule: recurringTx.businessDayRule,
            unadjustedDateTimestamp: Int(occurrence.unadjusted.timeIntervalSince1970),
            seriesPeriod: targetAnchor
          )

          do {
            let insertedId = try self.transactionRepo.insertTransactionAndGetId(instanceModel)
            newInstancesCreated += 1

            // Assign to correct monthly statement if linked to a credit card. Routed by the
            // unadjusted date: which billing cycle an occurrence falls in is decided by when it was
            // scheduled, not by a weekend shift moving it a day or two.
            if let cardId = recurringTx.creditCardId,
               let uid = AuthenticationManager.shared.currentUser?.uid {
              self.assignToStatement(
                transactionId: insertedId, creditCardId: cardId,
                transactionDate: occurrence.unadjusted, userId: uid)
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

        // Which occurrences of this series already exist, by number. See the note on
        // `installmentNumbersByParentId`: a card installment's month is its statement's due month,
        // not "purchase month + N", so the month is not a usable identity here.
        let existingNumbers = installmentNumbersByParentId[parentId] ?? []
        let excludedNumbers = Self.excludedInstallmentNumbers(for: parentId)

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

          // Only generate if this month is requested, and this occurrence neither already exists nor
          // was intentionally removed by the user.
          guard monthAnchors.contains(targetAnchor),
            !existingNumbers.contains(installmentNumber),
            !excludedNumbers.contains(installmentNumber)
          else {
            continue
          }

          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let occurrence = OccurrenceDateCalculator.occurrencePair(
            from: parentDate,
            targetMonth: targetMonth,
            targetYear: targetYear,
            rule: parent.businessDayRule,
            calendar: self.calendar
          )

          let installmentAmount =
            installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

          let installmentModel = TransactionModel(
            title: cleanTitle,
            category: parent.category.key,
            amount: installmentAmount,
            type: parent.type.key,
            dateTimestamp: Int(occurrence.adjusted.timeIntervalSince1970),
            budgetMonthDate: targetAnchor,
            parentTransactionId: parentId,
            originalAmount: originalAmount,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            businessDayRule: parent.businessDayRule,
            unadjustedDateTimestamp: Int(occurrence.unadjusted.timeIntervalSince1970),
            seriesPeriod: targetAnchor
          )

          do {
            try self.transactionRepo.insertTransaction(installmentModel)
            newInstancesCreated += 1
          } catch {
            logError("Error creating installment instance: \(error)")
          }
        }
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
  private func assignToStatement(transactionId: Int, creditCardId: Int, transactionDate: Date, userId: String) {
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
    } catch {
      logError("Error assigning transaction \(transactionId) to statement: \(error)")
    }
  }

  // MARK: - Helper Methods


  // MARK: - Notification Management

  /// Optimized system for scheduling recurring transaction notifications
  private func scheduleOptimizedNotificationsForRecurringInstances(_ instances: [TransactionModel])
  {
    SeriesNotificationScheduler.schedule(instances, kind: .recurring)
  }

}
