//
//  DateFieldParser.swift
//  Finova
//
//  Text to a Date that lands on the right calendar day.
//

import Foundation

struct DateFormatSpec: Hashable, Codable {
    let pattern: String
    /// POSIX for every numeric pattern. A device locale usually works and occasionally does not —
    /// some locales substitute their own digits or separators — whereas POSIX always does. Only
    /// month-NAME patterns need a real locale, because "janeiro" is not a POSIX token.
    let localeId: String

    init(pattern: String, localeId: String = "en_US_POSIX") {
        self.pattern = pattern
        self.localeId = localeId
    }

    /// Ordered roughly by how often they appear in the wild, so the first hit is usually the answer.
    static let candidates: [DateFormatSpec] = [
        DateFormatSpec(pattern: "dd/MM/yyyy"),
        DateFormatSpec(pattern: "yyyy-MM-dd"),
        DateFormatSpec(pattern: "MM/dd/yyyy"),
        DateFormatSpec(pattern: "dd-MM-yyyy"),
        DateFormatSpec(pattern: "dd.MM.yyyy"),
        DateFormatSpec(pattern: "dd/MM/yy"),
        DateFormatSpec(pattern: "yyyy/MM/dd"),
        DateFormatSpec(pattern: "dd/MM/yyyy HH:mm"),
        DateFormatSpec(pattern: "dd/MM/yyyy HH:mm:ss"),
        DateFormatSpec(pattern: "yyyy-MM-dd HH:mm:ss"),
        DateFormatSpec(pattern: "yyyy-MM-dd'T'HH:mm:ssZ"),
        DateFormatSpec(pattern: "yyyy-MM-dd'T'HH:mm:ss"),
        DateFormatSpec(pattern: "d 'de' MMMM 'de' yyyy", localeId: "pt_BR"),
        DateFormatSpec(pattern: "dd MMM yyyy", localeId: "pt_BR"),
        DateFormatSpec(pattern: "dd MMM yyyy", localeId: "en_US_POSIX"),
    ]

    /// The two readings that are indistinguishable whenever every component is ≤ 12.
    var isDayMonthAmbiguousWith: DateFormatSpec? {
        switch pattern {
        case "dd/MM/yyyy": return DateFormatSpec(pattern: "MM/dd/yyyy")
        case "MM/dd/yyyy": return DateFormatSpec(pattern: "dd/MM/yyyy")
        default: return nil
        }
    }
}

enum DateFieldParser {

    /// Dates outside this window are a parse gone wrong, not history.
    private static let earliestPlausibleYear = 1980
    private static let latestPlausibleYearOffset = 5

    private static var formatterCache: [DateFormatSpec: DateFormatter] = [:]
    private static let cacheLock = NSLock()

    /// A configured formatter for `spec`.
    ///
    /// Three settings carry weight, and all three have bitten someone:
    /// - `locale`: POSIX, so numeric patterns never meet a locale's own digits or separators.
    /// - `timeZone`: `.current`, because it must agree with `Date.monthAnchor`. Disagreeing by one
    ///   zone puts a month-boundary transaction in the wrong budget month.
    /// - `isLenient = false`: lenient parsing turns `29/02/2025` into 1 March without complaint.
    /// Whether a pattern already carries a time component.
    private static func hasTimeComponent(_ pattern: String) -> Bool {
        pattern.contains(where: { "HhmsS".contains($0) })
    }

    static func formatter(for spec: DateFormatSpec) -> DateFormatter {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = formatterCache[spec] { return cached }

        let formatter = DateFormatter()
        // A date-only pattern is parsed WITH an explicit noon appended rather than at the implicit
        // midnight — see `parse`. Patterns that already carry a time are left alone.
        formatter.dateFormat = hasTimeComponent(spec.pattern) ? spec.pattern : spec.pattern + " HH:mm"
        formatter.locale = Locale(identifier: spec.localeId)
        formatter.timeZone = TimeZone.current
        formatter.isLenient = false
        formatterCache[spec] = formatter
        return formatter
    }

