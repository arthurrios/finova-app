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

    private var work: Task<Void, Never>?
    private var downloadPoll: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var isApplying = false
    private var started = false

    /// Pairs the OS cannot do at all, and individual tags whose translation came back empty. Both are
    /// in-memory only: a fresh launch is allowed to try again, but one pass must not retry them in a
    /// loop. `failedTags` is keyed by name too, so a rename legitimately re-queues.
    private var failedPairs = Set<String>()
    private var failedTags = Set<String>()
    /// Pairs the OS supports but has not downloaded. Recorded rather than prompted for - see below.
    private(set) var pairsNeedingDownload = Set<String>()
    /// Pairs whose download the user has started. They stay in `pairsNeedingDownload` - the download
    /// is NOT finished - but Settings shows them as in progress rather than as a fresh offer.
    private(set) var pairsDownloading = Set<String>()

    init(
        service: AllocationTagService = .shared,
        cache: TagTranslationCache = .shared,
        translator: TagNameTranslating? = nil,
        language: @escaping () -> Locale.Language = { Locale.current.language },
        isEnabled: @escaping () -> Bool = { UserDefaultsManager.isTagNameTranslationEnabled() }
    ) {
        self.service = service
        self.cache = cache
        self.language = language
        self.isEnabled = isEnabled
        if let translator {
            self.translator = translator
        } else if #available(iOS 18.0, *) {
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
            Task { @MainActor in self?.reconcile() }
        }
        NotificationCenter.default.addObserver(
            forName: .allocationTagsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Ignore the notification our own write produced.
                guard let self, !self.isApplying else { return }
                self.reconcile()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        }

        // Deliberately no pass here. `start()` runs from `scene(willConnectTo:)`, while the splash is
        // still up and the root view controller is about to be replaced - anything the host put on
        // screen would be torn down with it. `didBecomeActive` covers the real first opportunity.
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
        work?.cancel()
        if #available(iOS 18.0, *), let apple = translator as? AppleTagNameTranslator {
            apple.detachHost()
        }
    }

    /// Downloads every pair the last pass found missing, then re-runs.
    ///
    /// Called from Settings, where the user tapped for it and the screen will still be there when the
    /// system sheet appears.
    func downloadMissingLanguages(completion: (() -> Void)? = nil) {
        let pending = pairsNeedingDownload
        guard !pending.isEmpty else {
            completion?()
            return
        }
        isDownloadingLanguages = true
        Task { @MainActor in
            defer {
                isDownloadingLanguages = false
                completion?()
                reconcile()
            }
            for pair in pending {
                let parts = pair.split(separator: ">")
                guard parts.count == 2 else { continue }
                let rawSource = String(parts[0])
                let source: String? = rawSource == "auto" ? nil : rawSource
                let target = String(parts[1])
                guard await translator.prepare(from: source, to: target) else { continue }

                // The pair stays pending. `prepareTranslation()` returns when the download STARTS,
                // not when it completes - retrying straight away made `translations(from:)` raise the
                // sheet again with no presenter left, which cancelled instantly (NSCocoaError 3072).
                // Only `availability` reporting `.installed` means it is actually usable.
                pairsDownloading.insert(pair)
                startDownloadPolling()

                // Clear tags an earlier cancelled attempt blacklisted, so the pass will consider them
                // again once the pair does arrive.
                failedTags = failedTags.filter { !$0.hasSuffix("|\(target)") }
            }
        }
    }

    /// Watches for a started download to actually land.
    ///
    /// The Translation framework reports no progress and calls nothing back when a download finishes -
    /// `availability` flipping to `.installed` is the only observable signal there is. So poll it,
    /// but only while a download is genuinely outstanding, and stop as soon as it lands. Without this
    /// the user had to leave Settings and return to discover the download had completed.
    private func startDownloadPolling() {
        guard downloadPoll == nil else { return }
        downloadPoll = Task { @MainActor [weak self] in
            defer { self?.downloadPoll = nil }
            // Capped so a download that never arrives cannot poll forever; the Settings row stays
            // tappable, so the user can always ask again.
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, !self.pairsDownloading.isEmpty else { return }

                let before = self.pairsDownloading
                await self.checkPendingPairs()
                if self.pairsDownloading != before {
                    NotificationCenter.default.post(
                        name: .tagTranslationDownloadStateChanged, object: nil)
                }
                if self.pairsDownloading.isEmpty {
                    logWarning("[TagTranslation] Download finished — translating")
                    self.reconcile()
                    return
                }
            }
            logWarning("[TagTranslation] Stopped waiting for the download; ask again in Settings")
        }
    }

    /// Removes any pending pair the system now reports as installed.
    private func checkPendingPairs() async {
        let target = language().minimalIdentifier
        for pair in pairsNeedingDownload {
            let parts = pair.split(separator: ">")
            guard parts.count == 2 else { continue }
            let rawSource = String(parts[0])
            let source: String? = rawSource == "auto" ? nil : rawSource
            if case .installed = await translator.availability(from: source, to: target) {
                logWarning("[TagTranslation] \(pair) is now installed")
                pairsNeedingDownload.remove(pair)
                pairsDownloading.remove(pair)
            }
        }
    }

    /// Re-asks the system whether the pending pairs have arrived.
    ///
    /// Apple exposes no progress for a language download and no way to re-open its sheet, so the only
    /// honest status is "ask again". Called when Settings appears, which is exactly when the user
    /// wants to know - and it also unsticks the row if they dismissed the sheet, rather than leaving
    /// it disabled until the watchdog gives up.
    func refreshDownloadState(completion: (() -> Void)? = nil) {
        guard !pairsNeedingDownload.isEmpty else {
            isDownloadingLanguages = false
            completion?()
            return
        }
        let target = language().minimalIdentifier
        Task { @MainActor in
            for pair in pairsNeedingDownload {
                let parts = pair.split(separator: ">")
                guard parts.count == 2 else { continue }
                let rawSource = String(parts[0])
                let source: String? = rawSource == "auto" ? nil : rawSource
                if case .installed = await translator.availability(from: source, to: target) {
                    logWarning("[TagTranslation] \(pair) is now installed")
                    pairsNeedingDownload.remove(pair)
                    pairsDownloading.remove(pair)
                }
            }
            // Whatever the answer, stop claiming a download is in flight: we have just checked, and a
            // sheet the user dismissed is not coming back on its own.
            isDownloadingLanguages = false
            completion?()
            if pairsNeedingDownload.isEmpty { reconcile() }
        }
    }

    /// Runs a pass immediately and waits for it. Tests only - production goes through `reconcile()`.
    func runPassNow() async {
        runPass()
        await work?.value
    }

    /// Whether Settings should offer the download row.
    var hasLanguagesToDownload: Bool { !pairsNeedingDownload.isEmpty }

    /// True while the download sheet is up. Distinct from `pairsDownloading`, which outlives it: the
    /// sheet closes as soon as the download starts.
    private(set) var isDownloadingLanguages = false

    /// A download has been started and the system has not yet reported the pair installed.
    var hasDownloadInProgress: Bool { !pairsDownloading.isEmpty }

    // MARK: - The pass

    private func runPass() {
        guard isEnabled(), translator.isAvailable, work == nil else { return }

        let target = language()
        let targetID = target.minimalIdentifier
        var byPair: [String: [TagTranslationRequest]] = [:]

        for tag in service.tags {
            // A recorded source is one we trust: it was stamped when the tag was created, where the
            // phone's language was a sound prior. Absent that, detect - and accept `nil`, meaning we
            // genuinely do not know.
            //
            // Deliberately does NOT store a guess for pre-existing tags. Writing "probably the current
            // language" would make the skip below fire on the very next pass and the tag would never
            // be translated, which is precisely the bug this replaced.
            let source = (cache.sourceLanguage(forTagId: tag.id, name: tag.name)
                ?? TagLanguageDetector.detect(tag.name))
                .map(TagLanguageDetector.normalized)

            // Skip only on a KNOWN source that matches the target. An unknown source is sent to the
            // framework to detect, not assumed to need nothing.
            if let source,
                Locale.Language(identifier: source).languageCode == target.languageCode { continue }
            // Already cached.
            guard tag.needsTranslation(for: target, cache: cache) else { continue }

            let pair = "\(source ?? "auto")>\(targetID)"
            if failedPairs.contains(pair) || pairsNeedingDownload.contains(pair) { continue }
            if failedTags.contains("\(tag.id)|\(tag.name)|\(targetID)") { continue }

            byPair[pair, default: []].append(
                TagTranslationRequest(tagId: tag.id, text: tag.name, sourceLanguage: source))
        }

        guard !byPair.isEmpty else {
            logInfo("[TagTranslation] Nothing to translate into \(targetID) (\(service.tags.count) tag(s))")
            return
        }
        logWarning(
            "[TagTranslation] \(byPair.values.reduce(0) { $0 + $1.count }) tag(s) → \(targetID): "
                + byPair.map { "\($0.key) x\($0.value.count)" }.joined(separator: ", "))

        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.work = nil }

            var wrote = false
            for (pair, requests) in byPair {
                guard !Task.isCancelled else { break }
                let rawSource = String(pair.split(separator: ">")[0])
                let source: String? = rawSource == "auto" ? nil : rawSource

                let needsUI: Bool
                switch await translator.availability(from: source, to: targetID) {
                case .unsupported:
                    logWarning("[TagTranslation] \(pair) unsupported by this device")
                    failedPairs.insert(pair)
                    continue
                case .installed:
                    needsUI = false
                case .needsDownload:
                    // The pair is missing, so `translations(from:)` will raise Apple's own download
                    // sheet. That is fine - as long as there is a real screen for it to appear over.
                    // On the splash it is cancelled the moment the root controller is swapped, so
                    // defer instead and let a later pass pick it up.
                    guard translator.canPresentUI else {
                        logWarning("[TagTranslation] \(pair) needs a download — waiting for a safe screen")
                        pairsNeedingDownload.insert(pair)
                        continue
                    }
                    logWarning("[TagTranslation] \(pair) needs a download — prompting")
                    needsUI = true
                }

                let results = await translator.translate(
                    requests, to: targetID, presentingUI: needsUI)
                guard !Task.isCancelled else { break }

                guard !results.isEmpty else {
                    logWarning("[TagTranslation] \(pair) returned nothing for \(requests.map(\.text))")
                    requests.forEach { failedTags.insert("\($0.tagId)|\($0.text)|\(targetID)") }
                    continue
                }

                // It worked, so whatever `status` claims, this pair is usable.
                pairsNeedingDownload.remove(pair)
                pairsDownloading.remove(pair)
                NotificationCenter.default.post(
                    name: .tagTranslationDownloadStateChanged, object: nil)

                for result in results {
                    logWarning(
                        "[TagTranslation] \"\(result.sourceText)\" → \"\(result.translatedText)\"")
                    cache.store(
                        result.translatedText, forTagId: result.tagId, name: result.sourceText,
                        language: targetID)
                    wrote = true
                }
            }

            // One notification for the whole pass, and only if something actually landed.
            guard wrote else { return }
            isApplying = true
            NotificationCenter.default.post(name: .allocationTagsChanged, object: nil)
            isApplying = false
        }
    }
}
