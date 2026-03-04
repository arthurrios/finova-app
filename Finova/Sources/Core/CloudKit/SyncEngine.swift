//
//  SyncEngine.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation

enum SyncStatus {
    case idle
    case syncing
    case synced
    case error(Error)
}

struct SyncPushProgress {
    let currentBatch: Int
    let totalBatches: Int
    let totalRecords: Int
}

protocol SyncEngineDelegate: AnyObject {
    func syncEngineDidChangeStatus(_ status: SyncStatus)
    func syncEngineDidUpdateData()
}

final class SyncEngine {
    static let shared = SyncEngine()

    weak var delegate: SyncEngineDelegate?
    private(set) var status: SyncStatus = .idle {
        didSet {
            DispatchQueue.main.async {
                self.delegate?.syncEngineDidChangeStatus(self.status)
                NotificationCenter.default.post(name: .syncStatusDidChange, object: self.status)
            }
        }
    }

    private let cloudKitOps: CloudKitOperationsProvider
    private let stateManager: SyncStateManager
    private let postSyncActions: PostSyncActions
    private let syncQueue = DispatchQueue(label: "com.finova.syncengine", qos: .utility)
    private var isSyncing = false
    private var hasSetupSubscriptions = false
    private var isProcessingCloudData = false
    private var pushThrottledUntil: Date?
    private var syncStartedAt: Date?
    private let syncFlagLock = NSLock()
    private var _needsPostSyncPush = false
    private var needsPostSyncPush: Bool {
        get { syncFlagLock.lock(); defer { syncFlagLock.unlock() }; return _needsPostSyncPush }
        set { syncFlagLock.lock(); defer { syncFlagLock.unlock() }; _needsPostSyncPush = newValue }
    }
    private(set) var currentPushProgress: SyncPushProgress?
    private var isInitialPush = false
    /// Maps CK record names to (entityType, localId) for records that need ck_record_id set after successful push.
    /// Populated during pushLocalChanges, consumed per-record in pushBatches.
    private var pendingCKIdAssignments: [String: (type: String, localId: Int)] = [:]
    /// Tracks whether a BalanceOffset record was received during the current pull,
    /// so post-sync fetchBalanceOffsetsFromCloud can skip re-fetching a potentially stale value.
    private(set) var didReceiveBalanceOffsetDuringPull = false
    /// When true, the current sync is a full re-fetch (reset sync). After pull,
    /// orphaned local records that weren't seen in the fetch will be cleaned up.
    private var isFullRefetch = false
    /// CK record names received during a full re-fetch, used for orphan cleanup.
    private var pulledCKRecordNames: Set<String> = []

    private init() {
        self.cloudKitOps = RealCloudKitOperations()
        self.stateManager = SyncStateManager.shared
        self.postSyncActions = RealPostSyncActions()
        setupObservers()
    }

