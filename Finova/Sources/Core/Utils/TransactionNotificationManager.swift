//
//  TransactionNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 25/03/26.
//

import Foundation
import UserNotifications

/// Single source of truth for all `transaction_<id>` notifications (one-off transactions).
final class TransactionNotificationManager {
  static let shared = TransactionNotificationManager()

  private let notificationCenter = UNUserNotificationCenter.current()
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal
  }()

  private init() {}

  // MARK: - Schedule for a Transaction object

  /// Schedules a notification for a `Transaction` (domain model).
  func scheduleNotification(for tx: Transaction) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .transaction) else { return }
    guard let transactionId = tx.id else { return }

    let id = "transaction_\(transactionId)"

    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    guard notificationDate > Date() else { return }

    let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if tx.date > oneYearFromNow { return }

    let timeInterval = notificationDate.timeIntervalSinceNow
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds { return }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

    let titleKey = tx.type == .income
      ? "notification.transaction.title.income"
      : "notification.transaction.title.expense"
    let bodyKey = tx.type == .income
      ? "notification.transaction.body.income"
      : "notification.transaction.body.expense"

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
        logError("Error scheduling notification for \(tx.title): \(error)")
      }
    }
  }

  // MARK: - Schedule for a TransactionModel (at creation time)

  /// Schedules a notification for a newly-created transaction using its raw model data.
  func scheduleNotification(transactionId: Int, model: TransactionModel) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .transaction) else { return }

    notificationCenter.getNotificationSettings { [weak self] settings in
      guard settings.authorizationStatus == .authorized else { return }
      DispatchQueue.main.async {
        self?.doScheduleNotification(transactionId: transactionId, model: model)
      }
    }
  }

  private func doScheduleNotification(transactionId: Int, model: TransactionModel) {
    let date = Date(timeIntervalSince1970: TimeInterval(model.data.dateTimestamp))

    let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow { return }

    var notificationDate = calendar.startOfDay(for: date)
    notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    guard notificationDate > Date() else { return }

    let dayIdentifier = "day_\(calendar.startOfDay(for: date).timeIntervalSince1970)"
    notificationCenter.removePendingNotificationRequests(withIdentifiers: [dayIdentifier])

    let id = "transaction_\(transactionId)"
    let timeInterval = notificationDate.timeIntervalSinceNow

    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: thirtyDaysInSeconds, repeats: false)
      let content = UNMutableNotificationContent()
      content.title = "notification.transaction.reminder.title".localized
      content.body = "notification.transaction.reminder.body".localized
      content.sound = .default
      content.categoryIdentifier = "TRANSACTION_REMINDER"
      content.userInfo = ["type": "reminder", "transactionId": transactionId]
      let request = UNNotificationRequest(identifier: dayIdentifier, content: content, trigger: trigger)
      notificationCenter.add(request) { error in
        if let error = error {
          logError("Error scheduling reminder notification: \(error)")
        }
      }
      return
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

    let titleKey = model.data.type == "income"
      ? "notification.transaction.title.income"
      : "notification.transaction.title.expense"
    let bodyKey = model.data.type == "income"
      ? "notification.transaction.body.income"
      : "notification.transaction.body.expense"

    let amountString = model.data.amount.currencyString
    let title = titleKey.localized
    let body = bodyKey.localized(amountString, model.data.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["transactionId": transactionId, "date": date.timeIntervalSince1970]

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling notification for \(model.data.title): \(error)")
      }
    }
  }

  // MARK: - Reschedule / Cancel

  /// Removes the existing notification for a transaction and re-schedules it from fresh DB data.
  func rescheduleNotification(for transactionId: Int) {
    let notificationId = "transaction_\(transactionId)"
    notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])

    let repo = TransactionRepository()
    guard let tx = repo.fetchTransaction(byId: transactionId) else { return }
    scheduleNotification(for: tx)
  }

  /// Cancels any pending notification for the given transaction ID.
  func cancelNotification(for transactionId: Int) {
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: ["transaction_\(transactionId)"]
    )
  }

  // MARK: - Bulk Scheduling

  /// Schedules notifications for a batch of transactions, optionally clearing existing ones first.
  /// - Parameters:
  ///   - transactions: All transactions to consider.
  ///   - clearExisting: If `true`, removes all pending notification requests before scheduling.
  ///   - limit: Maximum number of notifications to schedule (iOS caps at 64).
  func scheduleAllTransactionNotifications(
    transactions: [Transaction],
    clearExisting: Bool = true,
    limit: Int = 50
  ) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .transaction) else { return }

    let now = Date()

    if clearExisting {
      notificationCenter.removeAllPendingNotificationRequests()
    }

    let futureTxs = transactions.filter { tx in
      if tx.hasInstallments == true && tx.amount == 0 { return false }
      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 { return false }
      if tx.creditCardId != nil { return false }

      var notificationDate = calendar.startOfDay(for: tx.date)
      notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate
      return notificationDate > now
    }

    let sortedTxs = futureTxs.sorted { $0.date < $1.date }
    let limitedTxs = Array(sortedTxs.prefix(limit))

    limitedTxs.forEach { tx in
      scheduleNotification(for: tx)
    }
  }

  /// Re-schedules notifications for transactions between 30-60 days away that may now be schedulable.
  func rescheduleNearbyTransactions(transactions: [Transaction]) {
    let now = Date()
    let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
    let sixtyDaysFromNow = calendar.date(byAdding: .day, value: 60, to: now) ?? now

    let nearbyTxs = transactions.filter { tx in
      if tx.hasInstallments == true && tx.amount == 0 { return false }
      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 { return false }
      return tx.date >= thirtyDaysFromNow && tx.date <= sixtyDaysFromNow
    }

    nearbyTxs.forEach { tx in
      scheduleNotification(for: tx)
    }
  }
}
