//
//  SeriesMonths.swift
//  Finova
//
//  The single source of truth for the month arithmetic every recurring series depends on.
//

import Foundation

/// Month arithmetic shared by recurring transactions and recurring allocations.
///
/// EAGER GENERATION is the invariant these helpers exist to serve: a series' occurrences are
/// materialized in full at creation, re-materialized in full before any edit or delete, and topped up
/// by one rolling pass at dashboard load. Nothing is generated in response to navigation, rendering or
/// scrolling. A month that is missing is therefore a bug with no self-healing path — which is the
/// point (gaps stay visible), and why the enumeration here has to be total.
enum SeriesMonths {
  /// How far ahead of a series' start — or of today, whichever is later — occurrences are materialized.
  static let horizonMonths = 36

  /// The months the dashboard carousel renders.
  ///
  /// Deliberately narrower than `horizonMonths`: the extra year of generated-but-unrendered months is
  /// slack, so the last visible card is still materialized a year from now without a top-up having run.
  static let carouselRange: ClosedRange<Int> = -12...24

  /// The months an occurrence is allowed to occupy.
  ///
  /// Cleanup passes MUST use this and never `carouselRange`. Passing the carousel range deleted the
  /// twelve months that creation had just generated and pushed.
  static let retentionRange: ClosedRange<Int> = -12...horizonMonths

  /// Safety bound on month-stepping loops (~50 years).
  private static let maxSteps = 600

  /// Every month anchor from `start` through `end` inclusive, ascending. Empty when `start > end`.
  ///
  /// One calendar, `TimeZone.current` — the convention every `month_date` and `budget_month_date` in
  /// the database was written with. See `Date.monthAnchor(offsetByMonths:)`.
  static func anchors(from start: Int, through end: Int) -> [Int] {
    guard start <= end else { return [] }

    let origin = Date.fromMonthAnchor(start)
    var result: [Int] = []
    var step = 0

    while step < maxSteps {
      let anchor = origin.monthAnchor(offsetByMonths: step)
      if anchor > end { break }
      result.append(anchor)
      step += 1
    }

    return result
  }

  /// The last month a series starting at `start` materializes.
  ///
  /// `max(now, start)` is load-bearing: anchoring the horizon on `now` alone leaves a series created
  /// for a PAST month with a permanent hole between its start and today, and a series created for a
  /// FUTURE month short of its own full horizon.
  static func horizonAnchor(start: Int, asOf now: Date = Date()) -> Int {
    let base = max(now.monthAnchor, start)
    return Date.fromMonthAnchor(base).monthAnchor(offsetByMonths: horizonMonths)
  }

  /// Every month a series occupies: its own start month through the horizon, optionally truncated by
  /// an explicit end month (a bounded series). Includes the start month itself — callers that own a
  /// row there already should drop the first element rather than shifting the range.
  static func seriesAnchors(start: Int, endMonth: Int? = nil, asOf now: Date = Date()) -> [Int] {
    let horizon = horizonAnchor(start: start, asOf: now)
    let last = endMonth.map { min($0, horizon) } ?? horizon
    return anchors(from: start, through: last)
  }

  /// The anchors a dashboard-load top-up covers when it has no particular series in mind.
  ///
  /// Series-anchored generation (`seriesAnchors`) is the primary mechanism; this is the window used to
  /// decide which months are worth *checking*, never the window a series is allowed to occupy.
  static func rollingAnchors(asOf now: Date = Date()) -> [Int] {
    anchors(
      from: now.monthAnchor(offsetByMonths: retentionRange.lowerBound),
      through: now.monthAnchor(offsetByMonths: retentionRange.upperBound))
  }
}
