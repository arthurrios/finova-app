//
//  StatementNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 25/03/26.
//

import Foundation
import UserNotifications

/// Single source of truth for all `statement_closed_<id>` and `statement_pay_<id>` notifications.
final class StatementNotificationManager {
  static let shared = StatementNotificationManager()

  private let notificationCenter = UNUserNotificationCenter.current()
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal
  }()

  /// Serialises the coalesced full reschedules — see `rescheduleAllNotifications`.
  private let rescheduleQueue = DispatchQueue(label: "com.finova.statementNotifications")
  private var rescheduleWorkItem: DispatchWorkItem?

  private init() {}

  // MARK: - Bulk Scheduling

  /// Schedules due-soon and payment-due notifications for all unpaid statements.
  ///
  /// The stale-notification sweep and the re-scheduling MUST happen in this order and without
  /// interleaving. They used to race: `getPendingNotificationRequests` is asynchronous, so its
  /// removal block — carrying identifiers such as `statement_due_7` — landed *after* the loop below
  /// had already re-added `statement_due_7`, deleting the notification that had just been created.
  /// That is why statement reminders went missing for cards that already had them.
  func scheduleAllStatementNotifications() {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .creditCardStatement) else { return }

    guard let user = UserDefaultsManager.getUser(),
          let firebaseUID = user.firebaseUID else { return }

    notificationCenter.getPendingNotificationRequests { [weak self] requests in
      guard let self = self else { return }
      let staleIds = requests
        .filter { Self.isStatementIdentifier($0.identifier) }
        .map { $0.identifier }
      if !staleIds.isEmpty {
        self.notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIds)
      }
      self.scheduleUnpaidStatements(userId: firebaseUID)
    }
  }

  /// Reads every unpaid statement from the DB and schedules its notification pair.
  private func scheduleUnpaidStatements(userId: String) {
    let cardRepo = CreditCardRepository()
    let statementRepo = StatementRepository()
    let cards = cardRepo.fetchAllCards(userId: userId)
    let now = Date()

    for card in cards where !card.isDeleted {
      guard let cardId = card.id else { continue }
      let statements = statementRepo.fetchStatements(forCardId: cardId)
      let charges = Self.charges(of: statements)

      for statement in statements {
        guard let statementId = statement.id else { continue }
        scheduleStatement(
          statement, statementId: statementId, cardId: cardId, cardName: card.name,
          amount: charges[statementId] ?? statement.totalAmount, now: now)
      }
    }
  }

  // MARK: - Single Statement

  /// Schedules notifications for a single statement.
  func scheduleNotification(for statement: CreditCardStatement, card: CreditCard) {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .creditCardStatement) else { return }
    guard let statementId = statement.id, let cardId = card.id else { return }
    let charges = Self.charges(of: StatementRepository().fetchStatements(forCardId: cardId))
    scheduleStatement(
      statement, statementId: statementId, cardId: cardId, cardName: card.name,
      amount: charges[statementId] ?? statement.totalAmount, now: Date())
  }

  /// What each statement charges once credit carried from the card's earlier statements is counted
  /// in, the amount its dashboard row shows. A statement that credit covers gets no reminder.
  private static func charges(of statements: [CreditCardStatement]) -> [Int: Int] {
    CreditCardService.statementCharges(statements) { $0.totalAmount }.mapValues { $0.charged }
  }

  /// Reschedules all statement notifications (cancels existing, then re-fetches from DB).
  ///
  /// `scheduleAllStatementNotifications` already sweeps the stale requests inside the same
  /// completion block, so it does the whole job. Calling `cancelAllStatementNotifications` first
  /// added a *second* asynchronous removal that could land after the new requests were created.
  ///
  /// Coalesced, because callers arrive in bursts: deleting a series recalculates one statement per
  /// affected month, and each recalculation asks for a reschedule. One full sweep covers them all.
  func rescheduleAllNotifications() {
    rescheduleQueue.async { [weak self] in
      guard let self = self else { return }
      self.rescheduleWorkItem?.cancel()
      let item = DispatchWorkItem { [weak self] in
        self?.scheduleAllStatementNotifications()
      }
      self.rescheduleWorkItem = item
      self.rescheduleQueue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
  }

  // MARK: - Cancel

  /// Cancels both due-soon and payment-due notifications for a given statement.
  func cancelNotifications(for statementId: Int) {
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: StatementNotificationPlan.identifiers(for: statementId)
    )
  }

  /// Cancels all statement notifications.
  func cancelAllStatementNotifications() {
    notificationCenter.getPendingNotificationRequests { [weak self] requests in
      let ids = requests
        .filter { Self.isStatementIdentifier($0.identifier) }
        .map { $0.identifier }
      self?.notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }
  }

  // MARK: - Private

  private func scheduleStatement(
    _ statement: CreditCardStatement, statementId: Int, cardId: Int, cardName: String,
    amount: Int, now: Date
  ) {
    let planned = StatementNotificationPlan.plan(
      statementId: statementId,
      cardName: cardName,
      closingDate: statement.closingDate,
      dueDate: statement.dueDate,
      totalAmount: amount,
      isPaid: statement.isPaid,
      calendar: calendar,
      now: now)
    schedule(planned, statementId: statementId, cardId: cardId, now: now)
  }

  private static func isStatementIdentifier(_ identifier: String) -> Bool {
    StatementNotificationPlan.isStatementIdentifier(identifier)
  }

  /// Turns the plan into real requests. Every field the user reads comes from the plan, which was
  /// built from the statement row a moment ago — so the amount in the message is the amount in the
  /// ledger, not one captured when the notification was first scheduled.
  private func schedule(_ planned: [PlannedStatementNotification], statementId: Int, cardId: Int, now: Date) {
    for item in planned {
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: item.fireDate.timeIntervalSince(now), repeats: false)

      let content = UNMutableNotificationContent()
      content.title = item.kind.titleKey.localized
      content.body = String(
        format: item.kind.bodyKey.localized, item.cardName, item.amountMinor.currencyString)
      content.sound = .default
      content.userInfo = [
        "type": "credit_card_statement",
        "statementId": statementId,
        "cardId": cardId,
      ]

      let request = UNNotificationRequest(
        identifier: item.identifier, content: content, trigger: trigger)
      notificationCenter.add(request) { error in
        if let error = error {
          logError("Error scheduling \(item.kind.rawValue) statement notification: \(error)")
        }
      }
    }
  }
}
