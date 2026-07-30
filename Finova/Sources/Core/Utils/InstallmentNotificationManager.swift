//
//  InstallmentNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 25/03/26.
//

import Foundation
import UserNotifications

/// Single source of truth for all `installment_month_<key>` and `installment_reminder_<key>` notifications.
final class InstallmentNotificationManager {
  static let shared = InstallmentNotificationManager()

  private let notificationCenter = UNUserNotificationCenter.current()
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal
  }()

  private init() {}

  // MARK: - Schedule

  /// Groups installments by month and schedules one consolidated notification per month.
  func scheduleNotifications(for installments: [TransactionModel]) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .transaction) else { return }

    var installmentsByMonth: [String: [TransactionModel]] = [:]

    for installment in installments {
      let date = Date(timeIntervalSince1970: TimeInterval(installment.data.dateTimestamp))
      let monthKey = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
      installmentsByMonth[monthKey, default: []].append(installment)
    }

    for (monthKey, monthInstallments) in installmentsByMonth {
      scheduleMonthlyInstallmentNotification(monthKey: monthKey, installments: monthInstallments)
    }
  }

  /// Fetches fresh installment data from DB and reschedules notifications for a parent transaction.
  func rescheduleNotifications(parentTransactionId: Int) {
    cancelNotifications(forParent: parentTransactionId)

    let repo = TransactionRepository()
    let children = repo.fetchInstallmentTransactions(parentId: parentTransactionId)

    let models = children.map { tx in
      TransactionModel(
        id: tx.id,
        title: tx.title,
        category: tx.category.key,
        amount: tx.amount,
        type: String(describing: tx.type),
        dateTimestamp: tx.dateTimestamp,
        budgetMonthDate: tx.budgetMonthDate,
        parentTransactionId: tx.parentTransactionId,
        originalAmount: tx.originalAmount,
        installmentNumber: tx.installmentNumber,
        totalInstallments: tx.totalInstallments
      )
    }

    scheduleNotifications(for: models)
  }

  // MARK: - Cancel

  /// Cancels all installment notifications for a given parent transaction.
  func cancelNotifications(forParent parentTransactionId: Int) {
    let repo = TransactionRepository()
    let children = repo.fetchInstallmentTransactions(parentId: parentTransactionId)

    // Build the set of month keys used by these installments
    var monthKeys = Set<String>()
    for tx in children {
      let date = tx.date
      let monthKey = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
      monthKeys.insert(monthKey)
    }

    let identifiers = monthKeys.flatMap { key in
      ["installment_month_\(key)", "installment_reminder_\(key)"]
    }

    if !identifiers.isEmpty {
      notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
  }

  /// Cancels a single month-key notification pair.
  func cancelNotification(forMonthKey monthKey: String) {
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: ["installment_month_\(monthKey)", "installment_reminder_\(monthKey)"]
    )
  }

  // MARK: - Private

  private func scheduleMonthlyInstallmentNotification(monthKey: String, installments: [TransactionModel]) {
    guard let firstInstallment = installments.first else { return }

    let date = Date(timeIntervalSince1970: TimeInterval(firstInstallment.data.dateTimestamp))

    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow { return }

    var notificationDate = calendar.startOfDay(for: date)
    notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    guard notificationDate > Date() else { return }

    let timeInterval = notificationDate.timeIntervalSinceNow
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      scheduleReminderNotification(for: monthKey, installments: installments)
      return
    }

    let totalAmount = installments.reduce(0) { $0 + $1.data.amount }
    let installmentCount = installments.count

    let title = "notification.installment.title".localized
    let bodyKey = installmentCount == 1
      ? "notification.installment.body.singular"
      : "notification.installment.body.plural"
    let body = installmentCount == 1
      ? String(format: bodyKey.localized, totalAmount.currencyString)
      : String(format: bodyKey.localized, installmentCount, totalAmount.currencyString)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = [
      "type": "installment_month",
      "monthKey": monthKey,
      "installmentCount": installmentCount,
      "totalAmount": totalAmount,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(
      identifier: "installment_month_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling installment notification for month \(monthKey): \(error)")
      }
    }
  }

  private func scheduleReminderNotification(for monthKey: String, installments: [TransactionModel]) {
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: thirtyDaysInSeconds, repeats: false)

    let content = UNMutableNotificationContent()
    content.title = "notification.installment.reminder.title".localized
    content.body = "notification.installment.reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["type": "installment_reminder", "monthKey": monthKey]

    let request = UNNotificationRequest(
      identifier: "installment_reminder_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling installment reminder for month \(monthKey): \(error)")
      }
    }
  }
}
