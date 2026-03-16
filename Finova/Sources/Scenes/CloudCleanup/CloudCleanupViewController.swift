//
//  CloudCleanupViewController.swift
//  Finova
//
//  Created by Arthur Rios on 16/03/26.
//

import UIKit

final class CloudCleanupViewController: UIViewController {
    private let contentView = CloudCleanupView()
    private let service = CloudCleanupService()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
        service.delegate = self
        service.startScan()
    }
}

// MARK: - CloudCleanupViewDelegate

extension CloudCleanupViewController: CloudCleanupViewDelegate {
    func didTapClose() {
        service.cancelCleanup()
        dismiss(animated: true)
    }

    func didTapDeleteOrphans() {
        contentView.setState(.deleting(current: 0, total: 0))
        service.confirmDeletion()
    }
}

// MARK: - CloudCleanupServiceDelegate

extension CloudCleanupViewController: CloudCleanupServiceDelegate {
    func cloudCleanupDidUpdateProgress(_ progress: CloudCleanupProgress) {
        switch progress.phase {
        case .scanning:
            contentView.setState(.scanning(
                type: progress.currentRecordType,
                index: progress.currentIndex,
                total: progress.totalTypes
            ))
        case .deleting:
            contentView.setState(.deleting(
                current: progress.currentIndex,
                total: progress.totalTypes
            ))
        }
    }

    func cloudCleanupDidCompleteScan(_ result: CloudCleanupScanResult) {
        contentView.setState(.results(result))

        if result.totalOrphans > 0 {
            updateDetent(expanded: true)
        }
    }

    func cloudCleanupDidCompleteDeletion(_ result: CloudCleanupDeletionResult) {
        contentView.setState(.complete(
            deleted: result.totalDeleted,
            errors: result.totalErrors
        ))
    }

    func cloudCleanupDidFail(_ error: CloudCleanupError) {
        let message: String
        switch error {
        case .noGroup:
            message = "cloudCleanup.error.noGroup".localized
        case .fetchFailed:
            message = "cloudCleanup.error.failed".localized
        }
        contentView.setState(.error(message))
    }

    // MARK: - Detent Management

    private func updateDetent(expanded: Bool) {
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            if expanded {
                let customDetent = UISheetPresentationController.Detent.custom { context in
                    context.maximumDetentValue * 0.6
                }
                sheet.detents = [customDetent, .large()]
            } else {
                sheet.detents = [.medium()]
            }
        }
    }
}
