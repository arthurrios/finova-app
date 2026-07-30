//
//  RecurringNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 25/03/26.
//

import Foundation
import UserNotifications

/// Single source of truth for all `recurring_month_<key>` and `recurring_reminder_<key>` notifications.
final class RecurringNotificationManager {
  static let shared = RecurringNotificationManager()

  private let notificationCenter = UNUserNotificationCenter.current()
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal
  }()

  private init() {}

  // MARK: - Schedule

  /// Groups recurring instances by month and schedules one consolidated notification per month.
  func scheduleNotifications(for instances: [TransactionModel]) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .transaction) else { return }

    var instancesByMonth: [String: [TransactionModel]] = [:]

    for instance in instances {
      let date = Date(timeIntervalSince1970: TimeInterval(instance.data.dateTimestamp))
      let monthKey = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
      instancesByMonth[monthKey, default: []].append(instance)
    }

    for (monthKey, monthInstances) in instancesByMonth {
      scheduleMonthlyRecurringNotification(monthKey: monthKey, instances: monthInstances)
    }
  }

  /// Fetches fresh recurring instance data from DB and reschedules notifications.
  func rescheduleNotifications(parentTransactionId: Int) {
    cancelNotifications(forParent: parentTransactionId)

    let repo = TransactionRepository()
    let children = repo.fetchTransactionInstancesForRecurring(parentTransactionId)

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

  /// Cancels all recurring notifications for a given parent transaction.
  func cancelNotifications(forParent parentTransactionId: Int) {
    let repo = TransactionRepository()
    let children = repo.fetchTransactionInstancesForRecurring(parentTransactionId)

    var monthKeys = Set<String>()
    for tx in children {
      let date = tx.date
      let monthKey = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
      monthKeys.insert(monthKey)
    }

    let identifiers = monthKeys.flatMap { key in
      ["recurring_month_\(key)", "recurring_reminder_\(key)"]
    }

    if !identifiers.isEmpty {
      notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
  }

  /// Cancels a single month-key notification pair.
  func cancelNotification(forMonthKey monthKey: String) {
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: ["recurring_month_\(monthKey)", "recurring_reminder_\(monthKey)"]
    )
  }

  // MARK: - Private

  private func scheduleMonthlyRecurringNotification(monthKey: String, instances: [TransactionModel]) {
    guard let firstInstance = instances.first else { return }

    let date = Date(timeIntervalSince1970: TimeInterval(firstInstance.data.dateTimestamp))

    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow { return }

    var notificationDate = calendar.startOfDay(for: date)
    notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    guard notificationDate > Date() else { return }

    let timeInterval = notificationDate.timeIntervalSinceNow
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      scheduleRecurringReminderNotification(for: monthKey, instances: instances)
      return
    }

    let totalAmount = instances.reduce(0) { $0 + $1.data.amount }
    let instanceCount = instances.count

    let title = "notification.recurring.title".localized
    let bodyKey = instanceCount == 1
      ? "notification.recurring.body.singular"
      : "notification.recurring.body.plural"
    let body = instanceCount == 1
      ? String(format: bodyKey.localized, totalAmount.currencyString)
      : String(format: bodyKey.localized, instanceCount, totalAmount.currencyString)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = [
      "type": "recurring_month",
      "monthKey": monthKey,
      "instanceCount": instanceCount,
      "totalAmount": totalAmount,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(
      identifier: "recurring_month_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling recurring notification for month \(monthKey): \(error)")
      }
    }
  }

  private func scheduleRecurringReminderNotification(for monthKey: String, instances: [TransactionModel]) {
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: thirtyDaysInSeconds, repeats: false)

    let content = UNMutableNotificationContent()
    content.title = "notification.recurring.reminder.title".localized
    content.body = "notification.recurring.reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["type": "recurring_reminder", "monthKey": monthKey]

    let request = UNNotificationRequest(
      identifier: "recurring_reminder_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling recurring reminder for month \(monthKey): \(error)")
      }
    }
  }
}
