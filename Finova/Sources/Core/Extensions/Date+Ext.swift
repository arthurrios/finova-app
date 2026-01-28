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

  var monthAnchor: Int {
    var cal = Calendar(identifier: .gregorian)
    // Use user's current timezone for month anchor calculation
    cal.timeZone = TimeZone.current
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps) else {
      print("❌ Failed to create month anchor date from components")
      return Int(self.timeIntervalSince1970)
    }
    return Int(firstOfMonth.timeIntervalSince1970)
  }

  /// Get month anchor using a specific timezone
  func monthAnchor(in timezone: TimeZone) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timezone
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps) else {
      print("❌ Failed to create month anchor date from components with timezone: \(timezone)")
      return Int(self.timeIntervalSince1970)
    }
    return Int(firstOfMonth.timeIntervalSince1970)
  }

  /// Get month anchor using UTC timezone (for comparison/debugging)
  var monthAnchorUTC: Int {
    var cal = Calendar(identifier: .gregorian)
    guard let utcTimeZone = TimeZone(abbreviation: "UTC") else {
      print("❌ Failed to get UTC timezone")
      return Int(self.timeIntervalSince1970)
    }
    cal.timeZone = utcTimeZone
    let comps = cal.dateComponents([.year, .month], from: self)
    guard let firstOfMonth = cal.date(from: comps) else {
      print("❌ Failed to create month anchor date from components with UTC timezone")
      return Int(self.timeIntervalSince1970)
    }
    return Int(firstOfMonth.timeIntervalSince1970)
  }
}
