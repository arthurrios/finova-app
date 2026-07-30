//
//  InitialSyncViewController.swift
//  Finova
//
//  Created by Arthur Rios on 17/03/26.
//

import CloudKit
import UIKit

protocol InitialSyncFlowDelegate: AnyObject {
    func initialSyncDidComplete()
}

final class InitialSyncViewController: UIViewController {

    // MARK: - Properties

    let contentView = InitialSyncView()
    weak var flowDelegate: InitialSyncFlowDelegate?

    /// Fires if no terminal sync status arrives in time, so the user is never trapped on the
    /// spinner when the engine bails without publishing a status (e.g. a CloudKit operation
    /// that never calls back, or an early return before `status` is assigned).
    private var watchdog: DispatchWorkItem?
    private static let watchdogTimeout: TimeInterval = 45

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.isNavigationBarHidden = true
        setup()
        dismissSyncToastIfPresent()
        subscribeToNotifications()
        startOrObserveSync()
    }

    deinit {
        watchdog?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setup() {
        view.addSubview(contentView)
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
    }

    // MARK: - Toast Suppression

    private func dismissSyncToastIfPresent() {
        // Remove any sync toast from the window — this screen has its own progress UI
        guard let window = view.window ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        if let toast = window.viewWithTag(99998) as? SyncToastContainer {
            toast.hideSyncToast(animated: true)
        }
    }

    // MARK: - Notifications

    private func subscribeToNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePhaseProgress(_:)),
            name: .syncPhaseProgressDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncStatusChanged(_:)),
            name: .syncStatusDidChange,
            object: nil
        )
    }

    // MARK: - Sync Management

    private func startOrObserveSync() {
        if SyncEngine.shared.isSyncInProgress {
            // Attach to already-running sync (e.g., triggered by invitation acceptance or Splash)
            logInfo("[InitialSync] Attaching to running sync")
        } else {
            logInfo("[InitialSync] Triggering full sync")
            SyncEngine.shared.performFullSync(forceFullFetch: true)
        }
        contentView.setState(.syncing(phase: "sync.phase.preparing", progress: 0.0))
        armWatchdog()
    }

    /// Restarts the no-status-received timer. Cancelled as soon as a terminal status arrives.
    private func armWatchdog() {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            logWarning("[InitialSync] No terminal sync status after \(Int(Self.watchdogTimeout))s — showing recoverable state")
            self.showUnavailable(message: "initialSync.error.generic".localized)
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.watchdogTimeout, execute: item)
    }

    /// Terminal, recoverable state: reveals Retry and "Continue offline" so the user can always
    /// leave this screen. Used for both hard errors and "sync will not run" outcomes.
    private func showUnavailable(message: String) {
        watchdog?.cancel()
        watchdog = nil
        contentView.setState(.error(message))
    }

    // MARK: - Notification Handlers

    @objc private func handlePhaseProgress(_ notification: Notification) {
        guard let progress = notification.object as? SyncPhaseProgress else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Phase progress is the liveness signal for a healthy sync: re-arm the watchdog so a
            // long-but-progressing initial pull is never cut short, while a silently stalled one
            // still surfaces a recoverable state.
            self.armWatchdog()
            self.contentView.setState(
                .syncing(phase: progress.phaseKey, progress: progress.progress)
            )
        }
    }

    @objc private func handleSyncStatusChanged(_ notification: Notification) {
        guard let status = notification.object as? SyncStatus else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch status {
            case .synced:
                self.watchdog?.cancel()
                self.watchdog = nil
                self.contentView.setState(.syncing(phase: "sync.phase.complete", progress: 1.0))
                // Brief delay so user sees "Sync complete!" before transitioning
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.flowDelegate?.initialSyncDidComplete()
                }
            case .error(let error):
                self.showUnavailable(message: Self.errorMessage(from: error))
            case .idle:
                // `.idle` is TERMINAL, not transient: the engine publishes it when the sync will
                // not run at all — no iCloud account, restricted/undetermined account, or sync
                // disabled in settings. Treating it as "keep waiting" left this screen spinning
                // forever with Retry/Skip hidden, trapping the user (and hanging every run on a
                // Simulator, which has no iCloud account).
                logWarning("[InitialSync] Sync reported idle — cannot sync on this device right now")
                self.showUnavailable(message: "initialSync.error.icloud".localized)
            case .syncing:
                // Real progress — restart the watchdog so a long but healthy sync isn't cut off.
                self.armWatchdog()
            }
        }
    }

    // MARK: - Error Messages

    private static func errorMessage(from error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return "initialSync.error.network".localized
            case .notAuthenticated:
                return "initialSync.error.icloud".localized
            case .quotaExceeded:
                return "initialSync.error.storage".localized
            default:
                return "initialSync.error.generic".localized
            }
        }
        return "initialSync.error.generic".localized
    }
}

// MARK: - InitialSyncViewDelegate

extension InitialSyncViewController: InitialSyncViewDelegate {
    func didTapRetry() {
        contentView.setState(.syncing(phase: "sync.phase.preparing", progress: 0.0))
        armWatchdog()
        SyncEngine.shared.performFullSync(forceFullFetch: true)
    }

    func didTapSkip() {
        watchdog?.cancel()
        watchdog = nil
        flowDelegate?.initialSyncDidComplete()
    }
}
