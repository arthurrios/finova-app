//
//  AppleTagNameTranslator.swift
//  Finova
//

import Foundation
import Translation

/// Apple's on-device Translation framework, iOS 26 and up.
///
/// The iOS 18 version of this file kept a 1pt, 1%-opacity `UIHostingController` alive in the key
/// window for the whole life of the app, because `TranslationSession` had no public initialiser and
/// SwiftUI's `.translationTask` was the only thing that would vend one. Everything awkward about that
/// design followed from it: watchdogs to un-wedge a session that never arrived, one driver shared
/// between the background host and a modal, a walk up the controller hierarchy to guess a presenter,
/// and a string match on a class name to avoid landing on the splash.
///
/// iOS 26 added `TranslationSession(installedSource:target:)`, so translating is now a plain object
/// with no view lifetime attached and none of that is needed. The one thing that still requires
/// SwiftUI is asking the user to download a language - see `TagLanguageDownloadPresenter`.
@available(iOS 26.0, *)
@MainActor
final class AppleTagNameTranslator: TagNameTranslating {

    /// The framework does not function in the Simulator: no model is ever vended, so every call
    /// fails. Compiled out rather than discovered at runtime, which keeps the feature silently inert
    /// during simulator development instead of logging a failure per pass.
    var isAvailable: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            return true
        #endif
    }

    func translate(_ requests: [TagTranslationRequest], pair: TranslationPair) async
        -> TagTranslationOutcome
    {
        guard isAvailable, !requests.isEmpty else { return .translated([]) }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: pair.source),
            target: Locale.Language(identifier: pair.target))

        let sourceTexts = Dictionary(uniqueKeysWithValues: requests.map { ($0.tagId, $0.text) })
        do {
            // `translations(from:)` rather than `translate(batch:)`: it preserves order and returns
            // everything at once, so there is no streaming bookkeeping for a handful of short strings.
            let responses = try await session.translations(
                from: requests.map {
                    TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.tagId)
                })
            return .translated(
                responses.compactMap { response in
                    guard let id = response.clientIdentifier, let original = sourceTexts[id] else {
                        return nil
                    }
                    return TagTranslationResult(
                        tagId: id, sourceText: original, translatedText: response.targetText)
                })
        } catch {
            return Self.classify(error)
        }
    }

    func requestDownload(pair: TranslationPair, from presenter: TranslationSheetPresenting) async
        -> TagLanguageDownloadOutcome
    {
        guard isAvailable else { return .unsupported }
        return await TagLanguageDownloadPresenter.requestDownload(pair: pair, from: presenter)
    }

    // MARK: - Errors

    /// Maps a thrown error onto the outcome the coordinator acts on.
    ///
    /// `internal static` rather than a private `catch` ladder on purpose: **this is the only part of
    /// this type a Simulator can exercise**, so it is the only part that can be unit-tested at all,
    /// and the subtleties below are worth pinning.
    ///
    /// `TranslationError` is a *struct* with static members, not an enum, so `error == .notInstalled`
    /// does not compile. Pattern matching does, because `catch` and `switch` patterns call the
    /// `static func ~=` the framework ships.
    ///
    /// `nonisolated` because it is a pure mapping with no reason to need the main actor - and being
    /// callable from anywhere is what lets it be tested without one.
    nonisolated static func classify(_ error: Error) -> TagTranslationOutcome {
        // Cancellation arrives from two domains and neither is a TranslationError. Matched explicitly
        // rather than by pattern because it often turns up bridged as a bare NSError - and mistaking
        // a cancellation for a failure is what used to blacklist tags for a whole process.
        if error is CancellationError { return .cancelled }
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError { return .cancelled }

        switch error {
        // The languages are not on the device and this session may not ask for them. The ONLY error
        // that may offer a download.
        case TranslationError.notInstalled:
            return .notInstalled

        // Stable negatives: this device will not do this pair however many times we ask.
        case TranslationError.unsupportedLanguagePairing,
            TranslationError.unsupportedSourceLanguage,
            TranslationError.unsupportedTargetLanguage:
            return .unsupported

        // Nothing was sent, so nothing failed.
        case TranslationError.nothingToTranslate:
            return .translated([])

        case TranslationError.alreadyCancelled:
            return .cancelled

        // Should be unreachable - a source is always supplied - but retrying next launch is a better
        // response than blacklisting on something we do not understand.
        case TranslationError.unableToIdentifyLanguage:
            return .failed

        default:
            return .failed
        }
    }
}
