//
//  AllocationTagTranslationCoordinator.swift
//  Finova
//

import Foundation
import UIKit

/// Decides which tag names need translating and gets them into the cache.
///
/// **Lifecycle-driven, never render-driven.** Translating on first render would loop:
/// `MonthCarouselCell` observes `.allocationTagsChanged` and rebuilds, so render → translate → notify
/// → render. The two events that can genuinely change the answer are "the tag set changed" and "the
/// app came forward, possibly in a new language", so those are the only triggers.
///
/// **A pass never puts anything on screen.** Apple's language-download sheet appears only when the
/// user taps for it in Settings. The previous version let a pass raise it from any non-splash screen,
/// so an unannounced system modal could land over whatever the user was looking at — and if they
/// declined, the pair was never recorded as pending, so the Settings row that would have let them
/// retry stayed hidden for the rest of the session.
extension Notification.Name {
    /// A language download finished, or its state changed. Settings redraws its row on this.
    static let tagTranslationDownloadStateChanged = Notification.Name(
        "tagTranslationDownloadStateChanged")
}

@MainActor
final class AllocationTagTranslationCoordinator {

    static let shared = AllocationTagTranslationCoordinator()

    private let service: AllocationTagService
    private let cache: TagTranslationCache
    private let translator: TagNameTranslating
    private let language: () -> Locale.Language
    private let isEnabled: () -> Bool
    /// How long to wait between probes for a started download. Injected only so tests do not sit
    /// through the real schedule.
    private let watchDelays: [Duration]

    private var pass: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var downloadWatch: Task<Void, Never>?
    private var started = false
    private var lastTarget: String?

    /// Identifies notifications this coordinator posted itself, so its own write does not schedule
    /// another pass. A flag set around the `post` does not work: `post` is synchronous but the
    /// observer hops into a `Task`, so by the time the guard runs the flag is already back to false.
    /// Comparing identity is independent of turn ordering.
    private static let selfInflicted = NSObject()

    /// Pairs this device cannot do at all, and individual tags whose translation came back missing.
    /// All in-memory: a fresh launch is allowed to try again, but one session must not retry in a
    /// loop. `failedTags` includes the name, so a rename legitimately re-queues.
    private var unsupportedPairs = Set<TranslationPair>()
    private var failedTags = Set<TagFingerprint>()
    /// Tags whose source language could not be established. Recorded so the recognizer is not re-run
    /// for them every pass; never persisted, because a persisted guess is what made tags permanently
    /// un-translatable before.
    private var unresolvedSourceTags = Set<TagFingerprint>()
    private var pairFailureCounts: [TranslationPair: Int] = [:]
    private static let maxFailuresPerPair = 3

    /// Pairs the device has not downloaded. Recorded, never prompted for.
    private(set) var pairsNeedingDownload = Set<TranslationPair>()
    /// Pairs whose download the user has started. They stay in `pairsNeedingDownload` - the download
    /// is NOT finished - but Settings shows them as in progress rather than as a fresh offer.
    private(set) var pairsDownloading = Set<TranslationPair>()

    init(
        service: AllocationTagService = .shared,
        cache: TagTranslationCache = .shared,
        translator: TagNameTranslating? = nil,
        language: @escaping () -> Locale.Language = { Locale.current.language },
        isEnabled: @escaping () -> Bool = { UserDefaultsManager.isTagNameTranslationEnabled() },
        watchDelays: [Duration] = AllocationTagTranslationCoordinator.watchBackoff
    ) {
        self.service = service
        self.cache = cache
        self.language = language
        self.isEnabled = isEnabled
        self.watchDelays = watchDelays
        if let translator {
            self.translator = translator
        } else if #available(iOS 26.0, *) {
            self.translator = AppleTagNameTranslator()
        } else {
            self.translator = NoopTagNameTranslator()
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resetIfTargetChanged()
                // A download still running when the app went away needs picking back up.
                if !self.pairsDownloading.isEmpty { self.startDownloadWatch() }
                self.reconcile()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .allocationTagsChanged, object: nil, queue: .main
        ) { [weak self] note in
            // Ignore the notification our own write produced.
            guard (note.object as AnyObject?) !== Self.selfInflicted else { return }
            Task { @MainActor in self?.reconcile() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        }

        // Deliberately no pass here. `start()` runs from `scene(willConnectTo:)`, while the splash is
        // still up and the root view controller is about to be replaced. `didBecomeActive` covers the
        // real first opportunity.
    }

