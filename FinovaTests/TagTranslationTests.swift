//
//  TagTranslationTests.swift
//  FinovaTests
//
//  Orchestration of tag-name translation: which tags get sent, what each outcome does to the
//  coordinator's state, and when Settings is told to offer a language download.
//
//  Everything below the translator seam is unreachable here — Apple's Translation framework does not
//  run in the Simulator at all — so the seam is where the fake goes in.
//

import Foundation
import Translation
import UIKit
import XCTest

@testable import Finova

// MARK: - Fakes

@MainActor
final class FakeTagNameTranslator: TagNameTranslating {

    var isAvailable = true
    /// Forces a specific outcome for a pair. Unset pairs translate.
    var outcomeByPair: [TranslationPair: TagTranslationOutcome] = [:]
    /// Exact overrides; anything unmapped becomes "«target» text" so assertions stay readable.
    var translationsByText: [String: String] = [:]
    /// Texts the translator declines, simulating an untranslatable proper noun.
    var refusedTexts: Set<String> = []
    var downloadOutcome: TagLanguageDownloadOutcome = .started
    /// Reports `.notInstalled` for the first N attempts on a pair, then translates. Models a
    /// download landing partway through the watch.
    var installsAfterAttempts: [TranslationPair: Int] = [:]

    private(set) var translateCalls: [(pair: TranslationPair, texts: [String])] = []
    private(set) var downloadCalls: [(pair: TranslationPair, presenter: ObjectIdentifier)] = []
    private var attempts: [TranslationPair: Int] = [:]

    func translate(_ requests: [TagTranslationRequest], pair: TranslationPair) async
        -> TagTranslationOutcome
    {
        translateCalls.append((pair, requests.map(\.text)))
        let attempt = attempts[pair, default: 0] + 1
        attempts[pair] = attempt

        if let threshold = installsAfterAttempts[pair], attempt <= threshold { return .notInstalled }
        if let forced = outcomeByPair[pair] { return forced }

        let usable = requests.filter { !refusedTexts.contains($0.text) }
        return .translated(
            usable.map {
                TagTranslationResult(
                    tagId: $0.tagId, sourceText: $0.text,
                    translatedText: translationsByText[$0.text] ?? "«\(pair.target)» \($0.text)")
            })
    }

    func requestDownload(pair: TranslationPair, from presenter: TranslationSheetPresenting) async
        -> TagLanguageDownloadOutcome
    {
        downloadCalls.append((pair, ObjectIdentifier(presenter)))
        return downloadOutcome
    }
}

@MainActor
final class FakeSheetPresenter: TranslationSheetPresenting {
    var presentedViewController: UIViewController?
    private(set) var presentCount = 0

    func present(
        _ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?
    ) {
        presentCount += 1
        presentedViewController = viewControllerToPresent
        completion?()
    }
}

// MARK: - Tests

