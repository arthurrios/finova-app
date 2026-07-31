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
  func didUpdateSyncEnabled(_ isEnabled: Bool)
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

  var isSyncEnabled: Bool {
    UserDefaultsManager.getSyncEnabled()
  }

  // MARK: - Public Methods

  func loadState() {
    delegate?.didUpdateSyncEnabled(isSyncEnabled)

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

  func toggleSyncEnabled(_ isEnabled: Bool) {
    UserDefaultsManager.setSyncEnabled(isEnabled)
    delegate?.didUpdateSyncEnabled(isEnabled)
    if isEnabled {
      syncNow()
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
      self.syncEngine.performFullSync(forceFullFetch: true)
    }
  }

  /// Runs every repair pass, once, because the user asked. Nothing else may invoke these — see
  /// DataRepairService for why running them automatically is what made two devices disagree.
  func repairData(completion: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let result = DataRepairService.repairAll()
      DispatchQueue.main.async { completion(result.summary) }
    }
  }

  /// Deletes the CloudKit zones of groups this user already deleted locally.
  ///
  /// Destructive and outward-facing, so it is user-invoked only. Every guard lives in
  /// `DeadGroupZonePurge`: the zone must be `Group-<id>`, a local row must exist for that id, that
  /// row must be soft-deleted AND owned by this user, and `FinovaPrivateZone`/`_defaultZone` can
  /// never be touched. It logs everything it is about to destroy before destroying it.
  func purgeDeadGroupZones() {
    ensureCloudKitAvailable {
      DeadGroupZonePurge.runNow()
    }
  }

  /// Takes a restore point now. Cheap, local, and the thing to press before trying anything new.
  func createBackup() -> String? {
    DataRepairService.createBackup()
  }

  func recoverySync() {
    ensureCloudKitAvailable { [weak self] in
      guard let self = self else { return }
      self.delegate?.didUpdateSyncState(status: .syncing, lastSyncText: self.formatLastSyncDate())
      self.syncEngine.performPrivateZoneRecovery()
    }
  }

  func forceRePushLocal() {
    ensureCloudKitAvailable { [weak self] in
      guard let self = self else { return }
      self.delegate?.didUpdateSyncState(status: .syncing, lastSyncText: self.formatLastSyncDate())
      self.syncEngine.forceRePushAllLocal {
        // Status updates are handled by SyncEngine notifications
      }
    }
  }

  func checkCloudKitForCleanup(onAvailable: @escaping () -> Void) {
    ensureCloudKitAvailable(onAvailable: onAvailable)
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
