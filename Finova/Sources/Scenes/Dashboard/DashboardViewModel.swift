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

  var onCleanupChoiceNeeded: ((RecurringCleanupOption) -> Void)?

  /// Callback to notify UI that data has changed and needs refresh
  var onDataNeedsRefresh: (() -> Void)?

  /// Track if lazy generation is in progress to avoid duplicate runs
  private var isLazyGenerationInProgress = false

  init(
    budgetRepo: BudgetRepository = BudgetRepository(),
    transactionRepo: TransactionRepository = TransactionRepository(),
    monthRange: ClosedRange<Int> = -12...24
  ) {  // 3 years
    self.budgetRepo = budgetRepo
    self.transactionRepo = transactionRepo
    self.monthRange = monthRange
    self.recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    self.monthlyNotificationManager = MonthlyNotificationManager(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
    self.transactionLedger = TransactionLedgerService(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
  }

  func getStatementTransactions() -> [Transaction] {
    guard let uid = AuthenticationManager.shared.currentUser?.uid else { return [] }
    return creditCardService.generateStatementTransactions(userId: uid)
  }

  func loadMonthlyCards() -> [MonthBudgetCardType] {
    // Repair credit card transactions: fix orphans and reassign misplaced ones
    if let uid = AuthenticationManager.shared.currentUser?.uid {
      creditCardService.repairOrphanedCreditCardTransactions(userId: uid, transactionRepo: transactionRepo)
      creditCardService.reassignMisplacedTransactions(userId: uid, transactionRepo: transactionRepo)
    }

    // Clear duplicates left behind by the old per-instance generation guards, before anything
    // reads or extends a series. Runs once per install; a no-op on a clean database.
    RecurringDuplicateCleanup.runOnceIfNeeded()

    // Use the transaction ledger service for all calculations
    let monthlyData = transactionLedger.calculateMonthlyData(for: monthRange)

    // Trigger lazy generation AFTER returning data (non-blocking)
    triggerLazyGenerationInBackground()

    return monthlyData
  }

  /// Triggers lazy generation in background without blocking UI
  /// This is called after loadMonthlyCards returns to avoid blocking
  private func triggerLazyGenerationInBackground() {
    guard !isLazyGenerationInProgress else {
      return
    }

    isLazyGenerationInProgress = true

    // Run everything on background queue to avoid blocking main thread
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self = self else { return }

      // SERIES-anchored, not window-anchored. This used to enumerate the carousel's own range of
      // offsets around today, which clips any series whose start falls outside that window — so a
      // series older than the window kept permanent holes no amount of re-running could fill. The
      // union of every series' own span covers all of them without clipping any.
      let allTransactions = self.transactionRepo.fetchAllTransactions()
      let parents = allTransactions.filter {
        $0.isRecurring == true && ($0.parentTransactionId == nil || $0.parentTransactionId == $0.id)
      }
      var monthAnchors = Set<Int>()
      for parent in parents {
        monthAnchors.formUnion(SeriesMonths.seriesAnchors(start: parent.seriesPeriod))
      }

      // Allocations get the same treatment, and for the same reason: nothing materializes on render
      // any more, so this pass is what fills months the user has not visited.
      let newAllocations = BudgetAllocationService().materializeAllSeries()
      if newAllocations > 0 {
        logWarning("[Materialize] rolling top-up created \(newAllocations) allocation occurrence(s)")
      }

      // Generate instances (the manager will handle checking what's needed)
      self.recurringManager.generateInstancesLazilyForMonths(monthAnchors) { [weak self] newInstancesCreated in
        guard let self = self else { return }

        self.isLazyGenerationInProgress = false

        // Only refresh UI if new instances were actually created
        guard newInstancesCreated > 0 || newAllocations > 0 else { return }

        self.transactionLedger.invalidateCache()

        DispatchQueue.main.async {
          self.onDataNeedsRefresh?()
        }
      }
    }
  }

  /// Triggers lazy generation for a specific set of months (e.g., when user scrolls to new months)
  func triggerLazyGenerationForMonths(_ monthAnchors: Set<Int>, completion: (() -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.recurringManager.generateInstancesLazilyForMonths(monthAnchors) { [weak self] _ in
        self?.transactionLedger.invalidateCache()
        DispatchQueue.main.async {
          completion?()
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
    // LAZY GENERATION: Use lazy generation instead of eager generation
    triggerLazyGenerationInBackground()
  }

  func updateRecurringTransactionsWithCleanupChoice(
    cleanupOption: RecurringCleanupOption = .futureOnly
  ) {
    // LAZY GENERATION: Use lazy generation instead of eager generation
    // Cleanup is still needed when user explicitly requests deletion
    recurringManager.cleanupRecurringInstancesOutsideRange(
      monthRange, referenceDate: Date(), cleanupOption: cleanupOption)
  }

  func deleteTransaction(id: Int) -> Result<Void, Error> {
    do {
      let allTransactions = transactionRepo.fetchAllTransactions()
      guard let transaction = allTransactions.first(where: { $0.id == id }) else {
        return .failure(TransactionError.transactionNotFound)
      }

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

        // Use mode property to correctly identify transaction type
        // This is more reliable than looking up parent transactions
        switch transaction.mode {
        case .recurring:
          // Handle recurring transactions (both parent and instances)
          let parentId = transaction.parentTransactionId ?? transactionId
          self.recurringManager.cleanupRecurringInstancesFromDate(
            parentTransactionId: parentId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          ) {
            // Recalculate statement total if applicable
            if let stmtId = transaction.statementId {
              self.creditCardService.recalculateStatementTotal(statementId: stmtId)
            }
            // Invalidate ledger cache since transactions changed
            self.transactionLedger.invalidateCache()
            completion(.success(()))
          }
          return

        case .installments:
          // Handle installment transactions (both parent and instances)
          let parentId = transaction.parentTransactionId ?? transactionId
          self.recurringManager.cleanupInstallmentTransactionsFromDate(
            parentTransactionId: parentId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          ) {
            // Recalculate statement total if applicable
            if let stmtId = transaction.statementId {
              self.creditCardService.recalculateStatementTotal(statementId: stmtId)
            }
            // Invalidate ledger cache since transactions changed
            self.transactionLedger.invalidateCache()
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

  // MARK: - Recovery Methods

  /// Attempt to recover transactions from SQLite
  func attemptTransactionRecovery() -> Bool {
    return transactionLedger.attemptTransactionRecovery()
  }

  /// Check if transactions exist in SQLite
  func checkSQLiteRecovery() -> [Transaction] {
    return transactionLedger.checkSQLiteRecovery()
  }

}
