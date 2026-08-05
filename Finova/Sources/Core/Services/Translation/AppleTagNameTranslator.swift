//
//  AppleTagNameTranslator.swift
//  Finova
//

import SwiftUI
import Translation
import UIKit

/// Bridges UIKit to Apple's on-device Translation framework.
///
/// `TranslationSession` has no public initialiser - it is only vended by the SwiftUI
/// `.translationTask` modifier. A UIKit app therefore has to keep a live SwiftUI view around purely to
/// be handed one, which is what this host is.
@available(iOS 18.0, *)
@MainActor
final class TranslationSessionHost {

    /// Changing `configuration` to a NEW instance is what re-fires `.translationTask`; that is how one
    /// host serves several source→target pairs in sequence.
    private final class Driver: ObservableObject {
        @Published var configuration: TranslationSession.Configuration?
        var onSession: ((TranslationSession) async -> Void)?
    }

    private struct HostView: View {
        @ObservedObject var driver: Driver
        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(driver.configuration) { session in
                    await driver.onSession?(session)
                }
        }
    }

    private let driver = Driver()
    private var hostingController: UIHostingController<HostView>?
    private var pending:
        (requests: [TagTranslationRequest],
        continuation: CheckedContinuation<[TagTranslationResult], Never>)?
    private var watchdog: Task<Void, Never>?
    private var preparation: CheckedContinuation<Bool, Never>?
    private var preparationWatchdog: Task<Void, Never>?
    private var downloadController: UIHostingController<HostView>?
    private var downloadDriver: Driver?

    // MARK: - Attach / detach

    /// `.translationTask` runs off SwiftUI's appearance lifecycle, so the host has to be in a live,
    /// foreground window. Returns `false` when there isn't one and the caller simply gives up for now.
    @discardableResult
    func attach() -> Bool {
        guard hostingController == nil else { return true }
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
            let root = window.rootViewController
        else { return false }

        let controller = UIHostingController(rootView: HostView(driver: driver))
        // 1pt at 1% opacity rather than `isHidden` or `alpha = 0`: a view in a hidden subtree is not
        // guaranteed to be submitted for display, and `.translationTask` would then never fire.
        // Invisible in practice, and removed from hit-testing and accessibility.
        controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        controller.view.alpha = 0.01
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.isAccessibilityElement = false
        controller.view.accessibilityElementsHidden = true

        root.addChild(controller)
        window.insertSubview(controller.view, at: 0)
        controller.didMove(toParent: root)
        hostingController = controller
        return true
    }

    func detach() {
        watchdog?.cancel()
        watchdog = nil
        resumePending(with: [])  // never strand a continuation
        finishPreparation(false)
        driver.configuration = nil
        driver.onSession = nil
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
    }

    // MARK: - Run one pair

    func run(
        _ requests: [TagTranslationRequest], from source: String?, to target: String,
        presentingUI: Bool = false
    ) async -> [TagTranslationResult] {
        guard !requests.isEmpty else { return [] }

        // `translations(from:)` raises the download sheet ITSELF when the pair is missing, then
        // downloads and returns the translations in the same call. Given a real presenter that is the
        // whole feature in one step - no prepare, no availability polling, no waiting for a status
        // that has been unreliable at every turn. Without one it is cancelled instantly, which is what
        // happened from the splash and from the 1pt background host.
        if presentingUI {
            guard let presenter = Self.topViewController() else { return [] }
            let controller = UIHostingController(rootView: HostView(driver: driver))
            controller.view.backgroundColor = .clear
            controller.modalPresentationStyle = .overFullScreen
            downloadController = controller
            presenter.present(controller, animated: false)
        } else {
            guard attach() else { return [] }
        }

        return await withCheckedContinuation { continuation in
            pending = (requests, continuation)

            driver.onSession = { [weak self] session in
                guard let self, let job = self.takePending() else { return }
                do {
                    let responses = try await session.translations(
                        from: job.requests.map {
                            TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.tagId)
                        })
                    let sourceTexts = Dictionary(
                        uniqueKeysWithValues: job.requests.map { ($0.tagId, $0.text) })
                    job.continuation.resume(
                        returning: responses.compactMap { response in
                            guard let id = response.clientIdentifier,
                                let original = sourceTexts[id]
                            else { return nil }
                            return TagTranslationResult(
                                tagId: id, sourceText: original, translatedText: response.targetText)
                        })
                } catch {
                    // Includes "asset not installed" and every transient system failure. An empty
                    // result means nothing is cached and the tag keeps showing its typed name.
                    logWarning("[TagTranslation] Session failed: \(error)")
                    job.continuation.resume(returning: [])
                }
                if let controller = self.downloadController {
                    self.downloadController = nil
                    controller.dismiss(animated: false)
                }
            }

            // If the window goes away, or the task never fires, resume once with nothing rather than
            // leaving the caller suspended forever.
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.resumePending(with: [])
            }

            // A nil source asks the framework to detect it, which is the right answer when our own
            // detection was not confident.
            driver.configuration = TranslationSession.Configuration(
                source: source.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: target))
        }
    }

    /// Downloads a pair. The sheet the system raises belongs to whatever window the host is in, so
    /// this must only be called from a screen that will still be there when the user answers it -
    /// running it at launch put the sheet over the splash and the root-controller swap dismissed it
    /// before it could be read.
    /// Downloads a pair, presenting Apple's own download sheet.
    ///
    /// Presented as a real modal rather than run from the 1pt background host. The system sheet needs
    /// a genuine presentation context: from the invisible host it was dismissed by the splash's
    /// root-controller swap, and when the user swiped it away nothing resolved, so the caller hung
    /// until the watchdog fired. A transparent `overFullScreen` controller gives it a normal
    /// lifecycle while showing nothing of our own - the only UI is Apple's.
    func prepare(from source: String?, to target: String) async -> Bool {
        guard let presenter = Self.topViewController() else {
            logWarning("[TagTranslation] No view controller to present the download sheet from")
            return false
        }

        // Its OWN driver, not the shared one. With a single driver the background host and this modal
        // both observe the same configuration, so assigning it fires `.translationTask` on BOTH and
        // `onSession` is whichever wrote last — the sheet could end up anchored to the invisible host
        // again, which is the whole thing this modal exists to avoid.
        let downloadDriver = Driver()
        self.downloadDriver = downloadDriver
        let controller = UIHostingController(rootView: HostView(driver: downloadDriver))
        controller.view.backgroundColor = .clear
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        downloadController = controller
        presenter.present(controller, animated: false)

        return await withCheckedContinuation { continuation in
            preparation = continuation

            downloadDriver.onSession = { [weak self] session in
                guard let self else { return }
                logWarning("[TagTranslation] Download session vended — preparing")
                do {
                    try await session.prepareTranslation()
                    logWarning("[TagTranslation] prepareTranslation() returned")
                    self.finishPreparation(true)
                } catch {
                    // Includes the user dismissing or declining the system sheet.
                    logWarning("[TagTranslation] Language download failed or was declined: \(error)")
                    self.finishPreparation(false)
                }
            }

            // A download can genuinely take a while, but it must not be able to hang forever: if the
            // user swipes the system sheet away, the session task may simply never resolve, and
            // without this the caller stays suspended and its UI stuck on "Downloading…".
            preparationWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { return }
                logWarning("[TagTranslation] Language download timed out")
                self?.finishPreparation(false)
            }

            downloadDriver.configuration = TranslationSession.Configuration(
                source: source.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: target))
        }
    }

    /// Resumes the preparation continuation exactly once, whichever of the session, the watchdog or
    /// `detach()` gets there first, and takes the transparent presenter down with it.
    private func finishPreparation(_ success: Bool) {
        if let controller = downloadController {
            downloadController = nil
            downloadDriver = nil
            controller.dismiss(animated: false)
        }
        guard let continuation = preparation else { return }
        preparation = nil
        preparationWatchdog?.cancel()
        preparationWatchdog = nil
        continuation.resume(returning: success)
    }

    /// The deepest presented controller, so the sheet is not presented from something already covered.
    static func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return nil }
        // Descends through modals AND container controllers. Walking only `presentedViewController`
        // stopped at the UINavigationController that wraps the splash, so the "is this the splash?"
        // check below saw a nav controller, said yes-it-is-safe, and the sheet went up over the
        // splash again - dismissed a moment later by the root swap.
        var top = window.rootViewController
        while true {
            if let presented = top?.presentedViewController { top = presented; continue }
            if let nav = top as? UINavigationController,
                let visible = nav.visibleViewController { top = visible; continue }
            if let tab = top as? UITabBarController,
                let selected = tab.selectedViewController { top = selected; continue }
            break
        }
        return top
    }

    /// Takes the slot on the main actor before use, so the watchdog, the session callback and
    /// `detach()` can never resume the same continuation twice.
    private func takePending()
        -> (requests: [TagTranslationRequest],
        continuation: CheckedContinuation<[TagTranslationResult], Never>)?
    {
        defer {
            pending = nil
            watchdog?.cancel()
            watchdog = nil
        }
        return pending
    }

    private func resumePending(with results: [TagTranslationResult]) {
        takePending()?.continuation.resume(returning: results)
    }
}

