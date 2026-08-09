//
//  DashboardViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit
import UserNotifications

final class DashboardViewModel {
  let budgetRepo: BudgetRepository
  let transactionRepo: TransactionRepository
  private let recurringManager: RecurringTransactionManager
  private let monthlyNotificationManager: MonthlyNotificationManager
  let transactionLedger: TransactionLedgerService
  private let creditCardService = CreditCardService()
  private let calendar = Calendar.current

  private let monthRange: ClosedRange<Int>
  private let notificationCenter = UNUserNotificationCenter.current()

  /// Current viewing context — restored from last session or defaults to personal
  var currentContext: DataContext

  var onCleanupChoiceNeeded: ((RecurringCleanupOption) -> Void)?

  /// Callback to notify UI that data has changed and needs refresh
  var onDataNeedsRefresh: (() -> Void)?

  /// Guards against overlapping rolling top-ups. Read on main (from `loadMonthlyCards`) and written
  /// from the materialization queue, so it needs the lock — an unsynchronized `Bool` here let two
  /// full-table passes overlap.
  private var isMaterializationInProgress = false
  private let materializationLock = NSLock()

  /// Constructed here rather than injected because `BudgetAllocationService` is deliberately not a
  /// singleton (see the note on its `spendHistories`).
  private lazy var allocationService = BudgetAllocationService()

