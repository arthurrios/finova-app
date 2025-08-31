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
  }

  func loadMonthlyCards() -> [MonthBudgetCardType] {
    let today = Date()

    print("🔍 loadMonthlyCards() called with monthRange: \(monthRange)")

    let budgetsByAnchor: [Int: Int] = budgetRepo.fetchBudgets()
      .reduce(into: [:]) { acc, entry in
        acc[entry.monthDate] = entry.amount
      }

    let allTxs = transactionRepo.fetchTransactions()

    let expensesByAnchor =
      allTxs
      .filter { $0.type == .expense }
      .reduce(into: [:]) { acc, tx in
        acc[tx.budgetMonthDate, default: 0] += tx.amount
      }

    let incomesByAnchor =
      allTxs
      .filter { $0.type == .income }
      .reduce(into: [:]) { acc, tx in
        acc[tx.budgetMonthDate, default: 0] += tx.amount
      }

    // Generate month dates more reliably by working with year/month components
    var anchors: [Int] = []
    let currentComponents = calendar.dateComponents([.year, .month], from: today)
    let currentYear = currentComponents.year!
    let currentMonth = currentComponents.month!

    for offset in monthRange {
      let targetMonth = currentMonth + offset
      let targetYear = currentYear + (targetMonth - 1) / 12
      let normalizedMonth = ((targetMonth - 1) % 12) + 1

      var components = DateComponents()
      components.year = targetYear
      components.month = normalizedMonth
      components.day = 1
      components.hour = 0
      components.minute = 0
      components.second = 0

      let monthDate = calendar.date(from: components)!
      let anchor = monthDate.monthAnchor

      anchors.append(anchor)
      print("🔍 Offset \(offset): \(monthDate) -> anchor \(anchor)")
    }

    print("🔍 Generated \(anchors.count) anchors: \(anchors)")

    var runningBalance = [Int: Int]()
    var previousAvailable = 0

    let cards: [MonthBudgetCardType] = anchors.map { anchor in
      let date = Date(timeIntervalSince1970: TimeInterval(anchor))
      let month = DateFormatter.monthFormatter.string(from: date)
      let localizedMonth = "month.\(month.lowercased())".localized

      print("🔍 Processing anchor \(anchor): \(date) -> \(month) -> \(localizedMonth)")

      let expense = expensesByAnchor[anchor] ?? 0
      let income = incomesByAnchor[anchor] ?? 0
      let budgetLimit = budgetsByAnchor[anchor]

      let net = income - expense

      let currentBalance = calculateCurrentBalance(
        anchor: anchor,
        allTransactions: allTxs,
        previousBalance: previousAvailable  // Use the previous month's balance
      )

      let thisMonthPreviousBalance = previousAvailable

      let available = previousAvailable + net
      previousAvailable = available
      runningBalance[anchor] = available

      return MonthBudgetCardType(
        date: date,
        month: localizedMonth,
        usedValue: expense,
        budgetLimit: budgetLimit,
        finalBalance: available,
        currentBalance: currentBalance,
        previousBalance: thisMonthPreviousBalance
      )
    }

    print("🔍 Final cards count: \(cards.count)")
    print("🔍 Final card months: \(cards.map { $0.month })")

    // Monitorar saldo negativo após carregar os dados
    balanceMonitor.monitorCurrentMonthBalance()

    return cards
  }

  private func calculateCurrentBalance(
    anchor: Int, allTransactions: [Transaction], previousBalance: Int
  ) -> Int {
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(anchor))

    let utcCalendar = Calendar(identifier: .gregorian)
    var calendar = utcCalendar
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

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
            )
          } else {
            // This is an installment transaction
            self.recurringManager.cleanupInstallmentTransactionsFromDate(
              parentTransactionId: parentTransactionId,
              selectedTransactionDate: transaction.date,
              cleanupOption: cleanupOption
            )
          }

          // Add a small delay to ensure database operations complete
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            completion(.success(()))
          }
          return
        }

        // Handle parent recurring transaction
        if transaction.isRecurring == true {
          self.recurringManager.cleanupRecurringInstancesFromDate(
            parentTransactionId: transactionId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          )
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
          )
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
      return .simple
    }

    // Check if this is a recurring transaction instance
    if let parentId = transaction.parentTransactionId {
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

    // Check if this is a parent recurring transaction
    if transaction.isRecurring == true {
      return .recurringParent
    }

    // Check if this is a parent installment transaction
    if transaction.hasInstallments == true {
      return .installmentParent
    }

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
