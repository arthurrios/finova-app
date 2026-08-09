//
//  BusinessDayAdjuster.swift
//  Finova
//

import Foundation

/// Moves a date off a WEEKEND, in the direction a `BusinessDayRule` asks for.
///
/// Holidays are deliberately not considered. The rule exists so a scheduled amount lands on a day
/// banks actually move money, and weekends are the part of that every user shares. A national
/// holiday table is not: it is wrong for anyone whose bank, employer or country differs from the
/// device locale, it changes year to year, and — because occurrence dates are stored — a table
/// update would silently re-date occurrences that already exist. It also produced surprises like a
/// 1 January occurrence being pulled back into the previous December.
///
/// `HolidayCalendar` still exists for calendar arithmetic (`daysInMonth`, `weekday`) and is still
/// what the settings screen names; it just no longer shifts dates.
///
/// Every entry point takes the `Calendar` explicitly and never falls back to `Calendar.current`. The
/// codebase builds occurrence dates in two different calendars - a UTC one in
/// `RecurringTransactionManager`, the local one in `AddTransactionModalViewModel` - and a shared
/// default here would read a timestamp as a different civil day than the code that produced it. Passing
/// the caller's own calendar is what keeps the adjuster and its caller talking about the same day.
enum BusinessDayAdjuster {

    /// A bound on the walk, so an unexpected calendar degrades to "no shift" instead of looping.
    /// A weekend is two days; ten is far past anything reachable.
    static let maxShiftDays = 10

    static func isBusinessDay(_ date: Date, calendar: Calendar) -> Bool {
        !calendar.isDateInWeekend(date)
    }

    /// The adjusted date, or the input unchanged for `.exact` and for a date that is already a business
    /// day.
    ///
    /// Always call this with the *unadjusted* date. The result is by definition a business day, so
    /// re-applying it is a no-op - but feeding a previously adjusted date back in is still a mistake,
    /// because the caller has then lost the anchor the series regenerates from.
    static func adjust(
        _ date: Date,
        rule: BusinessDayRule,
        calendar: Calendar
    ) -> Date {
        guard rule.shiftsDates else { return date }
        guard !isBusinessDay(date, calendar: calendar) else { return date }

        let step = rule == .nextBusinessDay ? 1 : -1
        var candidate = date

        for _ in 1...maxShiftDays {
            // `byAdding: .day` rather than arithmetic on the interval: adding 86,400 seconds across a
            // DST boundary lands on the same civil day or skips one, and the whole point here is to
            // move exactly one civil day while keeping the time of day intact.
            guard
                let next = calendar.date(byAdding: .day, value: step, to: candidate)
            else {
                logWarning("[BusinessDay] Could not step from \(candidate); leaving the date unadjusted")
                return date
            }
            candidate = next
            if isBusinessDay(candidate, calendar: calendar) { return candidate }
        }

        logWarning(
            "[BusinessDay] No business day within \(maxShiftDays) days of \(date) for rule \(rule.rawValue); "
                + "leaving the date unadjusted")
        return date
    }
}