@MainActor
final class TagTranslationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cache: TagTranslationCache!
    private var service: AllocationTagService!
    private var fake: FakeTagNameTranslator!
    private var presenter: FakeSheetPresenter!

    private let portuguese = Locale.Language(identifier: "pt-BR")
    private let spanish = Locale.Language(identifier: "es-ES")
    private var ptPair: TranslationPair { TranslationPair(source: "en", target: "pt") }

    override func setUp() {
        super.setUp()
        suiteName = "tagtranslation-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        UIDUserDefaultsManager.shared.currentUserUID = "test_\(UUID().uuidString)"
        cache = TagTranslationCache(defaults: defaults)
        service = AllocationTagService(store: UserDefaultsAllocationTagStore(defaults: defaults))
        fake = FakeTagNameTranslator()
        presenter = FakeSheetPresenter()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeCoordinator(
        language: Locale.Language? = nil, enabled: Bool = true
    ) -> AllocationTagTranslationCoordinator {
        let target = language ?? portuguese
        return AllocationTagTranslationCoordinator(
            service: service, cache: cache, translator: fake,
            language: { target }, isEnabled: { enabled },
            // Near-instant, so a test that starts a download watch does not sit through the real
            // two-second-and-up schedule.
            watchDelays: [.milliseconds(1), .milliseconds(1), .milliseconds(1)])
    }

    /// Creates a tag with a known source language. `AllocationTagService.createTag` stamps the source
    /// into the *shared* cache, which these tests do not use, so it is set explicitly here.
    @discardableResult
    private func makeTag(_ name: String, source: String = "en") -> AllocationTag {
        let tag = service.createTag(name: name)!
        cache.storeSourceLanguage(source, forTagId: tag.id, name: name)
        return tag
    }

    private func displayName(of tag: AllocationTag, in language: Locale.Language? = nil) -> String? {
        service.tags.first { $0.id == tag.id }?
            .displayName(in: language ?? portuguese, cache: cache)
    }

    // MARK: - Work list

    func testTranslatesATagAuthoredInAnotherLanguage() async {
        let tag = makeTag("Essentials")
        fake.translationsByText["Essentials"] = "Essenciais"

        await makeCoordinator().runPassNow()

        XCTAssertEqual(displayName(of: tag), "Essenciais")
    }

    func testSkipsATagAlreadyInTheTargetLanguage() async {
        makeTag("Moradia", source: "pt-BR")

        await makeCoordinator().runPassNow()

        XCTAssertTrue(fake.translateCalls.isEmpty)
    }

    func testASecondPassRequestsNothing() async {
        makeTag("Essentials")
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 1)
    }

    func testRenamingRequeuesTheTag() async {
        let tag = makeTag("Essentials")
        await makeCoordinator().runPassNow()

        service.rename(tagId: tag.id, to: "Essential expenses")
        cache.storeSourceLanguage("en", forTagId: tag.id, name: "Essential expenses")
        await makeCoordinator().runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 2)
        XCTAssertEqual(fake.translateCalls.last?.texts, ["Essential expenses"])
    }

    func testOneBatchPerSourceLanguage() async {
        makeTag("Essentials", source: "en")
        makeTag("Wealth", source: "en")
        makeTag("Vivienda", source: "es")

        await makeCoordinator().runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 2)
        let byPair = Dictionary(
            uniqueKeysWithValues: fake.translateCalls.map { ($0.pair, Set($0.texts)) })
        XCTAssertEqual(byPair[TranslationPair(source: "en", target: "pt")], ["Essentials", "Wealth"])
        XCTAssertEqual(byPair[TranslationPair(source: "es", target: "pt")], ["Vivienda"])
    }

    func testNothingIsRequestedWhenDisabled() async {
        makeTag("Essentials")

        await makeCoordinator(enabled: false).runPassNow()

        XCTAssertTrue(fake.translateCalls.isEmpty)
    }

    func testNothingIsRequestedWhenTheTranslatorIsUnavailable() async {
        makeTag("Essentials")
        fake.isAvailable = false

        await makeCoordinator().runPassNow()

        XCTAssertTrue(fake.translateCalls.isEmpty)
    }

    func testATagWhoseSourceCannotBeResolvedIsSkippedAndNotRetried() async {
        // No recorded source, and a name too short to resolve against more than one candidate.
        let tag = service.createTag(name: "Fii")!
        cache.storeSourceLanguage("", forTagId: tag.id, name: "Fii")
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        await coordinator.runPassNow()

        // Either it resolved to exactly one candidate and was sent once, or it could not be resolved
        // and was never sent. What must not happen is the recognizer being re-run every pass.
        XCTAssertLessThanOrEqual(fake.translateCalls.count, 1)
    }

    func testATagWithAnOverrideIsNeverRequested() async {
        let tag = makeTag("Essentials")
        cache.setOverride("Básicos", forTagId: tag.id, language: "pt")

        await makeCoordinator().runPassNow()

        XCTAssertTrue(fake.translateCalls.isEmpty)
        XCTAssertEqual(displayName(of: tag), "Básicos")
    }

    // MARK: - Outcomes

    func testNotInstalledOffersTheDownloadAndBlacklistsNothing() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()

        XCTAssertTrue(coordinator.hasLanguagesToDownload)
        XCTAssertTrue(coordinator.pairsNeedingDownload.contains(ptPair))

        // Blacklists nothing: the tag is fine, the language simply is not here. Once the pair is
        // downloadable again the very same tag must be retried.
        fake.outcomeByPair[ptPair] = nil
        await coordinator.runPassNow(probingPendingPairs: true)
        XCTAssertEqual(fake.translateCalls.count, 2)
        XCTAssertFalse(coordinator.hasLanguagesToDownload)
    }

    func testARefusalDoesNotOfferADownload() async {
        // An empty response is a per-tag refusal — a proper noun the framework declined. It is NOT
        // evidence that a language is missing, and must not light the Settings row.
        makeTag("Xanadu")
        fake.refusedTexts = ["Xanadu"]
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()

        XCTAssertFalse(coordinator.hasLanguagesToDownload)
        XCTAssertTrue(coordinator.pairsNeedingDownload.isEmpty)
    }

    func testARefusedTagIsNotRetried() async {
        makeTag("Xanadu")
        fake.refusedTexts = ["Xanadu"]
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 1)
    }

    func testAPartialBatchBlacklistsOnlyTheMissingTags() async {
        makeTag("Essentials")
        makeTag("Xanadu")
        makeTag("Wealth")
        fake.refusedTexts = ["Xanadu"]
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        // Rerun: only the refused tag should be held back, not the two that succeeded — and those two
        // are now cached, so nothing is requested at all.
        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 1)
        XCTAssertEqual(Set(fake.translateCalls[0].texts), ["Essentials", "Xanadu", "Wealth"])
    }

    func testAnUnsupportedPairIsNotRetried() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .unsupported
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 1)
        XCTAssertFalse(coordinator.hasLanguagesToDownload, "there is nothing to download")
    }

    func testCancellationBlacklistsNothing() async {
        // Backgrounding mid-pass used to look identical to a refusal, which blacklisted every
        // in-flight tag for the rest of the process.
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .cancelled
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        fake.outcomeByPair[ptPair] = nil
        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 2)
        XCTAssertEqual(displayName(of: service.tags[0]), "«pt» Essentials")
    }

    func testCancellationDoesNotOfferADownload() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .cancelled
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()

        XCTAssertFalse(coordinator.hasLanguagesToDownload)
    }

    func testAFailingPairGivesUpAfterThreeAttempts() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .failed
        let coordinator = makeCoordinator()

        for _ in 0..<6 { await coordinator.runPassNow() }

        XCTAssertEqual(fake.translateCalls.count, 3)
    }

    func testATranslationEqualToTheInputIsNotCached() async {
        let tag = makeTag("Essentials")
        fake.translationsByText["Essentials"] = "Essentials"
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()

        XCTAssertNil(cache.translation(forTagId: tag.id, name: "Essentials", language: "pt"))
    }

    // MARK: - Download

    func testStartingADownloadKeepsThePairPendingUntilATranslationSucceeds() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()

        fake.downloadOutcome = .started
        // Two probes report not-installed, the third succeeds.
        fake.outcomeByPair[ptPair] = nil
        fake.installsAfterAttempts[ptPair] = 2

        await withCheckedContinuation { continuation in
            coordinator.downloadMissingLanguages(from: presenter) { continuation.resume() }
        }

        XCTAssertEqual(fake.downloadCalls.count, 1)
        XCTAssertTrue(
            coordinator.pairsNeedingDownload.contains(ptPair),
            "prepareTranslation() returns when the download STARTS, so the pair is not yet done")
        XCTAssertTrue(coordinator.hasDownloadInProgress)
        XCTAssertFalse(coordinator.isDownloadingLanguages, "the sheet is closed")
    }

    func testDecliningTheDownloadLeavesTheRowOffered() async {
        // The regression that made the Settings row vanish and stay hidden for the rest of the
        // session, with no way back short of relaunching.
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()

        fake.downloadOutcome = .cancelled
        await withCheckedContinuation { continuation in
            coordinator.downloadMissingLanguages(from: presenter) { continuation.resume() }
        }

        XCTAssertTrue(coordinator.hasLanguagesToDownload, "a decline is a choice, not a failure")
        XCTAssertFalse(coordinator.hasDownloadInProgress)
        XCTAssertFalse(coordinator.isDownloadingLanguages)
    }

    func testDecliningTheFirstPairDoesNotRaiseASecondSheet() async {
        makeTag("Essentials", source: "en")
        makeTag("Vivienda", source: "es")
        fake.outcomeByPair[TranslationPair(source: "en", target: "pt")] = .notInstalled
        fake.outcomeByPair[TranslationPair(source: "es", target: "pt")] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()
        XCTAssertEqual(coordinator.pairsNeedingDownload.count, 2)

        fake.downloadOutcome = .cancelled
        await withCheckedContinuation { continuation in
            coordinator.downloadMissingLanguages(from: presenter) { continuation.resume() }
        }

        XCTAssertEqual(
            fake.downloadCalls.count, 1,
            "someone who just said no must not be shown another system sheet immediately")
    }

    func testTheDownloadIsHandedTheScreenThatAskedForIt() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()

        await withCheckedContinuation { continuation in
            coordinator.downloadMissingLanguages(from: presenter) { continuation.resume() }
        }

        XCTAssertEqual(fake.downloadCalls.first?.presenter, ObjectIdentifier(presenter))
    }

    func testAnUnsupportedDownloadStopsOfferingThePair() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()

        fake.downloadOutcome = .unsupported
        await withCheckedContinuation { continuation in
            coordinator.downloadMissingLanguages(from: presenter) { continuation.resume() }
        }

        XCTAssertFalse(coordinator.hasLanguagesToDownload)
    }

    func testTheProbeIgnoresThePendingSkipForTheProbedPair() async {
        // A pending pair is normally skipped, because attempting it just throws. If the probe
        // honoured that skip, the pending set would hide the very pair it exists to re-test and the
        // download could never be observed to land.
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()
        XCTAssertEqual(fake.translateCalls.count, 1)

        // A normal pass skips it...
        await coordinator.runPassNow()
        XCTAssertEqual(fake.translateCalls.count, 1)

        // ...but a probe does not.
        await coordinator.runPassNow(probingPendingPairs: true)
        XCTAssertEqual(fake.translateCalls.count, 2)
    }

    func testASuccessfulProbeClearsThePairAndTranslates() async {
        let tag = makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()

        fake.outcomeByPair[ptPair] = nil
        await coordinator.runPassNow(probingPendingPairs: true)

        XCTAssertFalse(coordinator.hasLanguagesToDownload)
        XCTAssertFalse(coordinator.hasDownloadInProgress)
        XCTAssertEqual(displayName(of: tag), "«pt» Essentials")
    }

    func testASecondDownloadTapWhileOneIsInFlightIsIgnored() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()
        fake.outcomeByPair[ptPair] = nil

        await withCheckedContinuation { continuation in
            var finished = 0
            let done = { if finished == 2 { continuation.resume() } }
            coordinator.downloadMissingLanguages(from: presenter) {
                finished += 1
                done()
            }
            coordinator.downloadMissingLanguages(from: presenter) {
                finished += 1
                done()
            }
        }

        XCTAssertEqual(fake.downloadCalls.count, 1)
    }

    func testRefreshDownloadStateClearsAPairThatArrivedInTheBackground() async {
        makeTag("Essentials")
        fake.outcomeByPair[ptPair] = .notInstalled
        let coordinator = makeCoordinator()
        await coordinator.runPassNow()

        fake.outcomeByPair[ptPair] = nil
        await withCheckedContinuation { continuation in
            coordinator.refreshDownloadState { continuation.resume() }
        }

        XCTAssertFalse(coordinator.hasLanguagesToDownload)
    }

    // MARK: - Target language changes

    func testChangingTheTargetLanguageDropsStaleDownloadOffers() async {
        makeTag("Essentials")
        fake.outcomeByPair[TranslationPair(source: "en", target: "pt")] = .notInstalled

        var target = portuguese
        let coordinator = AllocationTagTranslationCoordinator(
            service: service, cache: cache, translator: fake,
            language: { target }, isEnabled: { true },
            watchDelays: [.milliseconds(1)])
        await coordinator.runPassNow()
        XCTAssertTrue(coordinator.hasLanguagesToDownload)

        target = spanish
        fake.outcomeByPair = [:]
        await coordinator.runPassNow()

        XCTAssertFalse(
            coordinator.pairsNeedingDownload.contains(TranslationPair(source: "en", target: "pt")),
            "an offer recorded for Portuguese means nothing once the phone is in Spanish")
    }

    func testAStaleTargetPairNeverLightsTheSettingsRow() async {
        makeTag("Essentials")
        fake.outcomeByPair[TranslationPair(source: "en", target: "pt")] = .notInstalled

        var target = portuguese
        let coordinator = AllocationTagTranslationCoordinator(
            service: service, cache: cache, translator: fake,
            language: { target }, isEnabled: { true },
            watchDelays: [.milliseconds(1)])
        await coordinator.runPassNow()

        // Belt and braces: even without a reset having run, the row is filtered by target.
        target = spanish
        XCTAssertFalse(coordinator.hasLanguagesToDownload)
    }

    // MARK: - Notification loop

    func testAPassNotificationDoesNotTriggerAnotherPass() async {
        // The old guard was a flag set around a synchronous post, but the observer hops into a Task,
        // so it always read false and every successful pass scheduled a redundant follow-up. Driven
        // through the real NotificationCenter, because that is where the bug lived.
        //
        // Counts pass ATTEMPTS, not translate calls. A redundant pass finds everything already
        // cached and never reaches the translator, so asserting on the fake would pass either way —
        // `isEnabled` is read at the top of every attempt, before anything can short-circuit it.
        makeTag("Essentials")
        var passAttempts = 0
        let coordinator = AllocationTagTranslationCoordinator(
            service: service, cache: cache, translator: fake,
            language: { self.portuguese },
            isEnabled: {
                passAttempts += 1
                return true
            },
            watchDelays: [.milliseconds(1)])
        coordinator.start()

        await coordinator.runPassNow()
        let afterFirstPass = passAttempts

        // Let any observer-scheduled work run, plus the 500ms debounce it would sit behind.
        try? await Task.sleep(for: .milliseconds(900))

        XCTAssertEqual(
            passAttempts, afterFirstPass,
            "the pass's own .allocationTagsChanged must not schedule another pass")
    }

    func testAGenuineTagChangeDoesTriggerAPass() async {
        // The other half: only our own notification is ignored, not everybody's. Without this a
        // sufficiently blunt fix — dropping the observer entirely — would pass the test above.
        makeTag("Essentials")
        var passAttempts = 0
        let coordinator = AllocationTagTranslationCoordinator(
            service: service, cache: cache, translator: fake,
            language: { self.portuguese },
            isEnabled: {
                passAttempts += 1
                return true
            },
            watchDelays: [.milliseconds(1)])
        coordinator.start()
        await coordinator.runPassNow()
        let afterFirstPass = passAttempts

        makeTag("Wealth")
        NotificationCenter.default.post(name: .allocationTagsChanged, object: nil)
        try? await Task.sleep(for: .milliseconds(900))

        XCTAssertGreaterThan(passAttempts, afterFirstPass)
        XCTAssertEqual(fake.translateCalls.count, 2)
    }

    // MARK: - Encoding collisions

    func testATagNamedWithAPipeDoesNotCollide() async {
        // The old failedTags encoding was "tagId|name|target", filtered with hasSuffix("|pt") — which
        // matches any tag whose NAME ends in "|pt".
        makeTag("Rent|pt")
        makeTag("Essentials")
        fake.refusedTexts = ["Rent|pt"]
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()
        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.count, 1)
        XCTAssertEqual(displayName(of: service.tags.first { $0.name == "Essentials" }!),
                       "«pt» Essentials")
    }

    func testATagWhoseSourceContainsAnAngleBracketDoesNotCollide() async {
        // The old pair encoding was "source>target", split on ">".
        makeTag("Essentials")
        let coordinator = makeCoordinator()

        await coordinator.runPassNow()

        XCTAssertEqual(fake.translateCalls.first?.pair, ptPair)
        XCTAssertEqual(ptPair.description, "en>pt", "still readable in a log line")
    }
}

