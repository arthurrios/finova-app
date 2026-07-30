//
//  MonthlyNotificationManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 17/01/25.
//

import Foundation
import UIKit
import UserNotifications

final class MonthlyNotificationManager {
  private let transactionRepo: TransactionRepository
  private let budgetRepo: BudgetRepository
  private let notificationCenter = UNUserNotificationCenter.current()
  private let calendar = Calendar.current
  private let preferencesManager = NotificationPreferencesManager.shared

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    budgetRepo: BudgetRepository = BudgetRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.budgetRepo = budgetRepo
  }

  // MARK: - Public Methods

  /// Configura o sistema de notificações mensais
  func setupMonthlyNotificationSystem() {
    scheduleMonthlyReminderNotification()
    scheduleMonthlyFallbackNotification()
  }

  /// Agenda todas as notificações do mês atual
  func scheduleAllMonthlyNotifications(showAlert: Bool = true) -> Bool {
    // Check if all notifications are disabled
    guard !preferencesManager.allNotificationsDisabled else {
      clearExistingMonthlyNotifications()
      return true
    }

    // Verificar permissões
    var hasPermission = false
    let semaphore = DispatchSemaphore(value: 0)

    notificationCenter.getNotificationSettings { settings in
      hasPermission = settings.authorizationStatus == .authorized
      semaphore.signal()
    }

    semaphore.wait()

    guard hasPermission else {
      if showAlert {
        showPermissionDeniedAlert()
      }
      return false
    }

    // Verificar se já foram agendadas para este mês
    let alreadyScheduled = areNotificationsScheduledForCurrentMonth()

    // Limpar notificações existentes
    clearExistingMonthlyNotifications()

    // Agendar notificações de transações (only if enabled)
    let transactionSuccess = preferencesManager.transactionNotificationsEnabled
      ? scheduleTransactionNotifications()
      : true

    // Agendar notificações de saldo negativo (only if enabled)
    let balanceSuccess = preferencesManager.negativeBalanceNotificationsEnabled
      ? scheduleBalanceNotifications()
      : true

    // Agendar notificações de parcelas/recorrentes
    let recurringSuccess = scheduleRecurringNotifications()

    let overallSuccess = transactionSuccess && balanceSuccess && recurringSuccess

    if overallSuccess {
      if showAlert {
        if alreadyScheduled {
          showRescheduledAlert()
        } else {
          showSuccessAlert()
        }
      }
    } else {
      if showAlert {
        showFailureAlert()
      }
    }

    return overallSuccess
  }

  /// Verifica se as notificações do mês foram configuradas
  func checkMonthlyNotificationsStatus() -> MonthlyNotificationStatus {
    var status = MonthlyNotificationStatus.notConfigured
    let semaphore = DispatchSemaphore(value: 0)

    notificationCenter.getPendingNotificationRequests { requests in
      let monthlyRequests = requests.filter { request in
        request.identifier.hasPrefix("monthly_") || request.identifier.hasPrefix("transaction_")
          || request.identifier.hasPrefix("negative_balance_")
          || request.identifier.hasPrefix("recurring_")
          || request.identifier.hasPrefix("installment_")
      }

      if monthlyRequests.isEmpty {
        status = .notConfigured
      } else {
        let currentMonth = self.calendar.component(.month, from: Date())
        let currentYear = self.calendar.component(.year, from: Date())

        let hasCurrentMonthNotifications = monthlyRequests.contains { request in
          if let trigger = request.trigger as? UNCalendarNotificationTrigger,
            let nextTriggerDate = trigger.nextTriggerDate()
          {
            let triggerMonth = self.calendar.component(.month, from: nextTriggerDate)
            let triggerYear = self.calendar.component(.year, from: nextTriggerDate)
            return triggerMonth == currentMonth && triggerYear == currentYear
          }
          return false
        }

        status = hasCurrentMonthNotifications ? .configured : .outdated
      }
      semaphore.signal()
    }

    semaphore.wait()
    return status
  }

  /// Verifica se as notificações já foram agendadas para o mês atual
  func areNotificationsScheduledForCurrentMonth() -> Bool {
    let currentDate = Date()
    let calendar = Calendar.current
    let currentMonth = calendar.component(.month, from: currentDate)
    let currentYear = calendar.component(.year, from: currentDate)
    let currentMonthKey = "\(currentYear)-\(currentMonth)"

    let lastScheduledMonthKey = UserDefaults.standard.string(forKey: "lastScheduledMonthKey")
    return lastScheduledMonthKey == currentMonthKey
  }

  // MARK: - Private Methods

  /// Agenda notificação de lembrete mensal
  private func scheduleMonthlyReminderNotification() {
    let today = Date()
    let firstDayOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today

    // Se já passou do primeiro dia, agendar para o próximo mês
    let targetDate =
      firstDayOfMonth > today
      ? firstDayOfMonth
      : calendar.date(byAdding: .month, value: 1, to: firstDayOfMonth) ?? firstDayOfMonth

    var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
    dateComponents.hour = 8
    dateComponents.minute = 0
    dateComponents.second = 0

    guard let notificationDate = calendar.date(from: dateComponents) else { return }

    let content = UNMutableNotificationContent()
    content.title = "notification.monthly.reminder.title".localized
    content.body = "notification.monthly.reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "MONTHLY_REMINDER"
    content.userInfo = ["type": "monthly_reminder"]

    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
    let request = UNNotificationRequest(
      identifier: "monthly_reminder_\(targetDate.timeIntervalSince1970)", content: content,
      trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling monthly reminder: \(error)")
      }
    }
  }

  /// Agenda notificação de fallback (3º dia do mês)
  private func scheduleMonthlyFallbackNotification() {
    let today = Date()
    let firstDayOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today

    // 3º dia do mês atual ou próximo mês
    let thirdDayOfMonth =
      calendar.date(byAdding: .day, value: 2, to: firstDayOfMonth) ?? firstDayOfMonth
    let targetDate =
      thirdDayOfMonth > today
      ? thirdDayOfMonth
      : calendar.date(byAdding: .month, value: 1, to: thirdDayOfMonth) ?? thirdDayOfMonth

    var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
    dateComponents.hour = 10  // 10h para não conflitar com a de 8h
    dateComponents.minute = 0
    dateComponents.second = 0

    guard let notificationDate = calendar.date(from: dateComponents) else { return }

    let content = UNMutableNotificationContent()
    content.title = "notification.monthly.fallback.title".localized
    content.body = "notification.monthly.fallback.body".localized
    content.sound = .default
    content.categoryIdentifier = "MONTHLY_FALLBACK"
    content.userInfo = ["type": "monthly_fallback"]

    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
    let request = UNNotificationRequest(
      identifier: "monthly_fallback_\(targetDate.timeIntervalSince1970)", content: content,
      trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling monthly fallback: \(error)")
      }
    }
  }

  /// Limpa notificações mensais existentes
  private func clearExistingMonthlyNotifications() {
    notificationCenter.getPendingNotificationRequests { requests in
      let monthlyIds =
        requests
        .filter { request in
          request.identifier.hasPrefix("transaction_")
            || request.identifier.hasPrefix("negative_balance_")
            || request.identifier.hasPrefix("recurring_")
            || request.identifier.hasPrefix("installment_")
        }
        .map { $0.identifier }

      if !monthlyIds.isEmpty {
        self.notificationCenter.removePendingNotificationRequests(withIdentifiers: monthlyIds)
      }
    }
  }

  /// Agenda notificações de transações via TransactionNotificationManager
  private func scheduleTransactionNotifications() -> Bool {
    // Gap #3 fix: Invalidate cache before fetching to ensure fresh data
    TransactionRepository.invalidateCache()
    let allTxs = transactionRepo.fetchAllTransactions()
    TransactionNotificationManager.shared.scheduleAllTransactionNotifications(
      transactions: allTxs, clearExisting: false, limit: 30)
    return true
  }

  /// Agenda notificações de saldo negativo
  private func scheduleBalanceNotifications() -> Bool {
    BalanceMonitorManager.shared.monitorCurrentMonthBalance()
    return true
  }

  /// Agenda notificações de transações recorrentes/parceladas
  private func scheduleRecurringNotifications() -> Bool {
    // Esta lógica seria implementada aqui
    // Por enquanto, retorna true
    return true
  }

  /// Mostra alerta de sucesso
  func showSuccessAlert() {
    DispatchQueue.main.async {
      let alert = UIAlertController(
        title: "notification.monthly.success.title".localized,
        message: "notification.monthly.success.body".localized,
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))

      // Encontrar o view controller ativo para apresentar o alerta
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = windowScene.windows.first,
        let rootViewController = window.rootViewController
      {

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
          topViewController = presentedViewController
        }

        topViewController.present(alert, animated: true)
      }
    }
  }

  /// Mostra alerta de reagendamento
  func showRescheduledAlert() {
    DispatchQueue.main.async {
      let alert = UIAlertController(
        title: "notification.monthly.rescheduled.title".localized,
        message: "notification.monthly.rescheduled.body".localized,
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))

      // Encontrar o view controller ativo para apresentar o alerta
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = windowScene.windows.first,
        let rootViewController = window.rootViewController
      {

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
          topViewController = presentedViewController
        }

        topViewController.present(alert, animated: true)
      }
    }
  }

  /// Mostra alerta de falha
  func showFailureAlert() {
    DispatchQueue.main.async {
      let alert = UIAlertController(
        title: "notification.monthly.failure.title".localized,
        message: "notification.monthly.failure.body".localized,
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))

      // Encontrar o view controller ativo para apresentar o alerta
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = windowScene.windows.first,
        let rootViewController = window.rootViewController
      {

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
          topViewController = presentedViewController
        }

        topViewController.present(alert, animated: true)
      }
    }
  }

  /// Mostra alerta de permissão negada
  func showPermissionDeniedAlert() {
    DispatchQueue.main.async {
      let alert = UIAlertController(
        title: "notification.monthly.permission.title".localized,
        message: "notification.monthly.permission.body".localized,
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))

      // Encontrar o view controller ativo para apresentar o alerta
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = windowScene.windows.first,
        let rootViewController = window.rootViewController
      {

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
          topViewController = presentedViewController
        }

        topViewController.present(alert, animated: true)
      }
    }
  }
}

// MARK: - Supporting Types

enum MonthlyNotificationStatus {
  case notConfigured
  case configured
  case outdated
}
