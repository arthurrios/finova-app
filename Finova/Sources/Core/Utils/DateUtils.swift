//
//  DateUtils.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

public struct DateUtils {
  public static func isPastMonth(date: Date) -> Bool {
    // Use user's current timezone for consistency with monthAnchor calculations
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    let now = Date()
    let currentComp = calendar.dateComponents([.year, .month], from: now)
    let targetComp = calendar.dateComponents([.year, .month], from: date)

    guard let cY = currentComp.year,
      let cM = currentComp.month,
      let dY = targetComp.year,
      let dM = targetComp.month
    else {
      return false
    }

    if dY < cY { return true }
    if dY == cY && dM < cM { return true }
    return false
  }
}