    /// Parses one cell, returning a date anchored at LOCAL NOON.
    ///
    /// Noon, not midnight, and this is not a style choice. Brazil observed DST until 2019, and
    /// `America/Sao_Paulo` SKIPPED midnight on DST-start days: 2018-11-04 00:00 is a wall-clock time
    /// that never existed. A non-lenient `DateFormatter` handed a date-only pattern therefore returns
    /// NIL for that row — the transaction does not fail to be placed correctly, it fails to parse at
    /// all — and a lenient one would silently slide it into an adjacent day.
    ///
    /// So noon is appended to the INPUT before parsing, not applied to the result afterwards. Noon is
    /// twelve hours from either DST boundary and cannot be shifted across a day.
    static func parse(_ raw: String, spec: DateFormatSpec) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let input = hasTimeComponent(spec.pattern) ? text : text + " 12:00"
        guard let parsed = formatter(for: spec).date(from: input) else { return nil }
        // Patterns carrying their own time still get normalised, so two rows on the same day always
        // land in the same bucket regardless of when they posted.
        guard let noon = anchorAtNoon(parsed) else { return nil }
        return isPlausible(noon) ? noon : nil
    }

    private static func anchorAtNoon(_ date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private static func isPlausible(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let year = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: Date())
        return year >= earliestPlausibleYear && year <= currentYear + latestPlausibleYearOffset
    }

    // MARK: - Format detection

    enum Detection: Equatable {
        /// A component greater than 12 settled it, or only one candidate parsed at all.
        case proven(DateFormatSpec)
        /// Both readings parse every sample. The monotonicity test broke the tie, but it is a
        /// heuristic and the caller may want to confirm.
        case likely(DateFormatSpec, alternative: DateFormatSpec)
        /// Both readings are equally defensible. Ask.
        case ambiguous(DateFormatSpec, DateFormatSpec)
        /// Rows contradict each other — one line proves dd/MM and another proves MM/dd.
        case inconsistent
        case none
    }

    /// Works out how a column spells its dates.
    static func detectFormat(in values: [String]) -> Detection {
        let samples = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !samples.isEmpty else { return .none }

        let dayFirst = DateFormatSpec(pattern: "dd/MM/yyyy")
        let monthFirst = DateFormatSpec(pattern: "MM/dd/yyyy")

        // Look for contradiction FIRST, before asking which formats parse everything. A file where
        // one row proves dd/MM and another proves MM/dd makes NEITHER reading viable, so a
        // viability check alone would report it as simply unrecognised rather than as the
        // self-contradicting file it is.
        var sawDayFirstProof = false
        var sawMonthFirstProof = false
        for sample in samples {
            let parts = sample.split(whereSeparator: { "/-.".contains($0) })
            guard parts.count >= 2, let first = Int(parts[0]), let second = Int(parts[1]),
                  // Only day/month-leading layouts are ambiguous; a 4-digit year settles it.
                  parts[0].count <= 2 else { continue }
            if first > 12 { sawDayFirstProof = true }
            if second > 12 { sawMonthFirstProof = true }
        }
        if sawDayFirstProof && sawMonthFirstProof { return .inconsistent }

        // Which candidates parse EVERY sample. A format that fails one row is not this column's
        // format — partial success is how you end up importing three quarters of a statement.
        let viable = DateFormatSpec.candidates.filter { spec in
            samples.allSatisfy { parse($0, spec: spec) != nil }
        }
        guard !viable.isEmpty else { return .none }

        if sawDayFirstProof, viable.contains(dayFirst) { return .proven(dayFirst) }
        if sawMonthFirstProof, viable.contains(monthFirst) { return .proven(monthFirst) }

        let bothSlashCandidatesViable = viable.contains(dayFirst) && viable.contains(monthFirst)
        if !bothSlashCandidatesViable, let only = viable.first {
            // Only one reading parses everything, so the rest are disproven by some row.
            return .proven(only)
        }

        // Genuinely ambiguous. Statements are date-ordered and cover a bounded window, so prefer the
        // reading that yields a monotonic sequence over a sane span. Below ~8 rows this proves
        // nothing, so say so rather than guessing.
        guard samples.count >= 8 else { return .ambiguous(dayFirst, monthFirst) }

        let dayScore = monotonicityScore(samples, spec: dayFirst)
        let monthScore = monotonicityScore(samples, spec: monthFirst)

        if dayScore > monthScore + 0.15 { return .likely(dayFirst, alternative: monthFirst) }
        if monthScore > dayScore + 0.15 { return .likely(monthFirst, alternative: dayFirst) }
        return .ambiguous(dayFirst, monthFirst)
    }

    /// How well a reading behaves like a bank statement: dates in order, over a plausible span.
    private static func monotonicityScore(_ samples: [String], spec: DateFormatSpec) -> Double {
        let dates = samples.compactMap { parse($0, spec: spec) }
        guard dates.count >= 2 else { return 0 }

        let ascending = zip(dates, dates.dropFirst()).filter { $0 <= $1 }.count
        let descending = zip(dates, dates.dropFirst()).filter { $0 >= $1 }.count
        let ordered = Double(max(ascending, descending)) / Double(dates.count - 1)

        guard let earliest = dates.min(), let latest = dates.max() else { return 0 }
        let span = latest.timeIntervalSince(earliest) / 86_400

        // Continuous, not a cliff at 400 days. Both readings of a file like 01/01, 02/01, 03/01… are
        // perfectly ordered — one as consecutive days, the other as consecutive months — so a
        // threshold that both pass discriminates nothing. Rewarding the TIGHTER span is what
        // separates them, because a statement covers a period, not a year of first-of-months.
        let spanScore = max(0, 1.0 - span / 400)

        return ordered * 0.6 + spanScore * 0.4
    }

    // MARK: - Dates fused into a description column

    /// The longest leading run of whitespace-separated tokens that parses as a date, plus whatever
    /// follows it.
    ///
    /// Several Brazilian banks export a single "Lançamentos" column carrying the date, sometimes a
    /// time, and the description all in one field: `15/07/2026 14:30 COMPRA MERCADO`. No column in
    /// such a file parses cleanly as dates, so plain column profiling finds nothing.
    ///
    /// Longest-first is what makes `15/07/2026 14:30 PADARIA` yield the timestamp rather than just the
    /// date with `14:30` left stranded at the front of the title.
    static func parseLeadingDate(_ raw: String) -> (date: Date, remainder: String, spec: DateFormatSpec)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard !tokens.isEmpty else { return nil }

        // Three tokens covers `dd/MM/yyyy HH:mm:ss` and `12 de janeiro de 2026`-style prefixes; more
        // than that starts swallowing the description.
        for length in stride(from: min(4, tokens.count), through: 1, by: -1) {
            let candidateText = tokens.prefix(length).joined(separator: " ")
            for spec in DateFormatSpec.candidates {
                guard let date = parse(candidateText, spec: spec) else { continue }
                let remainder = tokens.dropFirst(length).joined(separator: " ")
                return (date, remainder, spec)
            }
        }
        return nil
    }

    /// How much of a column begins with a parseable date.
    ///
    /// Sampled rather than exhaustive: this runs over every column only when plain date detection
    /// found nothing, and it is the most expensive probe in inference (tokens × candidates × rows).
    static func leadingDateHitRate(in values: [String], sample: Int = 60) -> Double {
        let candidates = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(sample)
        guard !candidates.isEmpty else { return 0 }

        let hits = candidates.filter { parseLeadingDate($0) != nil }.count
        return Double(hits) / Double(candidates.count)
    }

    /// The date prefixes of a fused column, so `detectFormat` can be applied to them directly.
    static func leadingDateTexts(in values: [String]) -> [String] {
        values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = parseLeadingDate(trimmed) else { return nil }
            // Reconstruct the consumed prefix by removing the remainder from the tail.
            guard !parsed.remainder.isEmpty else { return trimmed }
            return String(trimmed.dropLast(parsed.remainder.count))
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// Whether a column looks like dates at all, for column profiling.
    static func dateHitRate(in values: [String]) -> Double {
        let samples = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !samples.isEmpty else { return 0 }

        let best = DateFormatSpec.candidates
            .map { spec in samples.filter { parse($0, spec: spec) != nil }.count }
            .max() ?? 0
        return Double(best) / Double(samples.count)
    }
}
