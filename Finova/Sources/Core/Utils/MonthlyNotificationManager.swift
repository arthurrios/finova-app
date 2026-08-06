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

  /// Key under which the month whose notifications have been scheduled is recorded.
  static let lastScheduledMonthDefaultsKey = "lastScheduledMonthKey"

  private static let reminderPrefix = "monthly_reminder_"
  private static let fallbackPrefix = "monthly_fallback_"

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    budgetRepo: BudgetRepository = BudgetRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.budgetRepo = budgetRepo
  }

  // MARK: - Public Methods

  /// Configura o sistema de notificações mensais.
  ///
  /// The two "open the app to set up your notifications" prompts are keyed by the month they nag
  /// about (`monthly_fallback_2026-8`), not by their fire timestamp. That makes this idempotent
  /// across launches AND lets `markMonthAsScheduled` cancel the prompt for a month that has since
  /// been configured — without which the 3rd-of-the-month fallback kept firing two days after a
  /// successful first-of-the-month setup.
  func setupMonthlyNotificationSystem() {
    scheduleMonthlyReminderNotification()
    scheduleMonthlyFallbackNotification()
  }

  /// Agenda todas as notificações do mês atual
  func scheduleAllMonthlyNotifications(showAlert: Bool = true) -> Bool {
    // Check if all notifications are disabled
    guard !preferencesManager.allNotificationsDisabled else {
      clearExistingMonthlyNotificationsAndWait()
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

    // Limpar notificações existentes.
    // Blocking here is deliberate: the removal runs on UNUserNotificationCenter's own queue, so
    // letting it race with the scheduling below meant the clear landed AFTER the new requests and
    // deleted the very notifications this method had just added — same identifiers.
    clearExistingMonthlyNotificationsAndWait()

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

    // Agendar notificações de fatura de cartão
    let statementSuccess = scheduleStatementNotifications()

    let overallSuccess =
      transactionSuccess && balanceSuccess && recurringSuccess && statementSuccess

    if overallSuccess {
      // Record the month BEFORE any alert so this month's setup prompts are retired even when the
      // caller passes showAlert: false. Nothing wrote this key before, so
      // areNotificationsScheduledForCurrentMonth() was permanently false.
      markCurrentMonthAsScheduled()

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

  /// Verifica se as notificações do mês foram configuradas.
  ///
  /// Derived from the recorded month rather than from the pending-request list. Inspecting pending
  /// requests could never answer the question: it only recognised `UNCalendarNotificationTrigger`,
  /// while every transaction, installment and recurring notification uses
  /// `UNTimeIntervalNotificationTrigger` — so a fully configured month reported `.outdated`, and a
  /// month with no upcoming transactions at all reported `.notConfigured` forever.
  func checkMonthlyNotificationsStatus() -> MonthlyNotificationStatus {
    guard let stored = UserDefaults.standard.string(forKey: Self.lastScheduledMonthDefaultsKey)
    else {
      return .notConfigured
    }
    return stored == Self.monthKey(for: Date()) ? .configured : .outdated
  }

  /// Verifica se as notificações já foram agendadas para o mês atual
  func areNotificationsScheduledForCurrentMonth() -> Bool {
    return UserDefaults.standard.string(forKey: Self.lastScheduledMonthDefaultsKey)
      == Self.monthKey(for: Date())
  }

  /// Records the current month as configured and retires its setup prompts.
  func markCurrentMonthAsScheduled() {
    markMonthAsScheduled(Date())
  }

  // MARK: - Month Keys

  /// `"<year>-<month>"` — the identity used both for the UserDefaults marker and for the
  /// setup-prompt notification identifiers, so the two can never drift apart.
  static func monthKey(for date: Date) -> String {
    let calendar = Calendar.current
    let month = calendar.component(.month, from: date)
    let year = calendar.component(.year, from: date)
    return "\(year)-\(month)"
  }

  private func markMonthAsScheduled(_ date: Date) {
    let key = Self.monthKey(for: date)
    UserDefaults.standard.set(key, forKey: Self.lastScheduledMonthDefaultsKey)
    // This month no longer needs nagging.
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: ["\(Self.reminderPrefix)\(key)", "\(Self.fallbackPrefix)\(key)"])
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

    scheduleSetupPrompt(
      targetDate: targetDate,
      hour: 8,
      identifierPrefix: Self.reminderPrefix,
      titleKey: "notification.monthly.reminder.title",
      bodyKey: "notification.monthly.reminder.body",
      categoryIdentifier: "MONTHLY_REMINDER",
      type: "monthly_reminder")
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

    scheduleSetupPrompt(
      targetDate: targetDate,
      hour: 10,  // 10h para não conflitar com a de 8h
      identifierPrefix: Self.fallbackPrefix,
      titleKey: "notification.monthly.fallback.title",
      bodyKey: "notification.monthly.fallback.body",
      categoryIdentifier: "MONTHLY_FALLBACK",
      type: "monthly_fallback")
  }

  /// Schedules one of the "open the app to configure notifications" prompts for the month containing
  /// `targetDate`, unless that month has already been configured.
  private func scheduleSetupPrompt(
    targetDate: Date,
    hour: Int,
    identifierPrefix: String,
    titleKey: String,
    bodyKey: String,
    categoryIdentifier: String,
    type: String
  ) {
    let monthKey = Self.monthKey(for: targetDate)

    // Nothing to nag about — this is the fix for the fallback that kept arriving on the 3rd after a
    // successful setup on the 1st.
    let storedKey = UserDefaults.standard.string(forKey: Self.lastScheduledMonthDefaultsKey)
    guard storedKey != monthKey else {
      notificationCenter.removePendingNotificationRequests(
        withIdentifiers: ["\(identifierPrefix)\(monthKey)"])
      return
    }

    guard !preferencesManager.allNotificationsDisabled else { return }

    var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
    dateComponents.hour = hour
    dateComponents.minute = 0
    dateComponents.second = 0

    guard let fireDate = calendar.date(from: dateComponents), fireDate > Date() else { return }

    let content = UNMutableNotificationContent()
    content.title = titleKey.localized
    content.body = bodyKey.localized
    content.sound = .default
    content.categoryIdentifier = categoryIdentifier
    content.userInfo = ["type": type, "monthKey": monthKey]

    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
    // Month-keyed identifier: re-running setup on a later launch replaces the request instead of
    // stacking a second copy under a new timestamp-based ID.
    let request = UNNotificationRequest(
      identifier: "\(identifierPrefix)\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling \(type): \(error)")
      }
    }
  }

  /// Limpa notificações mensais existentes, retornando somente depois que a remoção foi aplicada.
  private func clearExistingMonthlyNotificationsAndWait() {
    let semaphore = DispatchSemaphore(value: 0)

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
      semaphore.signal()
    }

    semaphore.wait()
  }

  /// Agenda notificações de transações
  private func scheduleTransactionNotifications() -> Bool {
    // Usar lógica existente do AppDelegate
    let allTxs = transactionRepo.fetchAllTransactions()
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    let futureTxs = allTxs.filter { tx in
      // Skip parent transactions that are not visible in UI
      if tx.hasInstallments == true && tx.amount == 0 {
        return false
      }
      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 {
        return false
      }

      // Create notification time (8 AM) in local timezone
      var notificationDate = calendar.startOfDay(for: tx.date)
      notificationDate =
        calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

      return notificationDate > now
    }

    // Sort by date to prioritize closest transactions first
    let sortedTxs = futureTxs.sorted { tx1, tx2 in
      tx1.date < tx2.date
    }

    // Prioritize transactions in the next 30 days
    let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
    let next30DaysTxs = sortedTxs.filter { tx in
      tx.date <= thirtyDaysFromNow
    }
    let remainingTxs = sortedTxs.filter { tx in
      tx.date > thirtyDaysFromNow
    }

    // Combine arrays: prioritize next 30 days, then remaining sorted by date
    let prioritizedTxs = next30DaysTxs + remainingTxs

    let limitedTxs = Array(prioritizedTxs.prefix(30))  // Limitar a 30 para o mês

    limitedTxs.forEach { tx in
      scheduleTransactionNotification(for: tx, calendar: calendar)
    }

    return true
  }

  /// Agenda notificação individual de transação
  private func scheduleTransactionNotification(for tx: Transaction, calendar: Calendar) {
    guard let transactionId = tx.id else { return }

    let id = "transaction_\(transactionId)"

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else { return }

    // Verificar se a data é muito no futuro (mais de 1 ano)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if tx.date > oneYearFromNow {
      return
    }

    // Calculate time interval from now to notification date
    let timeInterval = notificationDate.timeIntervalSinceNow

    // Verificar se o intervalo é muito grande (mais de 30 dias)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      return
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

    let titleKey =
      tx.type == .income
      ? "notification.transaction.title.income" : "notification.transaction.title.expense"
    let bodyKey =
      tx.type == .income
      ? "notification.transaction.body.income" : "notification.transaction.body.expense"

    let amountString = tx.amount.currencyString
    let title = titleKey.localized
    let body = String(format: bodyKey.localized, amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["transactionId": transactionId, "date": tx.date.timeIntervalSince1970]

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling transaction notification: \(error)")
      }
    }
  }

  /// Agenda notificações de saldo negativo
  private func scheduleBalanceNotifications() -> Bool {
    BalanceMonitorManager.shared.monitorCurrentMonthBalance()
    return true
  }

  /// Agenda notificações de transações recorrentes/parceladas.
  ///
  /// `clearExistingMonthlyNotificationsAndWait` wipes every `recurring_*` and `installment_*`
  /// request, so these have to be rebuilt here — this was previously a `return true` stub, which
  /// meant the first app open of each month silently destroyed all installment and recurring
  /// reminders and never put them back.
  private func scheduleRecurringNotifications() -> Bool {
    guard preferencesManager.transactionNotificationsEnabled else { return true }

    let all = transactionRepo.fetchAllTransactions()

    let recurringParentIds = Set(
      all.filter { $0.isRecurring == true && $0.parentTransactionId == nil }.compactMap { $0.id })
    let installmentParentIds = Set(
      all.filter { $0.hasInstallments == true && $0.parentTransactionId == nil }.compactMap { $0.id }
    )

    // Handed over in ONE call per kind rather than per parent: these notifications are keyed by month
    // (`recurring_month_2026-9`) and consolidate every row falling in that month, so scheduling
    // parent-by-parent would have each parent overwrite the shared month reminder the previous one
    // wrote, leaving only the last parent's total in it.
    let recurringInstances = all.filter { tx in
      guard let parentId = tx.parentTransactionId else { return false }
      return recurringParentIds.contains(parentId) && tx.id != parentId
    }
    let installmentChildren = all.filter { tx in
      guard let parentId = tx.parentTransactionId else { return false }
      return installmentParentIds.contains(parentId)
    }

    SeriesNotificationScheduler.schedule(
      recurringInstances.map(Self.notificationModel), kind: .recurring)
    SeriesNotificationScheduler.schedule(
      installmentChildren.map(Self.notificationModel), kind: .installment)

    return true
  }

  /// Agenda notificações de fatura de cartão de crédito.
  private func scheduleStatementNotifications() -> Bool {
    guard preferencesManager.shouldShowNotification(type: .creditCardStatement) else { return true }
    StatementNotificationManager.shared.rescheduleAllNotifications()
    return true
  }

  private static func notificationModel(for tx: Transaction) -> TransactionModel {
    TransactionModel(
      id: tx.id,
      title: tx.title,
      category: tx.category.key,
      amount: tx.amount,
      type: tx.type.key,
      dateTimestamp: tx.dateTimestamp,
      budgetMonthDate: tx.budgetMonthDate,
      parentTransactionId: tx.parentTransactionId,
      originalAmount: tx.originalAmount,
      installmentNumber: tx.installmentNumber,
      totalInstallments: tx.totalInstallments
    )
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
