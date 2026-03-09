//
//  SyncSettingsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

protocol SyncSettingsFlowDelegate: AnyObject {
  func dismissSyncSettings()
}

final class SyncSettingsViewController: UIViewController {
  let contentView: SyncSettingsView
  private let viewModel: SyncSettingsViewModel
  weak var flowDelegate: SyncSettingsFlowDelegate?

  init(
    contentView: SyncSettingsView,
    viewModel: SyncSettingsViewModel,
    flowDelegate: SyncSettingsFlowDelegate
  ) {
    self.contentView = contentView
    self.viewModel = viewModel
    self.flowDelegate = flowDelegate
    super.init(nibName: nil, bundle: nil)

    self.viewModel.delegate = self
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    viewModel.loadState()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // Refresh state when returning to this screen (sync may have progressed while away)
    viewModel.loadState()
  }

  private func setup() {
    view.addSubview(contentView)
    buildHierarchy()
    setupDelegates()
  }

  private func setupDelegates() {
    contentView.delegate = self
  }

  private func buildHierarchy() {
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
  }
}

// MARK: - SyncSettingsViewDelegate
extension SyncSettingsViewController: SyncSettingsViewDelegate {
  func handleDidTapBackButton() {
    flowDelegate?.dismissSyncSettings()
  }

  func didTapSyncNow() {
    viewModel.syncNow()
  }

  func didTapResetSync() {
    let alert = UIAlertController(
      title: "syncSettings.reset.confirm.title".localized,
      message: "syncSettings.reset.confirm.message".localized,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
    alert.addAction(UIAlertAction(title: "syncSettings.reset.confirm.action".localized, style: .destructive) { [weak self] _ in
      self?.viewModel.resetSync()
    })
    present(alert, animated: true)
  }

  func didTapResumeUpload() {
    viewModel.resumeUpload()
  }

  func didToggleSyncEnabled(_ isEnabled: Bool) {
    viewModel.toggleSyncEnabled(isEnabled)
  }
}

// MARK: - SyncSettingsViewModelDelegate
extension SyncSettingsViewController: SyncSettingsViewModelDelegate {
  func didUpdateSyncState(status: SyncStatusIndicator.Status, lastSyncText: String) {
    DispatchQueue.main.async { [weak self] in
      self?.contentView.updateUI(status: status, lastSyncText: lastSyncText)
    }
  }

  func didShowCloudKitUnavailableAlert() {
    let alert = UIAlertController(
      title: "syncSettings.unavailable.title".localized,
      message: "syncSettings.unavailable.message".localized,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  func didUpdateUploadProgress(currentRecords: Int, totalRecords: Int, status: UploadStatus) {
    DispatchQueue.main.async { [weak self] in
      self?.contentView.updateUploadProgress(current: currentRecords, total: totalRecords, status: status)
    }
  }

  func didUpdateDownloadStatus(_ status: SyncStatusIndicator.Status) {
    DispatchQueue.main.async { [weak self] in
      self?.contentView.updateDownloadStatus(status)
    }
  }

  func didUpdateSyncEnabled(_ isEnabled: Bool) {
    DispatchQueue.main.async { [weak self] in
      self?.contentView.updateSyncEnabled(isEnabled)
    }
  }
}
