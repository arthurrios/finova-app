//
//  MerchantRule.swift
//  Finova
//
//  The keyword tier of categorization. Data, not code, so adding a merchant is a reviewable JSON
//  change rather than a release.
//

import Foundation

struct MerchantRule: Codable, Equatable {
    let id: String
    /// Already accent-folded and lowercased in the JSON, so matching never has to fold the pattern.
    let patterns: [String]
    let match: MatchKind
    /// Must resolve to a `TransactionCategory` case name. A typo here is caught at CI by
    /// `testEveryShippedRuleResolvesToARealCategory`, not by a user seeing "miscellaneous".
    let category: String
    /// Restricts the rule to one direction — "pagamento" means very different things on an income
    /// row and an expense row.
    let typeConstraint: String?
    let priority: Int

    enum MatchKind: String, Codable {
        case contains
        case prefix
        case wholeWord
    }

    func matches(_ normalizedTitle: String, type: TransactionType) -> Bool {
        if let constraint = typeConstraint, constraint != type.key { return false }
        return patterns.contains { pattern in
            switch match {
            case .contains: return normalizedTitle.contains(pattern)
            case .prefix: return normalizedTitle.hasPrefix(pattern)
            case .wholeWord:
                return normalizedTitle.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .contains { $0 == Substring(pattern) }
            }
        }
    }

    /// The longest pattern in the rule, used to prefer the most specific match.
    var specificity: Int { patterns.map(\.count).max() ?? 0 }
}

/// The rules that apply to this device, loaded once.
final class MerchantRuleSet {

    static let shared = MerchantRuleSet()

    private(set) var rules: [MerchantRule] = []
    /// Rules bucketed by their first token, so matching stays O(rows) rather than O(rows × rules).
    /// Four hundred rules across two thousand titles is 800k substring searches otherwise.
    private var byLeadingToken: [String: [MerchantRule]] = [:]
    private var unbucketable: [MerchantRule] = []

    init(forcedLocaleRegion: String? = nil) {
        load(forcedLocaleRegion: forcedLocaleRegion)
    }

    private func load(forcedLocaleRegion: String?) {
        var sources: [(name: String, json: String)] = [("base", MerchantRuleData.baseJSON)]

        // Region, NOT UI language. Somebody running the app in English while living in Brazil still
        // has Portuguese merchant names on their statement — language would get this exactly
        // backwards for the users who need it most.
        let region = forcedLocaleRegion ?? Locale.current.region?.identifier
        if region == "BR" { sources.append(("pt-BR", MerchantRuleData.ptBRJSON)) }

        for source in sources {
            // Decoded independently: a malformed set costs its own rules and nothing else.
            // Categorization then degrades to the next tier, which is never data loss.
            do {
                let data = Data(source.json.utf8)
                rules.append(contentsOf: try JSONDecoder().decode([MerchantRule].self, from: data))
            } catch {
                logError("[Import] Failed to decode merchant rules '\(source.name)': \(error)")
            }
        }

        index()
    }

    private func index() {
        // Most specific first, then by priority, so the first match found is the best one.
        rules.sort { ($0.specificity, $0.priority) > ($1.specificity, $1.priority) }

        for rule in rules {
            // Only `contains` rules can match mid-string, so only they need the catch-all bucket.
            if rule.match == .contains {
                unbucketable.append(rule)
            } else {
                for pattern in rule.patterns {
                    let token = String(pattern.prefix(while: { $0.isLetter || $0.isNumber }))
                    guard !token.isEmpty else { continue }
                    byLeadingToken[token, default: []].append(rule)
                }
            }
        }
    }

    /// The best matching category for a normalized title, or nil.
    func category(for normalizedTitle: String, type: TransactionType) -> TransactionCategory? {
        let tokens = normalizedTitle.split(whereSeparator: { !$0.isLetter && !$0.isNumber })

        for token in tokens {
            guard let bucket = byLeadingToken[String(token)] else { continue }
            for rule in bucket where rule.matches(normalizedTitle, type: type) {
                if let category = TransactionCategory.allCases.first(where: { $0.key == rule.category }) {
                    return category
                }
            }
        }

        for rule in unbucketable where rule.matches(normalizedTitle, type: type) {
            if let category = TransactionCategory.allCases.first(where: { $0.key == rule.category }) {
                return category
            }
        }

        return nil
    }
}
