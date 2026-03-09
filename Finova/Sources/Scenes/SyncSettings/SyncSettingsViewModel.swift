//
//  SyncSettingsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

enum UploadStatus {
  case uploading
  case complete
  case incomplete
}

protocol SyncSettingsViewModelDelegate: AnyObject {
  func didUpdateSyncState(status: SyncStatusIndicator.Status, lastSyncText: String)
  func didShowCloudKitUnavailableAlert()
  func didUpdateUploadProgress(currentRecords: Int, totalRecords: Int, status: UploadStatus)
  func didUpdateDownloadStatus(_ status: SyncStatusIndicator.Status)
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSyncPushProgress(_:)),
      name: .syncPushProgressDidChange,
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

      // Download status
      self.delegate?.didUpdateDownloadStatus(status)

      // Upload status — always visible
      self.refreshUploadStatus()
    }
  }

  func syncNow() {
    ensureCloudKitAvailable { [weak self] in
      guard let self = self else { return }
      self.delegate?.didUpdateSyncState(status: .syncing, lastSyncText: self.formatLastSyncDate())
      self.syncEngine.performFullSync()
    }
  }

  func resetSync() {
    ensureCloudKitAvailable { [weak self] in
      guard let self = self else { return }
      self.delegate?.didUpdateSyncState(status: .syncing, lastSyncText: self.formatLastSyncDate())
      // Re-fetch all records from CloudKit (resets change tokens).
      // Uses forceFullFetch instead of forceAcceptCloud to avoid resetting local timestamps
      // which can cause orphan cleanup to delete valid records and push deletions to CloudKit.
      self.syncEngine.performFullSync(forceFullFetch: true)
    }
  }

  func resumeUpload() {
    ensureCloudKitAvailable { [weak self] in
      guard let self = self else { return }
      self.delegate?.didUpdateSyncState(status: .syncing, lastSyncText: self.formatLastSyncDate())
      // Just trigger a normal sync — pending records will be pushed without resetting
      // already-synced records back to pending (which causes an upload loop).
      self.syncEngine.performFullSync()
    }
  }

  /// Re-checks iCloud account status before proceeding. Calls `onAvailable` on the main queue
  /// if the account is available; otherwise shows the unavailable alert.
  private func ensureCloudKitAvailable(onAvailable: @escaping () -> Void) {
    cloudKitManager.checkAccountStatus { [weak self] status in
      guard let self = self else { return }
      if status == .available {
        onAvailable()
      } else {
        self.delegate?.didShowCloudKitUnavailableAlert()
      }
    }
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

    // Download status
    delegate?.didUpdateDownloadStatus(status)

    // Refresh upload status on sync completion
    if case .synced = syncStatus {
      refreshUploadStatus()
    }
  }

  @objc private func handleSyncPushProgress(_ notification: Notification) {
    guard let progress = notification.object as? SyncPushProgress else { return }
    let completedRecords = recordsCompletedForProgress(progress)
    delegate?.didUpdateUploadProgress(
      currentRecords: completedRecords,
      totalRecords: progress.totalRecords,
      status: .uploading
    )
  }

  private func recordsCompletedForProgress(_ progress: SyncPushProgress) -> Int {
    guard progress.totalBatches > 0 else { return 0 }
    let recordsPerBatch = progress.totalRecords / progress.totalBatches
    return min(progress.currentBatch * recordsPerBatch, progress.totalRecords)
  }

  private func refreshUploadStatus() {
    if let progress = syncEngine.currentPushProgress {
      let completedRecords = recordsCompletedForProgress(progress)
      delegate?.didUpdateUploadProgress(
        currentRecords: completedRecords,
        totalRecords: progress.totalRecords,
        status: .uploading
      )
    } else {
      let pendingCount = countPendingRecords()
      if pendingCount > 0 {
        delegate?.didUpdateUploadProgress(
          currentRecords: 0,
          totalRecords: pendingCount,
          status: .incomplete
        )
      } else {
        delegate?.didUpdateUploadProgress(
          currentRecords: 0,
          totalRecords: 0,
          status: .complete
        )
      }
    }
  }

  private func countPendingRecords() -> Int {
    let txCount = TransactionRepository().fetchPendingSync().count
    let budgetCount = BudgetRepository().fetchPendingSync().count
    let cardCount = CreditCardRepository().fetchPendingSync().count
    let stmtCount = StatementRepository().fetchPendingSync().count
    let allocCount = BudgetAllocationRepository().fetchPendingSync().count
    return txCount + budgetCount + cardCount + stmtCount + allocCount
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
