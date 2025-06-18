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
    fmt.timeZone = TimeZone(secondsFromGMT: 0)
    return fmt
  }()

  static let fullDateFormatter: DateFormatter = {
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
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
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
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM"
    return df
  }()

  static let keyToDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    return formatter
  }()
}
