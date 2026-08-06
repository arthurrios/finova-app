//
//  BalanceMonitorManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 17/01/25.
//

import Foundation
import UserNotifications

final class BalanceMonitorManager {
  static let shared = BalanceMonitorManager()

  private let transactionRepo: TransactionRepository
  private let budgetRepo: BudgetRepository
  private let notificationCenter = UNUserNotificationCenter.current()
  private let calendar = Calendar.current
  private let preferencesManager = NotificationPreferencesManager.shared

  /// Fixed notification identifier — UNUserNotificationCenter auto-replaces on same ID
  private static let notificationId = "negative_balance_projection"

  /// The negative date we have already warned about immediately, so the eve-of warning fires once
  /// rather than on every foreground. See `scheduleNegativeBalanceNotifications`.
  private static let immediateNoticeDefaultsKey = "negativeBalanceImmediateNoticeDate"

  // Controle para evitar execuções muito frequentes
  private var lastMonitoringTime: Date?
  private let minimumMonitoringInterval: TimeInterval = 300  // 5 minutos

  private init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    budgetRepo: BudgetRepository = BudgetRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.budgetRepo = budgetRepo
    setupObservers()
  }

  // MARK: - Reactive Observer

  private func setupObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTransactionDataChanged),
      name: .transactionDataChanged,
      object: nil
    )
  }

  @objc private func handleTransactionDataChanged() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      self?.monitorCurrentMonthBalance()
    }
  }

  // MARK: - Public Methods

  /// Monitora o saldo do mês atual e agenda notificações se necessário
  func monitorCurrentMonthBalance() {
    // Check if notifications are disabled
    guard !preferencesManager.allNotificationsDisabled,
          preferencesManager.negativeBalanceNotificationsEnabled else {
      removeNegativeBalanceNotifications()
      return
    }

    // Verificar se já foi executado recentemente
    if let lastTime = lastMonitoringTime {
      let timeSinceLastMonitoring = Date().timeIntervalSince(lastTime)
      if timeSinceLastMonitoring < minimumMonitoringInterval {
        return
      }
    }

    // Atualizar tempo da última execução
    lastMonitoringTime = Date()

    let today = Date()
    let currentMonth = calendar.dateInterval(of: .month, for: today)!

    // Calcular saldo projetado para cada dia do mês
    let dailyBalanceProjection = calculateDailyBalanceProjectionInternal(for: currentMonth)

    // Verificar se há dias com saldo negativo
    let negativeBalanceDays = findNegativeBalanceDaysInternal(from: dailyBalanceProjection)

    if !negativeBalanceDays.isEmpty {
      scheduleNegativeBalanceNotifications(for: negativeBalanceDays)
    } else {
      // Remover notificações de saldo negativo se não há mais risco
      removeNegativeBalanceNotifications()
    }
  }

  /// Remove todas as notificações de saldo negativo
  func removeNegativeBalanceNotifications() {
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: [Self.notificationId])
  }

  // MARK: - Internal Methods (for testing)

  /// Método interno para testes - calcula projeção de saldo
  func calculateDailyBalanceProjection(for monthInterval: DateInterval) -> [Date: Int] {
    return calculateDailyBalanceProjectionInternal(for: monthInterval)
  }

  /// Método interno para testes - encontra dias com saldo negativo
  func findNegativeBalanceDays(from dailyBalance: [Date: Int]) -> [Date] {
    return findNegativeBalanceDaysInternal(from: dailyBalance)
  }

  // MARK: - Private Methods

  /// Calcula a projeção de saldo para cada dia do mês usando a mesma lógica do dashboard
  private func calculateDailyBalanceProjectionInternal(for monthInterval: DateInterval) -> [Date:
    Int]
  {
    // Both the row set and the starting balance now come from the ledger service, so the projection
    // is built from exactly what the dashboard shows.
    //
    // Three things were wrong with computing this locally. The set came from `fetchTransactions()`,
    // which holds no synthetic statement rows — so the credit card statement debit, usually the
    // month's largest single outflow, was invisible and the predicted negative day was wrong or
    // never found at all. Installments paid early were still counted. And the starting balance
    // accumulated past months by `budgetMonthDate` while the projection walks forward by transaction
    // date, so the two halves disagreed.
    let ledgerService = TransactionLedgerService()
    let cashTransactions = ledgerService.cashTransactionsForBalance()
    let currentBalance = ledgerService.balanceAsOf(Date(), transactions: cashTransactions)

    // Filtrar transações futuras dentro da janela de 30 dias — sem restrição de mês,
    // para capturar corretamente transações do mês seguinte (ex: aluguel em 1º do mês próximo).
    let today = Date()
    let todayStart = calendar.startOfDay(for: today)

    let futureTransactions = cashTransactions.filter { transaction in
      let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let txDateStart = calendar.startOfDay(for: txDate)
      return txDateStart > todayStart
    }

    // Calcular projeção para os próximos 30 dias
    var dailyBalance: [Date: Int] = [:]
    var runningBalance = currentBalance

    // Adicionar o saldo atual para hoje
    dailyBalance[todayStart] = currentBalance

    // Calcular para os próximos 30 dias
    for dayOffset in 1...30 {
      guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else {
        continue
      }

      let normalizedDate = calendar.startOfDay(for: futureDate)

      // Encontrar transações para este dia específico
      let transactionsForThisDay = futureTransactions.filter { transaction in
        let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
        let txDateStart = calendar.startOfDay(for: txDate)
        return calendar.isDate(txDateStart, inSameDayAs: normalizedDate)
      }

      let netForThisDay = transactionsForThisDay.reduce(0) { result, tx in
        tx.type == .income ? result + tx.amount : result - tx.amount
      }

      runningBalance += netForThisDay
      dailyBalance[normalizedDate] = runningBalance
    }

    return dailyBalance
  }

  /// Encontra o primeiro dia com saldo negativo
  private func findNegativeBalanceDaysInternal(from dailyBalance: [Date: Int]) -> [Date] {
    let today = Date()
    let todayStart = calendar.startOfDay(for: today)

    // Ordenar os dias cronologicamente
    let sortedDays = dailyBalance.keys.sorted()

    // Encontrar o primeiro dia futuro com saldo negativo
    for date in sortedDays {
      guard date > todayStart else { continue }  // Apenas dias futuros (excluindo hoje)

      if let balance = dailyBalance[date], balance < 0 {
        // Retornar apenas o primeiro dia negativo
        return [date]
      }
    }

    return []
  }

  /// Agenda a notificação para o primeiro dia com saldo negativo.
  ///
  /// Only the first negative day is ever notified — `findNegativeBalanceDaysInternal` returns one —
  /// and all of them shared a single fixed identifier anyway, so the old loop could only ever have
  /// left the last iteration standing.
  private func scheduleNegativeBalanceNotifications(for negativeDays: [Date]) {
    guard let negativeDay = negativeDays.first else { return }

    let now = Date()
    let todayStart = calendar.startOfDay(for: now)
    let negativeDayStart = calendar.startOfDay(for: negativeDay)

    let daysUntilNegative =
      calendar.dateComponents([.day], from: todayStart, to: negativeDayStart).day ?? 0

    // Notificar apenas para dias futuros (amanhã em diante), dentro da janela projetada
    guard daysUntilNegative >= 1 && daysUntilNegative <= 30 else {
      removeNegativeBalanceNotifications()
      return
    }

    // Formatar a data de acordo com o idioma
    let dateFormatter = DateFormatter()
    if let languageCode = Locale.current.languageCode, languageCode == "en" {
      dateFormatter.dateFormat = "MM/dd"
    } else {
      dateFormatter.dateFormat = "dd/MM"
    }
    let formattedDate = dateFormatter.string(from: negativeDay)

    // 8 AM on the day before the balance goes negative.
    guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: negativeDayStart) else {
      return
    }
    var fireComponents = calendar.dateComponents([.year, .month, .day], from: dayBefore)
    fireComponents.hour = 8
    fireComponents.minute = 0
    fireComponents.second = 0
    guard let fireDate = calendar.date(from: fireComponents) else { return }

    let trigger: UNNotificationTrigger

    if fireDate > now {
      trigger = UNCalendarNotificationTrigger(
        dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
        repeats: false)
    } else {
      // The 8 AM slot has already passed and the balance goes negative tomorrow: warn now, but only
      // once per negative date. Without this guard every foreground re-fired the same alert, because
      // an immediate trigger cannot be "replaced" once it has been delivered.
      let alreadyWarnedFor = UserDefaults.standard.object(
        forKey: Self.immediateNoticeDefaultsKey) as? Double
      guard alreadyWarnedFor != negativeDayStart.timeIntervalSince1970 else { return }
      UserDefaults.standard.set(
        negativeDayStart.timeIntervalSince1970, forKey: Self.immediateNoticeDefaultsKey)
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    }

    let content = UNMutableNotificationContent()
    content.title = "notification.negative.balance.title".localized
    // "tomorrow", not "in %d days": the body used to bake the distance in at SCHEDULING time while
    // delivery is 8 AM the day before, so an alert scheduled twelve days out still claimed
    // "in 12 days" when it actually arrived on the eve.
    content.body = String(
      format: "notification.negative.balance.body.tomorrow".localized, formattedDate)
    content.sound = .default
    content.categoryIdentifier = "NEGATIVE_BALANCE"
    content.userInfo = [
      "type": "negative_balance",
      "negativeDate": negativeDayStart.timeIntervalSince1970,
      "daysUntilNegative": daysUntilNegative,
      "formattedDate": formattedDate,
    ]

    let request = UNNotificationRequest(
      identifier: Self.notificationId, content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling negative balance notification: \(error)")
      }
    }
  }

  /// Verifica se há notificações de saldo negativo agendadas
  func hasNegativeBalanceNotifications() -> Bool {
    var hasNotifications = false
    let semaphore = DispatchSemaphore(value: 0)

    notificationCenter.getPendingNotificationRequests { requests in
      hasNotifications = requests.contains { $0.identifier == Self.notificationId }
      semaphore.signal()
    }

    semaphore.wait()
    return hasNotifications
  }

  /// Force trigger balance monitoring (bypasses time restrictions)
  func forceTriggerBalanceMonitoring() {
    // Reset the last monitoring time to force execution
    lastMonitoringTime = nil

    // Run the monitoring
    monitorCurrentMonthBalance()
  }

  /// Clear all negative balance notifications (for cleanup)
  func clearAllNegativeBalanceNotifications() {
    removeNegativeBalanceNotifications()
  }

  // MARK: - Debug Methods

  /// Debug balance monitoring without dashboard data
  func debugBalanceMonitoring() {
    logDebug("[BalanceMonitor] Debug without dashboard data:")

    let today = Date()
    let currentMonth = calendar.dateInterval(of: .month, for: today)!
    let dailyBalanceProjection = calculateDailyBalanceProjectionInternal(for: currentMonth)
    let negativeBalanceDays = findNegativeBalanceDaysInternal(from: dailyBalanceProjection)

    logDebug("   Daily balance projection count: \(dailyBalanceProjection.count)")
    logDebug("   Negative balance days: \(negativeBalanceDays)")
  }

  /// Test notification for tomorrow's negative balance (fires in 5 seconds)
  func testTomorrowNegativeBalanceNotification() {
    let content = UNMutableNotificationContent()
    content.title = "notification.negative.balance.title".localized
    content.body = String(format: "notification.negative.balance.body".localized, 1, "tomorrow")
    content.sound = .default
    content.categoryIdentifier = "NEGATIVE_BALANCE"

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
    let request = UNNotificationRequest(
      identifier: "test_negative_balance_tomorrow",
      content: content,
      trigger: trigger
    )

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling test notification: \(error)")
      } else {
        logInfo("Test notification scheduled for 5 seconds from now")
      }
    }
  }

  /// Test notification for negative balance in 1 minute
  func testNegativeBalanceNotificationIn1Minute() {
    let content = UNMutableNotificationContent()
    content.title = "notification.negative.balance.title".localized
    content.body = String(format: "notification.negative.balance.body".localized, 1, "test date")
    content.sound = .default
    content.categoryIdentifier = "NEGATIVE_BALANCE"

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
    let request = UNNotificationRequest(
      identifier: "test_negative_balance_1min",
      content: content,
      trigger: trigger
    )

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling test notification: \(error)")
      } else {
        logInfo("Test notification scheduled for 1 minute from now")
      }
    }
  }

}
