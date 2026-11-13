//
//  HolidayCalendar.swift
//  Finova
//

import Foundation

// MARK: - Civil date

/// A calendar date with no time and no timezone.
///
/// Holidays are civil facts - "the 25th of December" - not instants. Modelling them as `Date` would
/// mean every comparison depended on the timezone the `Date` was built in, which is the bug this whole
/// type exists to avoid.
struct DayKey: Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the civil date a timestamp represents *in the given calendar*.
    ///
    /// The calendar is required, never defaulted: the same instant is two different days either side of
    /// midnight, and the caller is the only one who knows which timezone the surrounding code used to
    /// build it.
    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}

// MARK: - Region

/// Which national holiday table applies.
///
/// Only the two countries the app ships localisations for. Everywhere else gets weekends only, which is
/// correct rather than merely conservative: applying Brazilian holidays to a user in France would move
/// their salary date onto a day their bank was open.
enum HolidayRegion: String, CaseIterable {
    case brazil
    case unitedStates
    /// Weekends only.
    case none

    static func fromDevice(_ locale: Locale = .current) -> HolidayRegion {
        switch locale.region?.identifier {
        case "BR": return .brazil
        case "US": return .unitedStates
        default: return .none
        }
    }

    var displayName: String {
        "settings.businessDay.region.\(rawValue)".localized
    }
}

// MARK: - Calendar

/// National holidays, computed rather than tabulated, so the app does not expire at the end of a
/// hard-coded list.
///
/// No network and no `Locale` inside the computation - the same year produces the same set on every
/// device, which is what lets two devices generating the same recurring series agree on its dates.
final class HolidayCalendar {

    static let shared = HolidayCalendar(region: .fromDevice())

    let region: HolidayRegion

    private var cache: [Int: Set<DayKey>] = [:]
    private let lock = NSLock()

    /// `region` is injected rather than read from the device so tests pin one instead of inheriting
    /// whatever region the simulator happens to be set to.
    init(region: HolidayRegion) {
        self.region = region
    }

    func isHoliday(_ key: DayKey) -> Bool {
        holidays(inYear: key.year).contains(key)
    }

    func isHoliday(_ date: Date, in calendar: Calendar) -> Bool {
        isHoliday(DayKey(date, in: calendar))
    }

    /// Every holiday observed *within* the given year.
    ///
    /// Generated from three source years because a US observed date can spill across a year boundary:
    /// New Year's Day 2022 fell on a Saturday, so the holiday was observed on 31 December 2021.
    func holidays(inYear year: Int) -> Set<DayKey> {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[year] { return cached }

        var observed = Set<DayKey>()
        for source in (year - 1)...(year + 1) {
            for key in rawHolidays(forYear: source) {
                let day = region == .unitedStates ? Self.observedDate(of: key) : key
                if day.year == year { observed.insert(day) }
            }
        }
        cache[year] = observed
        return observed
    }

    // MARK: - Per-region tables

    /// The holidays as legislated, before any observed-date shifting.
    private func rawHolidays(forYear year: Int) -> [DayKey] {
        switch region {
        case .none: return []
        case .brazil: return Self.brazilHolidays(year: year)
        case .unitedStates: return Self.unitedStatesHolidays(year: year)
        }
    }

    /// Brazilian *national* holidays (Lei 662/1949, Lei 6.802/1980, Lei 14.759/2023).
    ///
    /// Deliberately excluded, because each would shift dates for users the bank does not:
    /// - Quarta-feira de Cinzas: banks open from noon, so it is a working day for a transfer.
    /// - Easter Sunday: already a Sunday.
    /// - State and municipal holidays: not knowable from the device region.
    /// - "Ponto facultativo": optional by definition, and banks set their own hours.
    private static func brazilHolidays(year: Int) -> [DayKey] {
        let easter = easterDayOfYear(year: year)

        var days = [
            DayKey(year: year, month: 1, day: 1),  // Confraternização Universal
            DayKey(year: year, month: 4, day: 21),  // Tiradentes
            DayKey(year: year, month: 5, day: 1),  // Dia do Trabalho
            DayKey(year: year, month: 9, day: 7),  // Independência
            DayKey(year: year, month: 10, day: 12),  // Nossa Senhora Aparecida
            DayKey(year: year, month: 11, day: 2),  // Finados
            DayKey(year: year, month: 11, day: 15),  // Proclamação da República
            DayKey(year: year, month: 12, day: 25),  // Natal
        ]

        // Every Easter-derived date stays inside the same year: Easter falls between 22 March and
        // 25 April, so the earliest here is 3 February and the latest 24 June.
        days.append(dayKey(dayOfYear: easter - 48, year: year))  // Carnaval (segunda)
        days.append(dayKey(dayOfYear: easter - 47, year: year))  // Carnaval (terça)
        days.append(dayKey(dayOfYear: easter - 2, year: year))  // Sexta-feira Santa
        days.append(dayKey(dayOfYear: easter + 60, year: year))  // Corpus Christi

        // Consciência Negra became a national holiday only with Lei 14.759/2023, in force from 2024.
        // Before that it was municipal in some cities, which we cannot see from the device region.
        if year >= 2024 {
            days.append(DayKey(year: year, month: 11, day: 20))
        }

        return days
    }