    init(cloudKitOps: CloudKitOperationsProvider, stateManager: SyncStateManager = .shared,
         postSyncActions: PostSyncActions = RealPostSyncActions()) {
        self.cloudKitOps = cloudKitOps
        self.stateManager = stateManager
        self.postSyncActions = postSyncActions
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteNotification),
            name: .cloudKitRemoteNotificationReceived,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalDataChange),
            name: .transactionDataChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalDataChange),
            name: .budgetDataChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalDataChange),
            name: .creditCardDataChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalDataChange),
            name: .allocationDataChanged,
            object: nil
        )
    }

    // MARK: - Public API

    func performFullSync(forceFullFetch: Bool = false, forceRePush: Bool = false, forceAcceptCloud: Bool = false, completion: (() -> Void)? = nil) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            // When the user explicitly requests a force operation, clear any stuck sync state
            if forceRePush || forceAcceptCloud || forceFullFetch {
                if self.isSyncing {
                    logWarning("[Sync] Force operation requested while isSyncing=true — resetting stuck state")
                    self.isSyncing = false
                    self.isProcessingCloudData = false
                    self.syncStartedAt = nil
                }
            }
            if forceFullFetch {
                self.stateManager.resetAllTokens()
            }
            if forceAcceptCloud {
                Self.resetLocalModificationTimestamps()
                self.stateManager.resetAllTokens()
                self.isFullRefetch = true
                self.pulledCKRecordNames = []
            }
            if forceRePush {
                Self.resetAllSyncStatuses()
            }
            self.executeSyncCycle(completion: completion)
        }
    }

    /// Immediately pushes all pending local changes to CloudKit without pulling.
    /// Designed for background/termination scenarios where the 2-second debounce
    /// must be skipped. If a sync is already in progress, waits for it to finish
    /// and then pushes any remaining pending records.
    func flushPendingChanges(completion: @escaping (Bool) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            // If a sync is already running, wait for it to finish then push leftovers
            if self.isSyncing {
                logWarning("[Sync] Background flush: sync in progress — waiting")
                self.needsPostSyncPush = true
                let deadline = Date().addingTimeInterval(25)
                while self.isSyncing && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if self.isSyncing {
                    logWarning("[Sync] Background flush: timed out waiting for in-progress sync")
                    completion(false)
                    return
                }
            }

            guard self.hasPendingRecords() else {
                logWarning("[Sync] Background flush: no pending records — skipping")
                completion(true)
                return
            }

            logWarning("[Sync] Background flush: pushing pending changes immediately")
            self.pushLocalChanges { result in
                switch result {
                case .success:
                    logWarning("[Sync] Background flush: push completed successfully")
                    completion(true)
                case .failure(let error):
                    logError("[Sync] Background flush: push failed — \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    /// Resets all sync_status values to 'pending' so everything gets re-pushed to CloudKit.
    /// Also updates ck_modified_at to ensure re-pushed records win conflict resolution on other devices.
    private static func resetAllSyncStatuses() {
        logWarning("[Sync] Resetting all sync statuses to 'pending' for re-push")
        let now = Int(Date().timeIntervalSince1970)
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            DBHelper.shared.executeSyncUpdate(
                "UPDATE \(table) SET sync_status = 'pending', ck_modified_at = \(now) WHERE sync_status = 'synced' AND (is_deleted IS NULL OR is_deleted = 0);",
                textBindings: []
            )
        }
        TransactionRepository.invalidateCache()
    }

    /// Resets all local ck_modified_at and updated_at timestamps to 0 so incoming cloud data always wins
    /// conflict resolution. Used when the user explicitly chooses to accept cloud data.
    private static func resetLocalModificationTimestamps() {
        logWarning("[Sync] Resetting all local ck_modified_at and updated_at to 0 — cloud data will take priority")
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            DBHelper.shared.executeSyncUpdate(
                "UPDATE \(table) SET ck_modified_at = 0, updated_at = 0;",
                textBindings: []
            )
        }
    }

    @objc private func handleRemoteNotification() {
        // Also fetch invitations immediately (public DB notifications don't trigger private DB changes)
        BudgetGroupService.shared.fetchRemoteInvitations {}
        performFullSync()
    }

    @objc private func handleLocalDataChange() {
        guard !isProcessingCloudData && !isSyncing else {
            // A sync is in progress — flag that we need a follow-up push
            // (e.g., lazy-generated recurring instances created during sync)
            needsPostSyncPush = true
            return
        }
        syncQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.isSyncing else { return }
            self.pushLocalChanges()
        }
    }

    /// Centralised cleanup: resets sync flags, sets status, drains post-sync push, and calls completion.
    /// Every exit path from startSyncOperations must funnel through this to avoid stuck flags.
    private func finishSync(status newStatus: SyncStatus, completion: (() -> Void)?) {
        self.isProcessingCloudData = false
        self.status = newStatus
        self.isSyncing = false
        self.syncStartedAt = nil
        self.drainPostSyncPush()
        completion?()
    }

    private static let maxPostSyncPushCycles = 3
    private var postSyncPushCycleCount = 0

    /// If local data changed while a sync was in progress, push the pending records now.
    /// Limited to a maximum number of cycles to prevent infinite loops from conflict storms.
    private func drainPostSyncPush() {
        guard needsPostSyncPush else { return }
        needsPostSyncPush = false

        postSyncPushCycleCount += 1
        if postSyncPushCycleCount > Self.maxPostSyncPushCycles {
            logWarning("[Sync] Post-sync push cycle limit (\(Self.maxPostSyncPushCycles)) reached — stopping. Remaining records will sync on next cycle.")
            postSyncPushCycleCount = 0
            return
        }

        // Only push if there are actually pending records
        guard hasPendingRecords() else {
            logWarning("[Sync] Post-sync push requested but no pending records — skipping")
            postSyncPushCycleCount = 0
            return
        }

        logWarning("[Sync] Draining post-sync push (cycle \(postSyncPushCycleCount)/\(Self.maxPostSyncPushCycles)) for records created during sync")
        syncQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.pushLocalChanges { result in
                if case .success = result {
                    // Check if more post-sync pushes are needed
                    self?.drainPostSyncPush()
                }
            }
        }
    }

    // MARK: - Sync Cycle

    private func executeSyncCycle(completion: (() -> Void)? = nil) {
        // Safety: if isSyncing has been true for over 2 minutes, force-reset it
        if isSyncing, let started = syncStartedAt, Date().timeIntervalSince(started) > 120 {
            logWarning("[Sync] isSyncing stuck for over 2 minutes — force-resetting")
            isSyncing = false
            isProcessingCloudData = false
            syncStartedAt = nil
        }

        guard !isSyncing else {
            logWarning("[Sync] Already syncing — skipping")
            completion?()
            return
        }

        logWarning("[Sync] Starting sync cycle (isAvailable=\(cloudKitOps.isAvailable))")

        if cloudKitOps.isAvailable {
            startSyncOperations(completion: completion)
        } else {
            // Check account status first — isAvailable may not be set yet
            cloudKitOps.checkAccountStatus { [weak self] accountStatus in
                guard let self = self else {
                    completion?()
                    return
                }
                logWarning("[Sync] Account status check: \(accountStatus)")
                guard accountStatus == .available else {
                    logWarning("[Sync] Account not available (\(accountStatus)) — aborting")
                    self.status = .idle
                    completion?()
                    return
                }
                self.syncQueue.async {
                    self.startSyncOperations(completion: completion)
                }
            }
        }
    }

    private func startSyncOperations(completion: (() -> Void)? = nil) {
        guard !isSyncing else {
            completion?()
            return
        }

        isSyncing = true
        syncStartedAt = Date()
        postSyncPushCycleCount = 0
        didReceiveBalanceOffsetDuringPull = false
        status = .syncing
        cloudKitOps.ensureZoneExists { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }

            switch result {
            case .success:
                self.setupSubscriptionsIfNeeded()
                self.fetchPrivateDatabaseChanges { result in
                    switch result {
                    case .success:
                        // Fetch shared DB changes (group zones from other iCloud accounts)
                        self.fetchSharedDatabaseChanges {
                            // After a full re-fetch (reset sync), clean up local records
                            // that exist locally but were not seen in the CloudKit fetch.
                            // Safety: only clean up if we actually received records (avoids
                            // wiping everything if the pull returned 0 due to a network issue).
                            if self.isFullRefetch {
                                logWarning("[Sync] Full re-fetch complete — pulledCKRecordNames has \(self.pulledCKRecordNames.count) record(s)")
                                if !self.pulledCKRecordNames.isEmpty {
                                    self.cleanupOrphanedRecords()
                                } else {
                                    logWarning("[Sync] Full re-fetch pulled 0 records — skipping orphan cleanup to avoid data loss")
                                }
                                self.isFullRefetch = false
                                self.pulledCKRecordNames = []
                            }
                            // Mirror mode: ensure all personal data is tagged with group ID before push
                            MirrorModeManager.shared.reconcileMirrorData()
                            // One-time recovery: reset tokens if migration caused data loss
                            self.recoverFromGroupZoneMigration()
                            // One-time migration: move group-tagged records from private zone to group zones
                            self.migrateGroupRecordsToGroupZones()
                            self.pushLocalChanges { pushResult in
                            switch pushResult {
                            case .success:
                                self.stateManager.updateLastSyncDate(for: "privateDB")
                                // Discover groups from ALL zones (fallback for missed zone changes)
                                self.discoverGroupsFromAllZones {
                                    // Re-run reconciliation to tag any transactions pulled during zone discovery
                                    if MirrorModeManager.shared.isEnabled {
                                        MirrorModeManager.shared.reconcileMirrorData()
                                        self.needsPostSyncPush = true
                                    }
                                    self.postSyncActions.performPostSyncFetches {
                                        self.syncQueue.async {
                                            // Diagnostic: group balance state
                                            if let uid = UIDUserDefaultsManager.shared.currentUserUID {
                                                let personalOffset = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
                                                let groups = BudgetGroupRepository().fetchAllGroups()
                                                for g in groups {
                                                    let groupOffset = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(g.id)")
                                                    let txRepo = TransactionRepository()
                                                    let mirrorTxCount = txRepo.fetchTransactionsForGroup(groupId: g.id).count
                                                    let allTxCount = txRepo.fetchAllTransactions().count
                                                    logWarning("[Sync] Balance diagnostic: personalOffset=\(personalOffset), groupOffset=\(groupOffset) (group '\(g.name)'), mirrorTx=\(mirrorTxCount)/\(allTxCount)")
                                                }
                                            }
                                            logWarning("[Sync] Sync cycle complete — status: synced")

                                            // Post ALL data notifications once at the end of the sync cycle.
                                            // This ensures the UI only refreshes after pull + reconciliation
                                            // + push have all completed, avoiding intermediate broken states.
                                            // handleLocalDataChange guards against re-entrance via isSyncing check
                                            // and any pending records will already have been pushed above.
                                            TransactionRepository.invalidateCache()
                                            DispatchQueue.main.async {
                                                NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
                                                NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
                                                NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
                                                NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
                                                NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
                                            }

                                            self.finishSync(status: .synced, completion: completion)
                                        }
                                    }
                                }
                            case .failure(let error):
                                logError("[Sync] Push failed: \(error.localizedDescription)")
                                self.finishSync(status: .error(error), completion: completion)
                            }
                        }
                        } // fetchSharedDatabaseChanges
                    case .failure(let error):
                        logError("[Sync] Fetch changes failed: \(error.localizedDescription)")
                        self.finishSync(status: .error(error), completion: completion)
                    }
                }
            case .failure(let error):
                logError("[Sync] Zone creation failed: \(error.localizedDescription)")
                self.finishSync(status: .error(error), completion: completion)
            }
        }
    }

    private func setupSubscriptionsIfNeeded() {
        guard !hasSetupSubscriptions else { return }
        hasSetupSubscriptions = true
        cloudKitOps.setupSubscriptions(email: AuthenticationManager.shared.currentUser?.email)
    }

    // MARK: - Fetch Changes (Pull)

    private func fetchPrivateDatabaseChanges(completion: @escaping (Result<Void, Error>) -> Void) {
        let token = stateManager.changeToken(for: "privateDB", database: "private")
        logWarning("[Sync] Fetching database changes (hasToken=\(token != nil))")
        var changedZoneIDs: [CKRecordZone.ID] = []

        cloudKitOps.fetchDatabaseChanges(
            token: token,
            changedZoneHandler: { zoneID in
                changedZoneIDs.append(zoneID)
            },
            completion: { [weak self] result in
                switch result {
                case .success(let newToken):
                    let zoneNames = changedZoneIDs.map { $0.zoneName }
                    logWarning("[Sync] Database changes fetched — \(changedZoneIDs.count) changed zone(s): \(zoneNames)")
                    self?.stateManager.saveChangeToken(newToken, for: "privateDB", database: "private")

                    if changedZoneIDs.isEmpty {
                        logWarning("[Sync] No changed zones — skipping zone fetch")
                        completion(.success(()))
                    } else {
                        self?.fetchZoneChanges(zoneIDs: changedZoneIDs, database: .private, completion: completion)
                    }
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                        logWarning("Change token expired for privateDB — resetting and retrying")
                        self?.stateManager.resetAllTokens()
                        self?.fetchPrivateDatabaseChanges(completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        )
    }

    /// Fetches changes from the shared database (group zones shared by other iCloud accounts).
    /// Non-fatal — if this fails, sync continues with private data only.
    private func fetchSharedDatabaseChanges(completion: @escaping () -> Void) {
        let token = stateManager.changeToken(for: "sharedDB", database: "shared")
        logWarning("[Sync] Fetching shared database changes (hasToken=\(token != nil))")
        var changedZoneIDs: [CKRecordZone.ID] = []

        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)

        operation.recordZoneWithIDChangedBlock = { zoneID in
            changedZoneIDs.append(zoneID)
        }

        operation.fetchDatabaseChangesResultBlock = { [weak self] result in
            switch result {
            case .success(let (newToken, _)):
                let zoneNames = changedZoneIDs.map { $0.zoneName }
                logWarning("[Sync] Shared DB changes fetched — \(changedZoneIDs.count) changed zone(s): \(zoneNames)")
                self?.stateManager.saveChangeToken(newToken, for: "sharedDB", database: "shared")

                if changedZoneIDs.isEmpty {
                    logWarning("[Sync] No changed shared zones — skipping")
                    completion()
                } else {
                    self?.fetchZoneChanges(zoneIDs: changedZoneIDs, database: .shared) { _ in
                        completion()
                    }
                }
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                    logWarning("[Sync] Shared DB change token expired — resetting and retrying")
                    self?.stateManager.saveChangeToken(nil, for: "sharedDB", database: "shared")
                    self?.fetchSharedDatabaseChanges(completion: completion)
                } else {
                    logWarning("[Sync] Shared DB changes fetch failed (non-fatal): \(error.localizedDescription)")
                    completion()
                }
            }
        }

        operation.qualityOfService = .userInitiated
        CloudKitManager.shared.sharedDatabase.add(operation)
    }

    private func fetchZoneChanges(
        zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.isProcessingCloudData = true
        var pulledRecordCount = 0
        var pulledDeleteCount = 0

        logWarning("[Sync] Fetching zone changes for \(zoneIDs.map { $0.zoneName })")

        cloudKitOps.fetchZoneChanges(
            zoneIDs: zoneIDs,
            database: database,
            tokenForZone: { [weak self] zoneID in
                let dbKey = database == .private ? "private" : "shared"
                return self?.stateManager.changeToken(for: zoneID.zoneName, database: dbKey)
            },
            recordHandler: { [weak self] record in
                pulledRecordCount += 1
                if self?.isFullRefetch == true {
                    self?.pulledCKRecordNames.insert(record.recordID.recordName)
                }
                self?.processIncomingRecord(record)
            },
            deleteHandler: { [weak self] recordID, recordType in
                pulledDeleteCount += 1
                self?.processDeletedRecord(recordID: recordID, recordType: recordType)
            },
            zoneTokenHandler: { [weak self] zoneID, token in
                let dbKey = database == .private ? "private" : "shared"
                self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: dbKey)
            },
            completion: { [weak self] result in
                self?.isProcessingCloudData = false
                switch result {
                case .success:
                    logWarning("[Sync] Pull complete — \(pulledRecordCount) record(s), \(pulledDeleteCount) delete(s)")
                    TransactionRepository.invalidateCache()
                    let localCount = TransactionRepository().fetchAllTransactions().count
                    logWarning("[Sync] Local DB has \(localCount) transaction(s) after pull")
                    // NOTE: fixAndDeduplicateAfterSync() removed from per-sync execution.
                    // The ConflictResolver already handles deduplication during pull.
                    // Running dedup after every sync was too aggressive — it deleted
                    // legitimate transactions that shared (title, budget_month_date).

                    // Data notifications are deferred to the end of the sync cycle
                    // so the UI only refreshes once all pull + reconciliation + push
                    // steps have completed, avoiding intermediate/broken states.
                    completion(.success(()))
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                        logWarning("Zone changes token expired — resetting all tokens and retrying")
                        self?.stateManager.resetAllTokens()
                        self?.fetchZoneChanges(zoneIDs: zoneIDs, database: database, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        )
    }

    // MARK: - Group Zone Routing

    /// Returns the appropriate CKRecordZone.ID for a given group.
    /// For groups owned by the current user, returns the group zone in the private DB.
    /// Otherwise, returns the private zone (member-to-owner push not yet supported).
    private func targetZoneID(forGroupId groupId: String?) -> CKRecordZone.ID {
        guard let groupId = groupId, !groupId.isEmpty else {
            return CloudKitManager.privateZoneID
        }

        let group = BudgetGroupRepository().fetchGroup(byId: groupId)
        guard let group = group, group.isOwner else {
            return CloudKitManager.privateZoneID
        }

        return CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
    }

    /// One-time migration: marks group-tagged synced records as pending so they get
    /// re-pushed to group zones instead of FinovaPrivateZone.
    private func migrateGroupRecordsToGroupZones() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedGroupZoneMigration_v1") else { return }

        // Tables with shared_group_id column
        let groupTables = ["Transactions", "Budgets", "CreditCards", "BudgetAllocations"]
        for table in groupTables {
            DBHelper.shared.executeSyncUpdate(
                "UPDATE \(table) SET sync_status = 'pending' WHERE sync_status = 'synced' AND shared_group_id IS NOT NULL AND shared_group_id != '';",
                textBindings: []
            )
        }

        // CreditCardStatements don't have shared_group_id — mark them pending
        // if their parent credit card belongs to a group
        DBHelper.shared.executeSyncUpdate(
            "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE sync_status = 'synced' AND credit_card_id IN (SELECT id FROM CreditCards WHERE shared_group_id IS NOT NULL AND shared_group_id != '');",
            textBindings: []
        )

        TransactionRepository.invalidateCache()
        UserDefaults.standard.set(true, forKey: "hasCompletedGroupZoneMigration_v1")
        logWarning("[Sync] Migrated group records to pending for group zone push")
    }

    /// Recovery: if the group zone migration already ran and the private-zone
    /// deletes corrupted local data, reset tokens to force a full re-fetch
    /// from CloudKit.  The Group zone still has every record, so the pull
    /// will restore whatever was lost.
    private func recoverFromGroupZoneMigration() {
        guard UserDefaults.standard.bool(forKey: "hasCompletedGroupZoneMigration_v1"),
              !UserDefaults.standard.bool(forKey: "hasRecoveredGroupZoneMigration_v1") else { return }

        logWarning("[Sync] Recovering from group zone migration — resetting tokens for full re-fetch")
        stateManager.resetAllTokens()
        UserDefaults.standard.set(true, forKey: "hasRecoveredGroupZoneMigration_v1")
    }

    // MARK: - CloudKit Record Construction Helpers

    /// Maps a CK record name prefix to its SQLite table name.
    private func tableForRecordName(_ name: String) -> String? {
        if name.hasPrefix("transaction-") { return "Transactions" }
        if name.hasPrefix("budget-") { return "Budgets" }
        if name.hasPrefix("creditCard-") { return "CreditCards" }
        if name.hasPrefix("statement-") { return "CreditCardStatements" }
        if name.hasPrefix("allocation-") { return "BudgetAllocations" }
        return nil
    }

    /// Clears stored system fields for a record so the next push treats it as new.
    private func clearSystemFields(ckRecordName name: String) {
        guard let table = tableForRecordName(name) else { return }
        DBHelper.shared.clearSystemFields(ckRecordName: name, table: table)
    }

    /// Encodes a CKRecord's system fields and stores them in the local DB.
    private func storeSystemFields(from record: CKRecord) {
        guard let table = tableForRecordName(record.recordID.recordName) else { return }
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        DBHelper.shared.saveSystemFields(coder.encodedData, ckRecordName: record.recordID.recordName, table: table)
    }

    /// Rebuilds a push-ready CKRecord by merging the local field values (from `fresh`) onto
    /// a system-fields-bearing CKRecord decoded from `systemFieldsData`.
    /// This preserves `recordChangeTag`, enabling `.ifServerRecordUnchanged`.
    /// Falls back to the fresh record when no system fields are stored yet (new records).
    private func buildCKRecord(fresh: CKRecord, systemFieldsData: Data?) -> CKRecord {
        guard let data = systemFieldsData,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return fresh }
        unarchiver.requiresSecureCoding = true
        guard let archived = CKRecord(coder: unarchiver) else { return fresh }
        unarchiver.finishDecoding()
        // Copy all user-defined fields from the fresh record onto the archived one.
        // The archived record retains its recordChangeTag; the fresh record provides
        // the current local values.
        for key in fresh.allKeys() {
            archived[key] = fresh[key]
        }
        return archived
    }

    // MARK: - Push Local Changes

    private static let batchSize = 50

    /// Returns true if any repository has records pending sync or pending deletion.
    private func hasPendingRecords() -> Bool {
        let txRepo = TransactionRepository()
        TransactionRepository.invalidateCache()
        if !txRepo.fetchPendingSync().isEmpty { return true }
        if !txRepo.fetchPendingDeletes().isEmpty { return true }

        let budgetRepo = BudgetRepository()
        if !budgetRepo.fetchPendingSync().isEmpty { return true }
        if !budgetRepo.fetchPendingDeletes().isEmpty { return true }

        let cardRepo = CreditCardRepository()
        if !cardRepo.fetchPendingSync().isEmpty { return true }
        if !cardRepo.fetchPendingDeletes().isEmpty { return true }

        let stmtRepo = StatementRepository()
        if !stmtRepo.fetchPendingSync().isEmpty { return true }
        if !stmtRepo.fetchPendingDeletes().isEmpty { return true }

        let allocRepo = BudgetAllocationRepository()
        if !allocRepo.fetchPendingSync().isEmpty { return true }
        if !allocRepo.fetchPendingDeletes().isEmpty { return true }

        return false
    }

    private func pushLocalChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Respect CloudKit throttle window
        if let throttledUntil = pushThrottledUntil, Date() < throttledUntil {
            let remaining = Int(throttledUntil.timeIntervalSinceNow)
            logWarning("Push throttled — retrying in \(remaining)s")
            let error = NSError(domain: "SyncEngine", code: -1001,
                                userInfo: [NSLocalizedDescriptionKey: "CloudKit quota exceeded. Will retry in \(remaining)s."])
            completion?(.failure(error))
            return
        }
        var allRecords: [CKRecord] = []
        var allDeleteIDs: [CKRecord.ID] = []
        pendingCKIdAssignments = [:]

        // Repair: any soft-deleted transaction whose sync_status was corrupted (e.g. overwritten
        // by a previous pull before the pendingDelete could be pushed) gets re-queued here.
        // This covers installments/recurring batches deleted before the ConflictResolver fix,
        // without requiring a full reset sync to trigger the per-record repair path.
        let repairedCount = DBHelper.shared.repairCorruptedPendingDeletes()
        if repairedCount > 0 {
            logWarning("[Sync] Repaired \(repairedCount) soft-deleted transaction(s) whose pendingDelete status was lost")
        }

        // Transactions — use stored ck_record_id to avoid creating duplicate CK records
        let txRepo = TransactionRepository()
        TransactionRepository.invalidateCache()
        let allTxCount = txRepo.fetchAllTransactions().count
        let pendingTransactions = txRepo.fetchPendingSync()
        logWarning("[Sync] Transactions: \(allTxCount) total, \(pendingTransactions.count) pending")
        for tx in pendingTransactions {
            let storedName = tx.id.flatMap { txRepo.fetchCKRecordName(for: $0) }
            let groupId = tx.id.flatMap { txRepo.fetchSharedGroupId(for: $0) }
            let zone = targetZoneID(forGroupId: groupId)

            let freshRecord = tx.toCKRecord(in: zone, storedRecordName: storedName)
            // Phase 3B: Defer setCKRecordId to after push succeeds to avoid orphaned names
            if let txId = tx.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "transaction", localId: txId)
            }
            // Include shared_group_id in CK record
            if let groupId = groupId {
                freshRecord["sharedGroupId"] = groupId as CKRecordValue
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "Transactions")
            }
            allRecords.append(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields))
        }

        // Transaction deletes
        for pending in txRepo.fetchPendingDeletes() {
            let groupId = txRepo.fetchSharedGroupId(for: pending.localId)
            let zone = targetZoneID(forGroupId: groupId)
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: zone))
        }

        // Budgets (uses monthDate as key — deterministic across devices)
        let budgetRepo = BudgetRepository()
        let pendingBudgets = budgetRepo.fetchPendingSync()
        for budget in pendingBudgets {
            let zone = targetZoneID(forGroupId: budget.sharedGroupId)
            let freshRecord = budget.toCKRecord(in: zone)
            let budgetRecordName = freshRecord.recordID.recordName
            let systemFields = DBHelper.shared.fetchSystemFields(ckRecordName: budgetRecordName, table: "Budgets")
            allRecords.append(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields))
        }

        // Budget deletes
        for pending in budgetRepo.fetchPendingDeletes() {
            let groupId = DBHelper.shared.fetchSingleString(
                "SELECT shared_group_id FROM Budgets WHERE month_date = ?;",
                intBinding: pending.monthDate
            )
            let zone = targetZoneID(forGroupId: groupId)
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: zone))
        }

        // Credit Cards — use stored ck_record_id
        let cardRepo = CreditCardRepository()
        let pendingCards = cardRepo.fetchPendingSync()
        for card in pendingCards {
            let storedName = card.id.flatMap { cardRepo.fetchCKRecordName(for: $0) }
            let groupId = card.sharedGroupId
            let zone = targetZoneID(forGroupId: groupId)

            let freshRecord = card.toCKRecord(in: zone, storedRecordName: storedName)
            if let cardId = card.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "creditCard", localId: cardId)
            }
            if let groupId = groupId {
                freshRecord["sharedGroupId"] = groupId as CKRecordValue
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "CreditCards")
            }
            allRecords.append(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields))
        }

        // Credit Card deletes
        for pending in cardRepo.fetchPendingDeletes() {
            let groupId = cardRepo.fetchSharedGroupId(for: pending.localId)
            let zone = targetZoneID(forGroupId: groupId)
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: zone))
        }

        // Credit Card Statements — use stored ck_record_id
        // Statements inherit their group zone from their parent credit card
        let stmtRepo = StatementRepository()
        let pendingStmts = stmtRepo.fetchPendingSync()
        for stmt in pendingStmts {
            let storedName = stmt.id.flatMap { stmtRepo.fetchCKRecordName(for: $0) }
            let parentGroupId = cardRepo.fetchSharedGroupId(for: stmt.creditCardId)
            let zone = targetZoneID(forGroupId: parentGroupId)

            let freshRecord = stmt.toCKRecord(in: zone, storedRecordName: storedName)
            if let stmtId = stmt.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "statement", localId: stmtId)
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "CreditCardStatements")
            }
            allRecords.append(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields))
        }

        // Statement deletes
        for pending in stmtRepo.fetchPendingDeletes() {
            let parentCardId = DBHelper.shared.fetchSingleInt(
                "SELECT credit_card_id FROM CreditCardStatements WHERE id = ?;",
                intBinding: pending.localId
            )
            let parentGroupId = parentCardId.flatMap { cardRepo.fetchSharedGroupId(for: $0) }
            let zone = targetZoneID(forGroupId: parentGroupId)
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: zone))
        }

        // Budget Allocations — use stored ck_record_id
        let allocRepo = BudgetAllocationRepository()
        let pendingAllocs = allocRepo.fetchPendingSync()
        for alloc in pendingAllocs {
            let storedName = alloc.id.flatMap { allocRepo.fetchCKRecordName(for: $0) }
            let zone = targetZoneID(forGroupId: alloc.sharedGroupId)

            let freshRecord = alloc.toCKRecord(in: zone, storedRecordName: storedName)
            if let allocId = alloc.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "allocation", localId: allocId)
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "BudgetAllocations")
            }
            allRecords.append(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields))
        }

        // Allocation deletes
        for pending in allocRepo.fetchPendingDeletes() {
            let groupId = DBHelper.shared.fetchSingleString(
                "SELECT shared_group_id FROM BudgetAllocations WHERE id = ?;",
                intBinding: pending.localId
            )
            let zone = targetZoneID(forGroupId: groupId)
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: zone))
        }

        logWarning("[Sync] Push: \(allRecords.count) record(s) to save, \(allDeleteIDs.count) to delete")

        guard !allRecords.isEmpty || !allDeleteIDs.isEmpty else {
            completion?(.success(()))
            return
        }

        let batches = stride(from: 0, to: allRecords.count, by: Self.batchSize).map {
            Array(allRecords[$0..<min($0 + Self.batchSize, allRecords.count)])
        }

        // Detect initial push: many records and never completed before
        if allRecords.count > Self.batchSize && !UserDefaults.standard.bool(forKey: "hasCompletedInitialCloudPush_v1") {
            isInitialPush = true
            let progress = SyncPushProgress(currentBatch: 0, totalBatches: batches.count, totalRecords: allRecords.count)
            currentPushProgress = progress
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .syncPushProgressDidChange, object: progress)
            }
        }

        pushBatches(batches, deleteIDs: allDeleteIDs, index: 0, completion: completion)
    }

    private static let maxThrottleRetries = 5

    private func pushBatches(
        _ batches: [[CKRecord]],
        deleteIDs: [CKRecord.ID] = [],
        index: Int,
        throttleRetryCount: Int = 0,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard index < batches.count else {
            // All batches complete — mark initial push as done
            if isInitialPush {
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialCloudPush_v1")
                isInitialPush = false
                currentPushProgress = nil
            }

            // After all save batches, send deletes if any
            if !deleteIDs.isEmpty {
                pushDeletes(deleteIDs, completion: completion)
            } else {
                completion?(.success(()))
            }
            return
        }

        let batch = batches[index]
        var hitQuotaLimit = false
        var hitSchemaError = false

        var batchSuccessCount = 0
        var batchFailureCount = 0

        cloudKitOps.saveRecords(batch) { [weak self] recordID, result in
            let name = recordID.recordName
            switch result {
            case .success(let savedRecord):
                batchSuccessCount += 1
                // Store the server-returned record's system fields (includes updated recordChangeTag).
                // This ensures the next push can use .ifServerRecordUnchanged with the correct tag.
                self?.storeSystemFields(from: savedRecord)

                // Phase 3B fix: set ck_record_id AFTER successful push to avoid orphaned names
                if let assignment = self?.pendingCKIdAssignments.removeValue(forKey: name) {
                    switch assignment.type {
                    case "transaction":
                        TransactionRepository().setCKRecordId(for: assignment.localId, ckRecordName: name)
                    case "creditCard":
                        CreditCardRepository().setCKRecordId(for: assignment.localId, ckRecordName: name)
                    case "statement":
                        StatementRepository().setCKRecordId(for: assignment.localId, ckRecordName: name)
                    case "allocation":
                        BudgetAllocationRepository().setCKRecordId(for: assignment.localId, ckRecordName: name)
                    default:
                        break
                    }
                }

                if name.hasPrefix("transaction-") {
                    TransactionRepository().markAsSynced(ckRecordName: name)
                } else if name.hasPrefix("budget-") {
                    BudgetRepository().markAsSynced(ckRecordName: name)
                } else if name.hasPrefix("creditCard-") {
                    CreditCardRepository().markAsSynced(ckRecordName: name)
                } else if name.hasPrefix("statement-") {
                    StatementRepository().markAsSynced(ckRecordName: name)
                } else if name.hasPrefix("allocation-") {
                    BudgetAllocationRepository().markAsSynced(ckRecordName: name)
                }
            case .failure(let error):
                batchFailureCount += 1
                if let ckError = error as? CKError {
                    switch ckError.code {
                    case .serverRecordChanged:
                        // CloudKit rejected our push because the server has a newer version of the record.
                        // Process the server record through ConflictResolver to update local state,
                        // then store its system fields so the next push uses the correct recordChangeTag.
                        if let serverRecord = ckError.serverRecord {
                            logWarning("[Sync] ⚠️ serverRecordChanged for \(name) — merging server version")
                            self?.storeSystemFields(from: serverRecord)
                            self?.processIncomingRecord(serverRecord)
                        } else {
                            logWarning("[Sync] ⚠️ serverRecordChanged for \(name) — no server record in error")
                        }
                        // Keep as pending; the next sync cycle will push again with the updated tag.
                        self?.needsPostSyncPush = true
                    case .quotaExceeded:
                        if !hitQuotaLimit {
                            hitQuotaLimit = true
                            let retryAfter = ckError.retryAfterSeconds ?? 300
                            self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                            logWarning("[Sync] ⚠️ CloudKit quota exceeded — throttling for \(Int(retryAfter))s. Pending records will sync on next launch.")
                        }
                    case .invalidArguments:
                        let desc = error.localizedDescription
                        if desc.contains("Cannot create or modify field") || desc.contains("production schema") {
                            // Schema mismatch (e.g. new field not yet deployed to production).
                            // Non-retryable until the schema is deployed via CloudKit Dashboard.
                            if !hitSchemaError {
                                hitSchemaError = true
                                logWarning("[Sync] ⚠️ CloudKit schema error — new fields not yet deployed to production. Records will sync after schema deployment.")
                            }
                        } else if desc.contains("record not found") {
                            // Stale recordChangeTag — clear stored system fields so next push creates a fresh record.
                            logWarning("[Sync] ⚠️ Record \(name) has stale changeTag — clearing system fields for re-push")
                            self?.clearSystemFields(ckRecordName: name)
                            self?.needsPostSyncPush = true
                        } else {
                            logWarning("[Sync] ❌ Failed to push record \(name) (invalidArguments): \(desc)")
                        }
                    default:
                        logWarning("[Sync] ❌ Failed to push record \(name): \(error.localizedDescription)")
                    }
                } else {
                    logWarning("[Sync] ❌ Failed to push record \(name): \(error.localizedDescription)")
                }
            }
        } completion: { [weak self] result in
            logWarning("[Sync] Batch \(index + 1)/\(batches.count) result: \(batchSuccessCount) succeeded, \(batchFailureCount) failed")

            if let self = self, self.isInitialPush {
                let progress = SyncPushProgress(currentBatch: index + 1, totalBatches: batches.count, totalRecords: batches.reduce(0) { $0 + $1.count })
                self.currentPushProgress = progress
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .syncPushProgressDidChange, object: progress)
                }
            }

            if hitQuotaLimit {
                // Stop processing remaining batches — pending records will sync on next launch
                logWarning("[Sync] Stopping push due to quota limit. Remaining records will sync later.")
                completion?(.success(()))
                return
            }
            if hitSchemaError {
                // Stop processing remaining save batches — schema needs to be deployed first.
                // But still send deletes, since they don't involve the new field.
                logWarning("[Sync] Stopping save batches due to schema error. Deploy schema via CloudKit Dashboard, then sync again.")
                if !deleteIDs.isEmpty {
                    self?.pushDeletes(deleteIDs, completion: completion)
                } else {
                    completion?(.success(()))
                }
                return
            }
            switch result {
            case .success:
                // Throttle between batches to avoid CloudKit rate limiting
                let delay: TimeInterval = batches.count > 5 ? 1.5 : 0.5
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                    self?.pushBatches(batches, deleteIDs: deleteIDs, index: index + 1, throttleRetryCount: 0, completion: completion)
                }
            case .failure(let error):
                if let ckError = error as? CKError {
                    switch ckError.code {
                    case .quotaExceeded:
                        let retryAfter = ckError.retryAfterSeconds ?? 300
                        self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                        logWarning("[Sync] ⚠️ CloudKit quota exceeded (batch level) — throttling for \(Int(retryAfter))s")
                        completion?(.success(()))
                    case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                        let nextRetry = throttleRetryCount + 1
                        if nextRetry > Self.maxThrottleRetries {
                            logWarning("[Sync] ⚠️ Batch \(index + 1)/\(batches.count) exceeded \(Self.maxThrottleRetries) throttle retries — stopping push. Records remain pending for next sync.")
                            completion?(.success(()))
                            return
                        }
                        let baseDelay = ckError.retryAfterSeconds ?? 3
                        let backoff = baseDelay * Double(nextRetry)
                        logWarning("[Sync] ⚠️ Batch \(index + 1)/\(batches.count) throttled (code \(ckError.code.rawValue)) — retry \(nextRetry)/\(Self.maxThrottleRetries) in \(Int(backoff))s")
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + backoff) {
                            self?.pushBatches(batches, deleteIDs: deleteIDs, index: index, throttleRetryCount: nextRetry, completion: completion)
                        }
                    default:
                        logWarning("[Sync] ❌ Batch \(index + 1)/\(batches.count) failed: \(error.localizedDescription)")
                        // Saves failed but deletes are independent — still push pending deletes
                        // so that locally deleted records are removed from CloudKit even when
                        // a save batch encounters an unrecoverable error (e.g. serverRecordChanged).
                        if !deleteIDs.isEmpty {
                            self?.pushDeletes(deleteIDs, completion: { _ in completion?(.failure(error)) })
                        } else {
                            completion?(.failure(error))
                        }
                    }
                } else {
                    logWarning("[Sync] ❌ Batch \(index + 1)/\(batches.count) failed: \(error.localizedDescription)")
                    if !deleteIDs.isEmpty {
                        self?.pushDeletes(deleteIDs, completion: { _ in completion?(.failure(error)) })
                    } else {
                        completion?(.failure(error))
                    }
                }
            }
        }
    }

    private func pushDeletes(_ deleteIDs: [CKRecord.ID], completion: ((Result<Void, Error>) -> Void)?) {
        cloudKitOps.deleteRecords(deleteIDs) { [weak self] recordID, result in
            let name = recordID.recordName
            switch result {
            case .success:
                // Hard-delete the local row after successful CK deletion
                Self.hardDeleteLocal(recordName: name)
            case .failure(let error):
                if let ckError = error as? CKError {
                    if ckError.code == .unknownItem {
                        // Record already gone from CloudKit — still clean up locally
                        logWarning("[Sync] Record \(name) already deleted from CloudKit — hard-deleting locally")
                        Self.hardDeleteLocal(recordName: name)
                    } else if ckError.code == .quotaExceeded {
                        let retryAfter = ckError.retryAfterSeconds ?? 300
                        self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                    } else {
                        logWarning("[Sync] ❌ Failed to delete record \(name): \(error.localizedDescription)")
                    }
                } else {
                    logWarning("[Sync] ❌ Failed to delete record \(name): \(error.localizedDescription)")
                }
            }
        } completion: { [weak self] result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    let retryAfter = ckError.retryAfterSeconds ?? 300
                    self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                    logWarning("[Sync] ⚠️ CloudKit quota exceeded during deletes — throttling for \(Int(retryAfter))s")
                    completion?(.success(()))
                } else {
                    completion?(.failure(error))
                }
            }
        }
    }

    private static func hardDeleteLocal(recordName name: String) {
        if name.hasPrefix("transaction-") {
            TransactionRepository().hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("budget-") {
            BudgetRepository().hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("creditCard-") {
            CreditCardRepository().hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("statement-") {
            StatementRepository().hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("allocation-") {
            BudgetAllocationRepository().hardDeleteByCKRecordName(name)
        }
    }

    // MARK: - Process Incoming Records

    private func processIncomingRecord(_ record: CKRecord) {
        logWarning("[Sync] Processing incoming record: type=\(record.recordType), name=\(record.recordID.recordName), zone=\(record.recordID.zoneID.zoneName)")

        // Extract group ID from zone name (e.g. "Group-ABC123" → "ABC123")
        // and inject into the record so ConflictResolver can tag it
        let zoneName = record.recordID.zoneID.zoneName
        if zoneName.hasPrefix("Group-"), record["sharedGroupId"] == nil {
            let groupId = String(zoneName.dropFirst("Group-".count))
            record["sharedGroupId"] = groupId as CKRecordValue
        }

        // Mirror mode: records from the private zone don't carry sharedGroupId in CloudKit.
        // Without this, updateFromCloud(sharedGroupId: nil) clears shared_group_id on the
        // local record, breaking the group view until reconcileMirrorData re-tags them.
        // Inject the linked group ID so the local tag is preserved through the pull.
        if !zoneName.hasPrefix("Group-"),
           record["sharedGroupId"] == nil,
           MirrorModeManager.shared.isEnabled,
           let mirrorGroupId = MirrorModeManager.shared.linkedGroupId {
            record["sharedGroupId"] = mirrorGroupId as CKRecordValue
        }

        switch record.recordType {
        case "Transaction":
            guard let transaction = Transaction.fromCKRecord(record) else {
                logError("[Sync] Failed to parse Transaction from CKRecord \(record.recordID.recordName)")
                return
            }
            logWarning("[Sync] Resolved transaction: \(transaction.title) amount=\(transaction.amount)")
            ConflictResolver.shared.resolveTransaction(remote: transaction, ckRecord: record)
        case "Budget":
            guard let budget = BudgetModel.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveBudget(remote: budget, ckRecord: record)
        case "CreditCard":
            guard let card = CreditCard.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveCreditCard(remote: card, ckRecord: record)
        case "CreditCardStatement":
            guard let stmt = CreditCardStatement.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveCreditCardStatement(remote: stmt, ckRecord: record)
        case "BudgetAllocation":
            guard let alloc = BudgetAllocationModel.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveBudgetAllocation(remote: alloc, ckRecord: record)
        case "GroupActivity":
            processGroupActivity(record)
        case "BalanceOffset":
            processBalanceOffset(record)
        case "BudgetGroup":
            processIncomingBudgetGroup(record)
        case _ where record.recordType.hasPrefix("cloudkit."):
            // System record types (cloudkit.share, etc.) — ignore silently
            break
        default:
            logWarning("Unknown record type received: \(record.recordType)")
        }
    }

    private func processDeletedRecord(recordID: CKRecord.ID, recordType: String) {
        switch recordType {
        case "Transaction":
            TransactionRepository().deleteFromCloud(ckRecordName: recordID.recordName)
        case "Budget":
            BudgetRepository().deleteFromCloud(ckRecordName: recordID.recordName)
        case "CreditCard":
            CreditCardRepository().deleteFromCloud(ckRecordName: recordID.recordName)
        case "CreditCardStatement":
            StatementRepository().deleteFromCloud(ckRecordName: recordID.recordName)
        case "BudgetAllocation":
            BudgetAllocationRepository().deleteFromCloud(ckRecordName: recordID.recordName)
        default:
            break
        }
    }

    /// After a full re-fetch (reset sync), removes local records that have a ck_record_id
    /// but were not seen in the CloudKit fetch — meaning they were deleted on another device.
    private func cleanupOrphanedRecords() {
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        var totalOrphans = 0
        for table in tables {
            let localNames = DBHelper.shared.fetchAllCKRecordNames(table: table)
            let orphans = localNames.filter { !pulledCKRecordNames.contains($0) }
            logWarning("[Sync] Orphan check \(table): \(localNames.count) local record(s) with ck_record_id, \(orphans.count) orphan(s)")
            if !orphans.isEmpty {
                logWarning("[Sync] Cleaning up \(orphans.count) orphaned record(s) from \(table): \(orphans.prefix(10))")
                DBHelper.shared.deleteOrphanedRecords(table: table, ckRecordNames: orphans)
                totalOrphans += orphans.count
            }
        }
        if totalOrphans > 0 {
            logWarning("[Sync] Orphan cleanup complete — removed \(totalOrphans) record(s) not found in CloudKit")
            TransactionRepository.invalidateCache()
        } else {
            logWarning("[Sync] Orphan cleanup found no orphans — all local records matched CloudKit")
        }
    }

    private func processGroupActivity(_ record: CKRecord) {
        GroupNotificationManager.shared.handleIncomingActivity(record)
    }

    private func processBalanceOffset(_ record: CKRecord) {
        guard let key = record["key"] as? String,
              let offset = record["offset"] as? Int,
              let uid = UIDUserDefaultsManager.shared.currentUserUID
        else { return }

        didReceiveBalanceOffsetDuringPull = true

        DispatchQueue.main.async {
            var didUpdate = false
            if key == "personal" {
                let current = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
                if current != offset {
                    UserDefaults.standard.set(offset, forKey: "balanceOffset_\(uid)")
                    logInfo("Balance offset updated from sync: personal = \(offset)")
                    didUpdate = true
                }
                // Mirror mode: keep linked group offset in sync locally
                if MirrorModeManager.shared.isEnabled,
                   let groupId = MirrorModeManager.shared.linkedGroupId {
                    UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(groupId)")
                }
            } else if key.hasPrefix("group-") {
                let groupId = String(key.dropFirst("group-".count))
                let current = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(groupId)")
                if current != offset {
                    UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(groupId)")
                    logInfo("Balance offset updated from sync: \(key) = \(offset)")
                    didUpdate = true
                }
                // Mirror mode: keep personal offset in sync locally
                if MirrorModeManager.shared.isEnabled,
                   MirrorModeManager.shared.linkedGroupId == groupId {
                    UserDefaults.standard.set(offset, forKey: "balanceOffset_\(uid)")
                }
            }
            // Balance offset update notification is deferred to the end of
            // the sync cycle along with all other data notifications.
        }
    }

    /// Enumerates ALL record zones in the private database and ensures any Group-{id} zones
    /// have corresponding local BudgetGroup entries. This is a robust fallback that bypasses
    /// the change token flow entirely — handles cases where fetchDatabaseChanges doesn't
    /// report CKShare-based zones.
    private func discoverGroupsFromAllZones(completion: @escaping () -> Void) {
        let repo = BudgetGroupRepository()
        let existingGroups = repo.fetchAllGroups()
        let existingGroupIds = Set(existingGroups.map { $0.id })

        logWarning("[Sync] discoverGroupsFromAllZones: \(existingGroupIds.count) local group(s): \(existingGroupIds)")
        // Also check for soft-deleted groups that might be hidden
        let allGroupRows = DBHelper.shared.fetchBudgetGroupRows(
            "SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, created_at, updated_at, is_deleted FROM BudgetGroups"
        )
        for g in allGroupRows {
            logWarning("[Sync]   group '\(g.name)' id=\(g.id) owner=\(g.ownerId) isDeleted=\(g.isDeleted) ckRecord=\(g.ckRecordId ?? "nil") ckShare=\(g.ckShareUrl ?? "nil")")
        }

        let operation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
        var newGroupZoneIDs: [CKRecordZone.ID] = []
        var unfetchedZoneIDs: [CKRecordZone.ID] = []

        var allZoneNames: [String] = []

        operation.perRecordZoneResultBlock = { [weak self] zoneID, result in
            switch result {
            case .success:
                allZoneNames.append(zoneID.zoneName)
                if zoneID.zoneName.hasPrefix("Group-") {
                    let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
                    if !existingGroupIds.contains(groupId) {
                        newGroupZoneIDs.append(zoneID)
                        logWarning("[Sync] Discovered missing group zone: \(zoneID.zoneName)")
                    } else if self?.stateManager.changeToken(for: zoneID.zoneName, database: "private") == nil {
                        // Group exists locally but zone changes were never fetched
                        unfetchedZoneIDs.append(zoneID)
                        logWarning("[Sync] Group zone exists but never fetched: \(zoneID.zoneName)")
                    }
                }
            case .failure(let error):
                logError("[Sync] Failed to fetch zone \(zoneID.zoneName): \(error.localizedDescription)")
            }
        }

        operation.fetchRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                logWarning("[Sync] Private zone enumeration complete — all zones: \(allZoneNames)")
                logWarning("[Sync] Private zone enumeration — \(newGroupZoneIDs.count) new, \(unfetchedZoneIDs.count) unfetched group zone(s)")

                // Detect local groups whose CloudKit zones are missing and need repair
                let foundGroupZoneIds = Set(
                    allZoneNames
                        .filter { $0.hasPrefix("Group-") }
                        .map { String($0.dropFirst("Group-".count)) }
                )
                let orphanedGroups = existingGroups.filter { group in
                    group.ckRecordId != nil && !foundGroupZoneIds.contains(group.id)
                }
                if !orphanedGroups.isEmpty {
                    logWarning("[Sync] Found \(orphanedGroups.count) local group(s) with missing CloudKit zones — repairing")
                }

                let continueAfterRepair = {
                    let handleUnfetchedZones = {
                        guard !unfetchedZoneIDs.isEmpty else {
                            self?.discoverGroupsFromSharedDatabase(
                                existingGroupIds: existingGroupIds,
                                completion: completion
                            )
                            return
                        }
                        logWarning("[Sync] Fetching zone changes for \(unfetchedZoneIDs.count) previously unfetched group zone(s)")
                        self?.fetchZoneChanges(zoneIDs: unfetchedZoneIDs, database: .private) { _ in
                            self?.discoverGroupsFromSharedDatabase(
                                existingGroupIds: existingGroupIds,
                                completion: completion
                            )
                        }
                    }

                    if !newGroupZoneIDs.isEmpty {
                        self?.fetchMissingGroupRecords(from: newGroupZoneIDs, database: .private) {
                            handleUnfetchedZones()
                        }
                    } else {
                        handleUnfetchedZones()
                    }
                }

                if !orphanedGroups.isEmpty {
                    self?.repairMissingGroupZones(orphanedGroups) {
                        continueAfterRepair()
                    }
                } else {
                    continueAfterRepair()
                }
            case .failure(let error):
                logError("[Sync] Private zone enumeration failed: \(error.localizedDescription)")
                // Still try shared DB even if private fails
                self?.discoverGroupsFromSharedDatabase(
                    existingGroupIds: existingGroupIds,
                    completion: completion
                )
            }
        }

        operation.qualityOfService = .userInitiated
        CloudKitManager.shared.privateDatabase.add(operation)
    }

    /// Discovers group zones in the shared database (zones shared by other iCloud accounts).
    private func discoverGroupsFromSharedDatabase(
        existingGroupIds: Set<String>,
        completion: @escaping () -> Void
    ) {
        let operation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
        var sharedGroupZoneIDs: [CKRecordZone.ID] = []
        var sharedUnfetchedZoneIDs: [CKRecordZone.ID] = []

        operation.perRecordZoneResultBlock = { [weak self] zoneID, result in
            switch result {
            case .success:
                logWarning("[Sync] Shared DB zone found: \(zoneID.zoneName) (owner: \(zoneID.ownerName))")
                if zoneID.zoneName.hasPrefix("Group-") {
                    let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
                    if !existingGroupIds.contains(groupId) {
                        sharedGroupZoneIDs.append(zoneID)
                        logWarning("[Sync] Discovered missing shared group zone: \(zoneID.zoneName)")
                    } else if self?.stateManager.changeToken(for: zoneID.zoneName, database: "shared") == nil {
                        sharedUnfetchedZoneIDs.append(zoneID)
                        logWarning("[Sync] Shared group zone exists but never fetched: \(zoneID.zoneName)")
                    }
                }
            case .failure(let error):
                logError("[Sync] Failed to fetch shared zone \(zoneID.zoneName): \(error.localizedDescription)")
            }
        }

        operation.fetchRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                logWarning("[Sync] Shared DB zone enumeration complete — \(sharedGroupZoneIDs.count) new, \(sharedUnfetchedZoneIDs.count) unfetched group zone(s)")

                let handleSharedUnfetched = {
                    guard !sharedUnfetchedZoneIDs.isEmpty else {
                        completion()
                        return
                    }
                    logWarning("[Sync] Fetching zone changes for \(sharedUnfetchedZoneIDs.count) shared group zone(s)")
                    self?.fetchZoneChanges(zoneIDs: sharedUnfetchedZoneIDs, database: .shared) { _ in
                        completion()
                    }
                }

                if !sharedGroupZoneIDs.isEmpty {
                    self?.fetchMissingGroupRecords(from: sharedGroupZoneIDs, database: .shared) {
                        handleSharedUnfetched()
                    }
                } else {
                    handleSharedUnfetched()
                }
            case .failure(let error):
                logError("[Sync] Shared DB zone enumeration failed: \(error.localizedDescription)")
                completion()
            }
        }

        operation.qualityOfService = .userInitiated
        CloudKitManager.shared.sharedDatabase.add(operation)
    }

    /// Re-creates CloudKit zones and BudgetGroup records for local groups whose zones
    /// have gone missing from CloudKit. This repairs the state so other devices can discover them.
    private func repairMissingGroupZones(_ groups: [BudgetGroup], completion: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()

        for group in groups {
            guard group.isOwner else {
                logWarning("[Sync] Skipping repair for group '\(group.name)' — not owner")
                continue
            }

            dispatchGroup.enter()

            let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
            let zone = CKRecordZone(zoneID: zoneID)

            logWarning("[Sync] Repairing group zone for '\(group.name)' (id=\(group.id))")

            // Step 1: Re-create the zone
            let zoneOp = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            zoneOp.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    logWarning("[Sync] Zone re-created for group '\(group.name)'")

                    // Step 2: Re-create the BudgetGroup record and CKShare
                    let recordID = CKRecord.ID(recordName: "budgetGroup-\(group.id)", zoneID: zoneID)
                    let record = CKRecord(recordType: "BudgetGroup", recordID: recordID)
                    record["name"] = group.name as CKRecordValue
                    record["ownerId"] = group.ownerId as CKRecordValue
                    record["ownerName"] = group.ownerName as CKRecordValue

                    let share = CKShare(rootRecord: record)
                    share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
                    share.publicPermission = .readWrite

                    let saveOp = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
                    saveOp.modifyRecordsResultBlock = { saveResult in
                        switch saveResult {
                        case .success:
                            // Update local share URL
                            if let newShareURL = share.url?.absoluteString {
                                var updated = group
                                updated.ckShareUrl = newShareURL
                                BudgetGroupRepository().updateGroup(updated)
                                logWarning("[Sync] Group '\(group.name)' repaired — new share URL: \(newShareURL)")
                            } else {
                                logWarning("[Sync] Group '\(group.name)' repaired (no share URL returned)")
                            }
                        case .failure(let error):
                            logError("[Sync] Failed to save BudgetGroup record for repair: \(error.localizedDescription)")
                        }
                        dispatchGroup.leave()
                    }
                    saveOp.qualityOfService = .userInitiated
                    CloudKitManager.shared.privateDatabase.add(saveOp)

                case .failure(let error):
                    logError("[Sync] Failed to re-create zone for group '\(group.name)': \(error.localizedDescription)")
                    dispatchGroup.leave()
                }
            }
            zoneOp.qualityOfService = .userInitiated
            CloudKitManager.shared.privateDatabase.add(zoneOp)
        }

        dispatchGroup.notify(queue: .global(qos: .utility)) {
            completion()
        }
    }

    /// Fetches BudgetGroup records from group zones that don't have local entries,
    /// then fetches zone changes to pull their transactions and other data.
    private func fetchMissingGroupRecords(
        from zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope = .private,
        completion: @escaping () -> Void
    ) {
        let group = DispatchGroup()
        let db = database == .private ? CloudKitManager.shared.privateDatabase : CloudKitManager.shared.sharedDatabase
        let dbLabel = database == .private ? "private" : "shared"

        for zoneID in zoneIDs {
            let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
            let recordID = CKRecord.ID(recordName: "budgetGroup-\(groupId)", zoneID: zoneID)

            group.enter()
            db.fetch(withRecordID: recordID) { [weak self] record, error in
                if let record = record {
                    logWarning("[Sync] Fetched missing BudgetGroup record from \(dbLabel) DB for zone \(zoneID.zoneName)")
                    self?.processIncomingBudgetGroup(record)
                } else if let error = error {
                    logWarning("[Sync] Could not fetch BudgetGroup for zone '\(zoneID.zoneName)' from \(dbLabel) DB: \(error.localizedDescription)")
                    // Create placeholder so the group is at least visible
                    self?.createPlaceholderGroup(groupId: groupId)
                }
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .utility)) { [weak self] in
            // Now fetch zone changes for these zones to pull transactions, budgets, etc.
            logWarning("[Sync] Fetching zone changes for \(zoneIDs.count) newly discovered group zone(s) from \(dbLabel) DB")
            self?.fetchZoneChanges(zoneIDs: zoneIDs, database: database) { _ in
                completion()
            }
        }
    }

    /// Creates a minimal BudgetGroup from zone info when the CKRecord isn't available.
    private func createPlaceholderGroup(groupId: String) {
        let repo = BudgetGroupRepository()
        guard repo.fetchGroup(byId: groupId) == nil else { return }
        guard let uid = AuthenticationManager.shared.currentUser?.uid else { return }

        let userName = UserDefaultsManager.getUser()?.name ?? "User"
        let userEmail = AuthenticationManager.shared.currentUser?.email ?? ""
        let group = BudgetGroup(
            id: groupId,
            name: "Group",
            ownerId: uid,
            ownerName: userName,
            ownerEmail: userEmail
        )
        repo.insertGroup(group)

        let ownerMember = GroupMember(
            groupId: groupId,
            userId: uid,
            name: userName,
            email: userEmail,
            role: .owner,
            permissions: .fullAccess
        )
        repo.insertMember(ownerMember)
        logInfo("[Sync] Created placeholder BudgetGroup for group \(groupId)")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
        }
    }

    private func processIncomingBudgetGroup(_ record: CKRecord) {
        guard let name = record["name"] as? String,
              let ownerId = record["ownerId"] as? String,
              let ownerName = record["ownerName"] as? String
        else {
            logError("[Sync] Failed to parse BudgetGroup from CKRecord \(record.recordID.recordName)")
            return
        }

        // Extract group ID from record name "budgetGroup-{id}"
        let recordName = record.recordID.recordName
        guard recordName.hasPrefix("budgetGroup-") else {
            logWarning("[Sync] Unexpected BudgetGroup record name: \(recordName)")
            return
        }
        let groupId = String(recordName.dropFirst("budgetGroup-".count))

        let repo = BudgetGroupRepository()
        let ownerEmail = (ownerId == AuthenticationManager.shared.currentUser?.uid)
            ? (AuthenticationManager.shared.currentUser?.email ?? "")
            : ""

        // Check if group already exists locally
        if let existing = repo.fetchGroup(byId: groupId) {
            // Always update to ensure name, ownerName, and is_deleted are correct
            var updated = existing
            updated.name = name
            updated.ownerName = ownerName
            updated.isDeleted = false  // Restore if it was soft-deleted
            repo.updateGroup(updated)
            logInfo("[Sync] Updated BudgetGroup from CloudKit: \(name) (\(groupId)) isDeleted was: \(existing.isDeleted)")
        } else {
            let group = BudgetGroup(
                id: groupId,
                name: name,
                ownerId: ownerId,
                ownerName: ownerName,
                ownerEmail: ownerEmail,
                createdAt: record.creationDate ?? Date(),
                updatedAt: record.modificationDate ?? Date()
            )

            repo.insertGroup(group)
            logInfo("[Sync] Inserted new BudgetGroup from CloudKit: \(name) (\(groupId))")
        }

        // Ensure the current user is a member (owner or invited member)
        if let uid = AuthenticationManager.shared.currentUser?.uid {
            let existingMembers = repo.fetchMembers(forGroupId: groupId)
            let alreadyMember = existingMembers.contains(where: { $0.userId == uid })
            if !alreadyMember {
                let userName = UserDefaultsManager.getUser()?.name ?? "User"
                let userEmail = AuthenticationManager.shared.currentUser?.email ?? ""
                let isOwner = ownerId == uid
                let member = GroupMember(
                    groupId: groupId,
                    userId: uid,
                    name: isOwner ? ownerName : userName,
                    email: isOwner ? ownerEmail : userEmail,
                    role: isOwner ? .owner : .member,
                    permissions: isOwner ? .fullAccess : .memberDefault
                )
                repo.insertMember(member)
                logInfo("[Sync] Added current user as \(isOwner ? "owner" : "member") of group \(name) (\(groupId))")
            }
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
        }
    }
}
