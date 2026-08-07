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

  /// The `count` most recently closed month anchors, oldest first.
  ///
  /// One definition of "closed", `isPastMonth`'s, and no way to opt out of it: the current month is
  /// partial, so it is never in here. Offsets `-count ... -1` from `reference`'s own month are closed
  /// by construction, so this agrees with `isPastMonth` without calling it - the tests assert the
  /// agreement rather than the code re-checking it.
  ///
  /// Takes a `Date` and not an anchor on purpose. `Date.fromMonthAnchor(a).monthAnchor == a` only
  /// holds in the zone `a` was written in; west of the writer that instant lands in the previous
  /// month. Stepping from an anchor would inherit that skew, stepping from a real `Date` cannot.
  public static func closedMonthAnchors(count: Int, asOf reference: Date = Date()) -> [Int] {
    guard count > 0 else { return [] }
    return (1...count).reversed().map { reference.monthAnchor(offsetByMonths: -$0) }
  }
}
