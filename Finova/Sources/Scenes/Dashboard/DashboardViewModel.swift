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
  private let balanceMonitor: BalanceMonitorManager
  private let monthlyNotificationManager: MonthlyNotificationManager
  let transactionLedger: TransactionLedgerService
  private let calendar = Calendar.current

  private let monthRange: ClosedRange<Int>
  private let notificationCenter = UNUserNotificationCenter.current()

  var onCleanupChoiceNeeded: ((RecurringCleanupOption) -> Void)?

  init(
    budgetRepo: BudgetRepository = BudgetRepository(),
    transactionRepo: TransactionRepository = TransactionRepository(),
    monthRange: ClosedRange<Int> = -12...24
  ) {  // 3 years
    self.budgetRepo = budgetRepo
    self.transactionRepo = transactionRepo
    self.monthRange = monthRange
    self.recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    self.balanceMonitor = BalanceMonitorManager(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
    self.monthlyNotificationManager = MonthlyNotificationManager(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
    self.transactionLedger = TransactionLedgerService(
      transactionRepo: transactionRepo, budgetRepo: budgetRepo)
  }

  func loadMonthlyCards() -> [MonthBudgetCardType] {
    print("🔍 loadMonthlyCards() called with monthRange: \(monthRange)")

    // Use the transaction ledger service for all calculations
    let monthlyData = transactionLedger.calculateMonthlyData(for: monthRange)

    print("🔍 Final cards count: \(monthlyData.count)")
    print("🔍 Final card months: \(monthlyData.count > 0 ? monthlyData.map { $0.month } : [])")

    // Log balance information for debugging
    if let currentMonthData = monthlyData.first(where: {
      Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
    }) {
      print(
        "💰 Current month balance - Final: \(currentMonthData.finalBalance ?? 0), Current: \(currentMonthData.currentBalance ?? 0), Previous: \(currentMonthData.previousBalance ?? 0)"
      )
    }

    // Monitor negative balance after loading data
    balanceMonitor.monitorCurrentMonthBalance()

    return monthlyData
  }

  /// Clean up any existing duplicate transactions
  func cleanupExistingDuplicates() {
    print("🧹 Starting duplicate transaction cleanup...")
    transactionLedger.cleanupDuplicateTransactions()
    print("🧹 Duplicate transaction cleanup completed")
  }

  /// Force refresh current month balance (useful for debugging)
  func forceRefreshCurrentMonthBalance() {
    print("🔄 Force refreshing current month balance...")
    transactionLedger.forceRefreshCurrentMonthBalance()
  }

  /// Force refresh all balance calculations (useful after fixing date comparison issues)
  func forceRefreshAllBalances() {
    print("🔄 Force refreshing all balance calculations...")
    transactionLedger.forceRefreshAllBalances()
  }

  /// Debug "Aula de canto" transaction specifically
  func debugAulaDeCantoTransaction() {
    print("🎵 Debugging 'Aula de canto' transaction...")
    transactionLedger.debugAulaDeCantoTransaction()
  }

  /// Migrate budgets to new timezone-based month anchors
  func migrateBudgetsToNewTimezone() {
    print("🔄 Starting budget migration...")
    transactionLedger.migrateBudgetsToNewTimezone()
  }

  /// Migrate all data (budgets and transactions) to new timezone-based month anchors
  func migrateAllDataToNewTimezone() {
    print("🔄 Starting comprehensive data migration...")
    transactionLedger.migrateAllDataToNewTimezone()
  }

  /// Get a summary of duplicate transactions (without removing them)
  func analyzeDuplicateTransactions() -> String {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let transactionsByMonth = Dictionary(grouping: allTransactions) { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate.monthAnchor
    }

    var summary = "🔍 Duplicate Transaction Analysis:\n"
    var totalDuplicates = 0

    for (monthAnchor, transactions) in transactionsByMonth {
      if transactions.count > 1 {
        let date = Date(timeIntervalSince1970: TimeInterval(monthAnchor))
        let monthName = DateFormatter.monthFormatter.string(from: date)
        let year = Calendar.current.component(.year, from: date)

        summary += "\n📅 \(monthName) \(year): \(transactions.count) transactions\n"

        // Group by title to identify potential duplicates
        let groupedByTitle = Dictionary(grouping: transactions) { $0.title }
        for (title, titleGroup) in groupedByTitle {
          if titleGroup.count > 1 {
            summary += "   • \(title): \(titleGroup.count) instances\n"
            totalDuplicates += titleGroup.count - 1
          }
        }
      }
    }

    summary += "\n📊 Total potential duplicates: \(totalDuplicates)"
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
    recurringManager.generateRecurringTransactionsForRange(monthRange)
    recurringManager.cleanupRecurringInstancesOutsideRange(
      monthRange, referenceDate: Date(), cleanupOption: .futureOnly)
  }

  func updateRecurringTransactionsWithCleanupChoice(
    cleanupOption: RecurringCleanupOption = .futureOnly
  ) {
    recurringManager.generateRecurringTransactionsForRange(monthRange)
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

        // Handle recurring transaction instances
        if let parentTransactionId = transaction.parentTransactionId {
          let parentTransaction = allTransactions.first(where: { $0.id == parentTransactionId })

          if parentTransaction?.isRecurring == true {
            // This is a recurring transaction instance
            self.recurringManager.cleanupRecurringInstancesFromDate(
              parentTransactionId: parentTransactionId,
              selectedTransactionDate: transaction.date,
              cleanupOption: cleanupOption
            ) {
              // Invalidate ledger cache since transactions changed
              self.transactionLedger.invalidateCache()
              completion(.success(()))
            }
          } else {
            // This is an installment transaction
            self.recurringManager.cleanupInstallmentTransactionsFromDate(
              parentTransactionId: parentTransactionId,
              selectedTransactionDate: transaction.date,
              cleanupOption: cleanupOption
            ) {
              // Invalidate ledger cache since transactions changed
              self.transactionLedger.invalidateCache()
              completion(.success(()))
            }
          }
          return
        }

        // Handle parent recurring transaction
        if transaction.isRecurring == true {
          self.recurringManager.cleanupRecurringInstancesFromDate(
            parentTransactionId: transactionId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          ) {
            // Invalidate ledger cache since transactions changed
            self.transactionLedger.invalidateCache()
            completion(.success(()))
          }
          return
        }

        // Handle parent installment transaction
        if transaction.hasInstallments == true {
          self.recurringManager.cleanupInstallmentTransactionsFromDate(
            parentTransactionId: transactionId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          ) {
            // Invalidate ledger cache since transactions changed
            self.transactionLedger.invalidateCache()
            completion(.success(()))
          }
          return
        }

        DispatchQueue.main.async {
          completion(.failure(TransactionError.transactionNotFound))
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

    // Return true if it's a parent recurring transaction OR a recurring instance
    return transaction.isRecurring == true || transaction.parentTransactionId != nil
  }

  func getTransactionType(id: Int) -> TransactionComplexityType {
    guard let transaction = transactionRepo.fetchAllTransactions().first(where: { $0.id == id })
    else {
      print("🔍 GET TRANSACTION TYPE DEBUG: Transaction with ID \(id) not found")
      return .simple
    }

    print("🔍 GET TRANSACTION TYPE DEBUG: Analyzing transaction '\(transaction.title)' (ID: \(id))")
    print("🔍 GET TRANSACTION TYPE DEBUG: Mode: \(transaction.mode)")
    print("🔍 GET TRANSACTION TYPE DEBUG: Is recurring: \(transaction.isRecurring ?? false)")
    print("🔍 GET TRANSACTION TYPE DEBUG: Has installments: \(transaction.hasInstallments ?? false)")
    print("🔍 GET TRANSACTION TYPE DEBUG: Parent ID: \(transaction.parentTransactionId ?? 0)")

    // Check if this is a recurring transaction instance
    if let parentId = transaction.parentTransactionId {
      // Special case: if parentTransactionId points to itself, treat it as a parent transaction
      if parentId == id {
        print(
          "🔍 GET TRANSACTION TYPE DEBUG: Parent ID points to self, treating as parent transaction")
        // Continue to parent transaction checks below
      } else {
        let parentTransaction = transactionRepo.fetchAllTransactions().first(where: {
          $0.id == parentId
        }
        )
        if parentTransaction?.isRecurring == true {
          print("🔍 GET TRANSACTION TYPE DEBUG: Detected as recurring instance")
          return .recurringInstance
        } else {
          print("🔍 GET TRANSACTION TYPE DEBUG: Detected as installment instance")
          return .installmentInstance
        }
      }
    }

    // Check if this is a parent recurring transaction
    if transaction.isRecurring == true {
      print("🔍 GET TRANSACTION TYPE DEBUG: Detected as recurring parent")
      return .recurringParent
    }

    // Special case: if mode is recurring but isRecurring is false (data corruption), treat as recurring parent
    if transaction.mode == .recurring && transaction.isRecurring != true {
      print(
        "🔍 GET TRANSACTION TYPE DEBUG: Mode is recurring but isRecurring is false (data corruption), treating as recurring parent"
      )
      return .recurringParent
    }

    // Check if this is a parent installment transaction (only if not recurring)
    if transaction.hasInstallments == true && transaction.isRecurring != true {
      print("🔍 GET TRANSACTION TYPE DEBUG: Detected as installment parent")
      return .installmentParent
    }

    print("🔍 GET TRANSACTION TYPE DEBUG: Detected as simple transaction")
    return .simple
  }

  // MARK: - Debug Functions

  func debugPendingNotifications() {
    notificationCenter.getPendingNotificationRequests { requests in
      print("🔔 Pending notifications: \(requests.count)")
      for request in requests {
        if let trigger = request.trigger as? UNCalendarNotificationTrigger,
          let nextTriggerDate = trigger.nextTriggerDate()
        {
          print("   \(request.identifier): \(nextTriggerDate)")
        } else if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
          let fireTime = Date().addingTimeInterval(trigger.timeInterval)
          print("   \(request.identifier): \(fireTime)")
        }
      }
    }
  }

  // MARK: - Balance Monitor Functions

  /// Força o monitoramento de saldo negativo
  func forceBalanceMonitoring() {
    balanceMonitor.monitorCurrentMonthBalance()
  }

  /// Remove todas as notificações de saldo negativo
  func removeNegativeBalanceNotifications() {
    balanceMonitor.removeNegativeBalanceNotifications()
  }

  /// Verifica se há notificações de saldo negativo agendadas
  func hasNegativeBalanceNotifications() -> Bool {
    return balanceMonitor.hasNegativeBalanceNotifications()
  }

  /// Debug: Lista todas as notificações de saldo negativo
  func debugNegativeBalanceNotifications() {
    balanceMonitor.debugNegativeBalanceNotifications()
  }

  /// Debug: Testa formatação de data para diferentes idiomas
  func debugDateFormatting() {
    balanceMonitor.debugDateFormatting()
  }

  /// Debug: Check for duplicate transactions
  func debugDuplicateTransactions() {
    transactionRepo.debugDuplicateTransactions()
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
    print("🔄 DashboardViewModel: Attempting transaction recovery...")
    return transactionLedger.attemptTransactionRecovery()
  }

  /// Check if transactions exist in SQLite
  func checkSQLiteRecovery() -> [Transaction] {
    return transactionLedger.checkSQLiteRecovery()
  }

}
