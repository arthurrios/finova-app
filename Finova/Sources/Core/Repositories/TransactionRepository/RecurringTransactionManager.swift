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
  /// EAGER GENERATION — the invariant this whole type exists to hold:
  ///
  /// A series' occurrences are materialized IN FULL at creation, re-materialized IN FULL before any
  /// edit or delete, and topped up by ONE rolling pass at dashboard load. Nothing is ever generated in
  /// response to navigation, rendering or scrolling. A month that is missing is a bug with no
  /// self-healing path — that is deliberate, because the alternative (materialize-on-render) is what
  /// left months stale wherever the user had not happened to scroll.
  ///
  /// Generation is always SERIES-anchored — from a parent's own start month through the horizon —
  /// never window-anchored. A window pass leaves permanent holes in any series older than the window.
  ///
  /// It stays idempotent, forward-only, tombstone-aware and hydration-gated, which is what makes it
  /// sync cleanly: every occurrence is a first-class synced row created once, not regenerated
  /// independently on each device (which produced duplicates and resurrected deletions).
  static var horizonMonths: Int { SeriesMonths.horizonMonths }

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

  // MARK: - Eager Materialization
  //
  // The window-based generators that used to live here (`generateRecurringTransactionsForRange`,
  // `generateInstancesForNewRecurringTransaction`, `performInstanceGeneration`) are gone. They
  // enumerated a range of month OFFSETS around a reference date, which left permanent holes in any
  // series whose start fell outside that window, and they had drifted from the path actually in use.
  // Everything now goes through `materializeMissingOccurrences`, which is SERIES-anchored.

  /// Materializes every missing occurrence of ONE series, from its own start month through the
  /// horizon, and returns how many rows were created.
  ///
  /// This is the entry point every CRUD action uses. `SeriesMonths.seriesAnchors` anchors the horizon
  /// on `max(now, start)`, which is what makes a series created for a past month fill the gap between
  /// its start and today instead of leaving it empty forever.
  @discardableResult
  func materializeSeries(parentId: Int) -> Int {
    return materializeSeriesInline(parentId: parentId)
  }

  /// Relinks orphaned occurrences into this series and then materializes it in full, on the serial
  /// queue, answering only once BOTH are done.
  ///
  /// The entry point creation uses. Answering early is what let the dashboard refresh onto a series
  /// that was still being written — and with nothing generating on render, a month missed here stays
  /// missing until the next rolling top-up.
  func linkAndMaterializeSeries(parentId: Int, completion: @escaping (Int) -> Void) {
    Self.operationQueue.async { [weak self] in
      guard let self = self else {
        completion(0)
        return
      }

      let relinked = RecurringSeriesLinker(transactionRepo: self.transactionRepo)
        .repairTransactionSeries(around: parentId)
      if relinked > 0 {
        logWarning("[RecurringCreate] adopted \(relinked) orphaned occurrence(s) into series \(parentId)")
      }

      completion(self.materializeSeriesInline(parentId: parentId))
    }
  }

  /// Synchronous core of `materializeSeries`. Safe to call inline when already serialized on
  /// `operationQueue` — the edit and delete paths do exactly that.
  private func materializeSeriesInline(parentId: Int) -> Int {
    let all = transactionRepo.fetchAllTransactions()
    guard let parent = all.first(where: { $0.id == parentId }) else { return 0 }
    let anchors = SeriesMonths.seriesAnchors(start: parent.seriesPeriod)
    guard !anchors.isEmpty else { return 0 }
    return materializeMissingOccurrences(Set(anchors), limitedToSeries: parentId)
  }

  /// Materializes every missing occurrence of EVERY recurring series, each from its own start month
  /// through the horizon. The rolling top-up at dashboard load; also covers series that arrived from
  /// another device.
  func materializeAllSeries(completion: ((Int) -> Void)? = nil) {
    Self.operationQueue.async { [weak self] in
      guard let self = self else {
        completion?(0)
        return
      }

      let all = self.transactionRepo.fetchAllTransactions()
      let parents = all.filter {
        $0.isRecurring == true && ($0.parentTransactionId == nil || $0.parentTransactionId == $0.id)
      }

      // Union of every series' own span, so one pass covers all of them without any series being
      // clipped to a shared window.
      var anchors = Set<Int>()
      for parent in parents {
        anchors.formUnion(SeriesMonths.seriesAnchors(start: parent.seriesPeriod))
      }

      guard !anchors.isEmpty else {
        completion?(0)
        return
      }

      let created = self.materializeMissingOccurrences(anchors)
      completion?(created)
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
    // test below ("month <= this series' start month") is trivially true for it. Cleanup therefore
    // deleted the parent of every series it looked at, taking the whole series with it.
    //
    // It survived unnoticed only because the loop used to `return` on the first row with a nil id;
    // fixing that to `continue` made it reachable for every row. Same exclusion the duplicate
    // scanner already uses (`fetchRecurringOccurrenceSlots`).
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

    // RELINK FIRST. "This and future" / "all" select siblings by parent pointer, and that pointer is
    // a local autoincrement id — a row that arrived from another device, or that predates a repair,
    // can point at a row that does not exist here. Those rows were silently skipped and stayed stale
    // forever. Re-attaching them by content BEFORE the selection runs is what makes the plain
    // pointer filter below sufficient.
    let relinked = RecurringSeriesLinker(transactionRepo: transactionRepo)
      .repairTransactionSeries(around: parentTransactionId)
    if relinked > 0 {
      logWarning("[RecurringEdit] Relinked \(relinked) orphaned occurrence(s) before edit")
    }

    // DETERMINISTIC EDIT: "this and future" / "all" must affect the WHOLE series, not only the months
    // that happen to exist right now. Nothing materializes on navigation any more, so a device that
    // never scrolled forward has no future rows at all and the edit would touch only the current one.
    // Materialize the series in full first. Materialization skips intentionally-deleted months, so
    // this never resurrects a deleted occurrence. Runs inline on operationQueue (the async caller
    // already serialized us; materializeMissingOccurrences is documented safe to call inline here).
    if editOption != .currentSelection {
      let materialized = materializeSeriesInline(parentId: parentTransactionId)
      if materialized > 0 {
        logWarning("[RecurringEdit] Materialized \(materialized) missing occurrence(s) before edit (option=\(editOption))")
      }
    }

    // Fetch all transactions ONCE (now includes any just-relinked and just-materialized rows)
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Filter to related instances. A plain pointer filter is correct here ONLY because the relink
    // above has already re-attached every row that belongs to this series.
    let relatedInstances = allTransactions.filter {
      $0.parentTransactionId == parentTransactionId || $0.id == parentTransactionId
    }

    guard !relatedInstances.isEmpty else { return }

    // Build list of instances to update based on edit option
    // Store the original timestamp and budgetMonthDate to preserve them
    var instancesToUpdate: [(id: Int, originalTimestamp: Int, originalUnadjustedTimestamp: Int, originalRule: BusinessDayRule, originalBudgetMonthDate: Int, originalSeriesPeriod: Int, originalIsRecurring: Bool?, originalParentId: Int?, originalCreditCardId: Int?, originalStatementId: Int?)] = []

    for instance in relatedInstances {
      guard let instanceId = instance.id else { continue }

      // The row's own anchor, not one recomputed from its timestamp. Once a business-day rule can
      // push a date across a month boundary the two disagree, and recomputing would scope the edit to
      // the month the date landed in rather than the month the occurrence is for.
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
          originalUnadjustedTimestamp: instance.unadjustedDateTimestamp ?? instance.dateTimestamp,
          originalRule: instance.businessDayRule,
          originalBudgetMonthDate: instance.budgetMonthDate,
          originalSeriesPeriod: instance.seriesPeriod,
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
    // The rule the user just picked. Occurrences adopt it; keeping each row's existing rule would
    // make "edit this and future" silently a no-op for the rule.
    let newRule = newData.data.businessDayRule
    // The series' own anchor row, for the un-clamped anchor day.
    let parent = relatedInstances.first(where: { $0.id == parentTransactionId })

    // Track old statement IDs that need recalculation
    var oldStatementIdsToRecalculate: Set<Int> = []

    // Perform all updates
    for (instanceId, originalTimestamp, originalUnadjustedTimestamp, originalRule, originalBudgetMonthDate, originalSeriesPeriod, originalIsRecurring, originalParentId, originalCreditCardId, originalStatementId) in instancesToUpdate {
      // Recalculate when the day changed OR the rule did.
      //
      // The rule half matters on its own: switching a series to "previous business day" without
      // touching the day left every occurrence on its original date, because the old check only
      // looked at the day. It also has to be the NEW rule, not the one already on the row - the
      // whole point of the edit is to change it.
      let finalTimestamp: Int
      let finalUnadjustedTimestamp: Int
      let finalBudgetMonthDate: Int
      let dateChanged: Bool

      // Compare against the SERIES' anchor day, never this row's own day.
      //
      // A row's day is clamped to its month: a day-31 series is day 28 in February. Comparing the
      // picked day against the clamped one reported "changed" for February on every single edit.
      let seriesAnchorDay =
        parent.map { SeriesDay.anchorDay(of: $0) }
        ?? localCalendar.component(
          .day, from: Date(timeIntervalSince1970: TimeInterval(originalUnadjustedTimestamp)))
      let dayChanged = newDay != seriesAnchorDay
      // Legacy rows whose accounting month drifted away from their slot get repaired on any edit.
      let slotDrifted = originalBudgetMonthDate != originalSeriesPeriod

      if !dayChanged && newRule == originalRule && !slotDrifted {
        // Nothing that affects the date changed - preserve both timestamps exactly.
        finalTimestamp = originalTimestamp
        finalUnadjustedTimestamp = originalUnadjustedTimestamp
        finalBudgetMonthDate = originalBudgetMonthDate
        dateChanged = false
      } else {
        // Rebuild from the SLOT, through the same helper generation uses.
        //
        // This used to build `DateComponents` from the ROW's own date with the new day, which is
        // wrong twice over. Day 31 in February does not fail — Foundation rolls it forward to 3
        // March — so `finalBudgetMonthDate` became March: the February occurrence vanished from
        // February and landed on top of March's, which is where the "missing month plus a duplicate
        // in a later month" came from. And deriving the month from a date a business-day rule had
        // already shifted put the occurrence in the neighbouring month for the same reason.
        //
        // `OccurrenceDateCalculator.occurrence` clamps properly (min(day, lastDayOfMonth)), and the
        // slot is authoritative about which month this occurrence is FOR.
        let slotDate = Date.fromMonthAnchor(originalSeriesPeriod)
        let targetYear = localCalendar.component(.year, from: slotDate)
        let targetMonth = localCalendar.component(.month, from: slotDate)

        let unadjusted = OccurrenceDateCalculator.occurrence(
          anchorDay: newDay, targetMonth: targetMonth, targetYear: targetYear,
          calendar: localCalendar)
        let adjusted = BusinessDayAdjuster.adjust(
          unadjusted, rule: newRule, calendar: localCalendar)

        finalTimestamp = Int(adjusted.timeIntervalSince1970)
        finalUnadjustedTimestamp = Int(unadjusted.timeIntervalSince1970)
        // Pinned to the slot, exactly as generation does (`budgetMonthDate: targetAnchor`). An
        // occurrence can no longer leave the month it is scheduled for, whatever the rule did to
        // its date.
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
        isCreditCardStatement: finalCreditCardId != nil ? false : nil,
        businessDayRule: newRule,
        unadjustedDateTimestamp: finalUnadjustedTimestamp,
        seriesPeriod: originalSeriesPeriod
      )

      // Carries the business-day columns in the same statement - a second write here would stamp a
      // later `updated_at` than the snapshot the sync engine pushes, and the row would never clear
      // `pending`.
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
        // Card changed or date changed: reassign to correct statement. Routed on the unadjusted date,
        // matching both generation paths - the billing cycle follows the purchase date.
        let newDate = Date(timeIntervalSince1970: TimeInterval(finalUnadjustedTimestamp))
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

  /// Find existing recurring transactions with the same characteristics.
  ///
  /// `anchorDay` is part of the predicate because generation's duplicate guard keys on the day too.
  /// Without it the two disagreed: creation would link a new series into an existing one anchored on
  /// a different day, and generation would then refuse to fill it — leaving a stray row and no
  /// occurrences.
  func findSimilarRecurringTransaction(
    title: String,
    category: String,
    amount: Int,
    type: String,
    anchorDay: Int
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
        && SeriesDay.anchorDay(of: transaction) == anchorDay

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

  /// Materializes missing occurrences for the given month anchors, on the serial queue.
  ///
  /// Prefer `materializeSeries(parentId:)` or `materializeAllSeries()` — they compute the anchors from
  /// each series' own span. This overload exists for callers that already know exactly which months
  /// they need (the "delete future" backfill).
  /// - Parameters:
  ///   - monthAnchors: Set of month anchors to materialize
  ///   - completion: Called on the materialization queue when the pass is complete
  func materializeOccurrences(
    for monthAnchors: Set<Int>,
    completion: ((_ newInstancesCreated: Int) -> Void)? = nil
  ) {
    guard !monthAnchors.isEmpty else {
      // Same queue as the success path. This used to answer on main while success answered on
      // `operationQueue`, so a caller's completion ran on a different thread depending on whether
      // there was work to do.
      Self.operationQueue.async { completion?(0) }
      return
    }

    Self.operationQueue.async { [weak self] in
      guard let self = self else {
        completion?(0)
        return
      }
      let created = self.materializeMissingOccurrences(monthAnchors)
      completion?(created)
    }
  }

  /// Synchronous core of materialization. Creates any missing recurring occurrence for the given
  /// month anchors and returns how many rows were created.
  ///
  /// Safe to call inline while already serialized on `operationQueue` — used by the async wrappers
  /// above, by the edit path (which materializes the whole series before applying a scope), and by
  /// the "delete future" backfill, which must materialize pre-cutoff months before the parent's
  /// recurrence is disabled.
  ///
  /// - Parameter limitedToSeries: when set, only that parent's series is considered. Creation uses
  ///   this so a brand-new series is filled without walking every other series in the ledger.
  @discardableResult
  private func materializeMissingOccurrences(
    _ monthAnchors: Set<Int>, limitedToSeries seriesId: Int? = nil
  ) -> Int {
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
          instancesByParentId[parentId]?.insert(tx.seriesPeriod)
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
      // Sorted by SLOT, because that is what the template lookup searches on
      // (`last(where: { $0.seriesPeriod <= targetAnchor })`). Sorting by `budgetMonthDate` while
      // searching by `seriesPeriod` is only equivalent while the business-day rule is `.exact`; under
      // `.previous`/`.next` an occurrence pushed across a month boundary makes the two disagree, the
      // array is then unsorted with respect to the search key, and `last(where:)` silently picks the
      // wrong template — so a month materialized after an "edit this and future" inherited the
      // pre-edit amount.
      for (seriesId, occurrences) in occurrencesBySeriesId {
        occurrencesBySeriesId[seriesId] = occurrences.sorted {
          $0.seriesPeriod < $1.seriesPeriod
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

      // Filter recurring parents only — installments are now generated upfront at creation time
      var recurringParents = allTransactions.filter {
        $0.isRecurring == true && ($0.parentTransactionId == nil || $0.parentTransactionId == $0.id)
      }
      if let seriesId = seriesId {
        recurringParents = recurringParents.filter { $0.id == seriesId }
      }

      // Cross-device duplicate protection: which SLOTS are already occupied, per series identity.
      //
      // This used to be keyed on `title | slot | day` over EVERY row in the ledger, so a one-off
      // transaction — or a row in a different category, type or ledger that merely shared a title and
      // a day — silently blocked that month for a genuine series. That is the "some months are
      // skipped" bug. The key is now the full series fingerprint (scope, title, category, type, day)
      // and only rows that are part of a recurring series contribute to it.
      //
      // The day used is the SERIES' canonical day: for a child, the day its parent is anchored on,
      // not the child's own (which `OccurrenceDateCalculator` may have clamped in a short month).
      let scopeById = self.transactionRepo.fetchSharedGroupIds()
      let parentsById = Dictionary(
        uniqueKeysWithValues: allTransactions.compactMap { tx -> (Int, Transaction)? in
          guard let id = tx.id else { return nil }
          return (id, tx)
        })

      func fingerprint(of tx: Transaction) -> SeriesFingerprint? {
        guard let id = tx.id else { return nil }
        // Anchor day follows the series parent when it is known locally.
        let anchorSource = tx.parentTransactionId.flatMap { parentsById[$0] } ?? tx
        return SeriesFingerprint(
          scope: scopeById[id],
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

      // Early exit if no recurring parents to process
      guard !recurringParents.isEmpty else {
        return 0
      }

      var newInstancesCreated = 0
      var touchedSeriesIds = Set<Int>()

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

        // Only generate for slots this series doesn't hold yet and didn't intentionally delete.
        //
        // Compared against the parent's SLOT (`seriesPeriod`), not its accounting month. Once a
        // business-day rule can push a date across a month boundary the two disagree, and comparing
        // the wrong one either skipped a legitimate month or re-created one the parent already owns.
        let parentSlot = recurringTx.seriesPeriod
        let missingAnchors = monthAnchors.subtracting(existingAnchors)
          .subtracting(excludedAnchors)
          .filter { $0 > parentSlot }  // Forward-only; the parent occupies its own slot

        // Tombstones are the one thing that silently removes months from a series. Say so — a
        // silent skip here is indistinguishable from a generation bug, which is exactly how the
        // allocation side hid a permanent two-month hole for so long.
        let suppressed = monthAnchors.intersection(excludedAnchors).filter { $0 > parentSlot }
        if !suppressed.isEmpty {
          logWarning(
            "[Materialize] series \(recurringTxId) ('\(recurringTx.title)'): \(suppressed.count) month(s) suppressed by an earlier delete — not recreating \(suppressed.sorted())"
          )
        }

        guard !missingAnchors.isEmpty else { continue }

        // Occurrences of this series, ascending by month (for picking the in-effect template).
        let seriesOccurrences = occurrencesBySeriesId[recurringTxId] ?? [recurringTx]
        let seriesKey = fingerprint(of: recurringTx)

        for targetAnchor in missingAnchors.sorted() {
          // Inherit from the most recent occurrence at or before this month, so a prior
          // "edit this and future" change carries forward. Falls back to the parent.
          let template = seriesOccurrences.last(where: { $0.seriesPeriod <= targetAnchor })
            ?? recurringTx

          // Cross-device duplicate protection: a row matching this series' full fingerprint already
          // holds the slot, but is not linked to this parent — which means its parent pointer is
          // broken (a foreign device's autoincrement id). Creating a second row here would duplicate
          // the month; the repair belongs to RecurringSeriesLinker, which runs ahead of every CRUD.
          if let seriesKey = seriesKey, occupiedSlots[seriesKey]?.contains(targetAnchor) == true {
            logWarning(
              "[Materialize] slot \(targetAnchor) for series \(recurringTxId) ('\(recurringTx.title)') is held by an unlinked row — skipping; relink should have adopted it"
            )
            continue
          }

          // Which month this slot IS, read in the same timezone the anchor was written in.
          //
          // `targetAnchor` is local midnight on the 1st (`Date.monthAnchor` is `TimeZone.current`).
          // Reading it back through this type's UTC calendar lands in the PREVIOUS month for any zone
          // ahead of UTC, so the occurrence was generated for the wrong month while
          // `budgetMonthDate` still said the right one. The date is still CONSTRUCTED with
          // `self.calendar` below, so existing rows' timestamps keep their convention.
          let targetDate = Date(timeIntervalSince1970: TimeInterval(targetAnchor))
          var anchorCalendar = Calendar(identifier: .gregorian)
          anchorCalendar.timeZone = TimeZone.current
          let targetYear = anchorCalendar.component(.year, from: targetDate)
          let targetMonth = anchorCalendar.component(.month, from: targetDate)

          // The template's rule, so a series materialised lazily months later comes out identical to
          // one the eager path produced at creation time.
          let occurrence = OccurrenceDateCalculator.occurrencePair(
            from: template.unadjustedDate,
            targetMonth: targetMonth,
            targetYear: targetYear,
            rule: template.businessDayRule,
            calendar: self.calendar
          )

          let instanceModel = TransactionModel(
            title: template.title,
            category: template.category.key,
            amount: template.amount,
            type: template.type.key,
            dateTimestamp: Int(occurrence.adjusted.timeIntervalSince1970),
            budgetMonthDate: targetAnchor,
            parentTransactionId: recurringTxId,
            creditCardId: template.creditCardId,
            businessDayRule: template.businessDayRule,
            unadjustedDateTimestamp: Int(occurrence.unadjusted.timeIntervalSince1970),
            seriesPeriod: targetAnchor
          )

          do {
            let insertedId = try self.transactionRepo.insertTransactionAndGetId(instanceModel)
            newInstancesCreated += 1
            if let seriesKey = seriesKey {
              occupiedSlots[seriesKey, default: []].insert(targetAnchor)
            }
            touchedSeriesIds.insert(recurringTxId)

            // Derived identity for (series, month) — see the note at the other generation site.
            if let parentUuid = self.db.uuidIdentity(table: "Transactions", localId: recurringTxId)?
              .uuid
            {
              self.db.assignDeterministicUuid(
                table: "Transactions", localId: insertedId,
                uuid: DeterministicIdentity.recurringInstance(
                  parentUuid: parentUuid, monthDate: targetAnchor))
            }

            // An occurrence belongs to whatever ledger its SERIES belongs to — read from the parent,
            // not the template, which may be an edited child.
            if let groupId = scopeById[recurringTxId] {
              self.transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
            }

            // Assign to correct monthly statement if linked to a credit card
            if let cardId = template.creditCardId,
               let uid = AuthenticationManager.shared.currentUser?.uid {
              self.assignToStatement(transactionId: insertedId, creditCardId: cardId, transactionDate: occurrence.unadjusted, userId: uid)
            }
          } catch {
            logError("Error creating recurring instance: \(error)")
          }
        }
      }
      } // end inTransaction

      // NOTIFICATIONS: reconcile every series this pass touched.
      //
      // Outside the DB transaction — notification scheduling is async work that must not hold the
      // write lock. This is not optional bookkeeping: occurrences created here previously got NO
      // notification at all, because only the (now-deleted) eager generator scheduled them, so every
      // month materialized after creation was silently reminder-less.
      for parentId in touchedSeriesIds {
        RecurringNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
      }

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
    let startAnchor = parent.seriesPeriod
    guard startAnchor < cutoffAnchor else { return }

    // Months strictly between the parent's own slot and the cutoff.
    let anchors = Set(
      SeriesMonths.anchors(from: startAnchor, through: cutoffAnchor)
        .filter { $0 > startAnchor && $0 < cutoffAnchor })

    guard !anchors.isEmpty else { return }
    _ = materializeMissingOccurrences(anchors, limitedToSeries: parentTransactionId)
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

  // Occurrence dates come from `OccurrenceDateCalculator`. This file used to carry its own copy of
  // that arithmetic, byte-identical to a second copy in `AddTransactionModalViewModel`.

}
