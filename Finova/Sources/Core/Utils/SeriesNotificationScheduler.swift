//
//  SeriesNotificationScheduler.swift
//  Finova
//
//  One reminder per month per series kind, rather than one per row.
//

import Foundation
import UserNotifications

/// Schedules the consolidated month reminders for installment and recurring series.
///
/// Both kinds had a byte-identical copy of this logic — one private inside
/// `AddTransactionModalViewModel`, one private inside `RecurringTransactionManager` — which is why
/// `MonthlyNotificationManager` could not rebuild them after its monthly sweep and shipped a
/// `return true` stub instead. Having a single owner is what makes that rebuild possible.
///
/// A month gets ONE notification carrying the month's count and total, keyed `<kind>_month_<monthKey>`
/// so rescheduling replaces it rather than stacking duplicates.
enum SeriesNotificationScheduler {

  /// The two series kinds, differing only in their identifiers and copy.
  enum Kind {
    case installment
    case recurring

    var monthIdentifierPrefix: String {
      switch self {
      case .installment: return "installment_month_"
      case .recurring: return "recurring_month_"
      }
    }

    var reminderIdentifierPrefix: String {
      switch self {
      case .installment: return "installment_reminder_"
      case .recurring: return "recurring_reminder_"
      }
    }

    var monthType: String {
      switch self {
      case .installment: return "installment_month"
      case .recurring: return "recurring_month"
      }
    }

    var reminderType: String {
      switch self {
      case .installment: return "installment_reminder"
      case .recurring: return "recurring_reminder"
      }
    }

    /// Localization key stem: `notification.installment.*` / `notification.recurring.*`.
    var localizationStem: String {
      switch self {
      case .installment: return "notification.installment"
      case .recurring: return "notification.recurring"
      }
    }

    /// Preserved verbatim from the two original implementations so payloads are unchanged.
    var countUserInfoKey: String {
      switch self {
      case .installment: return "installmentCount"
      case .recurring: return "instanceCount"
      }
    }
  }

  private static let notificationCenter = UNUserNotificationCenter.current()

  /// Deliberately LOCAL, even though the recurring path that used to own this logic held a UTC
  /// calendar. That calendar exists to keep `monthAnchor` bucketing stable across time zones; a fire
  /// time is a different question, and reusing it meant `startOfDay` + 8h resolved to 8 AM UTC — so
  /// recurring reminders arrived at 5 AM for a user in UTC-3, while installment reminders on the
  /// local calendar correctly arrived at 8 AM.
  private static var calendar: Calendar {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal
  }

  private static let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60

  /// Groups `models` by calendar month and schedules one reminder per month.
  static func schedule(_ models: [TransactionModel], kind: Kind) {
    var byMonth: [String: [TransactionModel]] = [:]

    for model in models {
      let date = Date(timeIntervalSince1970: TimeInterval(model.data.dateTimestamp))
      let monthKey =
        "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
      byMonth[monthKey, default: []].append(model)
    }

    for (monthKey, monthModels) in byMonth {
      scheduleMonth(monthKey: monthKey, models: monthModels, kind: kind)
    }
  }

  /// Cancels the month reminders for the given month keys, both the real one and its distant-future
  /// placeholder.
  static func cancel(monthKeys: [String], kind: Kind) {
    guard !monthKeys.isEmpty else { return }
    let identifiers =
      monthKeys.map { "\(kind.monthIdentifierPrefix)\($0)" }
      + monthKeys.map { "\(kind.reminderIdentifierPrefix)\($0)" }
    notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  private static func scheduleMonth(monthKey: String, models: [TransactionModel], kind: Kind) {
    guard let first = models.first else { return }

    let cal = calendar
    let date = Date(timeIntervalSince1970: TimeInterval(first.data.dateTimestamp))

    // Beyond a year out there is nothing useful to remind anyone about yet.
    let oneYearFromNow = cal.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow { return }

    var notificationDate = cal.startOfDay(for: date)
    notificationDate = cal.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    guard notificationDate > Date() else { return }

    let timeInterval = notificationDate.timeIntervalSinceNow

    // iOS caps how far ahead this is worth committing to; past 30 days we schedule a placeholder that
    // brings the user back into the app, which reschedules the real thing from current data.
    if timeInterval > thirtyDaysInSeconds {
      scheduleDistantReminder(monthKey: monthKey, kind: kind)
      return
    }

    let totalAmount = models.reduce(0) { $0 + $1.data.amount }
    let count = models.count

    let bodyKey =
      count == 1
      ? "\(kind.localizationStem).body.singular" : "\(kind.localizationStem).body.plural"
    let body =
      count == 1
      ? String(format: bodyKey.localized, totalAmount.currencyString)
      : String(format: bodyKey.localized, count, totalAmount.currencyString)

    let content = UNMutableNotificationContent()
    content.title = "\(kind.localizationStem).title".localized
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = [
      "type": kind.monthType,
      "monthKey": monthKey,
      kind.countUserInfoKey: count,
      "totalAmount": totalAmount,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(
      identifier: "\(kind.monthIdentifierPrefix)\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling \(kind.monthType) notification for \(monthKey): \(error)")
      }
    }
  }

  private static func scheduleDistantReminder(monthKey: String, kind: Kind) {
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: thirtyDaysInSeconds, repeats: false)

    let content = UNMutableNotificationContent()
    content.title = "\(kind.localizationStem).reminder.title".localized
    content.body = "\(kind.localizationStem).reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["type": kind.reminderType, "monthKey": monthKey]

    let request = UNNotificationRequest(
      identifier: "\(kind.reminderIdentifierPrefix)\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling \(kind.reminderType) for \(monthKey): \(error)")
      }
    }
  }
}