// MARK: - Translator

@available(iOS 18.0, *)
@MainActor
final class AppleTagNameTranslator: TagNameTranslating {

    private let host = TranslationSessionHost()

    /// The Translation framework does not function in the Simulator: no session is ever vended, so the
    /// host would sit in the window until the watchdog fired. Compiled out rather than discovered at
    /// runtime, which also keeps the whole feature silently inert during simulator development.
    var isAvailable: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            return true
        #endif
    }

    func availability(from source: String?, to target: String) async -> TagTranslationAvailability {
        // Unknown source: assume it is worth trying. `translations(from:)` will detect and either
        // succeed or fail, and a failure is already handled as "leave the typed name".
        guard let source else { return .installed }
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target))
        switch status {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    func translate(_ requests: [TagTranslationRequest], to target: String, presentingUI: Bool) async
        -> [TagTranslationResult]
    {
        await host.run(
            requests, from: requests.first?.sourceLanguage, to: target, presentingUI: presentingUI)
    }

    /// A sheet is only safe once the app is settled on a real screen. The splash is replaced moments
    /// after launch and took the download sheet down with it every time.
    var canPresentUI: Bool {
        guard UIApplication.shared.applicationState == .active,
            let top = TranslationSessionHost.topViewController()
        else { return false }
        return !String(describing: type(of: top)).contains("Splash")
    }

    /// Presents the system download sheet for a pair and waits for it to finish.
    func prepare(from source: String?, to target: String) async -> Bool {
        await host.prepare(from: source, to: target)
    }

    func detachHost() { host.detach() }
}
