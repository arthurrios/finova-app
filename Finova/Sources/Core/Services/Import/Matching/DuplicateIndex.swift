//
//  DuplicateIndex.swift
//  Finova
//
//  Matching imported rows against what the user already has.
//
//  Note what this deliberately does NOT use: `TransactionRepository.fetchMatchingTransaction(
//  title:amount:budgetMonthDate:)`. It is the obvious reach and it is wrong here on two counts —
//  month granularity, so a R$50 charge on the 3rd collides with one on the 20th, and raw string
//  equality, so nothing folds. It exists for CloudKit conflict resolution; it stays there.
//

import Foundation

/// The exact-match key.
///
/// The cents are SIGNED even though the database stores a positive magnitude plus a `type`. Without
/// the sign a R$50 refund matches a R$50 charge on the same day, and one of the two silently
/// disappears — the worst possible outcome for a feature whose job is to not lose money.
struct MatchKey: Hashable {
    let dayStart: Int
    let signedCents: Int
    let normalizedTitle: String
}

struct DuplicateIndex {

    private var exact: [MatchKey: Int] = [:]
    /// Bucketed by (day, signed cents) so the ±3-day fuzzy scan touches a handful of rows rather
    /// than the whole ledger.
    private var byDayAndAmount: [Int: [(id: Int, dayStart: Int, title: String, tokens: Set<String>)]] = [:]

    /// How many days either side a fuzzy match may sit.
    ///
    /// Three covers the common cause — a transaction posting on the Monday after a weekend purchase.
    /// Wider starts matching genuinely different transactions, and the failure is invisible.
    static let fuzzyDayWindow = 3

    init(existing: [Transaction]) {
        for transaction in existing {
            guard let id = transaction.id else { continue }
            let day = Self.dayStart(of: transaction.date)
            let signed = Self.signedCents(amount: transaction.amount, type: transaction.type)
            let normalized = transaction.title.normalizedForSearch()

            exact[MatchKey(dayStart: day, signedCents: signed, normalizedTitle: normalized)] = id
            byDayAndAmount[signed, default: []].append(
                (id: id, dayStart: day, title: transaction.title,
                 tokens: TitleSimilarity.tokens(of: transaction.title)))
        }
    }

    /// `Calendar.startOfDay`, never `epoch / 86400`: integer division truncates toward zero, so a
    /// pre-1970 date in a corrupt file lands in the same bucket as a 1970 one.
    static func dayStart(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return Int(calendar.startOfDay(for: date).timeIntervalSince1970)
    }

    static func signedCents(amount: Int, type: TransactionType) -> Int {
        type == .income ? abs(amount) : -abs(amount)
    }

    func exactMatch(dayStart: Int, signedCents: Int, normalizedTitle: String) -> Int? {
        exact[MatchKey(dayStart: dayStart, signedCents: signedCents, normalizedTitle: normalizedTitle)]
    }

    /// Same amount to the cent, within a few days, and a similar title.
    ///
    /// The amount must match EXACTLY. Loosening it as well as the date is what turns a fuzzy matcher
    /// into a false-positive machine, and recurring instances — which are near-identical month to
    /// month by construction — are precisely the rows that would start matching each other.
    func fuzzyMatch(
        dayStart: Int, signedCents: Int, title: String
    ) -> (id: Int, similarity: Double)? {
        guard let bucket = byDayAndAmount[signedCents] else { return nil }
        let tokens = TitleSimilarity.tokens(of: title)
        let window = Self.fuzzyDayWindow * 86_400

        var best: (id: Int, similarity: Double)?
        for candidate in bucket {
            guard abs(candidate.dayStart - dayStart) <= window else { continue }
            let similarity = TitleSimilarity.score(
                tokens, candidate.tokens, rawA: title, rawB: candidate.title)
            guard similarity >= TitleSimilarity.threshold else { continue }
            if best == nil || similarity > best!.similarity {
                best = (candidate.id, similarity)
            }
        }
        return best
    }
}
