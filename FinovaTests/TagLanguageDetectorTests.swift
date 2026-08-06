//
//  TagLanguageDetectorTests.swift
//  FinovaTests
//
//  Working out what language a tag name was typed in — the step that decides whether a tag can be
//  translated at all, since iOS 26's TranslationSession needs a concrete source language.
//

import Foundation
import XCTest

@testable import Finova

final class TagLanguageDetectorTests: XCTestCase {

    // MARK: - normalized

    func testNormalizationStripsTheRegion() {
        XCTAssertEqual(TagLanguageDetector.normalized("pt-BR"), "pt")
        XCTAssertEqual(TagLanguageDetector.normalized("en-BR"), "en")
        XCTAssertEqual(TagLanguageDetector.normalized("en"), "en")
    }

    // MARK: - candidateSources

    func testCandidatesExcludeTheTarget() {
        let candidates = TagLanguageDetector.candidateSources(
            target: "pt-BR",
            recordedSources: ["en", "pt"],
            bundleLocalizations: ["en", "pt-BR"],
            preferredLanguages: ["pt-BR", "en-US"])

        XCTAssertFalse(candidates.contains("pt"), "the target is never a useful source")
        XCTAssertEqual(candidates, ["en"])
    }

    func testCandidatesDropBaseAndDeduplicateAcrossSources() {
        let candidates = TagLanguageDetector.candidateSources(
            target: "de",
            recordedSources: ["en"],
            bundleLocalizations: ["Base", "en", "pt-BR"],
            preferredLanguages: ["en-US", "pt-BR", "es-ES"])

        XCTAssertFalse(candidates.contains("Base"))
        XCTAssertEqual(Set(candidates), ["en", "pt", "es"])
        XCTAssertEqual(candidates.count, 3, "en arrives from three places and must appear once")
    }

    func testRecordedSourcesComeFirst() {
        let candidates = TagLanguageDetector.candidateSources(
            target: "pt",
            recordedSources: ["de"],
            bundleLocalizations: ["en"],
            preferredLanguages: ["es"])

        XCTAssertEqual(
            candidates.first, "de",
            "a language this user has actually typed in outranks one they merely might")
    }

    // MARK: - resolveSource

    func testARecordedSourceIsUsedVerbatimAndNeedsNoDetection() {
        // "Casa" is far too short to detect, so a resolution here can only have come from the stamp.
        let source = TagLanguageDetector.resolveSource(
            for: "Casa", target: "en", recorded: "pt-BR", candidates: ["de", "es", "fr", "it"])

        XCTAssertEqual(source, "pt", "recorded is authoritative, and normalized on the way out")
    }

    func testARecordedSourceMatchingTheTargetResolvesToNil() {
        let source = TagLanguageDetector.resolveSource(
            for: "Moradia", target: "pt-BR", recorded: "pt-BR", candidates: ["en"])

        XCTAssertNil(source, "there is nothing to translate between a language and itself")
    }

    func testASingleCandidateNeedsNoRecognizer() {
        // The common case: a monolingual English user on a Portuguese phone. "Rent" is four
        // characters and would never clear a confidence floor, but it does not have to — there is
        // only one language it could be.
        let source = TagLanguageDetector.resolveSource(
            for: "Rent", target: "pt", recorded: nil, candidates: ["en"])

        XCTAssertEqual(source, "en")
    }

    func testNoCandidatesResolvesToNil() {
        let source = TagLanguageDetector.resolveSource(
            for: "Essentials", target: "pt", recorded: nil, candidates: [])

        XCTAssertNil(source)
    }

    func testTooManyCandidatesDeclineRatherThanGuess() {
        // Past a handful the constraint stops collapsing the distribution and we are guessing again.
        // A wrong source is worse than no translation: the framework does not fail on one, it
        // returns confident nonsense.
        let source = TagLanguageDetector.resolveSource(
            for: "Essentials", target: "pt", recorded: nil,
            candidates: ["en", "es", "fr", "de", "it"])

        XCTAssertNil(source)
    }

    func testATooShortNameIsNotGuessedFromMultipleCandidates() {
        let source = TagLanguageDetector.resolveSource(
            for: "Fii", target: "pt", recorded: nil, candidates: ["en", "es"])

        XCTAssertNil(source, "three characters cannot distinguish English from Spanish")
    }

    func testConstrainedDetectionResolvesALongerNameAgainstTwoCandidates() {
        // The whole point of the candidate list: unconstrained, this string does not clear 0.55
        // against sixty languages. Against two it is a real question with a real answer.
        let source = TagLanguageDetector.resolveSource(
            for: "Essential household expenses", target: "pt", recorded: nil,
            candidates: ["en", "es"])

        XCTAssertEqual(source, "en")
    }

    func testResolutionNeverReturnsTheTarget() {
        // Belt and braces: the candidate list already excludes the target, but the recognizer is not
        // obliged to honour languageConstraints, and the framework rejects a same-language pair.
        for name in ["Essential household expenses", "Despesas essenciais da casa", "Casa"] {
            let source = TagLanguageDetector.resolveSource(
                for: name, target: "pt", recorded: nil, candidates: ["en", "es"])
            XCTAssertNotEqual(source, "pt", "\(name) resolved to the target")
        }
    }

    // MARK: - detectAtAuthoring

    func testAuthoringDetectionFallsBackToThePhoneLanguage() {
        // "Fii" is below the length floor, so nothing is detected and the phone's language stands in.
        let source = TagLanguageDetector.detectAtAuthoring(
            "Fii", authoredIn: Locale.Language(identifier: "pt-BR"))

        XCTAssertEqual(source, "pt")
    }

    func testAuthoringDetectionAgreesWithTheAuthoringLanguage() {
        let source = TagLanguageDetector.detectAtAuthoring(
            "Despesas essenciais da casa", authoredIn: Locale.Language(identifier: "pt-BR"))

        XCTAssertEqual(source, "pt")
    }

    /// Pins the `minimalIdentifier` behaviour the rest of this feature is built on, because it is
    /// asymmetric in a way nothing in the API name suggests: a region is dropped when it is the
    /// language's *likely* one and kept when it is not. So "pt-BR" collapses to "pt" (Brazil being
    /// where most Portuguese speakers are) while "en-BR" survives intact — which is exactly the case
    /// `normalized` exists to flatten, since asking the framework for en-BR→pt can miss assets that
    /// en→pt would have found.
    func testMinimalIdentifierDropsOnlyTheLikelyRegion() {
        XCTAssertEqual(Locale.Language(identifier: "pt-BR").minimalIdentifier, "pt")
        XCTAssertEqual(Locale.Language(identifier: "en-US").minimalIdentifier, "en")
        XCTAssertEqual(Locale.Language(identifier: "pt-PT").minimalIdentifier, "pt-PT")
        XCTAssertEqual(Locale.Language(identifier: "en-BR").minimalIdentifier, "en-BR")

        XCTAssertEqual(TagLanguageDetector.normalized("en-BR"), "en")
        XCTAssertEqual(TagLanguageDetector.normalized("pt-PT"), "pt")
    }
}