  init(
    budgetRepo: BudgetRepository = BudgetRepository(),
    transactionRepo: TransactionRepository = TransactionRepository(),
    monthRange: ClosedRange<Int> = SeriesMonths.carouselRange
  ) {
    self.budgetRepo = budgetRepo
    self.transactionRepo = transactionRepo
    self.monthRange = monthRange
    self.recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    self.monthlyNotificationManager = MonthlyNotificationManager(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
    self.transactionLedger = TransactionLedgerService(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
    self.currentContext = UIDUserDefaultsManager.shared.getLastContext()
  }

  func getStatementTransactions() -> [Transaction] {
    switch currentContext {
    case .personal:
      guard let uid = AuthenticationManager.shared.currentUser?.uid else { return [] }
      return creditCardService.generateStatementTransactions(userId: uid)
    case .group(let group):
      let sharedCards = CreditCardRepository().fetchCardsForGroup(groupId: group.id)
      return sharedCards.flatMap {
        creditCardService.generateStatementTransactions(forCard: $0, in: LedgerScope(currentContext))
      }
    }
  }

  func loadMonthlyCards() -> [MonthBudgetCardType] {
    switch currentContext {
    case .personal:
      // Repair passes no longer run here. Rewriting financial rows on every dashboard load marked
      // them pending, so two devices pushed their own repair results over each other's. They now
      // live behind an explicit action in Sync Settings (DataRepairService).

      // Use the transaction ledger service for all calculations
      let monthlyData = transactionLedger.calculateMonthlyData(for: monthRange)

      // Trigger lazy generation AFTER returning data (non-blocking)
      materializeAllSeriesInBackground()

      return monthlyData

    case .group(let group):
      // OWNERSHIP INVARIANT: do NOT run destructive credit-card repairs in group context.
      // These operate on fetchAllTransactions()/fetchAllCards(), which include the group
      // OWNER's shared records that a member's DB holds. Consolidating/reassigning/deleting
      // them marks the owner's records pending/pendingDelete and pushes those edits/deletes
      // into the shared zone — corrupting or deleting the owner's data for every member.
      // Group records are repaired only by their author, in that author's own personal context.
      logWarning("[CCRepair] Skipping ALL destructive CC repairs in group context (protects other members' data)")

      // Lazy-generate recurring instances for group context too,
      // so future months show the same instances as personal view.
      materializeAllSeriesInBackground()

      return transactionLedger.calculateMonthlyDataForGroup(
        groupId: group.id, for: monthRange
      )
    }
  }

  func switchContext(to context: DataContext) {
    currentContext = context
    UIDUserDefaultsManager.shared.saveLastContext(context)
    transactionLedger.invalidateCache()
    onDataNeedsRefresh?()

    // When switching to a group context, directly fetch that group's zone so the latest data is
    // loaded on demand (bypasses CKShare/replication propagation gaps). Members read the owner's
    // SHARED zone; the owner (and their other same-account devices) read the OWN group zone in the
    // PRIVATE DB — without this, a second device that missed the incremental force-include shows
    // the owner's group empty.
    if case .group(let group) = context {
      let onFetched: (Int) -> Void = { [weak self] count in
        if count > 0 {
          self?.transactionLedger.invalidateCache()
          self?.onDataNeedsRefresh?()
        }
      }
      if !group.isOwner, let zoneOwner = group.ckZoneOwner {
        SyncEngine.shared.fetchSharedGroupZone(groupId: group.id, zoneOwner: zoneOwner, completion: onFetched)
      } else if group.isOwner {
        SyncEngine.shared.fetchOwnedGroupZone(groupId: group.id, completion: onFetched)
      }
    }
  }

  func getAvailableGroups() -> [BudgetGroup] {
    return BudgetGroupService.shared.fetchAllGroups()
  }

  /// The rolling top-up: materializes every recurring series — transactions AND allocations — that is
  /// missing occurrences, in the background, after `loadMonthlyCards` has returned.
  ///
  /// This is the ONLY generation trigger that is not attached to a specific CRUD action. Nothing
  /// generates on render, navigation or scroll (see `SeriesMonths`), so this pass is what covers
  /// series that arrived from another device, or that predate a horizon change. Both passes are
  /// series-anchored and idempotent, so re-running is free when there is nothing to do.
  private func materializeAllSeriesInBackground() {
    // HYDRATION GATE: never materialize recurring instances before this device has completed a
    // verified full pull. Otherwise a freshly-logged-in device regenerates "deleted" future
    // instances from a cloud parent that still reads isRecurring=true (a fresh device has no
    // tombstones to suppress it), making a deleted series reappear. Once the authoritative
    // parent state is pulled, generation resumes on the next dashboard refresh.
    guard UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2") else {
      logWarning("[Materialize] Skipping — full pull not yet verified on this device")
      return
    }

    materializationLock.lock()
    guard !isMaterializationInProgress else {
      materializationLock.unlock()
      return
    }
    isMaterializationInProgress = true
    materializationLock.unlock()

    // Run everything on background queue to avoid blocking main thread
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self = self else { return }

      // INVARIANT SWEEP, before generating: one live occurrence per (series, slot), each in the
      // month it is scheduled for. Detects read-only and writes only when something is actually
      // broken, so a healthy ledger costs one query and marks nothing pending — which is what keeps
      // this safe to run on every load (see the note in `loadMonthlyCards`). Runs first so
      // generation does not fill a "gap" that is really a row sitting in the wrong month.
      let removed = RecurringDuplicateCleanup.sweepIfDirty(repository: self.transactionRepo)
      if removed > 0 { self.transactionLedger.invalidateCache() }

      // Both passes walk every recurring PARENT and fill that parent's own start month through the
      // horizon. Deliberately not a window of months: a series older than the window would keep
      // permanent holes, which is how "some months are skipped" survived the previous fix.
      self.recurringManager.materializeAllSeries { [weak self] newTransactions in
        guard let self = self else { return }

        self.allocationService.materializeAllSeries { [weak self] newAllocations in
          guard let self = self else { return }

          self.materializationLock.lock()
          self.isMaterializationInProgress = false
          self.materializationLock.unlock()

          guard newTransactions > 0 || newAllocations > 0 else { return }

          logWarning(
            "[Materialize] rolling top-up created \(newTransactions) transaction occurrence(s) and \(newAllocations) allocation occurrence(s)"
          )
          self.transactionLedger.invalidateCache()

          DispatchQueue.main.async {
            self.onDataNeedsRefresh?()
          }
        }
      }
    }
  }

