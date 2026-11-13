//
//  TagLanguageDownloadPresenter.swift
//  Finova
//

import SwiftUI
import Translation
import UIKit

/// Asks the system to download a language pair. **The only SwiftUI in this feature.**
///
/// A `TranslationSession` built with `init(installedSource:target:)` reports
/// `canRequestDownloads == false` and simply throws `.notInstalled` when a pair is missing. Getting
/// the user's consent still needs a session vended by `.translationTask`, so this hosts a one-shot
/// invisible SwiftUI view for exactly as long as the request takes and then tears it down.
///
/// Everything here is a local. The previous version kept the hosting controller, the driver and the
/// continuation as fields on a long-lived object, which gave it three distinct ways to break: two
/// callers overwrote each other's presenter, a second call overwrote the first's continuation so the
/// first never resumed, and the watchdog resumed without dismissing the modal - leaving a
/// transparent, *interactive*, full-screen controller on top of the app. There are no fields to
/// clobber now, and exactly one dismissal site.
@available(iOS 26.0, *)
@MainActor
enum TagLanguageDownloadPresenter {

    private final class Driver: ObservableObject {
        @Published var configuration: TranslationSession.Configuration?
        var onSession: ((TranslationSession) async -> Void)?
    }

    private struct HostView: View {
        @ObservedObject var driver: Driver
        var body: some View {
            Color.clear
                .translationTask(driver.configuration) { session in
                    await driver.onSession?(session)
                }
        }
    }

    /// Resumes its continuation at most once, whichever of the session or the watchdog gets there.
    private final class ResumeOnce {
        private var continuation: CheckedContinuation<TagLanguageDownloadOutcome, Never>?
        init(_ continuation: CheckedContinuation<TagLanguageDownloadOutcome, Never>) {
            self.continuation = continuation
        }
        func finish(_ outcome: TagLanguageDownloadOutcome) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: outcome)
        }
    }

    static func requestDownload(pair: TranslationPair, from presenter: TranslationSheetPresenting)
        async -> TagLanguageDownloadOutcome
    {
        // Presenting onto a controller that is already presenting throws. The coordinator serialises
        // download requests, so this is a guard against something unexpected rather than the norm.
        guard presenter.presentedViewController == nil else { return .failed }

        let driver = Driver()
        let controller = UIHostingController(rootView: HostView(driver: driver))
        controller.view.backgroundColor = .clear
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        presenter.present(controller, animated: false, completion: nil)

        let outcome = await withCheckedContinuation { continuation in
            let box = ResumeOnce(continuation)
            var watchdog: Task<Void, Never>?

            driver.onSession = { session in
                // Cancelled BEFORE the sheet goes up, which is the whole point of a short timeout
                // here. The only thing being waited on up to now is SwiftUI vending a session, which
                // takes moments. Once it has, the user may sit reading Apple's consent sheet for as
                // long as they like and nothing may time them out - and nothing can, because the only
                // thing left that can resolve is prepareTranslation(), which throws
                // CocoaError.userCancelled if they dismiss it.
                watchdog?.cancel()
                watchdog = nil
                do {
                    // Returns when the download STARTS, not when it finishes. Confirmed on device -
                    // it is why completion is observed by retrying the translation rather than by
                    // waiting here.
                    try await session.prepareTranslation()
                    box.finish(.started)
                } catch {
                    box.finish(Self.classifyDownload(error))
                }
            }

            watchdog = Task {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                logWarning("[TagTranslation] No translation session was vended for \(pair)")
                box.finish(.failed)
            }

            driver.configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.source),
                target: Locale.Language(identifier: pair.target))
        }

        // One dismissal site, reached unconditionally: the continuation always resumes, because the
        // watchdog covers the case where a session never arrives.
        controller.dismiss(animated: false)
        return outcome
    }

    nonisolated static func classifyDownload(_ error: Error) -> TagLanguageDownloadOutcome {
        switch AppleTagNameTranslator.classify(error) {
        case .cancelled: return .cancelled
        case .unsupported: return .unsupported
        default: return .failed
        }
    }
}