    /// Coalesces a burst of tag edits into one pass.
    func reconcile() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.runPass()
        }
    }

    private func suspend() {
        debounce?.cancel()
        pass?.cancel()
        downloadWatch?.cancel()
        downloadWatch = nil
        // Deliberately NOT downloadTask: Apple's consent sheet backgrounds the app while it is up, so
        // cancelling here would kill the very flow the user is looking at.
    }

    /// Drops state that belonged to a target language the phone is no longer in.
    ///
    /// Without this a pending `en>pt` recorded before a switch to Spanish would be probed as `en>es`,
    /// and an answer about Spanish would clear or keep the Portuguese offer.
    private func resetIfTargetChanged() {
        let target = language().minimalIdentifier
        guard lastTarget != target else { return }
        lastTarget = target

        pairsNeedingDownload = pairsNeedingDownload.filter { $0.target == target }
        pairsDownloading = pairsDownloading.filter { $0.target == target }
        unsupportedPairs = unsupportedPairs.filter { $0.target == target }
        failedTags = failedTags.filter { $0.target == target }
        unresolvedSourceTags = unresolvedSourceTags.filter { $0.target == target }
        pairFailureCounts = pairFailureCounts.filter { $0.key.target == target }
        downloadWatch?.cancel()
        downloadWatch = nil
        postDownloadStateChanged()
    }

    // MARK: - Settings surface

    /// Whether Settings should offer the download row. Filtered by the current target as well as by
    /// `resetIfTargetChanged`, so a missed reset can never light a row for a language the phone has
    /// already left.
    var hasLanguagesToDownload: Bool {
        let target = language().minimalIdentifier
        return pairsNeedingDownload.contains { $0.target == target }
    }

    /// True only while Apple's sheet is up. Derived rather than a flag with several assignment sites,
    /// which is how the old one could latch on "Downloading…" forever.
    var isDownloadingLanguages: Bool { downloadTask != nil }

    /// A download has been started and has not yet been observed to land.
    var hasDownloadInProgress: Bool {
        let target = language().minimalIdentifier
        return pairsDownloading.contains { $0.target == target }
    }

    private func postDownloadStateChanged() {
        NotificationCenter.default.post(name: .tagTranslationDownloadStateChanged, object: nil)
    }

    /// Downloads every pair the last pass found missing, then re-runs.
    ///
    /// - Parameter presenter: the screen Apple's sheet appears over. Injected because the only caller
    ///   is a Settings tap, and that is the screen the user chose to be on.
    func downloadMissingLanguages(
        from presenter: TranslationSheetPresenting, completion: (() -> Void)? = nil
    ) {
        guard downloadTask == nil else {
            completion?()
            return
        }
        resetIfTargetChanged()
        let target = language().minimalIdentifier
        let pending = pairsNeedingDownload
            .filter { $0.target == target }
            .sorted { $0.source < $1.source }
        guard !pending.isEmpty else {
            completion?()
            return
        }

        downloadTask = Task { @MainActor [weak self] in
            defer {
                self?.downloadTask = nil
                completion?()
                self?.postDownloadStateChanged()
            }
            for pair in pending {
                guard let self, !Task.isCancelled else { return }
                switch await self.translator.requestDownload(pair: pair, from: presenter) {
                case .started:
                    // Stays in pairsNeedingDownload: prepareTranslation() returns when the download
                    // STARTS. Only a translation actually succeeding proves the pair is usable.
                    self.pairsDownloading.insert(pair)
                    // An earlier cancelled attempt may have blacklisted these tags. Let them back in.
                    self.failedTags = self.failedTags.filter { $0.target != pair.target }
                    self.pairFailureCounts[pair] = nil
                    self.postDownloadStateChanged()
                    self.startDownloadWatch()
                case .cancelled:
                    // The offer stands - a decline is a legitimate choice, not a failure, and the row
                    // must stay tappable. Returning rather than continuing, so a user who has just
                    // said no is not immediately shown a second system sheet.
                    self.pairsDownloading.remove(pair)
                    return
                case .unsupported:
                    self.pairsNeedingDownload.remove(pair)
                    self.pairsDownloading.remove(pair)
                    self.unsupportedPairs.insert(pair)
                case .failed:
                    self.pairsDownloading.remove(pair)
                }
            }
        }
    }

    /// Watches for a started download to actually land.
    ///
    /// **The probe is the work.** Apple reports no progress and calls nothing back when a download
    /// finishes, and `LanguageAvailability.status` was observed on device still reporting
    /// `.supported` long after a pair was installed - so it cannot gate anything. Rather than poll a
    /// status that lies, this retries the real translation on a backoff: succeeding proves the pair
    /// is installed *and* does the work, which is a fact rather than a claim.
    private func startDownloadWatch() {
        guard downloadWatch == nil else { return }
        downloadWatch = Task { @MainActor [weak self] in
            defer { self?.downloadWatch = nil }
            for delay in self?.watchDelays ?? [] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, !self.pairsDownloading.isEmpty else { return }

                let before = self.pairsDownloading
                await self.runPassNow(probingPendingPairs: true)
                if self.pairsDownloading != before { self.postDownloadStateChanged() }
                if self.pairsDownloading.isEmpty { return }
            }
            // Giving up watching is not a dead end: the Settings row stays tappable, so the user can
            // always ask again.
            logWarning("[TagTranslation] Stopped waiting for a language download")
            self?.postDownloadStateChanged()
        }
    }

    /// Roughly four minutes, front-loaded: most downloads on Wi-Fi land in the first few probes, and
    /// the tail is there for a slow connection rather than to keep hammering.
    static let watchBackoff: [Duration] = [
        .seconds(2), .seconds(4), .seconds(8), .seconds(15),
        .seconds(30), .seconds(60), .seconds(60), .seconds(60),
    ]

    /// Re-checks pending pairs when Settings appears, which is exactly when the user wants to know -
    /// and is also what unsticks the row if they dismissed the sheet.
    func refreshDownloadState(completion: (() -> Void)? = nil) {
        resetIfTargetChanged()
        guard !pairsNeedingDownload.isEmpty else {
            completion?()
            return
        }
        Task { @MainActor in
            await runPassNow(probingPendingPairs: true)
            postDownloadStateChanged()
            completion?()
        }
    }

    /// Runs a pass immediately and waits for it. Used by the download watch and by tests; everything
    /// else goes through `reconcile()`.
    func runPassNow(probingPendingPairs: Bool = false) async {
        runPass(probingPendingPairs: probingPendingPairs)
        await pass?.value
    }

    // MARK: - The pass

    private func runPass(probingPendingPairs: Bool = false) {
        guard isEnabled(), translator.isAvailable, pass == nil else { return }
        resetIfTargetChanged()

        let target = language()
        let targetID = target.minimalIdentifier
        let recordedSources = Set(
            service.tags
                .compactMap { cache.sourceLanguage(forTagId: $0.id, name: $0.name) }
                .map(TagLanguageDetector.normalized))
        let candidates = TagLanguageDetector.candidateSources(
            target: targetID, recordedSources: recordedSources)

        var byPair: [TranslationPair: [TagTranslationRequest]] = [:]

        for tag in service.tags {
            let fingerprint = TagFingerprint(tagId: tag.id, name: tag.name, target: targetID)

            // A name the user typed by hand IS the answer. Translating over it would be wasted work,
            // and the cache refuses the write anyway.
            if cache.override(forTagId: tag.id, language: targetID) != nil { continue }
            if failedTags.contains(fingerprint) || unresolvedSourceTags.contains(fingerprint) {
                continue
            }
            guard tag.needsTranslation(for: target, cache: cache) else { continue }

            guard
                let source = TagLanguageDetector.resolveSource(
                    for: tag.name,
                    target: targetID,
                    recorded: cache.sourceLanguage(forTagId: tag.id, name: tag.name),
                    candidates: candidates)
            else {
                // Not knowing is a real answer. Guessing produces a confident wrong translation,
                // which is worse than showing what the user typed.
                unresolvedSourceTags.insert(fingerprint)
                continue
            }

            let pair = TranslationPair(source: source, target: targetID)
            if unsupportedPairs.contains(pair) { continue }
            if pairFailureCounts[pair, default: 0] >= Self.maxFailuresPerPair { continue }
            // A pair known to need a download is normally skipped, since attempting it just throws.
            // The download watch passes `probingPendingPairs` to suppress that - otherwise the
            // pending set hides the very pair the probe exists to re-test.
            if !probingPendingPairs, pairsNeedingDownload.contains(pair) { continue }

            byPair[pair, default: []].append(TagTranslationRequest(tagId: tag.id, text: tag.name))
        }

        guard !byPair.isEmpty else { return }

        pass = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pass = nil }

            var wrote = false
            for (pair, requests) in byPair {
                guard !Task.isCancelled else { break }
                let outcome = await self.translator.translate(requests, pair: pair)
                if self.apply(outcome, pair: pair, requests: requests, target: targetID) {
                    wrote = true
                }
            }

            // One notification for the whole pass, and only if something landed. Tagged so the
            // observer above can tell it apart from a genuine tag edit.
            guard wrote else { return }
            NotificationCenter.default.post(name: .allocationTagsChanged, object: Self.selfInflicted)
        }
    }

    /// Applies one pair's outcome. Returns whether anything was written.
    private func apply(
        _ outcome: TagTranslationOutcome,
        pair: TranslationPair,
        requests: [TagTranslationRequest],
        target: String
    ) -> Bool {
        switch outcome {
        case .translated(let results):
            // It worked, so the pair is provably installed whatever any status might claim.
            let wasPending = pairsNeedingDownload.remove(pair) != nil
            let wasDownloading = pairsDownloading.remove(pair) != nil
            if wasPending || wasDownloading { postDownloadStateChanged() }
            pairFailureCounts[pair] = nil

            // Only the tags actually missing from the response are blacklisted. A refusal is per-tag
            // - a proper noun the framework declines - so blacklisting the whole batch on any gap,
            // which an empty-array protocol forced, was always too broad.
            let returned = Set(results.map(\.tagId))
            for request in requests where !returned.contains(request.tagId) {
                failedTags.insert(
                    TagFingerprint(tagId: request.tagId, name: request.text, target: target))
            }

            var wrote = false
            for result in results {
                cache.store(
                    result.translatedText, forTagId: result.tagId, name: result.sourceText,
                    language: target)
                wrote = true
            }
            if wrote { logDebug("[TagTranslation] \(pair) translated \(results.count) name(s)") }
            return wrote

        case .notInstalled:
            // The only outcome that offers a download. Blacklists nothing: these tags are fine, the
            // language simply is not here yet.
            if pairsNeedingDownload.insert(pair).inserted {
                logWarning("[TagTranslation] \(pair) needs a language download")
                postDownloadStateChanged()
            }
            return false

        case .unsupported:
            logWarning("[TagTranslation] \(pair) is unsupported on this device")
            unsupportedPairs.insert(pair)
            pairsNeedingDownload.remove(pair)
            pairsDownloading.remove(pair)
            postDownloadStateChanged()
            return false

        case .cancelled:
            // Says nothing about whether the work would have succeeded, so it must leave every set
            // untouched. Treating this as a failure is what made backgrounding the app mid-pass
            // blacklist the in-flight tags for the rest of the process.
            return false

        case .failed:
            let count = pairFailureCounts[pair, default: 0] + 1
            pairFailureCounts[pair] = count
            logWarning("[TagTranslation] \(pair) failed (\(count)/\(Self.maxFailuresPerPair))")
            return false
        }
    }
}
