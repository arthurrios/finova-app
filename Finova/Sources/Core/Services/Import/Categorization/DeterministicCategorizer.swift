//
//  DeterministicCategorizer.swift
//  Finova
//
//  Category suggestions that always exist, always work offline, and never change between runs.
//
//  Tier order matters and is deliberate: the user's OWN history first. It has more signal than any
//  shipped keyword list, because it is built from the merchants this particular person actually
//  visits, and it costs nothing — the ledger is already in memory for dedupe. A keyword list can tell
//  you "PADARIA" is food; only the history can tell you "PAG*JOSESILVA" is the gym.
//

import Foundation

/// Where a category suggestion came from. Carried through to the review screen, and used by the
/// optional model layer to decide what it is allowed to overwrite.
enum CategorySource: String, Equatable {
    case history
    case rules
    /// The bank's own category column.
    case bankColumn
    /// Derived from the payment rail (PIX, boleto, fatura).
    case rail
    case fallback
    /// The on-device language model. Only ever replaces `.rail` or `.fallback`.
    case model
}

struct CategorySuggestion: Equatable {
    let category: TransactionCategory
    let source: CategorySource
    let confidence: Double
}

/// A map from normalized title to the category the user has actually been using for it.
struct HistoricalCategoryIndex {

    private var byExactTitle: [String: TransactionCategory] = [:]
    private var byToken: [String: [TransactionCategory: Int]] = [:]

    init(existing: [Transaction]) {
        var counts: [String: [TransactionCategory: Int]] = [:]

        for transaction in existing {
            let key = transaction.title.normalizedForSearch()
            guard !key.isEmpty else { continue }
            counts[key, default: [:]][transaction.category, default: 0] += 1

            for token in Self.tokens(of: key) {
                byToken[token, default: [:]][transaction.category, default: 0] += 1
            }
        }

        for (title, histogram) in counts {
            guard let (category, count) = histogram.max(by: { $0.value < $1.value }) else { continue }
            // Seen twice, or seen once with a category the user actually chose. A single
            // `.miscellaneous` is the default nobody picked, and treating it as evidence would teach
            // the index to keep suggesting nothing.
            if count >= 2 || category != .miscellaneous {
                byExactTitle[title] = category
            }
        }
    }

    private static func tokens(of normalized: String) -> [String] {
        normalized
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 3 && !$0.allSatisfy(\.isNumber) }
    }

    func lookup(normalizedTitle: String) -> CategorySuggestion? {
        if let category = byExactTitle[normalizedTitle] {
            return CategorySuggestion(category: category, source: .history, confidence: 0.95)
        }
        // Token fallback: "PADARIA CENTRAL LTDA" against a remembered "PADARIA CENTRAL".
        var votes: [TransactionCategory: Int] = [:]
        for token in Self.tokens(of: normalizedTitle) {
            guard let histogram = byToken[token] else { continue }
            for (category, count) in histogram { votes[category, default: 0] += count }
        }
        guard let (category, count) = votes.max(by: { $0.value < $1.value }), count >= 2 else {
            return nil
        }
        return CategorySuggestion(category: category, source: .history, confidence: 0.7)
    }
}

struct DeterministicCategorizer {

    private let history: HistoricalCategoryIndex
    private let rules: MerchantRuleSet

    init(existing: [Transaction], rules: MerchantRuleSet = .shared) {
        self.history = HistoricalCategoryIndex(existing: existing)
        self.rules = rules
    }

    /// Always returns something. `.miscellaneous` with source `.fallback` is a real answer — it says
    /// "nothing here identified this", which is what lets the model layer know it may help.
    func categorize(
        title: CleanedTitle,
        type: TransactionType,
        bankCategory: String? = nil
    ) -> CategorySuggestion {
        let normalized = title.title.normalizedForSearch()

        // 1. What this user already does with this merchant.
        if let fromHistory = history.lookup(normalizedTitle: normalized) {
            return fromHistory
        }

        // 2. The bank's own category, when it maps onto one of ours.
        if let bankCategory,
           let mapped = TransactionCategory.allCases.first(where: {
               $0.key.normalizedForSearch() == bankCategory.normalizedForSearch()
                   || $0.description.normalizedForSearch() == bankCategory.normalizedForSearch()
           }) {
            return CategorySuggestion(category: mapped, source: .bankColumn, confidence: 0.8)
        }

        // 3. Shipped merchant rules.
        if let matched = rules.category(for: normalized, type: type) {
            return CategorySuggestion(category: matched, source: .rules, confidence: 0.75)
        }

        // 4. The payment rail. Weak, but better than nothing, and honestly labelled so the model
        //    layer is allowed to improve on it.
        if let fromRail = railCategory(title: title, normalized: normalized, type: type) {
            return fromRail
        }

        return CategorySuggestion(category: .miscellaneous, source: .fallback, confidence: 0.2)
    }

    private func railCategory(
        title: CleanedTitle, normalized: String, type: TransactionType
    ) -> CategorySuggestion? {
        if type == .income, normalized.contains("salario") || normalized.contains("salary") {
            return CategorySuggestion(category: .salary, source: .rail, confidence: 0.5)
        }
        if normalized.contains("fatura") || normalized.contains("cartao de credito") {
            return CategorySuggestion(category: .creditCard, source: .rail, confidence: 0.5)
        }

        switch title.railHint {
        case "PIX", "TED", "DOC", "Transferência":
            return CategorySuggestion(category: .transfer, source: .rail, confidence: 0.4)
        case "Boleto":
            return CategorySuggestion(category: .bankSlip, source: .rail, confidence: 0.4)
        case "Saque":
            return CategorySuggestion(category: .miscellaneous, source: .rail, confidence: 0.3)
        default:
            return nil
        }
    }
}
