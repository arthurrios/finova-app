//
//  BalanceHistoryStart.swift
//  FinanceApp
//

import Foundation

/// Where an account's running balance starts counting transactions.
///
/// Until now every balance began at the first month of the dashboard range (12 months back), so
/// transactions older than a year silently dropped out and the balance drifted as the months
/// passed. Balances now count the whole history.
///
/// An account that had already adjusted its balance is the exception. Its offset was calibrated
/// against the old 12-month window, so counting the older rows would shift the balance it shows by
/// their net. That account keeps the window's first month as a fixed start: the balance reads the
/// same on the day of the update and no longer drifts afterwards. Adjusting the balance keeps
/// working unchanged, because it calibrates against whatever the card shows.
enum BalanceHistoryStart {
  /// Stored when every transaction counts.
  static let allHistory = Int.min

  static func key(uid: String) -> String { "balanceHistoryStart_v1_\(uid)" }

  /// The first month anchor whose transactions count toward the balance, or `nil` when all of
  /// them do. Decided on first use per account and stored, so it never moves again.
  static func anchor(
    uid: String?,
    offset: Int,
    now: Date = Date(),
    defaults: UserDefaults = .standard
  ) -> Int? {
    guard let uid else { return nil }
    let key = key(uid: uid)
    if defaults.object(forKey: key) == nil {
      let start =
        offset == 0
        ? allHistory
        : now.monthAnchor(offsetByMonths: SeriesMonths.carouselRange.lowerBound)
      defaults.set(start, forKey: key)
    }
    let stored = defaults.integer(forKey: key)
    return stored == allHistory ? nil : stored
  }

  /// Whether a transaction dated in `transactionMonthAnchor` counts toward the balance.
  static func counts(transactionMonthAnchor: Int, from start: Int?) -> Bool {
    guard let start else { return true }
    return transactionMonthAnchor >= start
  }

  /// Net of the cash transactions dated before `anchor` that count toward the balance: what the
  /// running balance carries into the first month of a range.
  static func netBefore(anchor: Int, start: Int?, transactions: [Transaction]) -> Int {
    transactions.reduce(0) { acc, tx in
      guard tx.creditCardId == nil || tx.isCreditCardStatement == true else { return acc }
      let txAnchor = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp)).monthAnchor
      guard txAnchor < anchor, counts(transactionMonthAnchor: txAnchor, from: start) else {
        return acc
      }
      return tx.type == .income ? acc + tx.amount : acc - tx.amount
    }
  }
}
