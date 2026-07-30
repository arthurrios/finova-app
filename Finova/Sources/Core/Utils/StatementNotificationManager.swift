//
//  StatementNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 25/03/26.
//

import Foundation
import UserNotifications

/// Single source of truth for all `statement_due_<id>` and `statement_pay_<id>` notifications.
final class StatementNotificationManager {
  static let shared = StatementNotificationManager()

  private let notificationCenter = UNUserNotificationCenter.current()
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal
  }()

  private init() {}

  // MARK: - Bulk Scheduling

  /// Schedules due-soon and payment-due notifications for all unpaid statements.
  func scheduleAllStatementNotifications() {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .creditCardStatement) else { return }

    guard let user = UserDefaultsManager.getUser(),
          let firebaseUID = user.firebaseUID else { return }

    let cardRepo = CreditCardRepository()
    let statementRepo = StatementRepository()
    let cards = cardRepo.fetchAllCards(userId: firebaseUID)
    let now = Date()

    // Remove old statement notifications first
    notificationCenter.getPendingNotificationRequests { [weak self] requests in
      guard let self = self else { return }
      let statementIds = requests
        .filter { $0.identifier.hasPrefix("statement_due_") || $0.identifier.hasPrefix("statement_pay_") }
        .map { $0.identifier }
      self.notificationCenter.removePendingNotificationRequests(withIdentifiers: statementIds)
    }

    for card in cards where !card.isDeleted {
      guard let cardId = card.id else { continue }
      let statements = statementRepo.fetchStatements(forCardId: cardId)

      for statement in statements {
        guard !statement.isPaid, let statementId = statement.id else { continue }
        scheduleNotificationPair(statementId: statementId, cardId: cardId, cardName: card.name, dueDate: statement.dueDate, totalAmount: statement.totalAmount, now: now)
      }
    }
  }

  // MARK: - Single Statement

  /// Schedules notifications for a single statement.
  func scheduleNotification(for statement: CreditCardStatement, card: CreditCard) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .creditCardStatement) else { return }
    guard !statement.isPaid, let statementId = statement.id, let cardId = card.id else { return }
    scheduleNotificationPair(statementId: statementId, cardId: cardId, cardName: card.name, dueDate: statement.dueDate, totalAmount: statement.totalAmount, now: Date())
  }

  /// Reschedules all statement notifications (cancels existing, then re-fetches from DB).
  func rescheduleAllNotifications() {
    cancelAllStatementNotifications()
    scheduleAllStatementNotifications()
  }

  // MARK: - Cancel

  /// Cancels both due-soon and payment-due notifications for a given statement.
  func cancelNotifications(for statementId: Int) {
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: ["statement_due_\(statementId)", "statement_pay_\(statementId)"]
    )
  }

  /// Cancels all statement notifications.
  func cancelAllStatementNotifications() {
    notificationCenter.getPendingNotificationRequests { [weak self] requests in
      let ids = requests
        .filter { $0.identifier.hasPrefix("statement_due_") || $0.identifier.hasPrefix("statement_pay_") }
        .map { $0.identifier }
      self?.notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }
  }

  // MARK: - Private

  private func scheduleNotificationPair(statementId: Int, cardId: Int, cardName: String, dueDate: Date, totalAmount: Int, now: Date) {
    guard dueDate > now else { return }

    let amountString = totalAmount.currencyString
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60

    // Due-soon notification (3 days before due date, at 9 AM)
    if let threeDaysBefore = calendar.date(byAdding: .day, value: -3, to: dueDate) {
      var dueSoonDate = calendar.startOfDay(for: threeDaysBefore)
      dueSoonDate = calendar.date(byAdding: .hour, value: 9, to: dueSoonDate) ?? dueSoonDate

      if dueSoonDate > now {
        let timeInterval = dueSoonDate.timeIntervalSinceNow
        if timeInterval <= thirtyDaysInSeconds {
          let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

          let content = UNMutableNotificationContent()
          content.title = "notification.statement.dueSoon.title".localized
          content.body = String(format: "notification.statement.dueSoon.body".localized, cardName, amountString)
          content.sound = .default
          content.userInfo = [
            "type": "credit_card_statement",
            "statementId": statementId,
            "cardId": cardId,
          ]

          let request = UNNotificationRequest(
            identifier: "statement_due_\(statementId)", content: content, trigger: trigger)
          notificationCenter.add(request) { error in
            if let error = error {
              logError("Error scheduling due-soon notification: \(error)")
            }
          }
        }
      }
    }

    // Payment reminder (on due date, at 9 AM)
    var paymentDate = calendar.startOfDay(for: dueDate)
    paymentDate = calendar.date(byAdding: .hour, value: 9, to: paymentDate) ?? paymentDate

    if paymentDate > now {
      let timeInterval = paymentDate.timeIntervalSinceNow
      if timeInterval <= thirtyDaysInSeconds {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "notification.statement.paymentDue.title".localized
        content.body = String(format: "notification.statement.paymentDue.body".localized, cardName, amountString)
        content.sound = .default
        content.userInfo = [
          "type": "credit_card_statement",
          "statementId": statementId,
          "cardId": cardId,
        ]

        let request = UNNotificationRequest(
          identifier: "statement_pay_\(statementId)", content: content, trigger: trigger)
        notificationCenter.add(request) { error in
          if let error = error {
            logError("Error scheduling payment-due notification: \(error)")
          }
        }
      }
    }
  }
}
