//
//  FoundationModelsCategorizer.swift
//  Finova
//
//  On-device category suggestions, iOS 26+.
//
//  Strictly an enhancement. The review screen is already complete and correct from the deterministic
//  tiers before this is asked anything, and it may only improve rows the deterministic engine already
//  admitted it was guessing about. It never touches dates, amounts or duplicate detection — a model
//  that "fixes" an ambiguous date is silent data corruption with no audit trail.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

/// The category vocabulary, as an enum rather than a `String` with a `@Guide`.
///
/// Guided generation constrains the decoder to these cases, so an out-of-vocabulary answer is
/// structurally impossible. A `@Guide` on a String is a suggestion the model can violate, and on a
/// long enough run it will.
@available(iOS 26.0, *)
@Generable
enum GenerableCategory: String, CaseIterable {
    case market, meals, gifts, salary, utilities, entertainment, transportation
    case healthcare, subscriptions, education, travel, groceries, insurance
    case savings, investments, taxes, loans, donations, miscellaneous, clothing
    case personalCare, homeMaintenance, communication, fitness, transfer
    case bankSlip, creditCard
}

@available(iOS 26.0, *)
@Generable
struct CategorizedMerchant {
    @Guide(description: "The id echoed back from the input, unchanged.")
    let id: Int
    @Guide(description: "The single best category for this merchant.")
    let category: GenerableCategory
}

@available(iOS 26.0, *)
@Generable
struct CategorizedMerchantBatch {
    @Guide(description: "Exactly one entry for each merchant in the input.")
    let items: [CategorizedMerchant]
}

@available(iOS 26.0, *)
final class FoundationModelsCategorizer: TransactionCategorizing {

    /// Merchants per prompt. Small enough that a single bad generation costs little, large enough
    /// that a typical statement takes only a handful of round trips.
    private static let batchSize = 30

    /// The whole model pass is bounded. It runs after the diff is already on screen, so exceeding
    /// this simply means the user keeps the deterministic answer.
    private static let overallBudget: TimeInterval = 8

    private var session: LanguageModelSession?

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func categorize(
        _ requests: [CategorizationRequest],
        examples: [CategorizationExample]
    ) async -> CategorizationOutcome {
        // Checked at CALL time, not at init: availability moves from `.modelNotReady` to
        // `.available` mid-session as assets finish downloading.
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled):
            return .unsupported          // stable for this device; do not retry
        case .unavailable(.modelNotReady):
            return .notReady             // soft; retryable, but never waited on
        case .unavailable:
            return .unsupported
        }

        guard !requests.isEmpty else { return .categorized([:]) }

        // Ask about DISTINCT merchants, not rows. A 2,000-row statement has on the order of 150
        // distinct titles; that reduction is the difference between viable and not.
        var byTitle: [String: [Int]] = [:]
        for request in requests {
            byTitle[request.title.normalizedForSearch(), default: []].append(request.id)
        }
        let distinct = byTitle.keys.sorted()

        let session = makeSession(examples: examples)
        self.session = session
        session.prewarm()

        var resolved: [Int: TransactionCategory] = [:]
        let deadline = Date().addingTimeInterval(Self.overallBudget)

        for chunk in stride(from: 0, to: distinct.count, by: Self.batchSize).map({
            Array(distinct[$0..<min($0 + Self.batchSize, distinct.count)])
        }) {
            if Task.isCancelled { return .cancelled }
            // Partial results are still useful — return what landed rather than discarding it.
            if Date() >= deadline { break }

            // Indices are local to the chunk so the model never sees the app's row identifiers.
            let numbered = chunk.enumerated().map { "\($0.offset): \($0.element)" }
                .joined(separator: "\n")

            do {
                let response = try await session.respond(
                    to: "Categorize these merchants:\n\(numbered)",
                    generating: CategorizedMerchantBatch.self)

                for item in response.content.items {
                    guard chunk.indices.contains(item.id) else { continue }
                    let title = chunk[item.id]
                    // Defence in depth: guided generation should make this impossible, but an
                    // unresolvable key is dropped rather than guessed at.
                    guard let category = TransactionCategory.allCases.first(where: {
                        $0.key == item.category.rawValue
                    }) else { continue }
                    for rowId in byTitle[title] ?? [] { resolved[rowId] = category }
                }
            } catch {
                logWarning("[Import] On-device categorization failed for one batch: \(error)")
                continue
            }
        }

        return resolved.isEmpty ? .failed : .categorized(resolved)
    }

    private func makeSession(examples: [CategorizationExample]) -> LanguageModelSession {
        var instructions = """
            You label bank-statement merchant names with one spending category each.
            Answer only with a category from the provided set. If a merchant is unclear, \
            choose miscellaneous rather than guessing.
            """

        // The user's own history goes in the INSTRUCTIONS, not in each prompt: it is constant across
        // batches, so it belongs in the reusable cached prefix.
        if !examples.isEmpty {
            let rendered = examples.prefix(60)
                .map { "\($0.title) -> \($0.categoryKey)" }
                .joined(separator: "\n")
            instructions += "\n\nThis person has previously categorized:\n\(rendered)"
        }

        return LanguageModelSession(instructions: instructions)
    }
}

