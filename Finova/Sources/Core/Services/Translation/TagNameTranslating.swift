//
//  TagNameTranslating.swift
//  Finova
//

import Foundation
import NaturalLanguage

// MARK: - Wire types

struct TagTranslationRequest: Equatable {
    let tagId: String
    let text: String
    /// `Locale.Language.minimalIdentifier`, or `nil` to let the framework detect it.
    let sourceLanguage: String?
}

struct TagTranslationResult: Equatable {
    let tagId: String
    /// The text this was translated FROM. Carried back so a tag renamed mid-flight can be spotted and
    /// its stale result dropped.
    let sourceText: String
    let translatedText: String
}

enum TagTranslationAvailability {
    case installed
    /// The OS supports the pair but has not downloaded it. Needs the user's consent, so never done
    /// silently.
    case needsDownload
    case unsupported
}

// MARK: - Seam

/// The boundary between "which tags need translating" and "how translation happens".
///
/// Exists so the coordinator is testable: Apple's Translation framework does not run in the Simulator
/// at all, so without a seam every test of the orchestration would need a physical device.
@MainActor
protocol TagNameTranslating: AnyObject {
    /// `false` short-circuits everything - no host view is created, no work list built.
    var isAvailable: Bool { get }
    func availability(from source: String?, to target: String) async -> TagTranslationAvailability
    /// One call, one source→target pair. Returns `[]` on any failure rather than throwing: a failed
    /// translation is a cosmetic non-event, and the caller's response to every error is identical.
    /// - Parameter presentingUI: when true the call runs from a presented modal, so the framework may
    ///   raise its own download sheet and complete the download as part of the same operation. False
    ///   uses the silent background host, which must never produce UI.
    func translate(_ requests: [TagTranslationRequest], to target: String, presentingUI: Bool) async
        -> [TagTranslationResult]
    /// Whether a sheet can safely be shown right now - i.e. the app is active and the screen it would
    /// appear over is not about to be replaced.
    var canPresentUI: Bool { get }
    /// Downloads a language pair, presenting the system's own consent UI.
    ///
    /// Separate from `translate` because it is the only part of this feature that puts something on
    /// screen, so it must be driven by a deliberate user action rather than a background pass.
    func prepare(from source: String?, to target: String) async -> Bool
}

/// Used below iOS 18 and in the Simulator. Makes "unavailable" a normal, silent state.
@MainActor
final class NoopTagNameTranslator: TagNameTranslating {
    var isAvailable: Bool { false }
    func availability(from: String?, to: String) async -> TagTranslationAvailability { .unsupported }
    func translate(_: [TagTranslationRequest], to: String, presentingUI: Bool) async
        -> [TagTranslationResult] { [] }
    var canPresentUI: Bool { false }
    func prepare(from: String?, to: String) async -> Bool { false }
}

// MARK: - Source language

enum TagLanguageDetector {

    /// Reduces an identifier to its bare language code: "en-BR" -> "en", "pt-BR" -> "pt".
    ///
    /// A region-qualified SOURCE is meaningless to the translation framework and actively harmful:
    /// a phone set to English-in-Brazil yields "en-BR", and asking for en-BR→pt can miss the assets
    /// that en→pt would have found. Regions matter for the display cache (pt-BR and pt-PT are
    /// different answers) but not for asking what a phrase means.
    static func normalized(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
    }

    /// `NLLanguageRecognizer` is unreliable on one- and two-word strings, which is what every tag name
    /// is ("Wealth", "Casa"). So it is only trusted above a confidence floor and on inputs long enough
    /// to carry a signal; otherwise the phone's language at the moment of typing is the better prior.
    static let confidenceFloor = 0.55
    static let minimumLength = 4

    /// A confident guess, or `nil`.
    ///
    /// Returns `nil` rather than a fallback on purpose. A fallback of "the phone's language" is a good
    /// prior at the moment of typing, and a bad one applied retroactively to a tag that already
    /// exists: it makes every hard-to-detect name look like it is already in the target language, so
    /// the tag is skipped as "nothing to do" and never translated. `nil` means "don't know", and the
    /// caller asks the framework to work it out instead.
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard
            let (language, confidence) = recognizer
                .languageHypotheses(withMaximum: 1)
                .max(by: { $0.value < $1.value }),
            confidence >= confidenceFloor,
            language != .undetermined
        else { return nil }

        return Locale.Language(identifier: language.rawValue).minimalIdentifier
    }

    /// For the moment a tag is CREATED, where the phone's language is a sound prior for anything the
    /// recognizer cannot pin down on its own.
    static func detectAtAuthoring(
        _ text: String,
        authoredIn authoring: Locale.Language = Locale.current.language
    ) -> String {
        guard let detected = detect(text) else { return authoring.minimalIdentifier }
        // Keep the authoring region when the language agrees: "pt-BR", not a vaguer "pt".
        if Locale.Language(identifier: detected).languageCode == authoring.languageCode {
            return authoring.minimalIdentifier
        }
        return detected
    }
}
