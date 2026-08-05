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
}

struct TagTranslationResult: Equatable {
    let tagId: String
    /// The text this was translated FROM. Carried back so a tag renamed mid-flight can be spotted and
    /// its stale result dropped.
    let sourceText: String
    let translatedText: String
}

// MARK: - Seam

/// The boundary between "which tags need translating" and "how translation happens".
///
/// Exists so the coordinator is testable: Apple's Translation framework does not run in the Simulator
/// at all, so without a seam every test of the orchestration would need a physical device.
@MainActor
protocol TagNameTranslating: AnyObject {
    /// `false` short-circuits everything - no work list is even built.
    var isAvailable: Bool { get }

    /// One call, one pair. Reports why it ended rather than throwing, because the coordinator's
    /// response genuinely differs per reason - see `TagTranslationOutcome`.
    ///
    /// **Cannot present anything.** On iOS 26 a directly-constructed `TranslationSession` has
    /// `canRequestDownloads == false`, so a missing pair comes back as `.notInstalled` instead of
    /// raising a sheet. "A background pass never puts UI on screen" used to be a boolean the caller
    /// had to remember to pass; it is now a property of the API.
    func translate(_ requests: [TagTranslationRequest], pair: TranslationPair) async
        -> TagTranslationOutcome

    /// Asks the system to download a pair, presenting Apple's own consent sheet from `presenter`.
    ///
    /// The presenter is injected because this only ever runs from a Settings tap, and the screen that
    /// owns the tap is the screen the sheet belongs to. Returns when the download *starts*.
    func requestDownload(pair: TranslationPair, from presenter: TranslationSheetPresenting) async
        -> TagLanguageDownloadOutcome
}

/// Used below iOS 26 and in the Simulator. Makes "unavailable" a normal, silent state.
@MainActor
final class NoopTagNameTranslator: TagNameTranslating {
    var isAvailable: Bool { false }
    func translate(_: [TagTranslationRequest], pair: TranslationPair) async -> TagTranslationOutcome {
        .unsupported
    }
    func requestDownload(pair: TranslationPair, from: TranslationSheetPresenting) async
        -> TagLanguageDownloadOutcome { .unsupported }
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

    // MARK: - Constrained resolution

    /// The floor for a detection made against a short candidate list.
    ///
    /// Higher than `confidenceFloor` because it is guarding a much easier question. The unconstrained
    /// recognizer spreads its probability mass over every language it knows; constrained to three, a
    /// hypothesis clearing 0.65 is a stronger claim than one clearing 0.55 out of sixty.
    static let constrainedConfidenceFloor = 0.65

    /// Languages a tag on THIS device could plausibly have been typed in.
    ///
    /// The point of the list is its shortness. `NLLanguageRecognizer` softmaxes over ~60 languages, so
    /// on a six-character string like "Casa" no single hypothesis gets anywhere near a usable
    /// confidence - which is why detection on tag names failed so often. Constraining it collapses
    /// that distribution onto the handful of languages the user actually plausibly types in.
    ///
    /// The target is excluded: a tag already in the phone's language needs no translation, so
    /// "it might be Portuguese" is never a useful answer when Portuguese is where we are heading.
    static func candidateSources(
        target: String,
        recordedSources: Set<String> = [],
        bundleLocalizations: [String] = Bundle.main.localizations,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [String] {
        let targetCode = normalized(target)
        var seen = Set<String>()
        var ordered: [String] = []

        // Recorded sources first: they are observed fact about this user's own tags, where the other
        // two are inference about what they are likely to type.
        for raw in Array(recordedSources).sorted() + preferredLanguages + bundleLocalizations {
            // Xcode synthesises a "Base" localization that is not a language.
            guard raw != "Base" else { continue }
            let code = normalized(raw)
            guard !code.isEmpty, code != targetCode, seen.insert(code).inserted else { continue }
            ordered.append(code)
        }
        return ordered
    }

    /// The language a tag name was written in, or `nil` when it genuinely cannot be established.
    ///
    /// `nil` is a supported answer and the caller must skip the tag. It used to mean "let the
    /// framework detect it", which iOS 26's `TranslationSession(installedSource:target:)` cannot do -
    /// the source is not optional. That is a better constraint than it looks: handed the wrong source
    /// the framework does not fail, it translates "Wealth" as though it were Portuguese and returns
    /// something confident and wrong. A list of plausible nonsense is a worse outcome than a list of
    /// the names the user typed, which is always an acceptable answer here.
    static func resolveSource(
        for name: String,
        target: String,
        recorded: String?,
        candidates: [String]
    ) -> String? {
        let targetCode = normalized(target)

        // 1. Stamped at authoring, where the phone's language was a sound prior. Authoritative.
        if let recorded {
            let code = normalized(recorded)
            return code == targetCode ? nil : code
        }

        // 2a. Only one language this could be. No recognizer call at all - and this is the common
        //     case, not a shortcut: a monolingual English user on a Portuguese phone has exactly one
        //     candidate, so their tags resolve without ever consulting a model.
        guard let first = candidates.first else { return nil }
        if candidates.count == 1 { return first }

        // 2b. Few enough to be a real question. Beyond a handful the constraint stops helping and we
        //     are back to guessing, so decline instead.
        guard candidates.count <= 4 else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map { NLLanguage($0) }
        recognizer.processString(trimmed)
        guard
            let (language, confidence) = recognizer
                .languageHypotheses(withMaximum: 1)
                .max(by: { $0.value < $1.value }),
            confidence >= constrainedConfidenceFloor,
            language != .undetermined
        else { return nil }

        let code = normalized(language.rawValue)
        // The constraint list already excludes the target, but a recognizer is not obliged to honour
        // it, and a source equal to the target is rejected by the framework anyway.
        return code == targetCode ? nil : code
    }
}