#else

/// The framework is unavailable at compile time (older SDK). Keeps the factory compiling.
@available(iOS 26.0, *)
final class FoundationModelsCategorizer: TransactionCategorizing {
    var isAvailable: Bool { false }
    func categorize(
        _ requests: [CategorizationRequest], examples: [CategorizationExample]
    ) async -> CategorizationOutcome {
        .unsupported
    }
}

#endif

// MARK: - Applying model output to a plan

enum ModelCategoryRefinement {

    /// Which rows the model is permitted to change, and the few-shot examples to steer it with.
    ///
    /// Only rows whose deterministic source was `.rail` or `.fallback` — i.e. where the engine
    /// already said it was guessing. A `.history` match must never be overwritten: what this user has
    /// actually done with a merchant beats any model's opinion about it, every time.
    static func requests(from plan: ImportPlan) -> [CategorizationRequest] {
        plan.rows.compactMap { row in
            guard let parsed = row.parsed,
                  let source = row.categorySuggestion?.source,
                  source == .fallback || source == .rail else { return nil }
            return CategorizationRequest(
                id: row.id,
                title: parsed.title.title,
                isIncome: parsed.signedCents > 0)
        }
    }

    /// Few-shot examples drawn from the user's own ledger.
    ///
    /// Filtered to drop long digit runs and payee names: a shorter, generic form works better as a
    /// hint anyway, and there is no reason to put someone's full name into a prompt.
    static func examples(from existing: [Transaction], perCategory: Int = 3) -> [CategorizationExample] {
        var byCategory: [TransactionCategory: [String]] = [:]

        for transaction in existing.reversed() where transaction.category != .miscellaneous {
            let title = transaction.title.trimmingCharacters(in: .whitespaces)
            guard title.count >= 3, title.count <= 40 else { continue }
            guard !title.contains(where: { $0.isNumber }) || title.filter(\.isNumber).count <= 2
            else { continue }
            guard title.normalizedForSearch().range(of: "pix para|transferencia para",
                                                    options: .regularExpression) == nil else { continue }

            var seen = byCategory[transaction.category] ?? []
            guard seen.count < perCategory,
                  !seen.contains(where: { $0.normalizedForSearch() == title.normalizedForSearch() })
            else { continue }
            seen.append(title)
            byCategory[transaction.category] = seen
        }

        return byCategory.flatMap { category, titles in
            titles.map { CategorizationExample(title: $0, categoryKey: category.key) }
        }
    }

    /// Folds model output back into a plan as ONE atomic replacement.
    ///
    /// Never streamed row by row: categories changing under the user's finger while they read the
    /// diff is worse than not helping at all. A row the user has already overridden is left alone.
    static func apply(
        _ categories: [Int: TransactionCategory],
        to plan: ImportPlan,
        overrides: ImportOverrides
    ) -> ImportPlan {
        guard !categories.isEmpty else { return plan }

        let updated = plan.rows.map { row -> ImportRow in
            guard let category = categories[row.id],
                  let existing = row.categorySuggestion,
                  existing.source == .fallback || existing.source == .rail,
                  overrides.override(for: row.fingerprint)?.categoryKey == nil
            else { return row }

            return ImportRow(
                id: row.id, rawCells: row.rawCells, fingerprint: row.fingerprint,
                parsed: row.parsed, disposition: row.disposition,
                categorySuggestion: CategorySuggestion(
                    category: category, source: .model, confidence: 0.6),
                warnings: row.warnings)
        }

        return ImportPlan(source: plan.source, schema: plan.schema,
                          confidence: plan.confidence, rows: updated)
    }
}
