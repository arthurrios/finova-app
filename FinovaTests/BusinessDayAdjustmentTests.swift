//
//  BusinessDayAdjustmentTests.swift
//  FinovaTests
//
//  The holiday tables are computed, not tabulated, so nothing here is checking data entry - it is
//  checking arithmetic that has to keep producing the right answer for years nobody has looked at yet.
//  The idempotency and calendar-stability sweeps at the bottom are the two properties the rest of the
//  feature leans on: a recurring series regenerates its dates on every device, and those dates have to
//  come out identical or the same occurrence lands twice.
//

import XCTest

@testable import Finova

final class BusinessDayAdjustmentTests: XCTestCase {

    // MARK: - Helpers

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func calendar(_ timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    /// Noon, matching what the generation paths use to keep a date away from midnight boundaries.
    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts)!
    }

    private func key(_ year: Int, _ month: Int, _ day: Int) -> DayKey {
        DayKey(year: year, month: month, day: day)
    }

    private let brazil = HolidayCalendar(region: .brazil)
    private let unitedStates = HolidayCalendar(region: .unitedStates)
    private let weekendsOnly = HolidayCalendar(region: .none)

    // MARK: - Easter

    func testEasterSundayMatchesKnownYears() {
        let expected: [Int: (Int, Int)] = [
            2024: (3, 31),
            2025: (4, 20),
            2026: (4, 5),
            2027: (3, 28),
            2030: (4, 21),
        ]
        for (year, want) in expected {
            let got = HolidayCalendar.easterSunday(year: year)
            XCTAssertEqual(got.month, want.0, "Easter month for \(year)")
            XCTAssertEqual(got.day, want.1, "Easter day for \(year)")
        }
    }

    func testEasterSundayIsAlwaysASunday() {
        for year in 1970...2100 {
            let easter = HolidayCalendar.easterSunday(year: year)
            XCTAssertEqual(
                HolidayCalendar.weekday(key(year, easter.month, easter.day)), .sunday,
                "Easter \(year) should be a Sunday")
        }
    }

    // MARK: - Brazil

    func testBrazilEasterDerivedHolidays2026() {
        // Easter 2026 is 5 April.
        XCTAssertTrue(brazil.isHoliday(key(2026, 2, 16)), "Carnaval segunda")
        XCTAssertTrue(brazil.isHoliday(key(2026, 2, 17)), "Carnaval terça")
        XCTAssertTrue(brazil.isHoliday(key(2026, 4, 3)), "Sexta-feira Santa")
        XCTAssertTrue(brazil.isHoliday(key(2026, 6, 4)), "Corpus Christi")
    }

    func testBrazilAshWednesdayIsAWorkingDay() {
        // Easter - 46. Banks open from midday, so a transfer clears: deliberately not a holiday.
        XCTAssertFalse(brazil.isHoliday(key(2026, 2, 18)))
    }

    func testBrazilFixedHolidays() {
        for (month, day) in [(1, 1), (4, 21), (5, 1), (9, 7), (10, 12), (11, 2), (11, 15), (12, 25)] {
            XCTAssertTrue(brazil.isHoliday(key(2026, month, day)), "\(day)/\(month) should be a holiday")
        }
    }

    func testBrazilConscienciaNegraOnlyFrom2024() {
        // 20 November 2023 was a Monday, and the national holiday did not exist yet.
        XCTAssertFalse(brazil.isHoliday(key(2023, 11, 20)))
        XCTAssertTrue(brazil.isHoliday(key(2024, 11, 20)))
        XCTAssertTrue(brazil.isHoliday(key(2026, 11, 20)))
    }

    func testBrazilDoesNotObserveWeekendHolidaysOnAnotherDay() {
        // 1 May 2027 is a Saturday. Brazil has no observed-date rule, so the Friday stays a workday.
        XCTAssertEqual(HolidayCalendar.weekday(key(2027, 5, 1)), .saturday)
        XCTAssertFalse(brazil.isHoliday(key(2027, 4, 30)))
    }

    // MARK: - United States

    func testUnitedStatesFloatingHolidays2026() {
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 1, 19)), "MLK Day")
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 2, 16)), "Washington's Birthday")
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 5, 25)), "Memorial Day")
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 9, 7)), "Labor Day")
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 10, 12)), "Columbus Day")
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 11, 26)), "Thanksgiving")
    }

    func testUnitedStatesRecentlyAddedHolidays() {
        XCTAssertFalse(unitedStates.isHoliday(key(1985, 1, 21)), "MLK Day predates 1986")
        XCTAssertTrue(unitedStates.isHoliday(key(1986, 1, 20)), "MLK Day from 1986")
        XCTAssertFalse(unitedStates.isHoliday(key(2020, 6, 19)), "Juneteenth predates 2021")
        XCTAssertTrue(unitedStates.isHoliday(key(2021, 6, 18)), "Juneteenth 2021 observed on the Friday")
    }

    func testUnitedStatesSaturdayHolidayIsObservedOnTheFriday() {
        // 4 July 2026 is a Saturday.
        XCTAssertEqual(HolidayCalendar.weekday(key(2026, 7, 4)), .saturday)
        XCTAssertTrue(unitedStates.isHoliday(key(2026, 7, 3)))
    }

    func testUnitedStatesObservedDateCanFallInThePreviousYear() {
        // New Year's Day 2022 was a Saturday, so it was observed on 31 December 2021. This is the case
        // the three-year generation window exists for.
        XCTAssertEqual(HolidayCalendar.weekday(key(2022, 1, 1)), .saturday)
        XCTAssertTrue(unitedStates.isHoliday(key(2021, 12, 31)))
    }

    func testUnitedStatesSundayHolidayIsObservedOnTheMonday() {
        // 25 December 2022 was a Sunday.
        XCTAssertEqual(HolidayCalendar.weekday(key(2022, 12, 25)), .sunday)
        XCTAssertTrue(unitedStates.isHoliday(key(2022, 12, 26)))
    }

    // MARK: - Region selection

    func testRegionSelectionFromLocale() {
        XCTAssertEqual(HolidayRegion.fromDevice(Locale(identifier: "pt_BR")), .brazil)
        XCTAssertEqual(HolidayRegion.fromDevice(Locale(identifier: "en_US")), .unitedStates)
        XCTAssertEqual(HolidayRegion.fromDevice(Locale(identifier: "fr_FR")), .none)
    }

    func testWeekendsOnlyRegionHasNoHolidays() {
        XCTAssertFalse(weekendsOnly.isHoliday(key(2026, 12, 25)))
        XCTAssertTrue(weekendsOnly.holidays(inYear: 2026).isEmpty)
    }

    // MARK: - Adjustment

    func testExactRuleNeverMovesADate() {
        let calendar = utcCalendar()
        // Christmas Day 2026, a Friday and a holiday in both regions.
        let christmas = date(2026, 12, 25, in: calendar)
        XCTAssertEqual(
            BusinessDayAdjuster.adjust(christmas, rule: .exact, calendar: calendar, holidays: brazil),
            christmas)
    }

    func testABusinessDayIsLeftAlone() {
        let calendar = utcCalendar()
        let wednesday = date(2026, 4, 8, in: calendar)
        for rule in [BusinessDayRule.nextBusinessDay, .previousBusinessDay] {
            XCTAssertEqual(
                BusinessDayAdjuster.adjust(wednesday, rule: rule, calendar: calendar, holidays: brazil),
                wednesday, "\(rule) should not move a plain Wednesday")
        }
    }

    func testNextBusinessDaySkipsAHolidayAndTheWeekendBehindIt() {
        let calendar = utcCalendar()
        // Good Friday 2026 (3 April) -> Sat, Sun -> Monday 6 April.
        let adjusted = BusinessDayAdjuster.adjust(
            date(2026, 4, 3, in: calendar), rule: .nextBusinessDay, calendar: calendar,
            holidays: brazil)
        XCTAssertEqual(DayKey(adjusted, in: calendar), key(2026, 4, 6))
    }

    func testPreviousBusinessDayCrossesAYearBoundary() {
        let calendar = utcCalendar()
        // 1 January 2026 is a Thursday and a holiday; 31 December 2025 is an ordinary Wednesday in Brazil.
        let adjusted = BusinessDayAdjuster.adjust(
            date(2026, 1, 1, in: calendar), rule: .previousBusinessDay, calendar: calendar,
            holidays: brazil)
        XCTAssertEqual(DayKey(adjusted, in: calendar), key(2025, 12, 31))
    }

    func testAdjustmentPreservesTheTimeOfDay() {
        let calendar = utcCalendar()
        let saturday = date(2026, 4, 4, in: calendar)
        let adjusted = BusinessDayAdjuster.adjust(
            saturday, rule: .nextBusinessDay, calendar: calendar, holidays: weekendsOnly)
        XCTAssertEqual(calendar.component(.hour, from: adjusted), 12)
        XCTAssertEqual(calendar.component(.minute, from: adjusted), 0)
    }

    // MARK: - Properties the rest of the feature depends on

    func testAdjustmentIsIdempotentForEveryDayOfAYear() {
        let calendar = utcCalendar()
        for holidays in [brazil, unitedStates, weekendsOnly] {
            for rule in [BusinessDayRule.nextBusinessDay, .previousBusinessDay] {
                for month in 1...12 {
                    for day in 1...HolidayCalendar.daysInMonth(month, year: 2026) {
                        let original = date(2026, month, day, in: calendar)
                        let once = BusinessDayAdjuster.adjust(
                            original, rule: rule, calendar: calendar, holidays: holidays)
                        let twice = BusinessDayAdjuster.adjust(
                            once, rule: rule, calendar: calendar, holidays: holidays)
                        XCTAssertEqual(
                            once, twice,
                            "\(holidays.region)/\(rule) not idempotent at 2026-\(month)-\(day)")
                    }
                }
            }
        }
    }

    func testAdjustmentAlwaysLandsOnABusinessDay() {
        let calendar = utcCalendar()
        for rule in [BusinessDayRule.nextBusinessDay, .previousBusinessDay] {
            for month in 1...12 {
                for day in 1...HolidayCalendar.daysInMonth(month, year: 2026) {
                    let adjusted = BusinessDayAdjuster.adjust(
                        date(2026, month, day, in: calendar), rule: rule, calendar: calendar,
                        holidays: brazil)
                    XCTAssertTrue(
                        BusinessDayAdjuster.isBusinessDay(
                            adjusted, calendar: calendar, holidays: brazil),
                        "\(rule) left 2026-\(month)-\(day) on a non-business day")
                }
            }
        }
    }

    /// The adjuster must read a timestamp as the same civil day the caller wrote it as. This is the
    /// guard against the UTC-versus-local split that already exists between the generation paths.
    func testAdjustmentIsStableAcrossCalendarTimeZones() {
        let zones = ["UTC", "America/Sao_Paulo", "Pacific/Auckland"]
        for zoneID in zones {
            let cal = calendar(zoneID)
            let adjusted = BusinessDayAdjuster.adjust(
                date(2026, 4, 3, in: cal), rule: .nextBusinessDay, calendar: cal, holidays: brazil)
            XCTAssertEqual(
                DayKey(adjusted, in: cal), key(2026, 4, 6),
                "Good Friday 2026 should roll to Monday 6 April in \(zoneID)")
        }
    }

    func testUnknownStoredRuleFallsBackToExact() {
        XCTAssertEqual(BusinessDayRule.fromStored(nil), .exact)
        XCTAssertEqual(BusinessDayRule.fromStored("someFutureRule"), .exact)
        XCTAssertEqual(BusinessDayRule.fromStored(""), .exact)
        XCTAssertEqual(BusinessDayRule.fromStored("nextBusinessDay"), .nextBusinessDay)
        XCTAssertEqual(BusinessDayRule.fromStored("previousBusinessDay"), .previousBusinessDay)
    }

    func testOnlyExactLeavesDatesUnshifted() {
        XCTAssertFalse(BusinessDayRule.exact.shiftsDates)
        XCTAssertTrue(BusinessDayRule.nextBusinessDay.shiftsDates)
        XCTAssertTrue(BusinessDayRule.previousBusinessDay.shiftsDates)
    }

    // MARK: - Civil date arithmetic

    func testShiftingAcrossMonthAndYearBoundaries() {
        XCTAssertEqual(HolidayCalendar.shifting(key(2026, 1, 1), byDays: -1), key(2025, 12, 31))
        XCTAssertEqual(HolidayCalendar.shifting(key(2025, 12, 31), byDays: 1), key(2026, 1, 1))
        XCTAssertEqual(HolidayCalendar.shifting(key(2024, 2, 28), byDays: 1), key(2024, 2, 29))
        XCTAssertEqual(HolidayCalendar.shifting(key(2026, 2, 28), byDays: 1), key(2026, 3, 1))
        XCTAssertEqual(HolidayCalendar.shifting(key(2026, 3, 1), byDays: -1), key(2026, 2, 28))
    }

    func testLeapYears() {
        XCTAssertTrue(HolidayCalendar.isLeapYear(2024))
        XCTAssertTrue(HolidayCalendar.isLeapYear(2000))
        XCTAssertFalse(HolidayCalendar.isLeapYear(1900))
        XCTAssertFalse(HolidayCalendar.isLeapYear(2026))
        XCTAssertEqual(HolidayCalendar.daysInMonth(2, year: 2024), 29)
        XCTAssertEqual(HolidayCalendar.daysInMonth(2, year: 2026), 28)
    }

    // MARK: - Multi-day walks

    /// The adjuster steps one day at a time until it finds a business day, so it skips a whole
    /// weekend rather than moving by one. Sunday the 15th backwards is Friday the 13th, not Saturday.
    func testPreviousFromASundaySkipsSaturdayAndLandsOnFriday() {
        let calendar = utcCalendar()
        // 15 February 2026 is a Sunday.
        XCTAssertEqual(HolidayCalendar.weekday(key(2026, 2, 15)), .sunday)

        let adjusted = BusinessDayAdjuster.adjust(
            date(2026, 2, 15, in: calendar), rule: .previousBusinessDay, calendar: calendar,
            holidays: weekendsOnly)
        XCTAssertEqual(DayKey(adjusted, in: calendar), key(2026, 2, 13))
        XCTAssertEqual(HolidayCalendar.weekday(key(2026, 2, 13)), .friday)
    }

    /// The forward mirror: a Saturday skips Sunday and lands on Monday.
    func testNextFromASaturdaySkipsSundayAndLandsOnMonday() {
        let calendar = utcCalendar()
        // 14 February 2026 is a Saturday.
        XCTAssertEqual(HolidayCalendar.weekday(key(2026, 2, 14)), .saturday)

        let adjusted = BusinessDayAdjuster.adjust(
            date(2026, 2, 14, in: calendar), rule: .nextBusinessDay, calendar: calendar,
            holidays: weekendsOnly)
        XCTAssertEqual(DayKey(adjusted, in: calendar), key(2026, 2, 16))
        XCTAssertEqual(HolidayCalendar.weekday(key(2026, 2, 16)), .monday)
    }

    /// Weekends and holidays are skipped by the same walk, so a run of both is crossed in one go.
    ///
    /// Sunday 15 February 2026 forwards in Brazil: Monday the 16th and Tuesday the 17th are Carnaval,
    /// so the first business day is Wednesday the 18th - four days later.
    func testWalkCrossesAWeekendAndConsecutiveHolidaysTogether() {
        let calendar = utcCalendar()
        let adjusted = BusinessDayAdjuster.adjust(
            date(2026, 2, 15, in: calendar), rule: .nextBusinessDay, calendar: calendar,
            holidays: brazil)
        XCTAssertEqual(DayKey(adjusted, in: calendar), key(2026, 2, 18))
    }

    /// And backwards over the same block: Wednesday 18 February is already a business day, but
    /// Tuesday the 17th walks back over both Carnaval days and the weekend to Friday the 13th.
    func testPreviousWalkCrossesHolidaysAndTheWeekendBehindThem() {
        let calendar = utcCalendar()
        let adjusted = BusinessDayAdjuster.adjust(
            date(2026, 2, 17, in: calendar), rule: .previousBusinessDay, calendar: calendar,
            holidays: brazil)
        XCTAssertEqual(DayKey(adjusted, in: calendar), key(2026, 2, 13))
    }

    // MARK: - Occurrence generation

    /// The property the whole design rests on: an occurrence is always re-derived from the
    /// UNADJUSTED date, so materialising the same month twice produces the same pair.
    func testRegeneratingAnOccurrenceIsStable() {
        let calendar = utcCalendar()
        let origin = date(2026, 1, 31, in: calendar)

        for month in 1...12 {
            let first = OccurrenceDateCalculator.occurrencePair(
                from: origin, targetMonth: month, targetYear: 2026, rule: .nextBusinessDay,
                calendar: calendar, holidays: brazil)
            // Re-deriving from the pair's own unadjusted value - what lazy generation does months
            // later - must land on exactly the same dates.
            let again = OccurrenceDateCalculator.occurrencePair(
                from: first.unadjusted, targetMonth: month, targetYear: 2026, rule: .nextBusinessDay,
                calendar: calendar, holidays: brazil)
            XCTAssertEqual(first.unadjusted, again.unadjusted, "month \(month)")
            XCTAssertEqual(first.adjusted, again.adjusted, "month \(month)")
        }
    }

    /// Re-deriving from the ADJUSTED date instead is the bug the unadjusted column exists to prevent:
    /// the series walks a little further every time a month is generated.
    func testDerivingFromTheAdjustedDateWouldDrift() {
        let calendar = utcCalendar()
        // 4 April 2026 is a Saturday, so `.next` moves it to Monday the 6th.
        let origin = date(2026, 4, 4, in: calendar)
        let correct = OccurrenceDateCalculator.occurrencePair(
            from: origin, targetMonth: 4, targetYear: 2026, rule: .nextBusinessDay,
            calendar: calendar, holidays: weekendsOnly)
        XCTAssertEqual(DayKey(correct.adjusted, in: calendar), key(2026, 4, 6))

        let drifted = OccurrenceDateCalculator.occurrencePair(
            from: correct.adjusted, targetMonth: 4, targetYear: 2026, rule: .nextBusinessDay,
            calendar: calendar, holidays: weekendsOnly)
        XCTAssertNotEqual(
            DayKey(drifted.unadjusted, in: calendar), DayKey(correct.unadjusted, in: calendar),
            "feeding the adjusted date back in should visibly move the anchor day - this is what the "
                + "unadjusted timestamp prevents")
    }

    /// A shifted occurrence keeps the anchor of the month it is FOR, even when the date lands in the
    /// next one. The one-row-per-month invariant is enforced on that anchor.
    func testShiftedOccurrenceKeepsItsOwnMonthAnchor() {
        let calendar = utcCalendar()
        // 31 January 2026 is a Saturday; `.next` pushes it to Monday 2 February.
        let origin = date(2026, 1, 31, in: calendar)
        let occurrence = OccurrenceDateCalculator.occurrencePair(
            from: origin, targetMonth: 1, targetYear: 2026, rule: .nextBusinessDay,
            calendar: calendar, holidays: weekendsOnly)

        XCTAssertEqual(DayKey(occurrence.adjusted, in: calendar), key(2026, 2, 2))
        XCTAssertEqual(DayKey(occurrence.unadjusted, in: calendar), key(2026, 1, 31))
        // The anchor is taken from the unadjusted date, so the row still counts in January.
        XCTAssertEqual(occurrence.unadjusted.monthAnchor, origin.monthAnchor)
        XCTAssertNotEqual(occurrence.adjusted.monthAnchor, origin.monthAnchor)
    }

    func testOccurrenceClampsToShortMonthsAndReturnsToTheAnchorDay() {
        let calendar = utcCalendar()
        let origin = date(2026, 1, 31, in: calendar)

        // February 2026 has 28 days.
        let february = OccurrenceDateCalculator.occurrence(
            from: origin, targetMonth: 2, targetYear: 2026, calendar: calendar)
        XCTAssertEqual(DayKey(february, in: calendar), key(2026, 2, 28))

        // April has 30 - and March, being long enough, gets the 31st back.
        XCTAssertEqual(
            DayKey(
                OccurrenceDateCalculator.occurrence(
                    from: origin, targetMonth: 4, targetYear: 2026, calendar: calendar), in: calendar),
            key(2026, 4, 30))
        XCTAssertEqual(
            DayKey(
                OccurrenceDateCalculator.occurrence(
                    from: origin, targetMonth: 3, targetYear: 2026, calendar: calendar), in: calendar),
            key(2026, 3, 31))
    }

    func testExactRuleProducesIdenticalUnadjustedAndAdjustedDates() {
        let calendar = utcCalendar()
        let pair = OccurrenceDateCalculator.occurrencePair(
            from: date(2026, 4, 4, in: calendar), targetMonth: 4, targetYear: 2026, rule: .exact,
            calendar: calendar, holidays: brazil)
        XCTAssertEqual(pair.unadjusted, pair.adjusted)
    }

    // MARK: - Series identity vs accounting month

    /// The regression that duplicated real transactions.
    ///
    /// A salary scheduled for Sunday 1 November with "previous business day" is paid Friday 30
    /// October. Two facts have to hold at once, and the first version of this feature could only
    /// manage one of them:
    ///   - it counts in OCTOBER, because that is when the money moves;
    ///   - it is still the NOVEMBER occurrence, so nothing thinks November is missing and refills it.
    func testShiftedOccurrenceCountsInTheLandingMonthButKeepsItsSlot() {
        let calendar = utcCalendar()
        // 1 November 2026 is a Sunday.
        XCTAssertEqual(HolidayCalendar.weekday(key(2026, 11, 1)), .sunday)

        let scheduled = date(2026, 11, 1, in: calendar)
        let occurrence = OccurrenceDateCalculator.occurrencePair(
            from: scheduled, targetMonth: 11, targetYear: 2026, rule: .previousBusinessDay,
            calendar: calendar, holidays: weekendsOnly)

        XCTAssertEqual(DayKey(occurrence.adjusted, in: calendar), key(2026, 10, 30))

        // Accounting: October.
        let accountingMonth = occurrence.adjusted.monthAnchor
        // Identity: still the November slot.
        let seriesPeriod = scheduled.monthAnchor

        XCTAssertNotEqual(
            accountingMonth, seriesPeriod,
            "this is the case the two fields exist to represent separately")
        XCTAssertEqual(accountingMonth, occurrence.adjusted.monthAnchor)
        XCTAssertEqual(seriesPeriod, occurrence.unadjusted.monthAnchor)
    }

    /// A row that carries an explicit slot reports it; one written before the column existed reports
    /// its accounting month, so nothing that keys on the slot changes behaviour for existing data.
    func testSeriesPeriodFallsBackToTheAccountingMonth() {
        let november = date(2026, 11, 1, in: utcCalendar()).monthAnchor
        let october = date(2026, 10, 30, in: utcCalendar()).monthAnchor

        let shifted = Transaction(
            data: UITransactionData(
                id: 1, title: "Salary", amount: 100,
                dateTimestamp: Int(date(2026, 10, 30, in: utcCalendar()).timeIntervalSince1970),
                budgetMonthDate: october, isRecurring: nil, hasInstallments: nil,
                parentTransactionId: nil, installmentNumber: nil, totalInstallments: nil,
                originalAmount: nil, seriesPeriod: november, category: .salary, type: .income))
        XCTAssertEqual(shifted.seriesPeriod, november)
        XCTAssertEqual(shifted.budgetMonthDate, october)

        let legacy = Transaction(
            data: UITransactionData(
                id: 2, title: "Salary", amount: 100,
                dateTimestamp: Int(date(2026, 10, 30, in: utcCalendar()).timeIntervalSince1970),
                budgetMonthDate: october, isRecurring: nil, hasInstallments: nil,
                parentTransactionId: nil, installmentNumber: nil, totalInstallments: nil,
                originalAmount: nil, category: .salary, type: .income))
        XCTAssertEqual(
            legacy.seriesPeriod, legacy.budgetMonthDate,
            "a row with no stored slot must read as its own accounting month")
    }

    /// Two occurrences of the same series legitimately sharing one accounting month is now a valid
    /// state - it is exactly what a `.previous` rule at a month boundary produces. Their slots still
    /// differ, which is what keeps them distinct.
    func testTwoOccurrencesMaySharaAnAccountingMonthWhileKeepingDistinctSlots() {
        let calendar = utcCalendar()
        // October's own occurrence, on the 30th, plus November's pulled back to the 30th.
        let october = OccurrenceDateCalculator.occurrencePair(
            from: date(2026, 10, 30, in: calendar), targetMonth: 10, targetYear: 2026,
            rule: .previousBusinessDay, calendar: calendar, holidays: weekendsOnly)
        let november = OccurrenceDateCalculator.occurrencePair(
            from: date(2026, 11, 1, in: calendar), targetMonth: 11, targetYear: 2026,
            rule: .previousBusinessDay, calendar: calendar, holidays: weekendsOnly)

        XCTAssertEqual(
            october.adjusted.monthAnchor, november.adjusted.monthAnchor,
            "both land in October")
        XCTAssertNotEqual(
            october.unadjusted.monthAnchor, november.unadjusted.monthAnchor,
            "but they are different occurrences and must stay distinguishable")
    }

    // MARK: - Model fallbacks

    /// A row written before the column existed has no unadjusted timestamp and must read as its own
    /// date, so nothing that regenerates from it moves.
    func testUnadjustedDateFallsBackToTheStoredDate() {
        let stored = 1_767_225_600  // 2026-01-01T00:00:00Z
        let legacy = Transaction(
            data: UITransactionData(
                id: 1, title: "Rent", amount: 100, dateTimestamp: stored,
                budgetMonthDate: stored, isRecurring: nil, hasInstallments: nil,
                parentTransactionId: nil, installmentNumber: nil, totalInstallments: nil,
                originalAmount: nil, category: .utilities, type: .expense))

        XCTAssertEqual(legacy.businessDayRule, BusinessDayRule.exact)
        XCTAssertNil(legacy.unadjustedDateTimestamp)
        XCTAssertEqual(legacy.unadjustedDate, legacy.date)
    }

    func testUnadjustedDateUsesTheStoredAnchorWhenPresent() {
        let adjusted = 1_767_398_400
        let unadjusted = 1_767_225_600
        let row = Transaction(
            data: UITransactionData(
                id: 1, title: "Salary", amount: 100, dateTimestamp: adjusted,
                budgetMonthDate: unadjusted, isRecurring: nil, hasInstallments: nil,
                parentTransactionId: nil, installmentNumber: nil, totalInstallments: nil,
                originalAmount: nil, businessDayRule: .nextBusinessDay,
                unadjustedDateTimestamp: unadjusted, category: .salary, type: .income))

        XCTAssertEqual(row.businessDayRule, BusinessDayRule.nextBusinessDay)
        XCTAssertEqual(Int(row.unadjustedDate.timeIntervalSince1970), unadjusted)
        XCTAssertEqual(Int(row.date.timeIntervalSince1970), adjusted)
    }

    func testWeekdayMatchesFoundation() {
        // Sakamoto's method against Foundation, so a rewrite of either is caught.
        let cal = utcCalendar()
        for offset in 0..<400 {
            let probe = cal.date(byAdding: .day, value: offset, to: date(2025, 1, 1, in: cal))!
            let parts = cal.dateComponents([.year, .month, .day, .weekday], from: probe)
            let mine = HolidayCalendar.weekday(
                key(parts.year!, parts.month!, parts.day!))
            // Foundation's `weekday` is 1-based from Sunday; ours is 0-based from Sunday.
            XCTAssertEqual(mine.rawValue, parts.weekday! - 1, "weekday mismatch at \(parts)")
        }
    }
}
