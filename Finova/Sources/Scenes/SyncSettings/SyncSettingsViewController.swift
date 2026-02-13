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
}

// MARK: - SyncSettingsViewModelDelegate
extension SyncSettingsViewController: SyncSettingsViewModelDelegate {
  func didUpdateSyncState(status: SyncStatusIndicator.Status, lastSyncText: String) {
    contentView.updateUI(status: status, lastSyncText: lastSyncText)
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
}
