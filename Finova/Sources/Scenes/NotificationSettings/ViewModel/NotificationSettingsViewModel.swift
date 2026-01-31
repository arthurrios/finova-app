//
//  NotificationSettingsViewModel.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import Foundation

protocol NotificationSettingsViewModelDelegate: AnyObject {
  func didUpdateNotificationSettings(
    allDisabled: Bool,
    transactionEnabled: Bool,
    appUpdateEnabled: Bool,
    negativeBalanceEnabled: Bool
  )
}

final class NotificationSettingsViewModel {
  weak var delegate: NotificationSettingsViewModelDelegate?

  private let preferencesManager = NotificationPreferencesManager.shared

  // MARK: - Public Methods

  func loadSettings() {
    notifyDelegate()
  }

  func toggleAllNotifications(_ disabled: Bool) {
    preferencesManager.allNotificationsDisabled = disabled
    notifyDelegate()
  }

  func toggleTransactionNotifications(_ enabled: Bool) {
    preferencesManager.transactionNotificationsEnabled = enabled
    notifyDelegate()
  }

  func toggleAppUpdateNotifications(_ enabled: Bool) {
    preferencesManager.appUpdateNotificationsEnabled = enabled
    notifyDelegate()
  }

  func toggleNegativeBalanceNotifications(_ enabled: Bool) {
    preferencesManager.negativeBalanceNotificationsEnabled = enabled
    notifyDelegate()
  }

  // MARK: - Private Methods

  private func notifyDelegate() {
    delegate?.didUpdateNotificationSettings(
      allDisabled: preferencesManager.allNotificationsDisabled,
      transactionEnabled: preferencesManager.transactionNotificationsEnabled,
      appUpdateEnabled: preferencesManager.appUpdateNotificationsEnabled,
      negativeBalanceEnabled: preferencesManager.negativeBalanceNotificationsEnabled
    )
  }
}
