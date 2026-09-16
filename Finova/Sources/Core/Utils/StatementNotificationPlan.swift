//
//  StatementNotificationPlan.swift
//  Finova
//
//  What a statement should tell the user, and when — worked out as plain values so it can be
//  checked without a notification centre.
//

import Foundation

/// One notification a statement wants, already resolved to a fire date and an amount.
struct PlannedStatementNotification: Equatable {
  enum Kind: String {
    /// The cycle has closed. This is the figure the user actually owes.
    case closed
    /// Due today.
    case paymentDue

    var identifierPrefix: String {
      switch self {
      case .closed: return "statement_closed_"
      case .paymentDue: return "statement_pay_"
      }
    }

    var titleKey: String {
      switch self {
      case .closed: return "notification.statement.closed.title"
      case .paymentDue: return "notification.statement.paymentDue.title"
      }
    }

    var bodyKey: String {
      switch self {
      case .closed: return "notification.statement.closed.body"
      case .paymentDue: return "notification.statement.paymentDue.body"
      }
    }
  }

  let kind: Kind
  let identifier: String
  let fireDate: Date
  /// Minor units, straight from the statement row. Read at plan time, never cached from an
  /// earlier one — the amount is the whole point of the message.
  let amountMinor: Int
  let cardName: String
}

/// Decides which notifications a statement gets. Pure: same inputs, same answer, no side effects.
enum StatementNotificationPlan {
  /// iOS keeps at most 64 pending requests per app, so nothing further out than this is worth a
  /// slot. `MonthlyNotificationManager` re-runs the whole plan, which is what brings later
  /// statements in as they come into range.
  static let horizon: TimeInterval = 30 * 24 * 60 * 60

  /// Notifications fire at 9 AM local time on their day.
  static let hourOfDay = 9

  static func identifiers(for statementId: Int) -> [String] {
    // "statement_due_" is the old due-soon reminder, dropped in favour of a notification on the
    // closing day. Still swept so an app updating from an older build does not keep firing it.
    ["statement_closed_\(statementId)", "statement_pay_\(statementId)", "statement_due_\(statementId)"]
  }

  static func isStatementIdentifier(_ identifier: String) -> Bool {
    identifiers(for: 0).contains { identifier.hasPrefix(String($0.dropLast())) }
  }

  /// The notifications this statement should have right now.
  ///
  /// A paid statement plans nothing: it is settled, and a reminder for it would name money the
  /// user no longer owes. That is also what makes marking one paid enough to silence it — the
  /// next reschedule simply stops planning for it.
  static func plan(
    statementId: Int,
    cardName: String,
    closingDate: Date,
    dueDate: Date,
    totalAmount: Int,
    isPaid: Bool,
    calendar: Calendar,
    now: Date
  ) -> [PlannedStatementNotification] {
    guard !isPaid else { return [] }
    // Nothing left to pay. The row can sit unpaid at zero between the last credit being booked and
    // the invoice being flagged, and "your statement of R$ 0,00 is due today" is exactly the wrong
    // message to send in that window.
    guard totalAmount > 0 else { return [] }

    var planned: [PlannedStatementNotification] = []

    for (kind, day) in [(PlannedStatementNotification.Kind.closed, closingDate),
                        (PlannedStatementNotification.Kind.paymentDue, dueDate)] {
      guard let fireDate = fireDate(on: day, calendar: calendar) else { continue }
      guard fireDate > now else { continue }
      guard fireDate.timeIntervalSince(now) <= horizon else { continue }

      planned.append(
        PlannedStatementNotification(
          kind: kind,
          identifier: "\(kind.identifierPrefix)\(statementId)",
          fireDate: fireDate,
          amountMinor: totalAmount,
          cardName: cardName))
    }

    return planned
  }

  static func fireDate(on day: Date, calendar: Calendar) -> Date? {
    calendar.date(byAdding: .hour, value: hourOfDay, to: calendar.startOfDay(for: day))
  }
}
