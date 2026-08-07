//
//  Date+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

extension Date {
  init(_ dateString: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM"

    if let date = dateFormatter.date(from: dateString) {
      self = date
    } else {
      self = Date()
    }
  }

  /// Creates a Date from a month anchor timestamp
  static func fromMonthAnchor(_ monthAnchor: Int) -> Date {
    return Date(timeIntervalSince1970: TimeInterval(monthAnchor))
  }

  var monthAnchor: Int {
    var cal = Calendar(identifier: .gregorian)
    // Use user's current timezone for month anchor calculation
    cal.timeZone = TimeZone.current
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps) else {
      logError("Failed to create month anchor date from components")
      return Int(self.timeIntervalSince1970)
    }
    return Int(firstOfMonth.timeIntervalSince1970)
  }

  /// The month anchor `offset` whole months from this date's own month. Negative goes back.
  ///
  /// Anchors to the first of the month before stepping. Not to dodge `date(byAdding: .month)`'s day
  /// clamping - that clamps the *day* and keeps the month, so 31 January plus a month is 28 February
  /// and the month is still right - but because it makes the result canonical: exactly
  /// `firstOfMonth + offset months`, independent of what time of day the receiver happens to carry.
  ///
  /// One calendar, `TimeZone.current` - the convention every `month_date` and `budget_month_date`
  /// already in the database was written with. Several existing call sites step in a UTC calendar and
  /// then read `.monthAnchor`, which is `TimeZone.current`: two conventions inside one expression.
  /// Prefer this to rolling another.
  func monthAnchor(offsetByMonths offset: Int) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps),
      let shifted = cal.date(byAdding: .month, value: offset, to: firstOfMonth)
    else {
      logError("Failed to offset month anchor by \(offset) months")
      return monthAnchor
    }
    return Int(shifted.timeIntervalSince1970)
  }

  /// Get month anchor using a specific timezone
  func monthAnchor(in timezone: TimeZone) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timezone
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps) else {
      logError("Failed to create month anchor date from components with timezone: \(timezone)")
      return Int(self.timeIntervalSince1970)
    }
    return Int(firstOfMonth.timeIntervalSince1970)
  }

  /// Get month anchor using UTC timezone (for comparison/debugging)
  var monthAnchorUTC: Int {
    var cal = Calendar(identifier: .gregorian)
    guard let utcTimeZone = TimeZone(abbreviation: "UTC") else {
      logError("Failed to get UTC timezone")
      return Int(self.timeIntervalSince1970)
    }
    cal.timeZone = utcTimeZone
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps) else {
      logError("Failed to create month anchor date from components with UTC timezone")
      return Int(self.timeIntervalSince1970)
    }
    return Int(firstOfMonth.timeIntervalSince1970)
  }
}