    /// US federal holidays (5 U.S.C. § 6103).
    private static func unitedStatesHolidays(year: Int) -> [DayKey] {
        var days = [
            DayKey(year: year, month: 1, day: 1),  // New Year's Day
            DayKey(year: year, month: 7, day: 4),  // Independence Day
            DayKey(year: year, month: 11, day: 11),  // Veterans Day
            DayKey(year: year, month: 12, day: 25),  // Christmas Day
            nthWeekday(3, .monday, month: 2, year: year),  // Washington's Birthday
            lastWeekday(.monday, month: 5, year: year),  // Memorial Day
            nthWeekday(1, .monday, month: 9, year: year),  // Labor Day
            nthWeekday(2, .monday, month: 10, year: year),  // Columbus Day
            nthWeekday(4, .thursday, month: 11, year: year),  // Thanksgiving
        ]

        // Martin Luther King Jr. Day was first observed in 1986.
        if year >= 1986 {
            days.append(nthWeekday(3, .monday, month: 1, year: year))
        }
        // Juneteenth became federal in 2021.
        if year >= 2021 {
            days.append(DayKey(year: year, month: 6, day: 19))
        }

        return days
    }

    /// Saturday holidays are observed the preceding Friday, Sunday holidays the following Monday
    /// (Executive Order 11582). Only the observed day is inserted - the literal weekend date is already
    /// a non-business day, so recording it as a holiday too would change nothing.
    static func observedDate(of key: DayKey) -> DayKey {
        switch weekday(key) {
        case .saturday: return shifting(key, byDays: -1)
        case .sunday: return shifting(key, byDays: 1)
        default: return key
        }
    }

    // MARK: - Easter

    /// Easter Sunday as a day-of-year, by the Meeus/Jones/Butcher Gregorian algorithm.
    ///
    /// All integer division; the intermediate names are the ones the published algorithm uses, so it
    /// stays checkable against the source rather than being readable on its own terms.
    static func easterDayOfYear(year y: Int) -> Int {
        let (month, day) = easterSunday(year: y)
        return dayOfYear(month: month, day: day, year: y)
    }

    static func easterSunday(year y: Int) -> (month: Int, day: Int) {
        let a = y % 19
        let b = y / 100
        let c = y % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return (month, day)
    }

    // MARK: - Civil date arithmetic

    /// 0 = Sunday. Sakamoto's method: pure integer arithmetic, so it cannot disagree with a `Calendar`
    /// configured in some other timezone.
    private static let weekdayOffsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]

    enum Weekday: Int {
        case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday
    }

    static func weekday(_ key: DayKey) -> Weekday {
        var y = key.year
        if key.month < 3 { y -= 1 }
        let index =
            (y + y / 4 - y / 100 + y / 400 + weekdayOffsets[key.month - 1] + key.day) % 7
        return Weekday(rawValue: (index + 7) % 7) ?? .sunday
    }

    /// The `n`th given weekday of a month, 1-based.
    private static func nthWeekday(_ n: Int, _ target: Weekday, month: Int, year: Int) -> DayKey {
        let firstWeekday = weekday(DayKey(year: year, month: month, day: 1)).rawValue
        let offset = ((target.rawValue - firstWeekday) + 7) % 7
        return DayKey(year: year, month: month, day: 1 + offset + 7 * (n - 1))
    }

    private static func lastWeekday(_ target: Weekday, month: Int, year: Int) -> DayKey {
        let last = daysInMonth(month, year: year)
        let lastWeekday = weekday(DayKey(year: year, month: month, day: last)).rawValue
        let offset = ((lastWeekday - target.rawValue) + 7) % 7
        return DayKey(year: year, month: month, day: last - offset)
    }

    static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Only ever called with small deltas (the ±1 of an observed-date shift), but written with full
    /// rollover because New Year's Day observed on a Saturday lands in the previous year.
    static func shifting(_ key: DayKey, byDays delta: Int) -> DayKey {
        var result = key
        for _ in 0..<abs(delta) {
            if delta > 0 {
                if result.day < daysInMonth(result.month, year: result.year) {
                    result = DayKey(year: result.year, month: result.month, day: result.day + 1)
                } else if result.month < 12 {
                    result = DayKey(year: result.year, month: result.month + 1, day: 1)
                } else {
                    result = DayKey(year: result.year + 1, month: 1, day: 1)
                }
            } else {
                if result.day > 1 {
                    result = DayKey(year: result.year, month: result.month, day: result.day - 1)
                } else if result.month > 1 {
                    let month = result.month - 1
                    result = DayKey(
                        year: result.year, month: month, day: daysInMonth(month, year: result.year))
                } else {
                    result = DayKey(year: result.year - 1, month: 12, day: 31)
                }
            }
        }
        return result
    }

    static func dayOfYear(month: Int, day: Int, year: Int) -> Int {
        var total = day
        for m in 1..<max(month, 1) { total += daysInMonth(m, year: year) }
        return total
    }

    private static func dayKey(dayOfYear: Int, year: Int) -> DayKey {
        var remaining = dayOfYear
        var month = 1
        while month <= 12 {
            let length = daysInMonth(month, year: year)
            if remaining <= length { break }
            remaining -= length
            month += 1
        }
        return DayKey(year: year, month: min(month, 12), day: max(remaining, 1))
    }
}
