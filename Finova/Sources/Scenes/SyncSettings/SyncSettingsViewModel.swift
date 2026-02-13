//
//  SyncSettingsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

protocol SyncSettingsViewModelDelegate: AnyObject {
  func didUpdateSyncState(status: SyncStatusIndicator.Status, lastSyncText: String)
  func didShowCloudKitUnavailableAlert()
}

final class SyncSettingsViewModel {
  weak var delegate: SyncSettingsViewModelDelegate?

  private let syncEngine = SyncEngine.shared
  private let stateManager = SyncStateManager.shared
  private let cloudKitManager = CloudKitManager.shared

  init() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSyncStatusChange),
      name: .syncStatusDidChange,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Public Methods

  func loadState() {
    cloudKitManager.checkAccountStatus { [weak self] _ in
      guard let self = self else { return }
      let status = self.mapStatus(self.syncEngine.status)
      let lastSyncText = self.formatLastSyncDate()
      self.delegate?.didUpdateSyncState(status: status, lastSyncText: lastSyncText)
    }
  }

  func syncNow() {
    guard cloudKitManager.isCloudKitAvailable else {
      delegate?.didShowCloudKitUnavailableAlert()
      return
    }
    delegate?.didUpdateSyncState(status: .syncing, lastSyncText: formatLastSyncDate())
    syncEngine.performFullSync()
  }

  func resetSync() {
    guard cloudKitManager.isCloudKitAvailable else {
      delegate?.didShowCloudKitUnavailableAlert()
      return
    }
    stateManager.resetAllTokens()
    delegate?.didUpdateSyncState(status: .syncing, lastSyncText: formatLastSyncDate())
    syncEngine.performFullSync()
  }

  // MARK: - Private Methods

  @objc private func handleSyncStatusChange(_ notification: Notification) {
    let syncStatus = notification.object as? SyncStatus ?? syncEngine.status
    let status = mapStatus(syncStatus)
    let lastSyncText: String
    if case .error(let error) = syncStatus {
      lastSyncText = error.localizedDescription
    } else {
      lastSyncText = formatLastSyncDate()
    }
    delegate?.didUpdateSyncState(status: status, lastSyncText: lastSyncText)
  }

  private func mapStatus(_ syncStatus: SyncStatus) -> SyncStatusIndicator.Status {
    switch syncStatus {
    case .idle:
      return cloudKitManager.isCloudKitAvailable ? .idle : .offline
    case .syncing:
      return .syncing
    case .synced:
      return .synced
    case .error:
      return .error
    }
  }

  private func formatLastSyncDate() -> String {
    guard let date = stateManager.lastSyncDate(for: "privateDB") else {
      return "syncSettings.lastSync.never".localized
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
