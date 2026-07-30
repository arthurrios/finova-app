//
//  SyncToastContainer.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import UIKit

final class SyncToastContainer: UIView {

    private var toastView: SyncToastView?
    private var isShowing = false
    private var dismissTimer: Timer?
    private var isObserving = false
    /// When true (global window-level overlay), the container keeps observing and stays mounted
    /// after a toast dismisses, so the NEXT push (e.g. a later sync) re-shows it automatically.
    var isPersistent = false
    var onDismissed: (() -> Void)?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        dismissTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    // MARK: - Touch Handling

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let toastView = toastView {
            let toastPoint = convert(point, to: toastView)
            if toastView.bounds.contains(toastPoint) {
                return super.hitTest(point, with: event)
            }
        }
        return nil
    }

    // MARK: - Public Methods

    func showSyncToast() {
        beginObserving()
        guard !isShowing else { return }

        let toast = SyncToastView()
        toast.updateStatus(.syncing)
        self.toastView = toast

        addSubview(toast)
        setupToastConstraints(toast)

        isShowing = true
        toast.show(animated: true)
    }

    /// Starts observing sync notifications WITHOUT showing a toast, so a mounted persistent
    /// container auto-shows the moment a push begins (idempotent).
    func beginObserving() {
        guard !isObserving else { return }
        isObserving = true
        startObserving()
    }

    func hideSyncToast(animated: Bool = true) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let toast = toastView, isShowing else {
            if !isPersistent { removeSelf() }
            return
        }

        toast.hide(animated: animated) { [weak self] in
            toast.removeFromSuperview()
            self?.toastView = nil
            self?.isShowing = false
            // A persistent window overlay stays mounted + observing so the next push re-shows it.
            if self?.isPersistent == false { self?.removeSelf() }
        }
    }

    // MARK: - Notification Observing

    private func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncStatusChange(_:)),
            name: .syncStatusDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncPushProgress(_:)),
            name: .syncPushProgressDidChange,
            object: nil
        )
    }

    @objc private func handleSyncStatusChange(_ notification: Notification) {
        guard let status = notification.object as? SyncStatus else { return }

        dismissTimer?.invalidate()
        dismissTimer = nil

        switch status {
        case .syncing:
            toastView?.updateStatus(.syncing)
        case .synced:
            toastView?.updateStatus(.synced)
            scheduleDismiss(after: 3.0)
        case .error(let error):
            let message = Self.userFacingMessage(for: error)
            toastView?.updateStatus(.error, message: message)
            scheduleDismiss(after: 5.0)
        case .idle:
            // CloudKit unavailable — dismiss immediately
            hideSyncToast(animated: true)
        }
    }

    @objc private func handleSyncPushProgress(_ notification: Notification) {
        guard let progress = notification.object as? SyncPushProgress else { return }

        // Auto-show toast if not visible
        if !isShowing {
            showSyncToast()
        }

        toastView?.updatePushProgress(progress)

        // Safety dismiss: overlapping pushes can emit a trailing progress AFTER the terminal
        // `.synced` status, cancelling that status's dismiss timer and leaving the toast stuck on
        // "uploading x/y". Instead of cancelling outright, (re)arm a timer that dismisses once the
        // engine is genuinely idle — and re-checks while a sync is still running.
        scheduleSafetyDismiss()
    }

    /// Dismisses the toast once no sync is actually in progress; reschedules itself while one is.
    /// Guards against the toast getting stuck when the last event received is a push-progress
    /// with no trailing `.synced`/`.idle` status.
    private func scheduleSafetyDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if SyncEngine.shared.isSyncInProgress {
                self.scheduleSafetyDismiss()
            } else {
                self.toastView?.updateStatus(.synced)
                self.scheduleDismiss(after: 1.5)
            }
        }
    }

    // MARK: - Private Helpers

    private static func userFacingMessage(for error: Error) -> String? {
        guard let ckError = error as? CKError else { return nil }
        switch ckError.code {
        case .quotaExceeded:
            return "iCloud storage full"
        case .networkUnavailable, .networkFailure:
            return "No network connection"
        case .notAuthenticated:
            return "Not signed into iCloud"
        case .serviceUnavailable, .requestRateLimited:
            return "iCloud temporarily unavailable"
        default:
            return nil
        }
    }

    private func scheduleDismiss(after interval: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.hideSyncToast(animated: true)
        }
    }

    private func setupToastConstraints(_ toast: SyncToastView) {
        toast.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    private func removeSelf() {
        NotificationCenter.default.removeObserver(self)
        onDismissed?()
        removeFromSuperview()
    }
}
