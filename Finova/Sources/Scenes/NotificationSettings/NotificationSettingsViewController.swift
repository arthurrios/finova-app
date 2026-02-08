//
//  NotificationSettingsViewController.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import UIKit

protocol NotificationSettingsFlowDelegate: AnyObject {
  func dismissNotificationSettings()
}

final class NotificationSettingsViewController: UIViewController {
  let contentView: NotificationSettingsView
  private let viewModel: NotificationSettingsViewModel
  weak var flowDelegate: NotificationSettingsFlowDelegate?

  init(
    contentView: NotificationSettingsView,
    viewModel: NotificationSettingsViewModel,
    flowDelegate: NotificationSettingsFlowDelegate
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
    viewModel.loadSettings()
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

// MARK: - NotificationSettingsViewDelegate
extension NotificationSettingsViewController: NotificationSettingsViewDelegate {
  func handleDidTapBackButton() {
    flowDelegate?.dismissNotificationSettings()
  }

  func didToggleAllNotifications(_ isEnabled: Bool) {
    viewModel.toggleAllNotifications(isEnabled)
  }

  func didToggleTransactionNotifications(_ isEnabled: Bool) {
    viewModel.toggleTransactionNotifications(isEnabled)
  }

  func didToggleAppUpdateNotifications(_ isEnabled: Bool) {
    viewModel.toggleAppUpdateNotifications(isEnabled)
  }

  func didToggleNegativeBalanceNotifications(_ isEnabled: Bool) {
    viewModel.toggleNegativeBalanceNotifications(isEnabled)
  }

  func didToggleCreditCardStatementNotifications(_ isEnabled: Bool) {
    viewModel.toggleCreditCardStatementNotifications(isEnabled)
  }
}

// MARK: - NotificationSettingsViewModelDelegate
extension NotificationSettingsViewController: NotificationSettingsViewModelDelegate {
  func didUpdateNotificationSettings(
    allDisabled: Bool,
    transactionEnabled: Bool,
    appUpdateEnabled: Bool,
    negativeBalanceEnabled: Bool,
    creditCardStatementEnabled: Bool
  ) {
    contentView.updateUI(
      allDisabled: allDisabled,
      transactionEnabled: transactionEnabled,
      appUpdateEnabled: appUpdateEnabled,
      negativeBalanceEnabled: negativeBalanceEnabled,
      creditCardStatementEnabled: creditCardStatementEnabled
    )
  }
}
