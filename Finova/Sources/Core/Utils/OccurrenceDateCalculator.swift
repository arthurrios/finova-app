//
//  OccurrenceDateCalculator.swift
//  Finova
//

import Foundation

/// Where a repeating transaction's date for a given month comes from.
///
/// Consolidates three implementations that had drifted apart: two byte-identical copies of
/// `generateValidDateForMonth` (in `RecurringTransactionManager` and `AddTransactionModalViewModel`)
/// and a third path in `TransactionRepository` that did raw `byAdding: .month` arithmetic and so
/// silently produced a different day for a series anchored on the 29th to 31st.
///
/// Two dates come out of here, and the distinction matters everywhere downstream:
/// - **unadjusted** - the canonical occurrence day. The month anchor is always derived from this, and
///   it is what the next regeneration re-derives from. Stable regardless of the business-day rule.
/// - **adjusted** - the unadjusted date passed through the rule. This is what the user sees and what
///   `dateTimestamp` stores.
///
/// Keeping both is what makes regeneration idempotent. Re-deriving from an already-shifted date would
/// let a series drift a few days further every time a month was materialised.
enum OccurrenceDateCalculator {

    static func lastDay(ofMonth month: Int, year: Int) -> Int {
        HolidayCalendar.daysInMonth(month, year: year)
    }

    /// The canonical occurrence date for a month, clamped to that month's length.
    ///
    /// A series anchored on the 31st falls back to the 30th, or to the 28th/29th in February - and then
    /// returns to the 31st in the next long month, because the anchor day is re-read from the original
    /// date every time rather than being carried forward.
    ///
    /// Noon, matching the existing behaviour: a date built at midnight sits one clock change away from
    /// belonging to the previous day.
    static func occurrence(
        anchorDay: Int,
        targetMonth: Int,
        targetYear: Int,
        calendar: Calendar
    ) -> Date {
        var parts = DateComponents()
        parts.year = targetYear
        parts.month = targetMonth
        parts.day = min(anchorDay, lastDay(ofMonth: targetMonth, year: targetYear))
        parts.hour = 12
        parts.minute = 0
        parts.second = 0

        if let date = calendar.date(from: parts) { return date }

        logError(
            "[Occurrence] Could not build \(parts.day ?? 0)/\(targetMonth)/\(targetYear); "
                + "falling back to the first of the month")
        parts.day = 1
        return calendar.date(from: parts) ?? Date()
    }

    static func occurrence(
        from originalDate: Date,
        targetMonth: Int,
        targetYear: Int,
        calendar: Calendar
    ) -> Date {
        occurrence(
            anchorDay: calendar.component(.day, from: originalDate),
            targetMonth: targetMonth,
            targetYear: targetYear,
            calendar: calendar)
    }

    /// The pair every generation site needs.
    ///
    /// - Parameter unadjustedOrigin: the series' canonical date - `Transaction.unadjustedDate`, never
    ///   `dateTimestamp`, or the anchor day drifts by whatever the rule last shifted.
    static func occurrencePair(
        from unadjustedOrigin: Date,
        targetMonth: Int,
        targetYear: Int,
        rule: BusinessDayRule,
        calendar: Calendar,
        holidays: HolidayCalendar = .shared
    ) -> (unadjusted: Date, adjusted: Date) {
        let unadjusted = occurrence(
            from: unadjustedOrigin, targetMonth: targetMonth, targetYear: targetYear,
            calendar: calendar)
        let adjusted = BusinessDayAdjuster.adjust(
            unadjusted, rule: rule, calendar: calendar, holidays: holidays)
        return (unadjusted, adjusted)
    }

    /// The same pair for a date that is already known, rather than derived for a target month - the
    /// one-off transaction and edit paths.
    static func pair(
        for date: Date,
        rule: BusinessDayRule,
        calendar: Calendar,
        holidays: HolidayCalendar = .shared
    ) -> (unadjusted: Date, adjusted: Date) {
        (date, BusinessDayAdjuster.adjust(date, rule: rule, calendar: calendar, holidays: holidays))
    }
}
