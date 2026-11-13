//
//  DateFormatter.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

extension DateFormatter {

  static let yyyyMMdd: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale.current
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  static let monthYearFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = DateFormatter.dateFormat(
      fromTemplate: "MM/yyyy",
      options: 0,
      locale: Locale.current
    )
    fmt.locale = Locale.current
    fmt.timeZone = TimeZone.current  // Use user's timezone instead of UTC
    return fmt
  }()

  static let fullDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM/yyyy"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  // Debug formatter for troubleshooting
  static let debugDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM/yyyy"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current  // Use user's timezone instead of UTC
    return formatter
  }()

  static let yearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("yyyy")
    formatter.locale = Locale.current
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  static let keyFormatter: DateFormatter = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone.current  // Use user's timezone instead of UTC
    df.dateFormat = "yyyy-MM"
    return df
  }()

  static let keyToDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    return formatter
  }()

  /// Compact month + two-digit year, e.g. "Jan/27". Used where a list row has to name a billing
  /// month without crowding out the amount beside it.
  static let monthYearShortFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM/yy"
    formatter.locale = Locale.current
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  static let debugTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()
}