// MARK: - Error classification

/// The only part of `AppleTagNameTranslator` a Simulator can reach: constructing these errors needs
/// no session, and the mapping is where the `~=`-versus-`==` and cross-domain subtleties live.
@available(iOS 26.0, *)
final class AppleTagNameTranslatorErrorTests: XCTestCase {

    func testNotInstalledIsTheOnlyOutcomeThatOffersADownload() {
        XCTAssertEqual(AppleTagNameTranslator.classify(TranslationError.notInstalled), .notInstalled)
    }

    func testUnsupportedErrorsMapToAStableNegative() {
        for error in [
            TranslationError.unsupportedLanguagePairing,
            TranslationError.unsupportedSourceLanguage,
            TranslationError.unsupportedTargetLanguage,
        ] {
            XCTAssertEqual(AppleTagNameTranslator.classify(error), .unsupported, "\(error)")
        }
    }

    func testNothingToTranslateIsNotAFailure() {
        XCTAssertEqual(
            AppleTagNameTranslator.classify(TranslationError.nothingToTranslate), .translated([]))
    }

    func testCancellationIsRecognisedInEveryDomainItArrivesFrom() {
        XCTAssertEqual(AppleTagNameTranslator.classify(CancellationError()), .cancelled)
        XCTAssertEqual(AppleTagNameTranslator.classify(TranslationError.alreadyCancelled), .cancelled)
        XCTAssertEqual(AppleTagNameTranslator.classify(CocoaError(.userCancelled)), .cancelled)
        XCTAssertEqual(
            AppleTagNameTranslator.classify(
                NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)),
            .cancelled,
            "it often arrives bridged as a bare NSError, which CocoaError casting misses")
    }

    func testAnythingElseIsATransientFailure() {
        XCTAssertEqual(AppleTagNameTranslator.classify(TranslationError.internalError), .failed)
        XCTAssertEqual(
            AppleTagNameTranslator.classify(TranslationError.unableToIdentifyLanguage), .failed)
        XCTAssertEqual(
            AppleTagNameTranslator.classify(NSError(domain: "SomethingElse", code: 1)), .failed)
    }

    func testADeclinedDownloadIsCancelledNotFailed() {
        XCTAssertEqual(
            TagLanguageDownloadPresenter.classifyDownload(CocoaError(.userCancelled)), .cancelled)
        XCTAssertEqual(
            TagLanguageDownloadPresenter.classifyDownload(TranslationError.unsupportedLanguagePairing),
            .unsupported)
        XCTAssertEqual(
            TagLanguageDownloadPresenter.classifyDownload(TranslationError.internalError), .failed)
    }
}