  /// Clean up any existing duplicate transactions
  func cleanupExistingDuplicates() {
    transactionLedger.cleanupDuplicateTransactions()
  }

  /// Force refresh current month balance (useful for debugging)
  func forceRefreshCurrentMonthBalance() {
    transactionLedger.forceRefreshCurrentMonthBalance()
  }

  /// Force refresh all balance calculations (useful after fixing date comparison issues)
  func forceRefreshAllBalances() {
    transactionLedger.forceRefreshAllBalances()
  }

  /// Migrate budgets to new timezone-based month anchors
  func migrateBudgetsToNewTimezone() {
    transactionLedger.migrateBudgetsToNewTimezone()
  }

  /// Migrate all data (budgets and transactions) to new timezone-based month anchors
  func migrateAllDataToNewTimezone() {
    transactionLedger.migrateAllDataToNewTimezone()
  }

  /// Get a summary of duplicate transactions (without removing them)
  func analyzeDuplicateTransactions() -> String {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let transactionsByMonth = Dictionary(grouping: allTransactions) { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate.monthAnchor
    }

    var summary = "Duplicate Transaction Analysis:\n"
    var totalDuplicates = 0

    for (monthAnchor, transactions) in transactionsByMonth {
      if transactions.count > 1 {
        let date = Date(timeIntervalSince1970: TimeInterval(monthAnchor))
        let monthName = DateFormatter.monthFormatter.string(from: date)
        let year = Calendar.current.component(.year, from: date)

        summary += "\n\(monthName) \(year): \(transactions.count) transactions\n"

        // Group by title to identify potential duplicates
        let groupedByTitle = Dictionary(grouping: transactions) { $0.title }
        for (title, titleGroup) in groupedByTitle {
          if titleGroup.count > 1 {
            summary += "   - \(title): \(titleGroup.count) instances\n"
            totalDuplicates += titleGroup.count - 1
          }
        }
      }
    }

    summary += "\nTotal potential duplicates: \(totalDuplicates)"
    return summary
  }

  private func calculateCurrentBalance(
    anchor: Int, allTransactions: [Transaction], previousBalance: Int
  ) -> Int {
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(anchor))

