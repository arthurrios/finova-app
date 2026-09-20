//
//  TransactionCategorizing.swift
//  Finova
//
//  The seam between deterministic categorization and the optional on-device model.
//
//  Shaped after `TagNameTranslating` / `AppleTagNameTranslator`: a protocol, a no-op implementation,
//  and the real one behind `@available`. The deployment target is iOS 17.6 and `FoundationModels`
//  needs iOS 26, so the model can only ever be an enhancement — the plan must be complete and
//  correct before it is asked anything.
//

import Foundation

struct CategorizationRequest: Equatable {
    /// Echoed back by the model so results can be matched to rows without relying on ordering.
    let id: Int
    let title: String
    let isIncome: Bool
}

/// A few of the user's own past categorizations, used to steer the model toward their habits.
struct CategorizationExample: Equatable {
    let title: String
    let categoryKey: String
}

enum CategorizationOutcome: Equatable {
    case categorized([Int: TransactionCategory])
    /// This device or this build will never have the model. Do not retry.
    case unsupported
    /// The model exists but is not ready yet — assets still downloading. Retryable, but never
    /// waited on.
    case notReady
    case cancelled
    case failed
}

protocol TransactionCategorizing: AnyObject {
    var isAvailable: Bool { get }
    func categorize(
        _ requests: [CategorizationRequest],
        examples: [CategorizationExample]
    ) async -> CategorizationOutcome
}

/// What every device below iOS 26 gets, and what the tests use.
final class NoopTransactionCategorizer: TransactionCategorizing {
    var isAvailable: Bool { false }
    func categorize(
        _ requests: [CategorizationRequest], examples: [CategorizationExample]
    ) async -> CategorizationOutcome {
        .unsupported
    }
}

enum TransactionCategorizerFactory {
    /// The best available categorizer for this device.
    static func make() -> TransactionCategorizing {
        #if targetEnvironment(simulator)
        // The simulator advertises the framework but has no model assets, so every call would stall
        // and then fail. Same call the translation layer makes.
        return NoopTransactionCategorizer()
        #else
        if #available(iOS 26.0, *) {
            return FoundationModelsCategorizer()
        }
        return NoopTransactionCategorizer()
        #endif
    }
}
