//
//  SeriesFingerprint.swift
//  Finova
//
//  What makes two rows part of the same recurring series when the parent pointer can't be trusted.
//

import Foundation

/// Identity of a recurring TRANSACTION series, derived from content rather than from
/// `parent_transaction_id`.
///
/// Needed because the parent pointer is a local autoincrement id. A row that arrived from another
/// device, or that predates a repair, can carry a pointer to a row that does not exist here — and then
/// "edit this and all future" silently skips it and it stays stale forever.
///
/// **Amount is deliberately absent.** After "edit this and future", occurrences before the cutoff
/// legitimately hold the old amount; including it would refuse to match exactly the rows that most
/// need re-attaching. The linker compares amount separately, against the series' *in-effect*
/// occurrence at that row's slot.
///
/// **Scope is required.** Without it a personal series and a group series that look alike merge, and a
/// later "delete all" would take both.
struct SeriesFingerprint: Hashable {
  let scope: String
  let title: String
  let category: String
  let type: String
  /// The series' canonical day of month, taken from the UNADJUSTED date.
  ///
  /// Unadjusted on purpose: two series anchored on the 15th and the 16th that both roll to the same
  /// Monday would otherwise collide, and the second would never generate.
  let anchorDay: Int

  init(scope: String?, title: String, category: String, type: String, anchorDay: Int) {
    self.scope = scope ?? ""
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.category = category
    self.type = type
    self.anchorDay = anchorDay
  }
}

/// Identity of a recurring ALLOCATION series.
///
/// Genuinely weaker than the transaction fingerprint: an allocation has no title, no type and no day,
/// and its amount varies across the series. Category + scope simply *is* the series identity here —
/// `BudgetAllocationRepository.insertAllocation` already guarantees at most one live allocation per
/// (category, month, scope), so two live series for one category in one scope cannot both materialize.
///
/// Because it is weaker, the linker applies an extra contiguity gate before adopting an orphan.
struct AllocationSeriesFingerprint: Hashable {
  let scope: String
  let category: String

  init(scope: String?, category: String) {
    self.scope = scope ?? ""
    self.category = category
  }
}

enum SeriesDay {
  /// Whether two day-of-month values describe the same recurrence anchor.
  ///
  /// `OccurrenceDateCalculator` clamps, so a day-31 series is day 30 in April and day 28 in February.
  /// Raw equality would split such a series into a different one every short month. Two days match
  /// when they are equal, or when each is the last day of its own month.
  static func matches(_ lhs: Int, inMonthOf lhsDate: Date, _ rhs: Int, inMonthOf rhsDate: Date)
    -> Bool
  {
    if lhs == rhs { return true }
    return isLastDayOfMonth(lhs, in: lhsDate) && isLastDayOfMonth(rhs, in: rhsDate)
  }

  static func isLastDayOfMonth(_ day: Int, in date: Date) -> Bool {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    guard let range = cal.range(of: .day, in: .month, for: date) else { return false }
    return day >= range.upperBound - 1
  }

  /// Day of month on the UNADJUSTED date, in the anchor timezone.
  static func anchorDay(of transaction: Transaction) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    return cal.component(.day, from: transaction.unadjustedDate)
  }
}