    // Use user's current timezone for consistency with monthAnchor calculations
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    let transactionsUpToToday = allTransactions.filter { tx in
      let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))

      let isSameMonth = calendar.isDate(txDate, equalTo: monthDate, toGranularity: .month)
      let isBeforeOrToday = txDate <= today

      return isSameMonth && isBeforeOrToday
    }

    let netUpToToday = transactionsUpToToday.reduce(0) { result, tx in
      tx.type == .income ? result + tx.amount : result - tx.amount
    }

    return previousBalance + netUpToToday
  }

  func cleanupRecurringTransactionsWithUserPrompt(
    onCleanupNeeded: @escaping (@escaping (RecurringCleanupOption) -> Void) -> Void
  ) {
    onCleanupNeeded { [weak self] cleanupOption in
      self?.updateRecurringTransactionsWithCleanupChoice(cleanupOption: cleanupOption)
    }
  }

  private func updateRecurringTransactions() {
    materializeAllSeriesInBackground()
  }

  func updateRecurringTransactionsWithCleanupChoice(
    cleanupOption: RecurringCleanupOption = .futureOnly
  ) {
    // RETENTION, not carousel. This used to pass `monthRange` (-12...24) to a routine that deletes
    // every occurrence outside the range it is given, while generation writes through +36 — so
    // cleanup destroyed the twelve months creation had just generated and pushed those deletes to
    // CloudKit. The window an occurrence may occupy is `retentionRange`; the carousel is only what
    // we happen to render.
    recurringManager.cleanupRecurringInstancesOutsideRange(
      SeriesMonths.retentionRange, referenceDate: Date(), cleanupOption: cleanupOption)
  }

  func deleteTransaction(id: Int) -> Result<Void, Error> {
    do {
      let allTransactions = transactionRepo.fetchAllTransactions()
      guard let transaction = allTransactions.first(where: { $0.id == id }) else {
        return .failure(TransactionError.transactionNotFound)
      }

      // Capture group ID before deletion (needed for activity log)
      let groupId = transactionRepo.fetchSharedGroupId(for: id)

      // Handle simple transactions directly
      if transaction.isRecurring != true && transaction.parentTransactionId == nil
        && transaction.hasInstallments != true
      {
        try transactionRepo.delete(id: id)

        // Remove associated notification if transaction has an ID
        if let transactionId = transaction.id {
          let notificationId = "transaction_\(transactionId)"
          notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        }

        // Recalculate statement total if this was a CC transaction
        if let stmtId = transaction.statementId {
          creditCardService.recalculateStatementTotal(statementId: stmtId)
        }

        // Invalidate ledger cache since transactions changed
        transactionLedger.invalidateCache()

        // Force re-evaluate the negative balance alert now that data has changed.
        // forceTriggerBalanceMonitoring bypasses the 5-min throttle so the
        // notification is updated immediately rather than waiting for the next foreground event.
        BalanceMonitorManager.shared.forceTriggerBalanceMonitoring()

        // Log group activity if transaction belonged to a group
        if let groupId = groupId {
          GroupNotificationService.shared.logActivity(
            action: .transactionDeleted, groupId: groupId, detail: transaction.title)
          SyncEngine.shared.pushPendingChangesNow()
        }

        return .success(())
      }

      // For complex transactions, we need user input - return a special error
      // The UI should catch this and show the user prompt
      return .failure(TransactionError.notARecurringTransaction)

    } catch {
      return .failure(error)
    }
  }

  func deleteComplexTransaction(
    transactionId: Int,
    cleanupOption: RecurringCleanupOption,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    // Perform deletion on background queue to avoid blocking UI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async {
          completion(.failure(TransactionError.transactionNotFound))
        }
        return
      }

      do {
        let allTransactions = self.transactionRepo.fetchAllTransactions()
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
          DispatchQueue.main.async {
            completion(.failure(TransactionError.transactionNotFound))
          }
          return
        }

        // Capture group ID before deletion (needed for activity log)
        let groupId = self.transactionRepo.fetchSharedGroupId(for: transactionId)

        // Use mode property to correctly identify transaction type
        // This is more reliable than looking up parent transactions
        switch transaction.mode {
        case .recurring, .installments:
          // Route BOTH recurring and installment deletions through the single canonical
          // delete engine (RecurringTransactionManager.deleteWithOption →
          // TransactionRepository.deleteTransactionWithOption), the same path the
          // Transaction/Statement/Allocation Details screens use. This removes the old
          // divergence where the Dashboard used month/exact-date-keyed cleanup that
          // deleted different rows than the detail screens for the identical action.
          self.recurringManager.deleteWithOption(
            transactionId: transactionId,
            option: cleanupOption
          ) { result in
            if case .failure(let error) = result {
              completion(.failure(error))
              return
            }
            // Recalculate statement total if applicable
            if let stmtId = transaction.statementId {
              self.creditCardService.recalculateStatementTotal(statementId: stmtId)
            }
            // Invalidate ledger cache since transactions changed
            self.transactionLedger.invalidateCache()
            BalanceMonitorManager.shared.forceTriggerBalanceMonitoring()
            if let groupId = groupId {
              GroupNotificationService.shared.logActivity(
                action: .transactionDeleted, groupId: groupId, detail: transaction.title)
              SyncEngine.shared.pushPendingChangesNow()
            }
            completion(.success(()))
          }
          return

        case .normal:
          // Handle simple transaction - should not reach here from complex deletion
          // but handle gracefully just in case
          try self.transactionRepo.delete(id: transactionId)
          // Recalculate statement total if applicable
          if let stmtId = transaction.statementId {
            self.creditCardService.recalculateStatementTotal(statementId: stmtId)
          }
          self.transactionLedger.invalidateCache()
          BalanceMonitorManager.shared.forceTriggerBalanceMonitoring()
          if let groupId = groupId {
            GroupNotificationService.shared.logActivity(
              action: .transactionDeleted, groupId: groupId, detail: transaction.title)
            SyncEngine.shared.pushPendingChangesNow()
          }
          DispatchQueue.main.async {
            completion(.success(()))
          }
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Notification Debugging
  //
  // Note: Notification scheduling is now handled at:
  // - App launch (AppDelegate.scheduleNotificationsOnLaunch)
  // - Transaction addition (AddTransactionModalViewModel.scheduleNotificationForNewTransaction)
  // - Transaction deletion (automatic cleanup in delete methods)
  //
  // We no longer schedule notifications on every dashboard load to prevent
  // clearing notifications that should have already fired.

  func isRecurringTransaction(id: Int) -> Bool {
    guard let transaction = transactionRepo.fetchAllTransactions().first(where: { $0.id == id })
    else {
      return false
    }

    // Use the mode property to correctly identify recurring transactions
    // This handles both parent recurring transactions AND their instances
    return transaction.mode == .recurring
  }

  func getTransactionType(id: Int) -> TransactionComplexityType {
    guard let transaction = transactionRepo.fetchAllTransactions().first(where: { $0.id == id })
    else {
      return .simple
    }

    // Check if this is a recurring transaction instance
    if let parentId = transaction.parentTransactionId {
      // Special case: if parentTransactionId points to itself, treat it as a parent transaction
      if parentId == id {
        // Continue to parent transaction checks below
      } else {
        let parentTransaction = transactionRepo.fetchAllTransactions().first(where: {
          $0.id == parentId
        }
        )
        if parentTransaction?.isRecurring == true {
          return .recurringInstance
        } else {
          return .installmentInstance
        }
      }
    }

    // Check if this is a parent recurring transaction
    if transaction.isRecurring == true {
      return .recurringParent
    }

    // Special case: if mode is recurring but isRecurring is false (data corruption), treat as recurring parent
    if transaction.mode == .recurring && transaction.isRecurring != true {
      return .recurringParent
    }

    // Check if this is a parent installment transaction (only if not recurring)
    if transaction.hasInstallments == true && transaction.isRecurring != true {
      return .installmentParent
    }

    return .simple
  }

  // MARK: - Debug Functions

  func debugPendingNotifications() {
    // This method is for debugging purposes only
    // Use the notification center's getPendingNotificationRequests directly if needed
  }

  // MARK: - Balance Monitor Functions

  /// Força o monitoramento de saldo negativo
  func forceBalanceMonitoring() {
    BalanceMonitorManager.shared.monitorCurrentMonthBalance()
  }

  /// Remove todas as notificações de saldo negativo
  func removeNegativeBalanceNotifications() {
    BalanceMonitorManager.shared.removeNegativeBalanceNotifications()
  }

  /// Verifica se há notificações de saldo negativo agendadas
  func hasNegativeBalanceNotifications() -> Bool {
    return BalanceMonitorManager.shared.hasNegativeBalanceNotifications()
  }

  // MARK: - Monthly Notification Functions

  /// Agenda todas as notificações do mês atual
  func scheduleAllMonthlyNotifications(showAlert: Bool = true) -> Bool {
    return monthlyNotificationManager.scheduleAllMonthlyNotifications(showAlert: showAlert)
  }

  /// Verifica o status das notificações mensais
  func checkMonthlyNotificationsStatus() -> MonthlyNotificationStatus {
    return monthlyNotificationManager.checkMonthlyNotificationsStatus()
  }

  /// Configura o sistema de notificações mensais
  func setupMonthlyNotificationSystem() {
    monthlyNotificationManager.setupMonthlyNotificationSystem()
  }

}
