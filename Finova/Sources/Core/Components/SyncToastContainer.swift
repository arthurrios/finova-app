//
//  SyncToastContainer.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class SyncToastContainer: UIView {

    private var toastView: SyncToastView?
    private var isShowing = false
    private var dismissTimer: Timer?
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
        guard !isShowing else { return }

        let toast = SyncToastView()
        toast.updateStatus(.syncing)
        self.toastView = toast

        addSubview(toast)
        setupToastConstraints(toast)

        isShowing = true
        toast.show(animated: true)

        startObserving()
    }

    func hideSyncToast(animated: Bool = true) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let toast = toastView, isShowing else {
            removeSelf()
            return
        }

        toast.hide(animated: animated) { [weak self] in
            toast.removeFromSuperview()
            self?.toastView = nil
            self?.isShowing = false
            self?.removeSelf()
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
            scheduleDismiss(after: 2.0)
        case .error:
            toastView?.updateStatus(.error)
            scheduleDismiss(after: 3.0)
        case .idle:
            // CloudKit unavailable — dismiss immediately
            hideSyncToast(animated: true)
        }
    }

    // MARK: - Private Helpers

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
