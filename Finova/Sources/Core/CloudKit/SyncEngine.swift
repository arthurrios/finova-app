//
//  SyncEngine.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation
import UIKit

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

struct SyncPhaseProgress {
    let progress: Float
    let phaseKey: String
    let totalBatches: Int
    let currentBatch: Int
    let totalRecords: Int
    let isLargeSync: Bool
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
    /// Public read-only accessor for UI to check if sync is in progress.
    var isSyncInProgress: Bool { isSyncing || isProcessingCloudData }
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

    /// Records that a local write landed while a sync cycle was in flight, so `finishSync` drains a
    /// follow-up push instead of leaving the row stranded as 'pending'. Called by
    /// `SyncChangeTracker` (which cannot post its usual notification mid-cycle without racing the
    /// running push). Thread-safe — `needsPostSyncPush` is lock-guarded.
    func noteLocalChangeDuringSync() {
        needsPostSyncPush = true
    }
    private(set) var currentPushProgress: SyncPushProgress?
    private var isInitialPush = false
    private var isLargeSyncCycle = false
    private var isRecoverySync = false
    /// Fix 4a: When true, forces full shared DB zone enumeration to discover member groups on new devices.
    private var needsFullSharedDBDiscovery = false
    /// Cooldown: prevents notification-triggered sync loops where our own push
    /// triggers a CK notification → another sync → another push → repeat.
    private var lastSyncCompletedAt: Date?
    private static let syncCooldownInterval: TimeInterval = 10

    private var isSyncDisabledByUser: Bool {
        !UserDefaultsManager.getSyncEnabled()
    }

    /// Answers "is somebody signed in?" — the guard on the front of every sync entry point.
    ///
    /// Injected rather than read from `AuthenticationManager.shared`, which resolves
    /// `Auth.auth().currentUser`: a live Firebase session that no unit test can produce. That single
    /// unmockable read is why 18 SyncEngineTests could only ever observe the "not signed in" path,
    /// and why the projection fan-out — which lives past this guard, inside `pushLocalChanges` —
    /// had no way to be exercised at all.
    var authProvider: AuthProviding = FirebaseAuthProvider()

    /// The database this engine reads and writes. Injected for the same reason the repositories and
    /// `ConflictResolver` already are: SyncEngineTests was the last suite still sharing the singleton
    /// database, and because that file survives across test RUNS, `pendingDelete` tombstones left by
    /// one run were pushed by the next and hard-deleted rows out from under it.
    ///
    /// Resolved LAZILY, and deliberately not captured in `init`. Reading the shared instance from
    /// `SyncEngine.init()` deadlocks the app before launch:
    ///
    ///     DBHelper.shared (dispatch_once) -> initializeDatabase -> performUuidBackfillV1
    ///       -> executeSyncUpdate -> SyncChangeTracker.markDirty -> SyncEngine.shared
    ///       -> SyncEngine.init -> DBHelper.shared, still inside its own dispatch_once
    ///
    /// which traps in `_dispatch_once_wait`. Keeping the singleton lookup out of `init` breaks the
    /// cycle: nothing reaches for it until the engine is actually used.
    private let injectedDB: DBHelper?
    var db: DBHelper { injectedDB ?? .shared }

    /// Bound to `db`, so inbound records resolve against the same database the engine pushes from.
    private lazy var resolver = ConflictResolver(db: db)

    private var isUserAuthenticated: Bool {
        authProvider.isAuthenticated
    }
    private static let largeSyncThreshold = 100
    /// Threshold for showing the InitialSync loading screen during background syncs.
    /// When a pull exceeds this many records while dashboard is visible, a notification
    /// is posted so AppFlowController can present the loading screen.
    static let loadingScreenThreshold = 30
    /// Cumulative record count across all pull phases in the current sync cycle.
    private var cyclePullRecordCount = 0
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

    /// The allocation tag book, synced as one record on its own path rather than as a table.
    ///
    /// Owned here because the engine lives for the app's lifetime, and held `weak` by
    /// `AllocationTagService` so an edit can push without the service depending on CloudKit. Its pull and
    /// push are invoked beside the batch engine, never inside it: `pushBatches` aborts every remaining
    /// batch on a schema error, and the tag book must not be able to take transactions down with it.
    private(set) lazy var allocationTagSync: AllocationTagBookSync = {
        let sync = AllocationTagBookSync(
            store: UserDefaultsAllocationTagStore(), operations: cloudKitOps)
        AllocationTagService.shared.cloudSync = sync
        return sync
    }()

    private init() {
        self.injectedDB = nil
        self.cloudKitOps = RealCloudKitOperations()
        self.stateManager = SyncStateManager.shared
        self.postSyncActions = RealPostSyncActions()
        setupObservers()
    }

    init(cloudKitOps: CloudKitOperationsProvider, stateManager: SyncStateManager = .shared,
         postSyncActions: PostSyncActions = RealPostSyncActions(),
         authProvider: AuthProviding = FirebaseAuthProvider(),
         db: DBHelper? = nil) {
        self.injectedDB = db
        self.cloudKitOps = cloudKitOps
        self.stateManager = stateManager
        self.postSyncActions = postSyncActions
        self.authProvider = authProvider
    }

    /// Pulls the tag book then pushes it, alongside the table cycle rather than inside it.
    ///
    /// Fired at a shallow point on purpose. The book shares no ids, no zone tokens and no
    /// `clearSyncedLocalData()` interaction with the tables, so its ordering against them does not
    /// matter - and hooking it here keeps it out of the nested pull/push chain, where a thrown error or
    /// an un-called completion would strand the whole cycle.
    ///
    /// Results are dropped deliberately: the syncer logs its own failures, and nothing in the table
    /// cycle depends on whether tags travelled.
    private func syncAllocationTagBook() {
        allocationTagSync.pull { [weak self] _ in
            self?.allocationTagSync.push()
        }
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalDataChange),
            name: .localSyncableDataDidChange,
            object: nil
        )
    }

    // MARK: - Public API

    /// Directly fetches records from a specific shared group zone, bypassing
    /// the database-level change detection that relies on CKShare propagation.
    /// This mirrors the same-account sync approach: go straight for the known zone.
    func fetchSharedGroupZone(
        groupId: String,
        zoneOwner: String,
        completion: @escaping (Int) -> Void
    ) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: zoneOwner)
        logWarning("[Sync] Direct fetch for shared group zone: \(zoneID.zoneName) (owner: \(zoneOwner))")

        var recordCount = 0

        cloudKitOps.fetchZoneChanges(
            zoneIDs: [zoneID],
            database: .shared,
            tokenForZone: { _ in nil }, // nil = full fetch from beginning
            recordHandler: { [weak self] record in
                recordCount += 1
                self?.processIncomingRecord(record)
            },
            deleteHandler: { [weak self] recordID, recordType in
                self?.processDeletedRecord(recordID: recordID, recordType: recordType)
            },
            zoneTokenHandler: { [weak self] zoneID, token in
                self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: "shared")
            },
            completion: { result in
                switch result {
                case .success:
                    logWarning("[Sync] Direct shared zone fetch complete — \(recordCount) record(s)")
                    TransactionRepository.invalidateCache()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
                        NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
                        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
                        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
                        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
                    }
                    completion(recordCount)
                case .failure(let error):
                    logError("[Sync] Direct shared zone fetch failed: \(error.localizedDescription)")
                    completion(0)
                }
            }
        )
    }

    /// Directly fetches the OWNER's own group zone from the PRIVATE database (nil token = full
    /// fetch). The private-DB counterpart of `fetchSharedGroupZone`: called when the user opens
    /// their own group's context so a second device of the same account reliably pulls the group's
    /// transactions/budgets even if the incremental force-include never fired (the local group row
    /// didn't exist yet at fetch time) — fixing an owner group that shows empty on a second device.
    func fetchOwnedGroupZone(groupId: String, completion: @escaping (Int) -> Void) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        logWarning("[Sync] Direct fetch for owned group zone: \(zoneID.zoneName)")

        var recordCount = 0

        cloudKitOps.fetchZoneChanges(
            zoneIDs: [zoneID],
            database: .private,
            tokenForZone: { _ in nil }, // nil = full fetch from beginning
            recordHandler: { [weak self] record in
                recordCount += 1
                self?.processIncomingRecord(record)
            },
            deleteHandler: { [weak self] recordID, recordType in
                self?.processDeletedRecord(recordID: recordID, recordType: recordType)
            },
            zoneTokenHandler: { [weak self] zoneID, token in
                self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: "private")
            },
            completion: { result in
                switch result {
                case .success:
                    logWarning("[Sync] Direct owned group zone fetch complete — \(recordCount) record(s)")
                    TransactionRepository.invalidateCache()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
                        NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
                        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
                        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
                        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
                    }
                    completion(recordCount)
                case .failure(let error):
                    logError("[Sync] Direct owned group zone fetch failed: \(error.localizedDescription)")
                    completion(0)
                }
            }
        )
    }

    /// Recovery sync: directly fetches ALL records from every private-DB zone using nil zone tokens.
    /// Fetches FinovaPrivateZone PLUS all owned group zones (which hold mirror-mode records).
    /// This bypasses the DB-level CKFetchDatabaseChangesOperation which can return an empty
    /// changedZoneIDs even with a nil token, causing the zone fetch to be silently skipped.
    /// After fetching, fires all data change notifications and saves updated zone tokens.
    func performPrivateZoneRecovery(completion: (() -> Void)? = nil) {
        guard isUserAuthenticated else {
            logWarning("[Sync] performPrivateZoneRecovery — skipped (user not authenticated)")
            completion?()
            return
        }
        syncQueue.async { [weak self] in
            guard let self = self else { completion?(); return }
            // Reset stuck sync state so recovery can proceed
            if self.isSyncing {
                logWarning("[Sync] performPrivateZoneRecovery: resetting stuck isSyncing=true")
                self.isSyncing = false
                self.isProcessingCloudData = false
                self.syncStartedAt = nil
            }
            // Re-reset tokens here (in case they were re-saved by a background sync
            // between the caller's resetAllTokens() and this dispatch block executing).
            self.stateManager.resetAllTokens()
            // Mark as syncing so handleLocalDataChange fires set needsPostSyncPush
            // instead of scheduling 4 concurrent pushLocalChanges calls.
            self.isSyncing = true
            self.isRecoverySync = true
            self.status = .syncing

            // Build the list of zones to fetch:
            // Private DB:
            //   1. FinovaPrivateZone — personal records not in any group
            //   2. Owned group zones — records pushed to Group-<id> by the group owner
            // Shared DB:
            //   3. Member group zones — records shared by other iCloud accounts
            var privateZoneIDs: [CKRecordZone.ID] = [CloudKitManager.privateZoneID]
            var sharedZoneIDs: [CKRecordZone.ID] = []
            let allGroups = BudgetGroupRepository(db: db).fetchAllGroups()
            for group in allGroups where !group.isDeleted {
                if group.isOwner {
                    let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
                    privateZoneIDs.append(zoneID)
                } else if let zoneOwner = group.ckZoneOwner {
                    let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: zoneOwner)
                    sharedZoneIDs.append(zoneID)
                }
            }
            logWarning("[Sync] Recovery: fetching \(privateZoneIDs.count) private-DB zone(s), \(sharedZoneIDs.count) shared-DB zone(s)")

            // Buffer all incoming records so we can sort them before processing.
            // CreditCards must be processed first so remapCrossDeviceIDs can resolve
            // creditCardId/statementId fields in Statements and Transactions correctly.
            var bufferedRecords: [CKRecord] = []
            var bufferedDeletes: [(CKRecord.ID, String)] = []
            // Same rule as fetchZoneChanges: hold zone tokens until the buffered records they cover
            // are actually applied. Recovery starts from nil tokens, so committing eagerly and then
            // failing would leave saved tokens pointing past records that were never written —
            // the next normal sync would skip them forever.
            var pendingZoneTokens: [(zoneID: CKRecordZone.ID, token: CKServerChangeToken?, dbKey: String)] = []

            // Step 1: Fetch private DB zones
            self.cloudKitOps.fetchZoneChanges(
                zoneIDs: privateZoneIDs,
                database: .private,
                tokenForZone: { _ in nil },     // nil = full fetch for every zone
                recordHandler: { record in
                    bufferedRecords.append(record)
                },
                deleteHandler: { recordID, recordType in
                    bufferedDeletes.append((recordID, recordType))
                },
                zoneTokenHandler: { zoneID, token in
                    pendingZoneTokens.append((zoneID, token, "private"))
                },
                completion: { [weak self] result in
                    guard let self = self else { completion?(); return }

                    guard case .success = result else {
                        if case .failure(let error) = result {
                            logError("[Sync] Recovery private fetch failed: \(error.localizedDescription)")
                            logWarning("[Sync] Recovery: discarding \(pendingZoneTokens.count) uncommitted zone token(s) — records were never applied")
                            self.finishSync(status: .error(error), completion: completion)
                        }
                        return
                    }

                    let privateCount = bufferedRecords.count
                    logWarning("[Sync] Recovery: private fetch got \(privateCount) record(s), \(bufferedDeletes.count) delete(s)")

                    // Step 2: Fetch shared DB zones (member groups)
                    let totalZoneCount = privateZoneIDs.count + sharedZoneIDs.count
                    let fetchSharedAndProcess = { [weak self] in
                        guard let self = self else { completion?(); return }
                        self.processRecoveryBuffer(
                            records: bufferedRecords, deletes: bufferedDeletes,
                            zoneCount: totalZoneCount,
                            zoneTokens: pendingZoneTokens,
                            completion: completion
                        )
                    }

                    guard !sharedZoneIDs.isEmpty else {
                        fetchSharedAndProcess()
                        return
                    }

                    self.cloudKitOps.fetchZoneChanges(
                        zoneIDs: sharedZoneIDs,
                        database: .shared,
                        tokenForZone: { _ in nil },
                        recordHandler: { record in
                            bufferedRecords.append(record)
                        },
                        deleteHandler: { recordID, recordType in
                            bufferedDeletes.append((recordID, recordType))
                        },
                        zoneTokenHandler: { zoneID, token in
                            pendingZoneTokens.append((zoneID, token, "shared"))
                        },
                        completion: { [weak self] result in
                            guard self != nil else { completion?(); return }
                            let sharedCount = bufferedRecords.count - privateCount
                            logWarning("[Sync] Recovery: shared fetch got \(sharedCount) record(s)")
                            // Process even if shared fetch fails — private data is more important.
                            // Drop the shared tokens in that case so the partially-fetched shared
                            // zones are retried from scratch rather than skipped.
                            if case .failure(let error) = result {
                                logWarning("[Sync] Recovery: shared fetch failed (non-fatal): \(error.localizedDescription) — dropping shared zone tokens for retry")
                                pendingZoneTokens.removeAll { $0.dbKey == "shared" }
                            }
                            fetchSharedAndProcess()
                        }
                    )
                }
            )
        }
    }

    /// Processes buffered records from a recovery fetch: clears local data, sorts by dependency,
    /// processes records and deletes, then finishes sync.
    private func processRecoveryBuffer(
        records bufferedRecords: [CKRecord],
        deletes bufferedDeletes: [(CKRecord.ID, String)],
        zoneCount: Int,
        zoneTokens: [(zoneID: CKRecordZone.ID, token: CKServerChangeToken?, dbKey: String)] = [],
        completion: (() -> Void)?
    ) {
        // Recovery is a clean-slate cloud-wins pull: delete every previously-synced
        // local row before processing incoming records.
        clearSyncedLocalData()

        func recoveryPriority(_ r: CKRecord) -> Int {
            switch r.recordType {
            case "CreditCard": return 0
            case "CreditCardStatement": return 1
            case "Budget": return 2
            case "BudgetAllocation": return 3
            case "Transaction":
                return (r["parentCKRecordName"] as? String) == nil ? 4 : 5
            default: return 4
            }
        }

        let liveRecordNames = Set(bufferedRecords.map { $0.recordID.recordName })
        let sortedRecords = bufferedRecords.sorted { recoveryPriority($0) < recoveryPriority($1) }

        // Process records in phases so we can build ID remapping tables between phases.
        // After clearSyncedLocalData, credit cards get NEW local auto-increment IDs
        // (AUTOINCREMENT never reuses). Old creditCardId/statementId in CK records point
        // to nothing. We patch every CK record with the correct new local IDs BEFORE
        // processIncomingRecord runs (which avoids depending on remapCrossDeviceIDs, since
        // old CK records lack the creditCardCKRecordName/statementCKRecordName fields).
        let cardRepo = CreditCardRepository(db: db)
        let stmtRepo = StatementRepository(db: db)

        // Phase 0: CreditCards
        let cardRecords = sortedRecords.filter { $0.recordType == "CreditCard" }
        for record in cardRecords {
            processIncomingRecord(record)
        }

        // Build two card maps:
        // 1. oldLocalId → newLocalId (from the CK record's localId field)
        // 2. ckRecordName → newLocalId (for records that have creditCardCKRecordName)
        var cardIdMap: [Int: Int] = [:]
        var cardCKNameMap: [String: Int] = [:]
        for record in cardRecords {
            guard let newCard = cardRepo.fetchCard(byCKRecordName: record.recordID.recordName),
                  let newId = newCard.id else { continue }
            cardCKNameMap[record.recordID.recordName] = newId
            let oldId = record["localId"] as? Int ?? 0
            if oldId > 0, newId != oldId {
                cardIdMap[oldId] = newId
            }
        }
        if !cardIdMap.isEmpty || !cardCKNameMap.isEmpty {
            logWarning("[Sync] Recovery: card maps — \(cardIdMap.count) localId remap(s), \(cardCKNameMap.count) CK name(s)")
        }
        // Persist card ID map so PostSyncActions repair can use it on subsequent syncs
        if !cardIdMap.isEmpty {
            let stringMap = cardIdMap.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value }
            UserDefaults.standard.set(stringMap, forKey: "recoveryCardIdMap")
            logWarning("[CCRepair] Persisted cardIdMap to UserDefaults: \(cardIdMap)")
        }

        // Helper: resolve the correct new local card ID for a statement/transaction CK record.
        // Tries CK record name first (most reliable), falls back to localId map.
        func resolveCardId(for record: CKRecord) -> Int? {
            if let cardCKName = record["creditCardCKRecordName"] as? String,
               let newId = cardCKNameMap[cardCKName] {
                return newId
            }
            if let oldCardId = record["creditCardId"] as? Int,
               let newId = cardIdMap[oldCardId] {
                return newId
            }
            return nil
        }

        // Phase 1: CreditCardStatements — patch creditCardId before processing
        let stmtRecords = sortedRecords.filter { $0.recordType == "CreditCardStatement" }
        for record in stmtRecords {
            if let newCardId = resolveCardId(for: record) {
                let oldCardId = record["creditCardId"] as? Int ?? -1
                record["creditCardId"] = newCardId as CKRecordValue
                if newCardId != oldCardId {
                    logWarning("[Sync] Recovery: patched statement creditCardId \(oldCardId) → \(newCardId)")
                }
            }
            processIncomingRecord(record)
        }

        // Build statement maps (same dual approach)
        var stmtIdMap: [Int: Int] = [:]
        var stmtCKNameMap: [String: Int] = [:]
        for record in stmtRecords {
            guard let newStmt = stmtRepo.fetchStatement(byCKRecordName: record.recordID.recordName),
                  let newId = newStmt.id else { continue }
            stmtCKNameMap[record.recordID.recordName] = newId
            let oldId = record["localId"] as? Int ?? 0
            if oldId > 0, newId != oldId {
                stmtIdMap[oldId] = newId
            }
        }
        if !stmtIdMap.isEmpty || !stmtCKNameMap.isEmpty {
            logWarning("[Sync] Recovery: statement maps — \(stmtIdMap.count) localId remap(s), \(stmtCKNameMap.count) CK name(s)")
        }

        // Helper: resolve the correct new local statement ID for a transaction CK record.
        func resolveStmtId(for record: CKRecord) -> Int? {
            if let stmtCKName = record["statementCKRecordName"] as? String,
               let newId = stmtCKNameMap[stmtCKName] {
                return newId
            }
            if let oldStmtId = record["statementId"] as? Int,
               let newId = stmtIdMap[oldStmtId] {
                return newId
            }
            return nil
        }

        // Phase 2-5: Remaining records — patch creditCardId and statementId on Transactions
        let remainingRecords = sortedRecords.filter {
            $0.recordType != "CreditCard" && $0.recordType != "CreditCardStatement"
        }
        for record in remainingRecords {
            if record.recordType == "Transaction" {
                if let newCardId = resolveCardId(for: record) {
                    record["creditCardId"] = newCardId as CKRecordValue
                }
                if let newStmtId = resolveStmtId(for: record) {
                    record["statementId"] = newStmtId as CKRecordValue
                }
            }
            processIncomingRecord(record)
        }
        let skippedTombstones = bufferedDeletes.filter { liveRecordNames.contains($0.0.recordName) }
        if !skippedTombstones.isEmpty {
            logWarning("[Sync] Recovery: skipped \(skippedTombstones.count) tombstone(s) superseded by live records — \(skippedTombstones.map { $0.0.recordName })")
        }
        for (recordID, recordType) in bufferedDeletes where !liveRecordNames.contains(recordID.recordName) {
            processDeletedRecord(recordID: recordID, recordType: recordType)
        }

        // Post-recovery verification: check for orphaned statements (creditCardId
        // doesn't reference any existing card) and repair them using the CK name maps.
        repairOrphanedStatementReferences(cardCKNameMap: cardCKNameMap, cardIdMap: cardIdMap,
                                          stmtCKNameMap: stmtCKNameMap, stmtIdMap: stmtIdMap)

        TransactionRepository.invalidateCache()
        let recoveredCount = sortedRecords.count
        logWarning("[Sync] Recovery complete — \(recoveredCount) record(s) from \(zoneCount) zone(s)")
        // Commit zone tokens only now that every buffered record has been written locally.
        for entry in zoneTokens {
            stateManager.saveChangeToken(entry.token, for: entry.zoneID.zoneName, database: entry.dbKey)
        }
        stateManager.updateLastSyncDate(for: "privateDB")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
            NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
        }
        finishSync(status: .synced, completion: completion)
    }

    /// Post-recovery repair: scans all CreditCardStatements and Transactions in the local DB
    /// to fix any creditCardId / statementId that don't reference valid rows.
    /// Uses the CK-name and localId maps built during recovery to find the correct IDs.
    /// Also runs a SQL-level repair for any remaining orphans (e.g., if the CK fields were
    /// missing from the original record and the localId map had no entry).
    private func repairOrphanedStatementReferences(
        cardCKNameMap: [String: Int],
        cardIdMap: [Int: Int],
        stmtCKNameMap: [String: Int],
        stmtIdMap: [Int: Int]
    ) {
        let db = db

        // 1. Repair statements: find any with credit_card_id that doesn't reference a valid card
        let orphanedStmts = db.fetchIntIntPairs(
            """
            SELECT s.id, s.credit_card_id FROM CreditCardStatements s
            LEFT JOIN CreditCards c ON s.credit_card_id = c.id
            WHERE c.id IS NULL AND s.credit_card_id > 0;
            """
        )
        if !orphanedStmts.isEmpty {
            logWarning("[Sync] Recovery repair: found \(orphanedStmts.count) statement(s) with orphaned creditCardId")
            for (stmtId, oldCardId) in orphanedStmts {
                if let newCardId = cardIdMap[oldCardId] {
                    db.executeSyncUpdate(
                        "UPDATE CreditCardStatements SET credit_card_id = ? WHERE id = ?;",
                        intBindings: [newCardId, stmtId]
                    )
                    logWarning("[Sync] Recovery repair: fixed statement \(stmtId) creditCardId \(oldCardId) → \(newCardId)")
                }
            }
        }

        // 2. Repair transactions: fix orphaned creditCardId
        let orphanedTxCards = db.fetchIntIntPairs(
            """
            SELECT t.id, t.credit_card_id FROM Transactions t
            LEFT JOIN CreditCards c ON t.credit_card_id = c.id
            WHERE c.id IS NULL AND t.credit_card_id IS NOT NULL AND t.credit_card_id > 0
              AND (t.is_deleted IS NULL OR t.is_deleted = 0);
            """
        )
        if !orphanedTxCards.isEmpty {
            logWarning("[Sync] Recovery repair: found \(orphanedTxCards.count) transaction(s) with orphaned creditCardId")
            for (txId, oldCardId) in orphanedTxCards {
                if let newCardId = cardIdMap[oldCardId] {
                    db.executeSyncUpdate(
                        "UPDATE Transactions SET credit_card_id = ? WHERE id = ?;",
                        intBindings: [newCardId, txId]
                    )
                }
            }
        }

        // 3. Repair transactions: fix orphaned statementId
        let orphanedTxStmts = db.fetchIntIntPairs(
            """
            SELECT t.id, t.statement_id FROM Transactions t
            LEFT JOIN CreditCardStatements s ON t.statement_id = s.id
            WHERE s.id IS NULL AND t.statement_id IS NOT NULL AND t.statement_id > 0
              AND (t.is_deleted IS NULL OR t.is_deleted = 0);
            """
        )
        if !orphanedTxStmts.isEmpty {
            logWarning("[Sync] Recovery repair: found \(orphanedTxStmts.count) transaction(s) with orphaned statementId")
            for (txId, oldStmtId) in orphanedTxStmts {
                if let newStmtId = stmtIdMap[oldStmtId] {
                    db.executeSyncUpdate(
                        "UPDATE Transactions SET statement_id = ? WHERE id = ?;",
                        intBindings: [newStmtId, txId]
                    )
                }
            }
        }
    }

    /// Fetches shared group data with escalating retries.
    /// Called after CKShare acceptance to handle CloudKit propagation delays.
    /// Uses a threshold > 1 because the zone-wide CKShare record itself counts as 1 record.
    func syncSharedGroupData(groupId: String, zoneOwner: String, completion: (() -> Void)? = nil) {
        let delays: [Double] = [2.0, 5.0, 10.0, 20.0, 40.0, 60.0]

        func attemptFetch(index: Int) {
            guard index < delays.count else {
                logWarning("[Sync] Shared group data: exhausted all \(delays.count) retries for group \(groupId)")
                completion?()
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delays[index]) { [weak self] in
                self?.fetchSharedGroupZone(groupId: groupId, zoneOwner: zoneOwner) { count in
                    // count > 1 because the CKShare record itself counts as 1
                    if count > 1 {
                        logWarning("[Sync] Shared group data fetched (\(count) records) on attempt \(index + 1)")
                        completion?()
                    } else {
                        logWarning("[Sync] Shared group data: \(count) record(s) on attempt \(index + 1) (only share metadata?) — retrying")
                        attemptFetch(index: index + 1)
                    }
                }
            }
        }

        attemptFetch(index: 0)
    }

    func performFullSync(forceFullFetch: Bool = false, forceRePush: Bool = false, forceAcceptCloud: Bool = false, completion: (() -> Void)? = nil) {
        if isSyncDisabledByUser {
            logWarning("[Sync] performFullSync — skipped (sync disabled by user)")
            status = .idle
            completion?()
            return
        }
        guard isUserAuthenticated else {
            logWarning("[Sync] performFullSync — skipped (user not authenticated)")
            // Deliberately does NOT publish a status. Assigning `.idle` here overwrote the terminal
            // status of a sync that had already finished (the engine is a singleton, so the flag
            // outlives any one cycle) and made every error-path test observe `idle` instead of the
            // `.error` it had just reported.
            //
            // "No user yet" is a transient pre-auth state, not an outcome. UI that gates on sync
            // status handles the silence via InitialSyncViewController's watchdog; the genuinely
            // terminal cases — account unavailable, sync disabled by the user — still publish
            // `.idle` at their own call sites.
            completion?()
            return
        }
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
                UserDefaults.standard.removeObject(forKey: Self.fullPullVerifiedKey)
            }
            if forceAcceptCloud {
                self.resetLocalModificationTimestamps()
                self.stateManager.resetAllTokens()
                self.isFullRefetch = true
                self.pulledCKRecordNames = []
                UserDefaults.standard.removeObject(forKey: Self.fullPullVerifiedKey)
            }
            if forceRePush {
                self.resetAllSyncStatuses()
            }
            self.executeSyncCycle(completion: completion)
        }
    }

    /// Immediately pushes all pending local changes to CloudKit without pulling.
    /// Designed for background/termination scenarios where the 2-second debounce
    /// must be skipped. If a sync is already in progress, waits for it to finish
    /// and then pushes any remaining pending records.
    func flushPendingChanges(completion: @escaping (Bool) -> Void) {
        if isSyncDisabledByUser {
            logWarning("[Sync] flushPendingChanges — skipped (sync disabled by user)")
            completion(true)
            return
        }
        guard isUserAuthenticated else {
            logWarning("[Sync] flushPendingChanges — skipped (user not authenticated)")
            completion(false)
            return
        }
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

    /// Force re-push: marks ALL local records as pending and pushes them to CloudKit.
    /// Does NOT pull from cloud — this is a push-only recovery operation.
    /// Bypasses the sync toggle (works even when sync is disabled).
    /// Use this to restore CloudKit from local data after data loss.
    func forceRePushAllLocal(completion: (() -> Void)? = nil) {
        guard isUserAuthenticated else {
            logWarning("[Sync] forceRePushAllLocal — skipped (user not authenticated)")
            completion?()
            return
        }
        logWarning("[Sync] forceRePushAllLocal — starting push-only recovery")
        self.resetAllSyncStatuses()
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            if self.isSyncing {
                logWarning("[Sync] forceRePushAllLocal — waiting for current sync to finish")
                self.isSyncing = false
                self.isProcessingCloudData = false
                self.syncStartedAt = nil
            }
            self.isSyncing = true
            self.status = .syncing
            self.pushLocalChanges { [weak self] result in
                switch result {
                case .success:
                    logWarning("[Sync] forceRePushAllLocal — push SUCCEEDED")
                    self?.status = .synced
                case .failure(let error):
                    logWarning("[Sync] forceRePushAllLocal — push FAILED: \(error.localizedDescription)")
                    self?.status = .error(error)
                }
                self?.isSyncing = false
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    /// Resets all sync_status values to 'pending' so everything gets re-pushed to CloudKit.
    /// Also updates ck_modified_at to ensure re-pushed records win conflict resolution on other devices.
    private func resetAllSyncStatuses() {
        logWarning("[Sync] Resetting all sync statuses to 'pending' for re-push")
        let now = Int(Date().timeIntervalSince1970)
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            db.executeSyncUpdate(
                "UPDATE \(table) SET sync_status = 'pending', ck_modified_at = \(now) WHERE sync_status = 'synced' AND (is_deleted IS NULL OR is_deleted = 0);",
                textBindings: []
            )
        }
        TransactionRepository.invalidateCache()
    }

    /// Resets all local ck_modified_at and updated_at timestamps to 0 so incoming cloud data always wins
    /// conflict resolution. Used when the user explicitly chooses to accept cloud data.
    private func resetLocalModificationTimestamps() {
        logWarning("[Sync] Resetting all local ck_modified_at and updated_at to 0 — cloud data will take priority")
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            db.executeSyncUpdate(
                "UPDATE \(table) SET ck_modified_at = 0, updated_at = 0;",
                textBindings: []
            )
        }
    }

    @objc private func handleRemoteNotification() {
        if isSyncDisabledByUser {
            logWarning("[Sync] handleRemoteNotification — skipped (sync disabled by user)")
            return
        }
        guard isUserAuthenticated else {
            logWarning("[Sync] handleRemoteNotification — skipped (user not authenticated)")
            return
        }
        // Cooldown: skip sync if we just finished one (our own push triggers CK notifications)
        if let lastCompleted = lastSyncCompletedAt,
           Date().timeIntervalSince(lastCompleted) < Self.syncCooldownInterval {
            logWarning("[SyncLife] handleRemoteNotification — skipped (cooldown, \(Int(Date().timeIntervalSince(lastCompleted)))s since last sync)")
            return
        }
        logWarning("[SyncLife] handleRemoteNotification — isSyncing=\(isSyncing)")
        // Also fetch invitations immediately (public DB notifications don't trigger private DB changes)
        BudgetGroupService.shared.fetchRemoteInvitations {}
        performFullSync()
    }

    /// Triggers an immediate push of pending local changes to CloudKit.
    /// Uses a background task to ensure the push completes even if the app is backgrounded.
    /// Call this after group transaction create/edit to ensure timely notification delivery.
    func pushPendingChangesNow() {
        if isSyncDisabledByUser {
            logWarning("[SyncEngine] pushPendingChangesNow — skipped (sync disabled by user)")
            return
        }
        guard isUserAuthenticated else {
            logWarning("[SyncEngine] pushPendingChangesNow — skipped (user not authenticated)")
            return
        }
        logWarning("[SyncEngine] pushPendingChangesNow — called")
        // The tag book has no pending rows for the batch engine to find, so it needs its own nudge here.
        allocationTagSync.push()
        // UIApplication is main-thread-only, and this is now called from background write paths
        // (allocation create/edit, recurring generation). Hop to main to claim the background task.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.pushPendingChangesNow() }
            return
        }
        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask {
            logWarning("[SyncEngine] pushPendingChangesNow — background task expired")
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
        syncQueue.async { [weak self] in
            guard let self = self else {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                return
            }
            if self.isSyncing {
                logWarning("[SyncEngine] pushPendingChangesNow — SKIPPED (isSyncing=true), setting needsPostSyncPush")
                self.needsPostSyncPush = true
                UIApplication.shared.endBackgroundTask(bgTaskID)
                return
            }
            logWarning("[SyncEngine] pushPendingChangesNow — executing pushLocalChanges")
            self.pushLocalChanges { [weak self] result in
                switch result {
                case .success:
                    logWarning("[SyncEngine] pushPendingChangesNow — push SUCCEEDED")
                    self?.status = .synced
                case .failure(let error):
                    logWarning("[SyncEngine] pushPendingChangesNow — push FAILED: \(error.localizedDescription)")
                    self?.status = .error(error)
                }
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }
    }

    @objc private func handleLocalDataChange() {
        // Block standalone pushes until initial pull is verified on new devices
        guard UserDefaults.standard.bool(forKey: Self.fullPullVerifiedKey) else {
            logWarning("[SyncLife] handleLocalDataChange — skipped (initial pull not verified)")
            return
        }
        if isSyncDisabledByUser {
            logWarning("[SyncLife] handleLocalDataChange — skipped (sync disabled by user)")
            return
        }
        guard isUserAuthenticated else {
            logWarning("[SyncLife] handleLocalDataChange — skipped (user not authenticated)")
            return
        }
        guard !isProcessingCloudData && !isSyncing else {
            // A sync is in progress — flag that we need a follow-up push
            // (e.g., lazy-generated recurring instances created during sync)
            logWarning("[SyncLife] handleLocalDataChange — deferred (isProcessingCloudData=\(isProcessingCloudData), isSyncing=\(isSyncing))")
            needsPostSyncPush = true
            return
        }
        // Skip standalone push if a sync just completed — the drain mechanism
        // handles any remaining pending records. Without this, data change
        // notifications posted at end of sync trigger concurrent pushes.
        if let lastCompleted = lastSyncCompletedAt,
           Date().timeIntervalSince(lastCompleted) < 5.0 {
            logWarning("[SyncLife] handleLocalDataChange — skipped (sync just completed \(Int(Date().timeIntervalSince(lastCompleted)))s ago)")
            return
        }
        logWarning("[SyncLife] handleLocalDataChange — scheduling push in 2s")
        syncQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            guard !self.isSyncing else {
                // A sync started during the debounce window — defer to post-sync drain
                // so the local change is not silently dropped.
                self.needsPostSyncPush = true
                logWarning("[SyncLife] handleLocalDataChange debounced push — deferred (isSyncing=true)")
                return
            }
            self.pushLocalChanges()
        }
    }

    /// Deletes every previously-synced row (ck_record_id IS NOT NULL) from all sync tables
    /// before a clean-slate recovery pull. Local-only rows (ck_record_id IS NULL) are preserved
    /// so pending new records are re-pushed on the next sync cycle.
    private func clearSyncedLocalData() {
        let db = db
        // Delete dependents before their parents to respect any FK ordering.
        db.executeSyncUpdate("DELETE FROM CreditCardStatements WHERE ck_record_id IS NOT NULL;")
        db.executeSyncUpdate("DELETE FROM Transactions WHERE ck_record_id IS NOT NULL;")
        // Also clear tombstones (is_deleted=1, ck_record_id=NULL) left by hardDeleteLocal
        // for recurring instances. Without this, restoreTombstoneForInstance blocks legitimate
        // re-insertion of live records from CloudKit during recovery.
        db.executeSyncUpdate("DELETE FROM Transactions WHERE is_deleted = 1;")
        // Clear unsynced lazily-generated recurring/installment instances. These have no CK
        // link and survive the ck_record_id cleanup above. If their parent was deleted from
        // CloudKit (by another device), these orphans persist as ghost duplicates. The pull
        // will re-generate any instances whose parent still exists in CloudKit.
        db.executeSyncUpdate("DELETE FROM Transactions WHERE ck_record_id IS NULL AND parent_transaction_id IS NOT NULL;")
        db.executeSyncUpdate("DELETE FROM BudgetAllocations WHERE ck_record_id IS NOT NULL;")
        db.executeSyncUpdate("DELETE FROM Budgets WHERE ck_record_id IS NOT NULL;")
        db.executeSyncUpdate("DELETE FROM CreditCards WHERE ck_record_id IS NOT NULL;")
        TransactionRepository.invalidateCache()
        logInfo("[Sync] Recovery: cleared all previously-synced local records + tombstones — clean-slate cloud pull")
    }

    /// Centralised cleanup: resets sync flags, sets status, drains post-sync push, and calls completion.
    /// Every exit path from startSyncOperations must funnel through this to avoid stuck flags.
    private func finishSync(status newStatus: SyncStatus, completion: (() -> Void)?) {
        logWarning("[SyncLife] finishSync — status=\(newStatus), needsPostSyncPush=\(needsPostSyncPush), isRecoverySync=\(isRecoverySync)")
        postPhaseProgress(progress: 1.0, phaseKey: "sync.phase.complete")
        self.isProcessingCloudData = false
        self.status = newStatus
        self.isSyncing = false
        self.syncStartedAt = nil
        self.lastSyncCompletedAt = Date()
        // Skip post-sync push during recovery — recovery is a clean-slate pull.
        // Pending local records will be pushed on the next normal sync cycle.
        // Without this guard, recovery chains into 1-3 push cycles (with 2s delays
        // each) that make it appear to "never finish".
        if isRecoverySync {
            isRecoverySync = false
            needsPostSyncPush = false
            logWarning("[SyncLife] Recovery complete — skipping post-sync push drain")
        } else {
            self.drainPostSyncPush()
        }
        logWarning("[SyncLife] finishSync done — isSyncing=\(isSyncing)")
        completion?()
    }

    private static let fullPullVerifiedKey = "syncFullPullVerified_v2"

    /// Ensures this device has completed at least one full pull from CloudKit.
    /// If we have a stale DB change token from a partial sync, CloudKit will report
    /// "no changed zones" and skip the pull entirely, leaving the device with
    /// incomplete data. This resets tokens to force a complete pull.
    private func checkAndRepairIncompleteSync() {
        guard !UserDefaults.standard.bool(forKey: Self.fullPullVerifiedKey) else { return }

        let hasToken = stateManager.changeToken(for: "privateDB", database: "private") != nil
        guard hasToken else {
            // Fix 4a: No token = first sync. Flag full shared DB discovery so member
            // groups are discovered even if CKFetchDatabaseChanges returns 0 zones.
            needsFullSharedDBDiscovery = true
            return
        }

        logWarning("[SyncLife] Device has not completed a verified full pull — resetting tokens for complete pull")
        stateManager.resetAllTokens()
        isLargeSyncCycle = true
        // Fix 4a: Also force full shared DB zone enumeration
        needsFullSharedDBDiscovery = true
    }

    /// Called after a successful sync that pulled records, marking this device as having
    /// a complete dataset. Future syncs will use incremental tokens normally.
    private func markFullPullVerified() {
        if !UserDefaults.standard.bool(forKey: Self.fullPullVerifiedKey) {
            UserDefaults.standard.set(true, forKey: Self.fullPullVerifiedKey)
            logWarning("[SyncLife] Full pull verified — future syncs will be incremental")

            // Fix 4c: Post-sync data integrity check after first verified pull
            performPostSyncIntegrityCheck()

            // Deletes are gated by this flag (canPushDeletes). Any delete the user made BEFORE
            // this first verified pull was deferred and is still sitting in `pendingDelete`; flush
            // it now that pushing deletes is allowed — otherwise the cloud stays stale (and a
            // deleted series would re-hydrate to other devices). Deferred so the current cycle
            // finishes first; pushPendingChangesNow is a no-op when nothing is pending.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.pushPendingChangesNow()
                // Same gate applies to the balance offset: flush any offset edit deferred while
                // this device was hydrating (it was blocked so it couldn't clobber the other
                // device's value with a pre-hydration 0).
                UIDUserDefaultsManager.shared.repushPendingBalanceOffsetsAfterHydration()
            }
        }
    }

    /// Lightweight integrity check after the first verified full pull.
    /// Logs warnings for missing data that should have arrived.
    private func performPostSyncIntegrityCheck() {
        let repo = BudgetGroupRepository(db: db)
        let groups = repo.fetchAllGroups().filter { !$0.isDeleted }

        // Verify all member groups have ckZoneOwner set
        let memberGroupsMissingOwner = groups.filter { !$0.isOwner && $0.ckZoneOwner == nil }
        if !memberGroupsMissingOwner.isEmpty {
            logWarning("[IntegrityCheck] \(memberGroupsMissingOwner.count) member group(s) missing ckZoneOwner: \(memberGroupsMissingOwner.map { $0.id })")
            // Flag for full shared DB discovery on next sync to repair
            needsFullSharedDBDiscovery = true
        }

        // Log record counts for diagnostics
        let db = db
        let txCount = db.fetchSingleInt("SELECT COUNT(*) FROM Transactions WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? 0
        let budgetCount = db.fetchSingleInt("SELECT COUNT(*) FROM Budgets WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? 0
        let cardCount = db.fetchSingleInt("SELECT COUNT(*) FROM CreditCards WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? 0
        let allocCount = db.fetchSingleInt("SELECT COUNT(*) FROM BudgetAllocations WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? 0
        logWarning("[IntegrityCheck] Post-pull counts: transactions=\(txCount), budgets=\(budgetCount), cards=\(cardCount), allocations=\(allocCount), groups=\(groups.count)")
    }

    /// Posts a `syncPhaseProgressDidChange` notification with the current phase progress.
    /// Guards against background state to avoid unnecessary UI updates.
    private func postPhaseProgress(
        progress: Float,
        phaseKey: String,
        totalBatches: Int = 0,
        currentBatch: Int = 0,
        totalRecords: Int = 0
    ) {
        let phaseProgress = SyncPhaseProgress(
            progress: progress,
            phaseKey: phaseKey,
            totalBatches: totalBatches,
            currentBatch: currentBatch,
            totalRecords: totalRecords,
            isLargeSync: isLargeSyncCycle
        )
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .syncPhaseProgressDidChange, object: phaseProgress)
        }
    }

    private static let maxPostSyncPushCycles = 3
    private var postSyncPushCycleCount = 0

    /// If local data changed while a sync was in progress, push the pending records now.
    /// Limited to a maximum number of cycles to prevent infinite loops from conflict storms.
    private func drainPostSyncPush() {
        guard needsPostSyncPush else {
            logWarning("[SyncLife] drainPostSyncPush — no push needed")
            return
        }
        logWarning("[SyncLife] drainPostSyncPush — starting drain")
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
                // Re-signal synced status after drain push completes.
                // Push progress notifications may have cancelled the toast dismiss timer.
                if let self = self, case .synced = self.status {
                    logWarning("[SyncLife] Drain push complete — re-posting synced status for toast dismiss")
                    self.status = .synced
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
            logWarning("[SyncLife] startSyncOperations skipped — already syncing")
            completion?()
            return
        }

        logWarning("[SyncLife] === SYNC CYCLE START ===")

        // One-time integrity check: if this device has a balance offset (mature account)
        // but very few transactions, the DB change token is stale. Reset tokens to force
        // a full pull so we don't permanently miss records.
        checkAndRepairIncompleteSync()

        // One-time: reset shared zone tokens to re-fetch group records.
        // Previous code silently dropped group-zone records that matched existing local
        // records with different CK names. The fix in ConflictResolver now correctly
        // re-links them, but records already fetched won't be re-delivered without
        // clearing the zone change tokens.
        let groupTokenResetKey = "hasResetGroupZoneTokens_groupSyncFix_v1"
        if !UserDefaults.standard.bool(forKey: groupTokenResetKey) {
            stateManager.resetSharedDBTokens()
            logWarning("[Sync] One-time reset of shared DB tokens to re-fetch group records")
            UserDefaults.standard.set(true, forKey: groupTokenResetKey)
        }

        // One-time: re-fetch shared records so processIncomingBudgetGroup can set ckZoneOwner
        // for groups that were already synced before the fix was in place.
        // v2: also re-fetches BalanceOffset + ensures GroupMember push uses .allKeys path.
        let zoneOwnerRepairKey = "hasResetSharedTokens_zoneOwnerFix_v2"
        if !UserDefaults.standard.bool(forKey: zoneOwnerRepairKey) {
            stateManager.resetSharedDBTokens()
            logWarning("[Sync] One-time reset of shared DB tokens to repair ckZoneOwner and re-fetch group data")
            UserDefaults.standard.set(true, forKey: zoneOwnerRepairKey)
        }

        isSyncing = true
        syncStartedAt = Date()
        postSyncPushCycleCount = 0
        didReceiveBalanceOffsetDuringPull = false
        isLargeSyncCycle = false
        cyclePullRecordCount = 0
        status = .syncing
        postPhaseProgress(progress: 0.0, phaseKey: "sync.phase.preparing")
        cloudKitOps.ensureZoneExists { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }

            switch result {
            case .success:
                self.setupSubscriptionsIfNeeded()
                self.syncAllocationTagBook()
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
                            self.postPhaseProgress(progress: 0.50, phaseKey: "sync.phase.processing")
                            // One-time recovery: reset tokens if migration caused data loss
                            self.recoverFromGroupZoneMigration()
                            // One-time migration: move group-tagged records from private zone to group zones
                            self.migrateGroupRecordsToGroupZones()
                            self.postPhaseProgress(progress: 0.55, phaseKey: "sync.phase.preparingUpload")
                            self.pushLocalChanges { pushResult in
                            switch pushResult {
                            case .success:
                                self.stateManager.updateLastSyncDate(for: "privateDB")
                                // Discover groups from ALL zones (fallback for missed zone changes)
                                self.discoverGroupsFromAllZones {
                                    // Re-register group activity subscriptions for any newly discovered groups
                                    CloudKitManager.shared.setupGroupActivitySubscriptions()

                                    logWarning("[SyncLife] Starting postSyncActions.performPostSyncFetches")
                                    self.postSyncActions.performPostSyncFetches {
                                        logWarning("[SyncLife] postSyncActions completed — entering syncQueue for finishSync")
                                        self.syncQueue.async {
                                            // Diagnostic: group balance state
                                            if let uid = UIDUserDefaultsManager.shared.currentUserUID {
                                                let personalOffset = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
                                                let groups = BudgetGroupRepository(db: self.db).fetchAllGroups()
                                                for g in groups {
                                                    let groupOffset = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(g.id)")
                                                    let txRepo = TransactionRepository(db: self.db)
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

                                            self.markFullPullVerified()
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
        postPhaseProgress(progress: 0.10, phaseKey: "sync.phase.checking")
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

                    // Always include owned group zones — CKShare-based writes from
                    // members may not be reported by fetchDatabaseChanges on the
                    // owner's private DB. Zone-level tokens keep this cheap when
                    // no new records exist.
                    let ownedGroups = BudgetGroupService.shared.fetchAllGroups().filter { $0.isOwner && !$0.isDeleted }
                    let existingZoneNames = Set(changedZoneIDs.map { $0.zoneName })
                    for group in ownedGroups {
                        let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
                        if !existingZoneNames.contains(zoneID.zoneName) {
                            changedZoneIDs.append(zoneID)
                            logWarning("[Sync] Force-included owned group zone: \(zoneID.zoneName)")
                        } else {
                            logWarning("[Sync] Owned group zone already in changed list: \(zoneID.zoneName)")
                        }
                    }

                    if changedZoneIDs.isEmpty {
                        // When the token was nil (forceFullFetch/reset), an empty changedZoneIDs
                        // is unexpected — it likely means the DB-level fetch returned before the
                        // zone handler fired (e.g. async delivery edge case). Enumerate ALL private
                        // record zones directly so the recovery pull covers the default zone AND the
                        // owner's own `Group-<id>` zones — otherwise a fresh device (no local group
                        // rows yet, so the force-include above adds nothing) never fetches the group
                        // zone and the group shows empty until a later cycle. Mirrors the shared-DB
                        // fallback.
                        if token == nil {
                            logWarning("[Sync] No changed zones with nil token — enumerating all private zones (incl. owned group zones) for recovery")
                            var recoveryZoneIDs: [CKRecordZone.ID] = [CloudKitManager.privateZoneID]
                            self?.cloudKitOps.fetchAllZones(database: .private) { [weak self] zonesResult in
                                if case .success(let zoneIDs) = zonesResult {
                                    for zoneID in zoneIDs
                                    where zoneID.zoneName.hasPrefix("Group-")
                                        && !recoveryZoneIDs.contains(where: { $0.zoneName == zoneID.zoneName }) {
                                        recoveryZoneIDs.append(zoneID)
                                        logWarning("[Sync] Fallback discovered private group zone: \(zoneID.zoneName)")
                                    }
                                }
                                self?.fetchZoneChanges(zoneIDs: recoveryZoneIDs, database: .private, completion: completion)
                            }
                        } else {
                            logWarning("[Sync] No changed zones — skipping zone fetch")
                            completion(.success(()))
                        }
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
        postPhaseProgress(progress: 0.15, phaseKey: "sync.phase.checking")
        let token = stateManager.changeToken(for: "sharedDB", database: "shared")
        logWarning("[Sync] Fetching shared database changes (hasToken=\(token != nil))")
        var changedZoneIDs: [CKRecordZone.ID] = []

        cloudKitOps.fetchDatabaseChanges(
            database: .shared,
            token: token,
            changedZoneHandler: { changedZoneIDs.append($0) }
        ) { [weak self, db] result in
            switch result {
            case .success(let newToken):
                let zoneNames = changedZoneIDs.map { $0.zoneName }
                logWarning("[Sync] Shared DB changes fetched — \(changedZoneIDs.count) changed zone(s): \(zoneNames)")
                self?.stateManager.saveChangeToken(newToken, for: "sharedDB", database: "shared")

                // Always include member group zones — owner-side writes may
                // not be reported by fetchDatabaseChanges on the member's
                // shared DB. Zone-level tokens keep this cheap.
                let memberGroups = BudgetGroupRepository(db: db).fetchAllGroups().filter { !$0.isOwner && !$0.isDeleted }
                let existingSharedZoneNames = Set(changedZoneIDs.map { $0.zoneName })
                for group in memberGroups {
                    if let zoneOwner = group.ckZoneOwner {
                        let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: zoneOwner)
                        if !existingSharedZoneNames.contains(zoneID.zoneName) {
                            changedZoneIDs.append(zoneID)
                        }
                    }
                }

                // Fix 1a + 4a: When shared DB reports 0 changed zones, enumerate ALL
                // shared zones directly in these cases:
                // - Member groups exist locally but none have ckZoneOwner (Fix 1a)
                // - First sync / incomplete sync flagged for full discovery (Fix 4a)
                // This breaks the chicken-and-egg dependency on new devices.
                if changedZoneIDs.isEmpty {
                    let allGroups = BudgetGroupRepository(db: db).fetchAllGroups()
                    let hasAnyMemberZoneOwner = memberGroups.contains { $0.ckZoneOwner != nil }
                    let isFirstSharedSync = token == nil && allGroups.isEmpty
                    let shouldEnumerateAll = (self?.needsFullSharedDBDiscovery == true)
                        || (!hasAnyMemberZoneOwner && !memberGroups.isEmpty)
                        || isFirstSharedSync
                    if shouldEnumerateAll {
                        self?.needsFullSharedDBDiscovery = false
                        logWarning("[Sync] No changed shared zones — enumerating all shared zones as fallback")
                        self?.cloudKitOps.fetchAllZones(database: .shared) { [weak self] zonesResult in
                            if case .success(let zoneIDs) = zonesResult {
                                for zoneID in zoneIDs where zoneID.zoneName.hasPrefix("Group-") {
                                    changedZoneIDs.append(zoneID)
                                    BudgetGroupRepository(db: db).updateZoneOwner(
                                        groupId: String(zoneID.zoneName.dropFirst("Group-".count)),
                                        zoneOwner: zoneID.ownerName)
                                    logWarning("[Sync] Fallback discovered shared zone: \(zoneID.zoneName) (owner: \(zoneID.ownerName))")
                                }
                            }
                            if changedZoneIDs.isEmpty {
                                logWarning("[Sync] Fallback shared zone enumeration found 0 zones")
                                completion()
                            } else {
                                self?.fetchZoneChanges(zoneIDs: changedZoneIDs, database: .shared) { _ in
                                    completion()
                                }
                            }
                        }
                        return
                    }
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
    }

    private func fetchZoneChanges(
        zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.isProcessingCloudData = true
        var pulledRecordCount = 0
        var pulledDeleteCount = 0
        var bufferedRecords: [CKRecord] = []
        // Zone tokens are held here until the records they cover have actually been applied.
        // See the completion block for why they must not be persisted as they arrive.
        var pendingZoneTokens: [(zoneID: CKRecordZone.ID, token: CKServerChangeToken?)] = []

        let pullBaseProgress: Float = database == .private ? 0.25 : 0.40
        let pullPhaseKey = database == .private ? "sync.phase.downloading" : "sync.phase.downloadingShared"
        postPhaseProgress(progress: pullBaseProgress, phaseKey: pullPhaseKey)

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
                self?.cyclePullRecordCount += 1
                if self?.isFullRefetch == true {
                    self?.pulledCKRecordNames.insert(record.recordID.recordName)
                }
                bufferedRecords.append(record)

                // Detect large sync early — as soon as threshold is crossed during pull
                if pulledRecordCount == Self.largeSyncThreshold + 1,
                   self?.isLargeSyncCycle == false {
                    self?.isLargeSyncCycle = true
                    logWarning("[SyncLife] Large sync detected during pull (\(pulledRecordCount) records so far)")
                    self?.postPhaseProgress(progress: pullBaseProgress + 0.05, phaseKey: pullPhaseKey)
                }

                // Notify AppFlowController to show loading screen for large background syncs
                if let count = self?.cyclePullRecordCount,
                   count == Self.loadingScreenThreshold {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .syncRequiresLoadingScreen, object: nil)
                    }
                }

                // Incremental pull progress every 25 records (capped at next phase boundary)
                if pulledRecordCount % 25 == 0 {
                    let increment = Float(pulledRecordCount) * 0.001
                    let nextBoundary: Float = database == .private ? 0.30 : 0.42
                    let pullProgress = min(pullBaseProgress + increment, nextBoundary - 0.01)
                    self?.postPhaseProgress(progress: pullProgress, phaseKey: pullPhaseKey)
                }
            },
            deleteHandler: { [weak self] recordID, recordType in
                pulledDeleteCount += 1
                self?.processDeletedRecord(recordID: recordID, recordType: recordType)
            },
            zoneTokenHandler: { zoneID, token in
                // Deliberately NOT persisted here — buffered until the records are applied below.
                pendingZoneTokens.append((zoneID, token))
            },
            completion: { [weak self, db] result in
                let dbKey = database == .private ? "private" : "shared"
                switch result {
                case .success:
                    logWarning("[Sync] Pull complete — \(pulledRecordCount) record(s), \(pulledDeleteCount) delete(s), largeSync=\(self?.isLargeSyncCycle ?? false)")
                    self?.processBufferedRecords(bufferedRecords, database: database)
                    // Commit zone tokens ONLY now that the records they cover are in the local DB.
                    // Persisting them as they arrived (the old behaviour) silently lost data: records
                    // are buffered and applied here, so any failure below — or a 30s request timeout,
                    // network drop, or app kill mid-fetch — discarded the buffer while the token had
                    // already advanced past those records, making CloudKit never re-deliver them.
                    // Re-fetching an already-applied record is idempotent, so erring toward
                    // re-delivery is always the safe direction.
                    for entry in pendingZoneTokens {
                        self?.stateManager.saveChangeToken(entry.token, for: entry.zoneID.zoneName, database: dbKey)
                    }
                    self?.isProcessingCloudData = false
                    TransactionRepository.invalidateCache()
                    let localCount = TransactionRepository(db: db).fetchAllTransactions().count
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
                    self?.isProcessingCloudData = false
                    // Intentionally drop `pendingZoneTokens`: the buffered records were never
                    // applied, so the next fetch must start from the previous token and re-deliver
                    // them. Committing here would strand those records permanently.
                    if !pendingZoneTokens.isEmpty {
                        logWarning("[Sync] Pull failed — discarding \(pendingZoneTokens.count) uncommitted zone token(s) so \(bufferedRecords.count) unapplied record(s) are re-delivered next fetch")
                    }
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

    private func processBufferedRecords(_ records: [CKRecord], database: CKDatabase.Scope) {
        var categorized: [SyncRecordCategory: [CKRecord]] = [:]
        var uncategorized: [CKRecord] = []
        for record in records {
            if let cat = SyncRecordCategory.category(for: record.recordType) {
                categorized[cat, default: []].append(record)
            } else {
                uncategorized.append(record)
            }
        }

        // Process uncategorized first (system types like cloudkit.share)
        for record in uncategorized { processIncomingRecord(record) }

        let progressStart: Float = database == .private ? 0.30 : 0.42
        let progressEnd: Float = database == .private ? 0.40 : 0.50
        let activeCategories = SyncRecordCategory.allCases.filter { !(categorized[$0] ?? []).isEmpty }
        guard !activeCategories.isEmpty else { return }
        let step = (progressEnd - progressStart) / Float(activeCategories.count)

        for (i, category) in activeCategories.enumerated() {
            postPhaseProgress(
                progress: progressStart + Float(i) * step,
                phaseKey: category.phaseKey,
                totalRecords: categorized[category]?.count ?? 0
            )

            // Sort within category: parents before children
            var recs = categorized[category] ?? []
            recs.sort { lhs, rhs in
                let lp = SyncRecordCategory.intraCategoryPriority(for: lhs.recordType)
                let rp = SyncRecordCategory.intraCategoryPriority(for: rhs.recordType)
                if lp != rp { return lp < rp }
                // Transactions: parents (no parentCKRecordName) before children
                if category == .transactions {
                    let lChild = (lhs["parentCKRecordName"] as? String) != nil
                    let rChild = (rhs["parentCKRecordName"] as? String) != nil
                    if lChild != rChild { return !lChild }
                }
                return false
            }

            for record in recs { processIncomingRecord(record) }
        }

        // Turn the uuid pointers just written by the inbound records into local integer foreign
        // keys. Runs after the whole buffer so intra-batch ordering stops mattering: a child that
        // arrived before its parent is simply resolved here, or on a later pull if the parent is
        // still absent. Idempotent, so calling it when nothing changed is free.
        db.resolveUuidForeignKeys()
    }

    // MARK: - Sync Record Categories

    private enum SyncRecordCategory: Int, CaseIterable, Comparable {
        case groups = 0        // BudgetGroup, GroupMember, GroupActivity
        case creditCards = 1   // CreditCard
        case budgets = 2       // Budget, BalanceOffset
        case statements = 3    // CreditCardStatement
        case allocations = 4   // BudgetAllocation
        case transactions = 5  // Transaction

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        static func category(for recordType: String) -> SyncRecordCategory? {
            switch recordType {
            case "BudgetGroup", "GroupMember", "GroupActivity": return .groups
            case "CreditCard": return .creditCards
            case "Budget", "BalanceOffset": return .budgets
            case "CreditCardStatement": return .statements
            case "BudgetAllocation": return .allocations
            case "Transaction": return .transactions
            default: return nil
            }
        }

        var phaseKey: String {
            switch self {
            case .groups:       return "sync.phase.syncingGroups"
            case .creditCards:  return "sync.phase.syncingCreditCards"
            case .budgets:      return "sync.phase.syncingBudgets"
            case .statements:   return "sync.phase.syncingStatements"
            case .allocations:  return "sync.phase.syncingAllocations"
            case .transactions: return "sync.phase.syncingTransactions"
            }
        }

        /// Intra-category priority: lower = processed first within the same category.
        static func intraCategoryPriority(for recordType: String) -> Int {
            switch recordType {
            case "BudgetGroup": return 0
            case "GroupMember": return 1
            case "GroupActivity": return 2
            case "Budget": return 0
            case "BalanceOffset": return 1
            default: return 0
            }
        }
    }

    // MARK: - Group Zone Routing

    private struct RecordDestination {
        let zoneID: CKRecordZone.ID
        let database: CKDatabase.Scope
    }

    /// Returns the appropriate zone and database for a given group.
    /// - Owner: writes to group zone in private DB.
    /// - Member: writes to group zone in shared DB (using stored zone owner name).
    /// - No group: writes to private zone in private DB.
    private func destination(forGroupId groupId: String?) -> RecordDestination {
        guard let groupId = groupId, !groupId.isEmpty else {
            return RecordDestination(zoneID: CloudKitManager.privateZoneID, database: .private)
        }

        let group = BudgetGroupRepository(db: db).fetchGroup(byId: groupId)
        if let group = group, group.isOwner {
            return RecordDestination(
                zoneID: CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName),
                database: .private
            )
        }

        // Diagnostic: log why we're routing to shared DB
        let currentUID = AuthenticationManager.shared.currentUser?.uid ?? "nil"
        let groupOwnerId = group?.ownerId ?? "groupNotFound"
        let isOwnerFlag = group?.isOwner ?? false
        logWarning("[Sync][Routing] groupId=\(groupId) → shared DB (currentUID=\(currentUID), groupOwnerId=\(groupOwnerId), isOwner=\(isOwnerFlag), groupFound=\(group != nil))")

        // Safety fallback: if the group is not found in local DB, we cannot safely route to
        // the shared zone (the record may actually live in our private group zone).
        // Default to private DB with the owner zone to prevent resurrection loops.
        guard let group = group else {
            logWarning("[Sync][Routing] ⚠️ Group \(groupId) not found locally — falling back to private DB to avoid cross-zone mismatch")
            return RecordDestination(
                zoneID: CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName),
                database: .private
            )
        }

        let ownerName = group.ckZoneOwner ?? CKCurrentUserDefaultName
        return RecordDestination(
            zoneID: CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: ownerName),
            database: .shared
        )
    }

    /// Returns false when a group record's CloudKit destination can't be safely resolved yet:
    /// the group hasn't been discovered locally, or a member's shared-zone owner (`ckZoneOwner`)
    /// hasn't been resolved. In those cases the push must be DEFERRED (row left pending) rather
    /// than misrouted to the private/self zone — misrouting silently fails on the real (owner's)
    /// zone and can delete the private-zone copy, making the record appear to vanish/resurrect.
    /// Personal (non-group) records always resolve.
    private func canResolveDestination(forGroupId groupId: String?) -> Bool {
        guard let groupId = groupId, !groupId.isEmpty else { return true }
        guard let group = BudgetGroupRepository(db: db).fetchGroup(byId: groupId) else { return false }
        if group.isOwner { return true }
        return !(group.ckZoneOwner?.isEmpty ?? true)
    }

    /// One-time migration: marks group-tagged synced records as pending and clears their
    /// system fields so they get re-pushed to group zones instead of FinovaPrivateZone.
    /// v2: also clears ck_system_fields to prevent buildCKRecord from using the old zone.
    private func migrateGroupRecordsToGroupZones() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedGroupZoneMigration_v2") else { return }

        // Tables with shared_group_id column
        let groupTables = ["Transactions", "Budgets", "CreditCards", "BudgetAllocations"]
        for table in groupTables {
            db.executeSyncUpdate(
                "UPDATE \(table) SET sync_status = 'pending', ck_system_fields = NULL WHERE sync_status = 'synced' AND shared_group_id IS NOT NULL AND shared_group_id != '';",
                textBindings: []
            )
        }

        // CreditCardStatements don't have shared_group_id — mark them pending
        // if their parent credit card belongs to a group
        db.executeSyncUpdate(
            "UPDATE CreditCardStatements SET sync_status = 'pending', ck_system_fields = NULL WHERE sync_status = 'synced' AND credit_card_id IN (SELECT id FROM CreditCards WHERE shared_group_id IS NOT NULL AND shared_group_id != '');",
            textBindings: []
        )

        TransactionRepository.invalidateCache()
        UserDefaults.standard.set(true, forKey: "hasCompletedGroupZoneMigration_v2")
        logWarning("[Sync] Migrated group records to pending (v2: cleared system fields) for group zone push")
    }

    /// Recovery: if the group zone migration already ran and the private-zone
    /// deletes corrupted local data, reset tokens to force a full re-fetch
    /// from CloudKit.  The Group zone still has every record, so the pull
    /// will restore whatever was lost.
    private func recoverFromGroupZoneMigration() {
        guard UserDefaults.standard.bool(forKey: "hasCompletedGroupZoneMigration_v2"),
              !UserDefaults.standard.bool(forKey: "hasRecoveredGroupZoneMigration_v2") else { return }

        logWarning("[Sync] Recovering from group zone migration — resetting tokens for full re-fetch")
        stateManager.resetAllTokens()
        UserDefaults.standard.set(true, forKey: "hasRecoveredGroupZoneMigration_v2")
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
        db.clearSystemFields(ckRecordName: name, table: table)
    }

    /// Encodes a CKRecord's system fields and stores them in the local DB.
    private func storeSystemFields(from record: CKRecord) {
        guard let table = tableForRecordName(record.recordID.recordName) else { return }
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()

        let zoneID = record.recordID.zoneID
        guard !isProjection(recordName: record.recordID.recordName, table: table, zoneID: zoneID) else {
            db.saveProjectionSystemFields(
                coder.encodedData,
                recordName: record.recordID.recordName,
                zoneName: zoneID.zoneName,
                zoneOwner: zoneID.ownerName
            )
            return
        }
        db.saveSystemFields(coder.encodedData, ckRecordName: record.recordID.recordName, table: table)
    }

    /// A group-zone record whose local row is NOT tagged to that group is a Transparent Mode
    /// projection — a published copy of a personal row — rather than the row's own cloud copy.
    ///
    /// The distinction is load-bearing on the write side. `ck_system_fields` is a column on the
    /// record's row, keyed by `ck_record_id` with no zone, so letting a projection save there would
    /// overwrite the personal record's system fields; `lastSyncedZone` would then report the group
    /// zone, `staleZoneCopy` would conclude the record had moved, and the personal copy would be
    /// deleted. Projections therefore keep their sync state in `ProjectionSyncState`.
    static func isProjection(
        recordName: String, table: String, zoneID: CKRecordZone.ID, db: DBHelper
    ) -> Bool {
        guard zoneID.zoneName.hasPrefix("Group-") else { return false }
        let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
        let localScope = db.fetchSingleString(
            "SELECT shared_group_id FROM \(table) WHERE ck_record_id = ?;",
            textBinding: recordName
        )
        return (localScope ?? "") != groupId
    }

    private func isProjection(recordName: String, table: String, zoneID: CKRecordZone.ID) -> Bool {
        Self.isProjection(recordName: recordName, table: table, zoneID: zoneID, db: db)
    }

    /// Decodes the zone a record was last successfully synced into, from its stored system fields.
    /// (`storeSystemFields` refreshes these after every successful push, so this is the record's
    /// current home in CloudKit.)
    private func lastSyncedZone(ckRecordName name: String, table: String) -> CKRecordZone.ID? {
        guard let data = db.fetchSystemFields(ckRecordName: name, table: table),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        guard let archived = CKRecord(coder: unarchiver) else { return nil }
        unarchiver.finishDecoding()
        return archived.recordID.zoneID
    }

    /// Returns the stale copy to delete when a record is moving zones, or nil when it isn't.
    ///
    /// A record's zone changes whenever its group tag changes: personal → group (mirror mode on),
    /// group → personal (mirror mode off, or leaving a group), or group A → group B. `buildCKRecord`
    /// already pushes to the NEW zone, but nothing removed the OLD zone's copy — so disabling mirror
    /// mode left every personal record sitting in the group zone, where members kept seeing it and a
    /// second device re-pulled it and re-applied the group tag (silently re-enabling the mirror).
    /// Deleting the old copy is what actually un-shares the record.
    private func staleZoneCopy(
        storedName: String?,
        table: String,
        newZoneID: CKRecordZone.ID
    ) -> (id: CKRecord.ID, database: CKDatabase.Scope)? {
        guard let name = storedName,
              let oldZone = lastSyncedZone(ckRecordName: name, table: table),
              oldZone != newZoneID else { return nil }
        // A zone we don't own lives in the shared DB; our own zones are in the private DB.
        let database: CKDatabase.Scope = oldZone.ownerName == CKCurrentUserDefaultName ? .private : .shared
        return (CKRecord.ID(recordName: name, zoneID: oldZone), database)
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

        // If the record has moved zones (e.g., from private default zone to a group zone),
        // the archived system fields have the OLD zone baked in. Discard them and use
        // the fresh record so the push targets the correct zone.
        if archived.recordID.zoneID != fresh.recordID.zoneID {
            // Dedupe: this fires once per record, so log only the first time we see each
            // archived→fresh zone pair (the interesting signal is the pair, not the count).
            let pairKey = "\(archived.recordID.zoneID.zoneName)→\(fresh.recordID.zoneID.zoneName)"
            if Self.loggedZoneMismatchPairs.insert(pairKey).inserted {
                logWarning("[GROUPDIAG] Zone mismatch (records tagged to a different group than last synced): archived=\(archived.recordID.zoneID.zoneName) vs fresh=\(fresh.recordID.zoneID.zoneName) — using fresh; suppressing further identical lines")
            }
            return fresh
        }

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
        let txRepo = TransactionRepository(db: db)
        TransactionRepository.invalidateCache()
        if !txRepo.fetchPendingSync().isEmpty { return true }
        if !txRepo.fetchPendingDeletes().isEmpty { return true }

        let budgetRepo = BudgetRepository(db: db)
        if !budgetRepo.fetchPendingSync().isEmpty { return true }
        if !budgetRepo.fetchPendingDeletes().isEmpty { return true }

        let cardRepo = CreditCardRepository(db: db)
        if !cardRepo.fetchPendingSync().isEmpty { return true }
        if !cardRepo.fetchPendingDeletes().isEmpty { return true }

        let stmtRepo = StatementRepository(db: db)
        if !stmtRepo.fetchPendingSync().isEmpty { return true }
        if !stmtRepo.fetchPendingDeletes().isEmpty { return true }

        let allocRepo = BudgetAllocationRepository(db: db)
        if !allocRepo.fetchPendingSync().isEmpty { return true }
        if !allocRepo.fetchPendingDeletes().isEmpty { return true }

        return false
    }

    /// Zone-pairs already logged by `buildCKRecord`, so a zone mismatch prints once per pair
    /// instead of once per record (~1000 lines). Diagnostic only.
    private static var loggedZoneMismatchPairs = Set<String>()

    /// Stable per-device identifier for the deterministic-version tiebreaker.
    private static let revDeviceId: String = {
        let key = "finovaRevDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private static func revTable(forRecordType type: String) -> String? {
        switch type {
        case "Transaction": return "Transactions"
        case "Budget": return "Budgets"
        case "CreditCard": return "CreditCards"
        case "CreditCardStatement": return "CreditCardStatements"
        case "BudgetAllocation": return "BudgetAllocations"
        default: return nil
        }
    }

    /// Whether to stamp `rev` / `revDevice` onto pushed records.
    ///
    /// This used to be a hand-flipped constant that had to stay `false` until the fields were live in
    /// the production CloudKit schema, because stamping a field the schema does not have makes
    /// CloudKit reject EVERY save with "Cannot create or modify field … in production schema" — which
    /// aborts the whole push and takes discovery, the balance-offset flush and the group refresh with
    /// it, since those only run on push success. A constant made the deploy order load-bearing: flip
    /// too early and sync stops, and the only symptom is one warning in the log.
    ///
    /// It is now self-correcting. Stamping is ON by default and turns itself OFF for good the first
    /// time CloudKit rejects a save because of these specific fields, falling back to the timestamp
    /// comparison that predates the rev model. So a build can ship before OR after the schema deploy:
    /// too early costs one failed push cycle, which then retries without the fields.
    ///
    /// Clearing `revStampingUnsupported` (or reinstalling) re-arms it, which is what you want after
    /// the schema does go live.
    private static let revStampingUnsupportedKey = "revStampingUnsupported_v1"

    private static var revStampingEnabled: Bool {
        !UserDefaults.standard.bool(forKey: revStampingUnsupportedKey)
    }

    /// Called when CloudKit rejects a save because `rev`/`revDevice` are missing from the schema.
    /// Latches off permanently rather than per-cycle: the schema will not appear mid-session, and
    /// retrying every cycle would cost a failed push each time.
    private static func disableRevStamping(reason: String) {
        guard revStampingEnabled else { return }
        UserDefaults.standard.set(true, forKey: revStampingUnsupportedKey)
        logWarning("""
            [Sync] ⚠️ rev/revDevice are not in the CloudKit schema — disabling version stamping and \
            falling back to timestamp ordering. Deploy `rev` (INT64) and `revDevice` (STRING) to every \
            synced record type, then clear \(revStampingUnsupportedKey) to re-enable. Reason: \(reason)
            """)
    }

    /// Stamps the deterministic version onto a record about to be pushed: bumps `rev` to
    /// (localRev + 1) — a logical clock, NOT wall time — and records this device as author. The
    /// new rev is persisted locally for existing records so bumps stay monotonic; brand-new
    /// records start at rev=1 and self-heal locally when the push echoes back on the next fetch.
    /// Returns the record for call-site chaining. Never changes sync_status (invisible to the user).
    private func stampedRev(_ record: CKRecord) -> CKRecord {
        let name = record.recordID.recordName
        let table = Self.revTable(forRecordType: record.recordType)
        let localRev = table.map { db.fetchRev(table: $0, ckRecordName: name).rev } ?? 0
        let newRev = localRev + 1
        // Local rev tracking stays live regardless of whether the fields can be pushed, so it is
        // already correct the moment the schema does support them.
        if Self.revStampingEnabled {
            record["rev"] = newRev as CKRecordValue
            record["revDevice"] = Self.revDeviceId as CKRecordValue
        }
        if let table = table {
            db.setRev(table: table, ckRecordName: name, rev: newRev, device: Self.revDeviceId)
        }
        return record
    }

    /// OWNERSHIP INVARIANT for group-shared records: a delete may only be pushed to CloudKit by
    /// the user who created the record, or by the group's owner. Personal (non-group) records are
    /// always deletable. Legacy records with no `created_by_uid` are treated as owned by the
    /// current user (they predate group sharing). This prevents a member's local repair/edit from
    /// deleting another member's — or the owner's — shared records for everyone.
    private func mayPushDeleteForGroupRecord(sharedGroupId: String?, createdByUid: String?) -> Bool {
        guard let gid = sharedGroupId, !gid.isEmpty else { return true }
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return false }
        if createdByUid == nil || createdByUid == uid { return true }
        // Another member created it — only the group owner may delete it.
        if let group = BudgetGroupRepository(db: db).fetchGroup(byId: gid) { return group.isOwner }
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
        var privateRecords: [CKRecord] = []
        var sharedRecords: [CKRecord] = []
        var privateDeleteIDs: [CKRecord.ID] = []
        var sharedDeleteIDs: [CKRecord.ID] = []
        var orphanDeleteNames: Set<String> = []
        pendingCKIdAssignments = [:]

        // HYDRATION INVARIANT: a device that has not completed a verified full pull must NEVER
        // push a delete to CloudKit (nor hard-delete the local rows those deletes are based on).
        // A fresh / re-installed / just-logged-in device can carry `pendingDelete` tombstones it
        // inherited (from a restored DB, a prior destructive migration, or a repair) — pushing
        // them up would remove the record for EVERY device. Deletes stay queued locally until the
        // first full pull is verified, after which they push normally. Worst case becomes a
        // still-present record, never silent data loss.
        let canPushDeletes = UserDefaults.standard.bool(forKey: Self.fullPullVerifiedKey)
        if !canPushDeletes {
            logWarning("[Sync] Full pull not yet verified — deferring ALL pending deletes (none will be pushed this cycle)")
        }

        // Repair: any soft-deleted transaction whose sync_status was corrupted (e.g. overwritten
        // by a previous pull before the pendingDelete could be pushed) gets re-queued here.
        // This covers installments/recurring batches deleted before the ConflictResolver fix,
        // without requiring a full reset sync to trigger the per-record repair path.
        // Fill in uuid foreign keys for rows created since the last push. Without this a locally
        // created row ships with a nil reference and the receiving device has nothing to resolve —
        // the insert trigger gives a row its own uuid, but not its pointers.
        db.deriveUuidForeignKeys()

        let repairedCount = db.repairCorruptedPendingDeletes()
        if repairedCount > 0 {
            logWarning("[Sync] Repaired \(repairedCount) soft-deleted transaction(s) whose pendingDelete status was lost")
        }

        // Helper to append a record to the correct array based on destination database
        func appendRecord(_ record: CKRecord, database: CKDatabase.Scope) {
            if database == .shared {
                sharedRecords.append(record)
            } else {
                privateRecords.append(record)
            }
        }
        func appendDeleteID(_ id: CKRecord.ID, database: CKDatabase.Scope) {
            if database == .shared {
                sharedDeleteIDs.append(id)
            } else {
                privateDeleteIDs.append(id)
            }
        }
        // Like appendDeleteID but also registers the record name as an orphan so that
        // pushDeletes skips hardDeleteLocal for it — the local row lives in a group zone and
        // must not be removed simply because the private-zone copy was absent/gone.
        func appendOrphanDeleteID(_ id: CKRecord.ID, database: CKDatabase.Scope) {
            appendDeleteID(id, database: database)
            orphanDeleteNames.insert(id.recordName)
        }

        // MARK: Transparent Mode projections

        // Counted rather than logged per record: fanning a 1300-row ledger out would bury the push
        // log in 1300 identical lines. The summary below is the only evidence this path ran at all,
        // and it is the least-exercised path in the sync layer — it had NO success logging until a
        // real user was about to turn it on for the first time.
        var projectionsPublished: [String: Int] = [:]
        var projectionsWithdrawn: [String: Int] = [:]

        // Every group the current user publishes their personal ledger into, resolved once for the
        // whole cycle. Groups whose destination isn't known yet are simply skipped — the next push
        // picks them up, which is safer than guessing a zone.
        let projectionTargets: [(groupId: String, dest: RecordDestination)] =
            TransparencyManager.shared.publishedGroupIds().compactMap { groupId in
                guard canResolveDestination(forGroupId: groupId) else {
                    needsPostSyncPush = true
                    return nil
                }
                let dest = destination(forGroupId: groupId)
                guard dest.zoneID != CloudKitManager.privateZoneID else { return nil }
                return (groupId, dest)
            }

        /// `staleZoneCopy`, minus any zone this record is about to be projected into.
        ///
        /// A record moving from a group zone back to personal is exactly what the un-tag migration
        /// produces, and `staleZoneCopy` correctly wants to remove the group-zone copy. But if the
        /// author publishes to that same group, `fanOutProjections` is simultaneously saving a
        /// projection there — the same (zone, recordName) would be queued for delete AND save in one
        /// CKModifyRecordsOperation. The projection is the intended state, so the delete is dropped.
        func staleZoneCopyOutsideProjections(
            storedName: String?, table: String, newZoneID: CKRecordZone.ID, isPersonal: Bool
        ) -> (id: CKRecord.ID, database: CKDatabase.Scope)? {
            guard let stale = staleZoneCopy(
                storedName: storedName, table: table, newZoneID: newZoneID
            ) else { return nil }
            guard isPersonal else { return stale }
            let projectedZones = Set(projectionTargets.map(\.dest.zoneID.zoneName))
            return projectedZones.contains(stale.id.zoneID.zoneName) ? nil : stale
        }

        /// Publishes a personal record into every group the author has made transparent, and
        /// withdraws it from groups that are no longer transparent.
        ///
        /// The projection reuses the personal record's name — CloudKit names are unique per zone —
        /// so it needs no identity of its own and there is no second local row to keep in step.
        /// Nothing here touches the personal row: that is the entire difference from Mirror Mode,
        /// which moved the row and thereby stopped it being personal.
        func fanOutProjections(of fresh: CKRecord, isPersonal: Bool) {
            let name = fresh.recordID.recordName
            let live = isPersonal ? projectionTargets : []
            let liveZoneNames = Set(live.map(\.dest.zoneID.zoneName))

            // Withdraw: a zone we projected into before but no longer publish to. This is what
            // makes revoking transparency actually un-share the record, and it is the ONLY delete
            // Transparent Mode ever issues — the personal row is never touched.
            for stale in db.projectionZones(recordName: name)
            where !liveZoneNames.contains(stale.zoneName) {
                let zoneID = CKRecordZone.ID(zoneName: stale.zoneName, ownerName: stale.zoneOwner)
                let database: CKDatabase.Scope =
                    stale.zoneOwner == CKCurrentUserDefaultName ? .private : .shared
                appendOrphanDeleteID(CKRecord.ID(recordName: name, zoneID: zoneID), database: database)
                db.deleteProjectionState(recordName: name, zoneName: stale.zoneName)
                projectionsWithdrawn[stale.zoneName, default: 0] += 1
            }

            for target in live {
                guard let copy = fresh.copy() as? CKRecord else { continue }
                let projected = CKRecord(recordType: copy.recordType, recordID:
                    CKRecord.ID(recordName: name, zoneID: target.dest.zoneID))
                for key in copy.allKeys() { projected[key] = copy[key] }
                // Receivers tag by zone, but state it explicitly so the record is self-describing.
                projected["sharedGroupId"] = target.groupId as CKRecordValue
                let systemFields = db.fetchProjectionSystemFields(
                    recordName: name, zoneName: target.dest.zoneID.zoneName
                )
                appendRecord(
                    stampedRev(buildCKRecord(fresh: projected, systemFieldsData: systemFields)),
                    database: target.dest.database
                )
                projectionsPublished[target.dest.zoneID.zoneName, default: 0] += 1
            }
        }

        // Transactions — use stored ck_record_id to avoid creating duplicate CK records
        let txRepo = TransactionRepository(db: db)
        let cardRepo = CreditCardRepository(db: db)
        TransactionRepository.invalidateCache()
        let allTxCount = txRepo.fetchAllTransactions().count
        let pendingTransactions = txRepo.fetchPendingSync()
        logWarning("[Sync] Transactions: \(allTxCount) total, \(pendingTransactions.count) pending")
        for tx in pendingTransactions {
            // Guard: skip credit card transactions whose card has no ck_record_name yet.
            // The card must be pushed first so other devices can remap IDs correctly.
            if let ccId = tx.creditCardId, cardRepo.fetchCKRecordName(for: ccId) == nil {
                // Card has no ck_record_name — skip this transaction for now.
                // The card must be pushed first so other devices can remap IDs.
                // NEVER detach transactions from their credit card — the card may
                // not have been synced yet (group zone, recovery sync, etc.).
                logWarning("[Sync] Skipping transaction \(tx.id ?? -1): credit card \(ccId) has no ck_record_name yet")
                // The card is being pushed in THIS cycle (its ck_record_name is assigned in the
                // per-record success callback), so retry right after — otherwise a brand-new card
                // and its transactions need a second cycle that nothing would schedule.
                needsPostSyncPush = true
                continue
            }
            let storedName = tx.id.flatMap { txRepo.fetchCKRecordName(for: $0) }
            let groupId = tx.id.flatMap { txRepo.fetchSharedGroupId(for: $0) }
            guard canResolveDestination(forGroupId: groupId) else {
                logWarning("[Sync] Deferring push of transaction \(tx.id ?? -1) — group \(groupId ?? "-") destination not resolved yet")
                // Group discovery / ckZoneOwner resolution happens later in this same cycle, so
                // retry after it finishes rather than stranding the row as 'pending'.
                needsPostSyncPush = true
                continue
            }
            let dest = destination(forGroupId: groupId)

            let freshRecord = tx.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            // Phase 3B: Defer setCKRecordId to after push succeeds to avoid orphaned names
            if let txId = tx.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "transaction", localId: txId)
            }
            // Include shared_group_id in CK record
            if let groupId = groupId {
                freshRecord["sharedGroupId"] = groupId as CKRecordValue
            }
            let systemFields = storedName.flatMap {
                db.fetchSystemFields(ckRecordName: $0, table: "Transactions")
            }
            appendRecord(stampedRev(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields)), database: dest.database)
            fanOutProjections(of: freshRecord, isPersonal: (groupId ?? "").isEmpty)
            // Remove the copy in whatever zone this record used to live in (covers personal→group,
            // group→personal on un-mirror/leave, and group A→group B).
            if let stale = staleZoneCopyOutsideProjections(
                storedName: storedName, table: "Transactions", newZoneID: dest.zoneID, isPersonal: (groupId ?? "").isEmpty
            ) {
                appendOrphanDeleteID(stale.id, database: stale.database)
            }
        }

        // Transaction deletes
        if canPushDeletes {
        for pending in txRepo.fetchPendingDeletes() {
            let groupId = txRepo.fetchSharedGroupId(for: pending.localId)
            // OWNERSHIP INVARIANT: never push a delete for a group-tagged record the local user
            // did not create (unless they own the group) — a member repairing/re-bucketing the
            // owner's data must not remove it for everyone.
            let createdBy = db.fetchSingleString(
                "SELECT created_by_uid FROM Transactions WHERE id = ?;", intBinding: pending.localId)
            guard mayPushDeleteForGroupRecord(sharedGroupId: groupId, createdByUid: createdBy) else {
                logWarning("[Sync] Skipping delete of transaction \(pending.localId): group record not owned by current user")
                continue
            }
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            // Also delete orphaned copy from FinovaPrivateZone to prevent ghost resurrection
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }
        }

        // Budgets (uses monthDate as key — deterministic across devices)
        let budgetRepo = BudgetRepository(db: db)
        let pendingBudgets = budgetRepo.fetchPendingSync()
        for budget in pendingBudgets {
            guard canResolveDestination(forGroupId: budget.sharedGroupId) else {
                logWarning("[Sync] Deferring push of budget \(budget.monthDate) — group destination not resolved yet")
                needsPostSyncPush = true
                continue
            }
            let dest = destination(forGroupId: budget.sharedGroupId)
            let freshRecord = budget.toCKRecord(in: dest.zoneID)
            let budgetRecordName = freshRecord.recordID.recordName

            // A group budget written by an older build is stored under the unqualified
            // `budget-<monthDate>` — the personal budget's name. Group names now carry the group, so
            // this row is effectively being renamed, and CKRecord names are immutable: withdraw the
            // old record and let the new name be created. Only ever fires for group budgets, and
            // only once per row.
            let storedBudgetName = budgetRepo.fetchCKRecordName(
                forMonthDate: budget.monthDate, sharedGroupId: budget.sharedGroupId
            )
            if let old = storedBudgetName, old != budgetRecordName {
                logWarning("[Sync] Budget \(budget.monthDate) renamed \(old) → \(budgetRecordName); withdrawing old record")
                appendOrphanDeleteID(
                    CKRecord.ID(recordName: old, zoneID: dest.zoneID), database: dest.database
                )
                clearSystemFields(ckRecordName: old)
                budgetRepo.clearCKRecordId(forMonthDate: budget.monthDate, sharedGroupId: budget.sharedGroupId)
            }
            budgetRepo.setCKRecordId(
                forMonthDate: budget.monthDate, sharedGroupId: budget.sharedGroupId,
                ckRecordName: budgetRecordName
            )

            let systemFields = db.fetchSystemFields(ckRecordName: budgetRecordName, table: "Budgets")
            appendRecord(stampedRev(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields)), database: dest.database)
            fanOutProjections(of: freshRecord, isPersonal: (budget.sharedGroupId ?? "").isEmpty)
            if let stale = staleZoneCopyOutsideProjections(
                storedName: budgetRecordName, table: "Budgets", newZoneID: dest.zoneID, isPersonal: (budget.sharedGroupId ?? "").isEmpty
            ) {
                appendOrphanDeleteID(stale.id, database: stale.database)
            }
        }

        // Budget deletes
        if canPushDeletes {
        for pending in budgetRepo.fetchPendingDeletes() {
            let groupId = db.fetchSingleString(
                "SELECT shared_group_id FROM Budgets WHERE month_date = ?;",
                intBinding: pending.monthDate
            )
            let createdBy = db.fetchSingleString(
                "SELECT created_by_uid FROM Budgets WHERE month_date = ?;", intBinding: pending.monthDate)
            guard mayPushDeleteForGroupRecord(sharedGroupId: groupId, createdByUid: createdBy) else {
                logWarning("[Sync] Skipping delete of budget \(pending.monthDate): group record not owned by current user")
                continue
            }
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }
        }

        // Credit Cards — use stored ck_record_id
        let pendingCards = cardRepo.fetchPendingSync()
        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            let allCards = cardRepo.fetchAllCards(userId: uid)
            let groupCards = allCards.filter { $0.sharedGroupId != nil && !($0.sharedGroupId?.isEmpty ?? true) }
            logWarning("[Sync] Credit Cards: \(allCards.count) total, \(groupCards.count) group-tagged, \(pendingCards.count) pending")
        }
        for card in pendingCards {
            let storedName = card.id.flatMap { cardRepo.fetchCKRecordName(for: $0) }
            let groupId = card.sharedGroupId
            guard canResolveDestination(forGroupId: groupId) else {
                logWarning("[Sync] Deferring push of credit card \(card.id ?? -1) — group destination not resolved yet")
                needsPostSyncPush = true
                continue
            }
            let dest = destination(forGroupId: groupId)

            let freshRecord = card.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            if let cardId = card.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "creditCard", localId: cardId)
            }
            if let groupId = groupId {
                freshRecord["sharedGroupId"] = groupId as CKRecordValue
            }
            let systemFields = storedName.flatMap {
                db.fetchSystemFields(ckRecordName: $0, table: "CreditCards")
            }
            appendRecord(stampedRev(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields)), database: dest.database)
            fanOutProjections(of: freshRecord, isPersonal: (groupId ?? "").isEmpty)
            if let stale = staleZoneCopyOutsideProjections(
                storedName: storedName, table: "CreditCards", newZoneID: dest.zoneID, isPersonal: (groupId ?? "").isEmpty
            ) {
                appendOrphanDeleteID(stale.id, database: stale.database)
            }
        }

        // Credit Card deletes
        if canPushDeletes {
        for pending in cardRepo.fetchPendingDeletes() {
            let groupId = cardRepo.fetchSharedGroupId(for: pending.localId)
            let createdBy = db.fetchSingleString(
                "SELECT created_by_uid FROM CreditCards WHERE id = ?;", intBinding: pending.localId)
            guard mayPushDeleteForGroupRecord(sharedGroupId: groupId, createdByUid: createdBy) else {
                logWarning("[Sync] Skipping delete of credit card \(pending.localId): group record not owned by current user")
                continue
            }
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }
        }

        // Credit Card Statements — use stored ck_record_id
        // Statements inherit their group zone from their parent credit card
        let stmtRepo = StatementRepository(db: db)
        let pendingStmts = stmtRepo.fetchPendingSync()
        for stmt in pendingStmts {
            // Guard: skip statements whose parent card has no ck_record_name yet.
            if cardRepo.fetchCKRecordName(for: stmt.creditCardId) == nil {
                logWarning("[Sync] Skipping statement \(stmt.id ?? -1): credit card \(stmt.creditCardId) has no ck_record_name yet")
                needsPostSyncPush = true
                continue
            }
            let storedName = stmt.id.flatMap { stmtRepo.fetchCKRecordName(for: $0) }
            let parentGroupId = cardRepo.fetchSharedGroupId(for: stmt.creditCardId)
            guard canResolveDestination(forGroupId: parentGroupId) else {
                logWarning("[Sync] Deferring push of statement \(stmt.id ?? -1) — group destination not resolved yet")
                needsPostSyncPush = true
                continue
            }
            let dest = destination(forGroupId: parentGroupId)

            let freshRecord = stmt.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            if let stmtId = stmt.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "statement", localId: stmtId)
            }
            let systemFields = storedName.flatMap {
                db.fetchSystemFields(ckRecordName: $0, table: "CreditCardStatements")
            }
            appendRecord(stampedRev(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields)), database: dest.database)
            fanOutProjections(of: freshRecord, isPersonal: (parentGroupId ?? "").isEmpty)
            if let stale = staleZoneCopyOutsideProjections(
                storedName: storedName, table: "CreditCardStatements", newZoneID: dest.zoneID, isPersonal: (parentGroupId ?? "").isEmpty
            ) {
                appendOrphanDeleteID(stale.id, database: stale.database)
            }
        }

        // Statement deletes
        var stmtLocalIdsToPurge: [Int] = []
        if canPushDeletes {
        let pendingStmtDeletes = stmtRepo.fetchPendingDeletes()
        for pending in pendingStmtDeletes {
            let parentCardId = db.fetchSingleInt(
                "SELECT credit_card_id FROM CreditCardStatements WHERE id = ?;",
                intBinding: pending.localId
            )
            let parentGroupId = parentCardId.flatMap { cardRepo.fetchSharedGroupId(for: $0) }
            let createdBy = db.fetchSingleString(
                "SELECT created_by_uid FROM CreditCardStatements WHERE id = ?;", intBinding: pending.localId)
            guard mayPushDeleteForGroupRecord(sharedGroupId: parentGroupId, createdByUid: createdBy) else {
                logWarning("[Sync] Skipping delete of statement \(pending.localId): group record not owned by current user")
                continue
            }
            let dest = destination(forGroupId: parentGroupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if parentGroupId != nil && !(parentGroupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
            stmtLocalIdsToPurge.append(pending.localId)
        }
        // Neutralize ONLY the statement deletes we actually collected above (owned + hydrated),
        // so a skipped (non-owned / deferred) statement's local row is never removed.
        // hardDeleteLocal on the CK callback thread is unreliable (SQLITE_BUSY), so these are
        // purged here on the sync queue now that their CKRecord.IDs are collected.
        for localId in stmtLocalIdsToPurge {
            db.executeSyncUpdate(
                "DELETE FROM CreditCardStatements WHERE id = ?;",
                intBindings: [localId]
            )
        }
        }

        // Budget Allocations — use stored ck_record_id
        let allocRepo = BudgetAllocationRepository(db: db)
        let pendingAllocs = allocRepo.fetchPendingSync()
        for alloc in pendingAllocs {
            guard canResolveDestination(forGroupId: alloc.sharedGroupId) else {
                logWarning("[Sync] Deferring push of allocation \(alloc.id ?? -1) — group destination not resolved yet")
                needsPostSyncPush = true
                continue
            }
            let storedName = alloc.id.flatMap { allocRepo.fetchCKRecordName(for: $0) }
            let dest = destination(forGroupId: alloc.sharedGroupId)

            let freshRecord = alloc.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            if let allocId = alloc.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "allocation", localId: allocId)
            }
            let systemFields = storedName.flatMap {
                db.fetchSystemFields(ckRecordName: $0, table: "BudgetAllocations")
            }
            appendRecord(stampedRev(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields)), database: dest.database)
            fanOutProjections(of: freshRecord, isPersonal: (alloc.sharedGroupId ?? "").isEmpty)
            if let stale = staleZoneCopyOutsideProjections(
                storedName: storedName, table: "BudgetAllocations", newZoneID: dest.zoneID, isPersonal: (alloc.sharedGroupId ?? "").isEmpty
            ) {
                appendOrphanDeleteID(stale.id, database: stale.database)
            }
        }

        // Allocation deletes
        if canPushDeletes {
        for pending in allocRepo.fetchPendingDeletes() {
            let groupId = db.fetchSingleString(
                "SELECT shared_group_id FROM BudgetAllocations WHERE id = ?;",
                intBinding: pending.localId
            )
            let createdBy = db.fetchSingleString(
                "SELECT created_by_uid FROM BudgetAllocations WHERE id = ?;", intBinding: pending.localId)
            guard mayPushDeleteForGroupRecord(sharedGroupId: groupId, createdByUid: createdBy) else {
                logWarning("[Sync] Skipping delete of allocation \(pending.localId): group record not owned by current user")
                continue
            }
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }
        }

        // Push current user's GroupMember record only when it hasn't been confirmed
        // on the server yet. Once the push succeeds we set a per-group flag so
        // subsequent sync cycles skip the push entirely. This prevents an infinite
        // sync loop: .allKeys overwrites the server record even when nothing changed,
        // which updates the zone's modification date and triggers a CK notification
        // on the owner → owner syncs → notifies member → member syncs → repeat.
        // IMPORTANT: GroupMember records are pushed SEPARATELY from the main shared batch
        // using .allKeys save policy. The shared database enforces zone-level atomicity,
        // so a GroupMember serverRecordChanged error (no stored system fields) would
        // cascade and fail ALL other shared records in the same batch.
        var groupMemberRecords: [CKRecord] = []
        var groupMemberGroupIds: [String] = [] // Track which group IDs correspond to each record
        let groupRepo = BudgetGroupRepository(db: db)
        let allGroups = groupRepo.fetchAllGroups()
        if let currentUser = AuthenticationManager.shared.currentUser {
            let currentUid = currentUser.uid
            for group in allGroups where !group.isOwner && !group.isDeleted {
                guard let zoneOwner = group.ckZoneOwner else { continue }

                // Skip if we've already confirmed a successful push for this group
                let flagKey = "groupMemberPushed_\(group.id)"
                if UserDefaults.standard.bool(forKey: flagKey) { continue }

                let members = groupRepo.fetchMembers(forGroupId: group.id)
                guard let selfMember = members.first(where: { $0.userId == currentUid }) else { continue }

                let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: zoneOwner)
                let recordID = CKRecord.ID(recordName: "groupMember-\(selfMember.id)", zoneID: zoneID)
                let record = CKRecord(recordType: "GroupMember", recordID: recordID)
                record["groupId"] = selfMember.groupId as CKRecordValue
                record["userId"] = selfMember.userId as CKRecordValue
                record["name"] = selfMember.name as CKRecordValue
                record["email"] = selfMember.email as CKRecordValue
                record["role"] = selfMember.role.rawValue as CKRecordValue
                record["joinedAt"] = selfMember.joinedAt as NSDate
                record["permissions"] = selfMember.permissions.asJSON as CKRecordValue
                groupMemberRecords.append(record)
                groupMemberGroupIds.append(group.id)
            }
        }

        let totalRecords = privateRecords.count + sharedRecords.count + groupMemberRecords.count
        let totalDeletes = privateDeleteIDs.count + sharedDeleteIDs.count
        let groupZoneRecords = privateRecords.filter { $0.recordID.zoneID.zoneName.hasPrefix("Group-") }
        let defaultZoneRecords = privateRecords.filter { !$0.recordID.zoneID.zoneName.hasPrefix("Group-") }
        logWarning("[Sync] Push: \(totalRecords) record(s) to save (\(defaultZoneRecords.count) private-default, \(groupZoneRecords.count) private-group, \(sharedRecords.count) shared, \(groupMemberRecords.count) groupMember), \(totalDeletes) to delete")

        // Transparent Mode summary. The only evidence this path ran, and the only way to tell a
        // projection fan-out apart from ordinary group records in the counts above — both land in
        // `private-group`. Logged even when zero, because "published 0" and "did not run" are
        // different diagnoses and the difference matters on a path this new.
        if projectionTargets.isEmpty {
            logWarning("[Transparency] No groups published to — no projections in this push")
        } else {
            let targets = projectionTargets
                .map { "\($0.dest.zoneID.zoneName)(\($0.dest.database == .shared ? "shared" : "private"))" }
                .joined(separator: ", ")
            let published = projectionsPublished.isEmpty
                ? "none"
                : projectionsPublished.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            logWarning("""
                [Transparency] Publishing to \(projectionTargets.count) group zone(s): \(targets)
                  projections queued: \(published)
                """)
        }
        if !projectionsWithdrawn.isEmpty {
            let withdrawn = projectionsWithdrawn.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            logWarning("[Transparency] Withdrawing projections from no-longer-published zone(s): \(withdrawn)")
        }

        postPhaseProgress(progress: 0.55, phaseKey: "sync.phase.preparingUpload", totalRecords: totalRecords)

        guard totalRecords > 0 || totalDeletes > 0 else {
            completion?(.success(()))
            return
        }

        let privateBatches = stride(from: 0, to: privateRecords.count, by: Self.batchSize).map {
            Array(privateRecords[$0..<min($0 + Self.batchSize, privateRecords.count)])
        }
        let sharedBatches = stride(from: 0, to: sharedRecords.count, by: Self.batchSize).map {
            Array(sharedRecords[$0..<min($0 + Self.batchSize, sharedRecords.count)])
        }

        // Track push progress for any multi-batch push
        let allBatchCount = privateBatches.count + sharedBatches.count
        if allBatchCount > 0 {
            let progress = SyncPushProgress(currentBatch: 0, totalBatches: allBatchCount, totalRecords: totalRecords)
            currentPushProgress = progress
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .syncPushProgressDidChange, object: progress)
            }
        }
        // Detect initial push for one-time flag
        if totalRecords > Self.batchSize && !UserDefaults.standard.bool(forKey: "hasCompletedInitialCloudPush_v1") {
            isInitialPush = true
        }

        // Push GroupMember records FIRST (separately with .allKeys save policy).
        // GroupMember has no stored system fields, so .ifServerRecordUnchanged
        // fails when the record already exists on the server. Shared DB also
        // enforces zone-level atomicity, so that failure would cascade to ALL
        // other records in the same batch.
        // Pushed BEFORE the main shared batch so that when the transaction push
        // triggers a notification on the owner's device, the GroupMember record
        // is already in the zone for the owner to fetch.
        let pushAfterGroupMember = { [weak self] in
            // Push private DB records first, then shared DB records
            self?.pushBatches(privateBatches, deleteIDs: privateDeleteIDs, database: .private, index: 0, orphanNames: orphanDeleteNames) { [weak self] result in
                switch result {
                case .success:
                    guard !sharedBatches.isEmpty || !sharedDeleteIDs.isEmpty else {
                        completion?(.success(()))
                        return
                    }
                    self?.pushBatches(sharedBatches, deleteIDs: sharedDeleteIDs, database: .shared, index: 0, completion: completion)
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }

        guard !groupMemberRecords.isEmpty else {
            pushAfterGroupMember()
            return
        }
        cloudKitOps.saveRecords(groupMemberRecords, database: .shared, savePolicy: .allKeys) { recordID, result in
            switch result {
            case .success:
                logInfo("[Sync] ✅ Pushed GroupMember \(recordID.recordName)")
                // Extract groupId from the record name (format: "groupMember-<memberId>")
                // and mark as pushed using the tracked group IDs
                if let idx = groupMemberRecords.firstIndex(where: { $0.recordID == recordID }),
                   idx < groupMemberGroupIds.count {
                    let gid = groupMemberGroupIds[idx]
                    UserDefaults.standard.set(true, forKey: "groupMemberPushed_\(gid)")
                }
            case .failure(let error):
                logWarning("[Sync] ⚠️ Failed to push GroupMember \(recordID.recordName): \(error.localizedDescription)")
            }
        } completion: { result in
            if case .failure(let error) = result {
                logWarning("[Sync] ⚠️ GroupMember batch failed: \(error.localizedDescription)")
            }
            // GroupMember failures are non-fatal — continue with main push
            pushAfterGroupMember()
        }
    }

    private static let maxThrottleRetries = 5

    private func pushBatches(
        _ batches: [[CKRecord]],
        deleteIDs: [CKRecord.ID] = [],
        database: CKDatabase.Scope,
        index: Int,
        throttleRetryCount: Int = 0,
        orphanNames: Set<String> = [],
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard index < batches.count else {
            // All batches complete — clear progress
            currentPushProgress = nil
            if isInitialPush {
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialCloudPush_v1")
                isInitialPush = false
            }

            // After all save batches, send deletes if any
            if !deleteIDs.isEmpty {
                pushDeletes(deleteIDs, database: database, orphanNames: orphanNames, completion: completion)
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

        // Suppress SyncChangeTracker during per-record completion so markAsSynced
        // calls don't re-trigger handleLocalDataChange → another push cycle.
        SyncChangeTracker.shared.isSuppressed = true

        cloudKitOps.saveRecords(batch, database: database, savePolicy: .ifServerRecordUnchanged) { [weak self, db] recordID, result in
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
                        TransactionRepository(db: db).setCKRecordId(for: assignment.localId, ckRecordName: name)
                    case "creditCard":
                        CreditCardRepository(db: db).setCKRecordId(for: assignment.localId, ckRecordName: name)
                        // Re-queue all statements for this CC so they are re-pushed on the
                        // next sync cycle with creditCardCKRecordName now filled in.
                        // Without this, statements pushed in the same batch as a new CC lack
                        // creditCardCKRecordName (the CC's ck_record_id wasn't stored yet when
                        // the statement CKRecord was being built), causing cross-device remapping
                        // to fail and statements to be inserted with the wrong local creditCardId.
                        StatementRepository(db: db).markStatementsPending(forCardId: assignment.localId)
                    case "statement":
                        StatementRepository(db: db).setCKRecordId(for: assignment.localId, ckRecordName: name)
                    case "allocation":
                        BudgetAllocationRepository(db: db).setCKRecordId(for: assignment.localId, ckRecordName: name)
                    default:
                        break
                    }
                }

                // The `updatedAt` we actually pushed (CloudKit echoes user fields back on save).
                // markAsSynced only clears the pending flag if the local row hasn't been edited
                // since, so an edit made while this push was in flight stays pending and goes up
                // on the next cycle instead of being silently marked synced and lost.
                let pushedUpdatedAt = savedRecord["updatedAt"] as? Date
                if name.hasPrefix("transaction-") {
                    TransactionRepository(db: db).markAsSynced(ckRecordName: name, pushedUpdatedAt: pushedUpdatedAt)
                } else if name.hasPrefix("budget-") {
                    BudgetRepository(db: db).markAsSynced(ckRecordName: name, pushedUpdatedAt: pushedUpdatedAt)
                } else if name.hasPrefix("creditCard-") {
                    CreditCardRepository(db: db).markAsSynced(ckRecordName: name, pushedUpdatedAt: pushedUpdatedAt)
                } else if name.hasPrefix("statement-") {
                    StatementRepository(db: db).markAsSynced(ckRecordName: name, pushedUpdatedAt: pushedUpdatedAt)
                } else if name.hasPrefix("allocation-") {
                    BudgetAllocationRepository(db: db).markAsSynced(ckRecordName: name, pushedUpdatedAt: pushedUpdatedAt)
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
                                logWarning("[Sync] ⚠️ CloudKit schema error for record \(name): \(desc)")
                            }
                            // If it is the version fields specifically, we can recover on our own:
                            // stop stamping them and retry. Everything else genuinely needs a deploy.
                            if desc.contains("rev") {
                                Self.disableRevStamping(reason: desc)
                                self?.needsPostSyncPush = true
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
            SyncChangeTracker.shared.isSuppressed = false
            logWarning("[GROUPDIAG] [Push] Batch \(index + 1)/\(batches.count) result: \(batchSuccessCount) succeeded, \(batchFailureCount) failed")

            if let self = self {
                let progress = SyncPushProgress(currentBatch: index + 1, totalBatches: batches.count, totalRecords: batches.reduce(0) { $0 + $1.count })
                self.currentPushProgress = progress
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .syncPushProgressDidChange, object: progress)
                }
            }

            // Phase progress for push batches (0.60 to 0.90 range)
            if let self = self, batches.count > 0 {
                let batchFraction = Float(index + 1) / Float(batches.count)
                let pushProgress = 0.60 + batchFraction * 0.30
                let totalRecs = batches.reduce(0) { $0 + $1.count }
                self.postPhaseProgress(
                    progress: Float(pushProgress),
                    phaseKey: "sync.phase.uploading",
                    totalBatches: batches.count,
                    currentBatch: index + 1,
                    totalRecords: totalRecs
                )
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
                logWarning("[GROUPDIAG] [Push] Stopping save batches due to schema error. Deploy schema via CloudKit Dashboard, then sync again.")
                if !deleteIDs.isEmpty {
                    self?.pushDeletes(deleteIDs, database: database, orphanNames: orphanNames, completion: completion)
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
                    self?.pushBatches(batches, deleteIDs: deleteIDs, database: database, index: index + 1, throttleRetryCount: 0, orphanNames: orphanNames, completion: completion)
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
                            self?.pushBatches(batches, deleteIDs: deleteIDs, database: database, index: index, throttleRetryCount: nextRetry, orphanNames: orphanNames, completion: completion)
                        }
                    default:
                        logWarning("[Sync] ❌ Batch \(index + 1)/\(batches.count) failed: \(error.localizedDescription)")
                        // Saves failed but deletes are independent — still push pending deletes
                        // so that locally deleted records are removed from CloudKit even when
                        // a save batch encounters an unrecoverable error (e.g. serverRecordChanged).
                        if !deleteIDs.isEmpty {
                            self?.pushDeletes(deleteIDs, database: database, orphanNames: orphanNames, completion: { _ in completion?(.failure(error)) })
                        } else {
                            completion?(.failure(error))
                        }
                    }
                } else {
                    logWarning("[Sync] ❌ Batch \(index + 1)/\(batches.count) failed: \(error.localizedDescription)")
                    if !deleteIDs.isEmpty {
                        self?.pushDeletes(deleteIDs, database: database, orphanNames: orphanNames, completion: { _ in completion?(.failure(error)) })
                    } else {
                        completion?(.failure(error))
                    }
                }
            }
        }
    }

    private func pushDeletes(_ deleteIDs: [CKRecord.ID], database: CKDatabase.Scope = .private, orphanNames: Set<String> = [], completion: ((Result<Void, Error>) -> Void)?) {
        guard !deleteIDs.isEmpty else {
            completion?(.success(()))
            return
        }

        postPhaseProgress(progress: 0.95, phaseKey: "sync.phase.finalizing")

        // Batch deletes to stay under CloudKit's 400-item limit
        let batches = stride(from: 0, to: deleteIDs.count, by: Self.batchSize).map {
            Array(deleteIDs[$0..<min($0 + Self.batchSize, deleteIDs.count)])
        }

        func pushDeleteBatch(index: Int) {
            guard index < batches.count else {
                completion?(.success(()))
                return
            }

            let batch = batches[index]
            SyncChangeTracker.shared.isSuppressed = true
            cloudKitOps.deleteRecords(batch, database: database) { [weak self] recordID, result in
                let name = recordID.recordName
                // Orphan deletes clean up private-zone copies of group-zone records.
                // If the private-zone copy was absent, hardDeleteLocal must NOT run —
                // the actual record lives in the group zone and is still active locally.
                let isOrphan = orphanNames.contains(name)
                switch result {
                case .success:
                    logWarning("[Sync] ✓ Deleted record \(name) from CloudKit")
                    if !isOrphan { self?.hardDeleteLocal(recordName: name) }
                case .failure(let error):
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .unknownItem:
                            if isOrphan {
                                logWarning("[Sync] Orphan record \(name) not found in private zone — skipping local delete (record lives in group zone)")
                            } else {
                                logWarning("[Sync] Record \(name) already deleted from CloudKit — hard-deleting locally")
                                self?.hardDeleteLocal(recordName: name)
                            }
                        case .permissionFailure:
                            // Member doesn't have permission to delete this record from the shared
                            // zone. Do NOT hard-delete locally — the CK record still exists, so a
                            // local delete would be pure data loss (and the record would reappear on
                            // the next full pull anyway, looking like a resurrection). The ownership
                            // guard in pushLocalChanges (mayPushDeleteForGroupRecord) means we should
                            // not normally reach here for non-owned records; if we do, leave the local
                            // row intact and stop trying — the guard prevents a re-push loop.
                            logWarning("[Sync] ⚠️ Permission denied deleting \(name) — keeping local row (never hard-delete a record that still exists in CloudKit)")
                        case .userDeletedZone, .zoneNotFound:
                            // Zone no longer exists — record is effectively gone; clean up locally.
                            logWarning("[Sync] ⚠️ Zone gone for \(name) — removing locally")
                            if !isOrphan { self?.hardDeleteLocal(recordName: name) }
                        case .quotaExceeded:
                            let retryAfter = ckError.retryAfterSeconds ?? 300
                            self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                        default:
                            logWarning("[Sync] ❌ Failed to delete record \(name): \(ckError.code.rawValue) \(error.localizedDescription)")
                        }
                    } else {
                        logWarning("[Sync] ❌ Failed to delete record \(name): \(error.localizedDescription)")
                    }
                }
            } completion: { [weak self] result in
                SyncChangeTracker.shared.isSuppressed = false
                switch result {
                case .success:
                    pushDeleteBatch(index: index + 1)
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

        logWarning("[Sync] Pushing \(deleteIDs.count) delete(s) in \(batches.count) batch(es) to \(database == .shared ? "shared" : "private") DB — names: \(deleteIDs.prefix(10).map { $0.recordName })")
        pushDeleteBatch(index: 0)
    }

    private func hardDeleteLocal(recordName name: String) {
        if name.hasPrefix("transaction-") {
            // For installment/recurring instances (parent_transaction_id IS NOT NULL),
            // leave a tombstone row (is_deleted=1, ck_record_id=NULL) instead of a full DELETE.
            // This prevents lazy generation from recreating the deleted instance on the next
            // dashboard refresh — the tombstone's anchor is visible to fetchDeletedChildAnchors().
            // ck_record_id is cleared so repairCorruptedPendingDeletes (which requires IS NOT NULL)
            // will never re-queue it, and processDeletedRecord's deleteFromCloud won't match it.
            let isInstance = db.fetchSingleInt(
                "SELECT 1 FROM Transactions WHERE ck_record_id = ? AND parent_transaction_id IS NOT NULL;",
                textBinding: name
            ) != nil
            if isInstance {
                db.executeSyncUpdate(
                    "UPDATE Transactions SET is_deleted = 1, sync_status = 'synced', ck_record_id = NULL WHERE ck_record_id = ?;",
                    textBindings: [name]
                )
                TransactionRepository.invalidateCache()
            } else {
                TransactionRepository(db: db).hardDeleteByCKRecordName(name)
            }
        } else if name.hasPrefix("budget-") {
            BudgetRepository(db: db).hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("creditCard-") {
            CreditCardRepository(db: db).hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("statement-") {
            // Statement rows are already deleted in pushLocalChanges (on the sync queue)
            // before the CK push begins. This is a no-op safety net.
            StatementRepository(db: db).hardDeleteByCKRecordName(name)
        } else if name.hasPrefix("allocation-") {
            BudgetAllocationRepository(db: db).hardDeleteByCKRecordName(name)
        }
    }

    // MARK: - Process Incoming Records

    private func processIncomingRecord(_ record: CKRecord) {
        // Only log CC-related and non-Transaction types to reduce noise
        if record.recordType != "Transaction" && record.recordType != "Budget" && record.recordType != "BudgetAllocation" {
            logWarning("[Sync] Processing incoming record: type=\(record.recordType), name=\(record.recordID.recordName), zone=\(record.recordID.zoneID.zoneName)")
        }

        // Extract group ID from zone name (e.g. "Group-ABC123" → "ABC123")
        // and inject into the record so ConflictResolver can tag it.
        // Skip injection for soft-deleted groups — their data has been untagged
        // and should stay personal.
        let zoneName = record.recordID.zoneID.zoneName

        // Transparent Mode: my own projection coming back to me.
        //
        // The publisher's other devices see the record in BOTH zones. Applying the group-zone copy
        // would tag the personal row with the group id — which is exactly the Mirror Mode
        // corruption, arriving by a different route. The personal-zone copy is the authoritative
        // one, so drop this.
        //
        // Identified by NAME plus SCOPE, deliberately NOT by authorship.
        //
        // This guard used to also require `createdByUid == currentUser.uid`, and that condition
        // destroyed data the first time Transparent Mode was enabled on real data. Authorship was
        // only recorded from a certain build onward, so rows predating it have `created_by_uid IS
        // NULL`; the adapter then writes no `createdByUid` at all, the comparison fails, and the
        // record falls through to be treated as an ordinary group record — which re-tags the personal
        // row with the group id and removes it from the personal ledger. Precisely the Mirror Mode
        // corruption the whole design exists to prevent.
        //
        // The remaining two conditions are sufficient AND strictly stronger. Record names are
        // `<type>-<uuid>`, unique per record identity, so a group-zone record can only share a name
        // with a local row of mine if it IS a copy of that row. `isProjection` then confirms the local
        // row's scope is not this zone's group, which distinguishes a projection from a record I
        // genuinely moved into the group. Authorship added nothing and, when absent, broke it.
        if zoneName.hasPrefix("Group-"),
           let table = tableForRecordName(record.recordID.recordName),
           isProjection(recordName: record.recordID.recordName, table: table, zoneID: record.recordID.zoneID),
           db.fetchSingleInt(
               "SELECT COUNT(*) FROM \(table) WHERE ck_record_id = ?;",
               textBinding: record.recordID.recordName
           ) ?? 0 > 0
        {
            logWarning("[Transparency] Skipping own projection \(record.recordID.recordName) from \(zoneName)")
            return
        }

        if zoneName.hasPrefix("Group-"), record["sharedGroupId"] == nil {
            let groupId = String(zoneName.dropFirst("Group-".count))
            let group = BudgetGroupRepository(db: db).fetchGroup(byId: groupId)
            if group == nil || !group!.isDeleted {
                record["sharedGroupId"] = groupId as CKRecordValue
            }
        }

        // Cross-device ID remapping: resolve local auto-increment IDs via CK record names
        // before parsing, so the parsed objects already have correct local IDs.
        remapCrossDeviceIDs(in: record)

        switch record.recordType {
        case "Transaction":
            guard let transaction = Transaction.fromCKRecord(record) else {
                logError("[Sync] Failed to parse Transaction from CKRecord \(record.recordID.recordName)")
                return
            }
            // Only log CC transactions to reduce noise
            if transaction.creditCardId != nil {
                logWarning("[StmtSync] Incoming CC transaction: id=\(transaction.id ?? -1), title=\(transaction.title), creditCardId=\(transaction.creditCardId ?? -1), statementId=\(transaction.statementId ?? -1)")
            }
            resolver.resolveTransaction(remote: transaction, ckRecord: record)
            // Persist statement override flag from cloud
            if (record["isStatementOverridden"] as? Int) == 1,
               let localId = TransactionRepository(db: db).fetchTransaction(byCKRecordName: record.recordID.recordName)?.id {
                db.setStatementOverridden(transactionId: localId, overridden: true)
            }
        case "Budget":
            guard let budget = BudgetModel.fromCKRecord(record) else { return }
            resolver.resolveBudget(remote: budget, ckRecord: record)
        case "CreditCard":
            guard let card = CreditCard.fromCKRecord(record) else { return }
            logWarning("[StmtSync] Incoming CreditCard: name=\(card.name), ckLocalId=\(card.id ?? -1), ckName=\(record.recordID.recordName)")
            resolver.resolveCreditCard(remote: card, ckRecord: record)
        case "CreditCardStatement":
            guard let stmt = CreditCardStatement.fromCKRecord(record) else {
                logWarning("[StmtSync] Failed to parse CreditCardStatement from \(record.recordID.recordName)")
                return
            }
            let hasCKCardName = record["creditCardCKRecordName"] as? String
            logWarning("[StmtSync] Incoming statement: ckName=\(record.recordID.recordName), creditCardId=\(stmt.creditCardId), creditCardCKRecordName=\(hasCKCardName ?? "nil"), closingDate=\(stmt.closingDate)")
            resolver.resolveCreditCardStatement(remote: stmt, ckRecord: record)
        case "BudgetAllocation":
            guard let alloc = BudgetAllocationModel.fromCKRecord(record) else { return }
            resolver.resolveBudgetAllocation(remote: alloc, ckRecord: record)
        case "GroupActivity":
            processGroupActivity(record)
        case "GroupMember":
            processIncomingGroupMember(record)
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

    /// Remaps local auto-increment IDs (creditCardId, statementId) in the CKRecord
    /// using stored CK record names, so the receiving device gets correct local references.
    private func remapCrossDeviceIDs(in record: CKRecord) {
        Self.remapCrossDeviceIDs(in: record, db: .shared)
    }

    /// Static, database-injectable form so the two-device test harness can reproduce the real pull
    /// path faithfully instead of approximating it. Behaviour is unchanged.
    static func remapCrossDeviceIDs(in record: CKRecord, db: DBHelper) {
        let cardRepo = CreditCardRepository(db: db)
        let stmtRepo = StatementRepository(db: db)

        switch record.recordType {
        case "CreditCardStatement":
            let cardCKName = record["creditCardCKRecordName"] as? String
            let remoteCardId = record["creditCardId"] as? Int ?? -1
            if let cardCKName = cardCKName,
               let localCard = cardRepo.fetchCard(byCKRecordName: cardCKName),
               let localCardId = localCard.id {
                if localCardId != remoteCardId {
                    logWarning("[StmtSync] Remapped statement creditCardId: \(remoteCardId) → \(localCardId) (via \(cardCKName))")
                }
                record["creditCardId"] = localCardId as CKRecordValue
            } else {
                logWarning("[StmtSync] Cannot remap statement creditCardId=\(remoteCardId) — creditCardCKRecordName=\(cardCKName ?? "nil"), card exists=\(cardCKName.flatMap { cardRepo.fetchCard(byCKRecordName: $0) } != nil)")
            }

        case "Transaction":
            if let cardCKName = record["creditCardCKRecordName"] as? String,
               let localCard = cardRepo.fetchCard(byCKRecordName: cardCKName),
               let localCardId = localCard.id {
                let remoteCardId = record["creditCardId"] as? Int ?? -1
                if localCardId != remoteCardId {
                    logWarning("[Sync] Remapped transaction creditCardId: \(remoteCardId) → \(localCardId)")
                }
                record["creditCardId"] = localCardId as CKRecordValue
            }
            // If creditCardCKRecordName is nil, the remote creditCardId stays as-is.
            // CCRepair will detect it as orphaned (no matching local card) and reassign it.

            if let stmtCKName = record["statementCKRecordName"] as? String,
               let localStmt = stmtRepo.fetchStatement(byCKRecordName: stmtCKName),
               let localStmtId = localStmt.id {
                let remoteStmtId = record["statementId"] as? Int ?? -1
                if localStmtId != remoteStmtId {
                    logWarning("[Sync] Remapped transaction statementId: \(remoteStmtId) → \(localStmtId)")
                }
                record["statementId"] = localStmtId as CKRecordValue
            }

        default:
            break
        }
    }

    /// Whether a deletion reported from `recordID.zoneID` refers to the local row that holds that
    /// record name — or merely to a DIFFERENT COPY that happens to share it.
    ///
    /// CloudKit record names are unique per ZONE, not globally. The same name legitimately exists in
    /// two zones at once, which is the property Transparent Mode is built on and the property a
    /// record moving zones passes through. `processDeletedRecord` used to discard `recordID.zoneID`
    /// and delete by name alone, so a deletion aimed at one copy destroyed the other. Two ways that
    /// bites, both of them data loss:
    ///
    ///   1. A row restored from a group back to personal is pushed to the private zone, and its old
    ///      group-zone copy is correctly withdrawn (`staleZoneCopy`). The push side already protects
    ///      the local row via `orphanDeleteNames` — but when that withdrawal came back on a later
    ///      fetch, the row now living in the private zone was deleted under the shared name. This is
    ///      what emptied a restored personal ledger.
    ///   2. Revoking Transparent Mode deletes a projection from a group zone. That deletion would
    ///      take the author's personal row with it.
    ///
    /// So the zone has to be honoured: a deletion applies only when the local row's scope is the
    /// scope that zone represents. Personal zone ↔ `shared_group_id IS NULL`; `Group-X` ↔ `X`.
    static func deletionTargetsLocalRow(
        recordID: CKRecord.ID, table: String, db: DBHelper
    ) -> Bool {
        let zoneName = recordID.zoneID.zoneName
        let deletionScope: String? = zoneName.hasPrefix("Group-")
            ? String(zoneName.dropFirst("Group-".count))
            : nil

        let local = db.rowScope(table: table, ckRecordName: recordID.recordName)
        // No local row: nothing to protect, and the repositories are no-ops anyway. Let it through so
        // tombstone bookkeeping still runs.
        guard local.exists else { return true }

        let applies = (local.sharedGroupId ?? "") == (deletionScope ?? "")
        if !applies {
            logWarning("""
                [Sync] Ignoring deletion of \(recordID.recordName) from zone \(zoneName) — the local \
                row's scope is \(local.sharedGroupId ?? "personal"), so that deletion refers to a \
                different copy of the same record name, not to this row.
                """)
        }
        return applies
    }

    private func processDeletedRecord(recordID: CKRecord.ID, recordType: String) {
        guard let table = Self.revTable(forRecordType: recordType),
              Self.deletionTargetsLocalRow(recordID: recordID, table: table, db: db)
        else { return }

        switch recordType {
        case "Transaction":
            TransactionRepository(db: db).deleteFromCloud(ckRecordName: recordID.recordName)
        case "Budget":
            BudgetRepository(db: db).deleteFromCloud(ckRecordName: recordID.recordName)
        case "CreditCard":
            CreditCardRepository(db: db).deleteFromCloud(ckRecordName: recordID.recordName)
        case "CreditCardStatement":
            StatementRepository(db: db).deleteFromCloud(ckRecordName: recordID.recordName)
        case "BudgetAllocation":
            BudgetAllocationRepository(db: db).deleteFromCloud(ckRecordName: recordID.recordName)
        default:
            break
        }
    }

    /// After a full re-fetch (reset sync), removes local records that have a ck_record_id
    /// but were not seen in the CloudKit fetch — meaning they were deleted on another device.
    private func cleanupOrphanedRecords() {
        // SAFETY (group data): orphan cleanup deletes local rows whose ck_record_id wasn't seen
        // in the pull. Shared-database (group zone) fetches can silently under-deliver, so a
        // member's valid group records would be wrongly treated as orphans and deleted. Since
        // this only runs on an explicit cloud-reset, skip it entirely when the account belongs
        // to any group — deletes still propagate through the normal inbound-delete path. Solo
        // accounts (no shared zones to partially fetch) keep the cleanup.
        if !BudgetGroupService.shared.fetchAllGroups().isEmpty {
            logWarning("[Sync] Orphan cleanup SKIPPED — account is in one or more groups; shared-zone fetches can under-deliver and cleanup could delete valid group records")
            return
        }

        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]

        // Safety: count total local synced records across all tables.
        let totalLocalSynced = tables.reduce(0) { $0 + db.fetchAllCKRecordNames(table: $1).count }

        // Guard against partial CloudKit fetches (network issues, zone unavailability, schema errors).
        // If CK returned significantly fewer records than we have locally, the pull was likely incomplete —
        // running cleanup would incorrectly delete valid local data. Allow up to 25% discrepancy for
        // records that are legitimately only local (newly created, not yet pushed). Hard limit: never
        // delete more than 30% of local records in a single cleanup pass.
        if totalLocalSynced > 0 {
            let orphanCandidates = tables.reduce(0) { count, table in
                let localNames = db.fetchAllCKRecordNames(table: table)
                return count + localNames.filter { !pulledCKRecordNames.contains($0) }.count
            }
            let orphanRatio = Double(orphanCandidates) / Double(totalLocalSynced)
            if orphanRatio > 0.30 {
                logWarning("[Sync] ⚠️ Orphan cleanup SKIPPED — \(orphanCandidates)/\(totalLocalSynced) local records (\(Int(orphanRatio * 100))%) not in pull. This likely indicates an incomplete CloudKit fetch. Aborting to prevent data loss.")
                return
            }
        }

        var totalOrphans = 0
        for table in tables {
            let localNames = db.fetchAllCKRecordNames(table: table)
            let orphans = localNames.filter { !pulledCKRecordNames.contains($0) }
            logWarning("[Sync] Orphan check \(table): \(localNames.count) local record(s) with ck_record_id, \(orphans.count) orphan(s)")
            if !orphans.isEmpty {
                logWarning("[Sync] Cleaning up \(orphans.count) orphaned record(s) from \(table): \(orphans.prefix(10))")
                db.deleteOrphanedRecords(table: table, ckRecordNames: orphans)
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

    private func processIncomingGroupMember(_ record: CKRecord) {
        guard let groupId = record["groupId"] as? String,
              let userId = record["userId"] as? String,
              let name = record["name"] as? String,
              let email = record["email"] as? String
        else {
            logError("[Sync] Failed to parse GroupMember from CKRecord \(record.recordID.recordName)")
            return
        }

        let isRemoved = (record["isRemoved"] as? Int ?? 0) == 1
        let roleStr = record["role"] as? String ?? "member"
        let role = GroupRole(rawValue: roleStr) ?? .member
        let joinedAt = record["joinedAt"] as? Date ?? record.creationDate ?? Date()
        let permissions: GroupPermissions
        if let permJSON = record["permissions"] as? String {
            permissions = GroupPermissions.fromJSON(permJSON)
        } else {
            permissions = role == .owner ? .fullAccess : .memberDefault
        }

        let repo = BudgetGroupRepository(db: db)

        // Handle removal flag
        if isRemoved {
            let currentUserId = AuthenticationManager.shared.currentUser?.uid
            if userId == currentUserId {
                // Current user was removed — soft-delete the group locally
                logInfo("[Sync] Current user was removed from group \(groupId) — cleaning up")
                repo.softDeleteGroup(id: groupId)
                repo.removeMember(id: record.recordID.recordName.replacingOccurrences(of: "groupMember-", with: ""))

                // The group's zone is gone, so its projections can never be withdrawn from it.
                // Forget them, or every subsequent push retries a delete that cannot succeed.
                db.deleteProjectionState(zoneName: "Group-\(groupId)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
                }
            } else {
                // Another member was removed — mark them locally
                let existingMembers = repo.fetchMembers(forGroupId: groupId)
                if let existing = existingMembers.first(where: { $0.userId == userId }) {
                    repo.removeMember(id: existing.id)
                    logInfo("[Sync] Marked member \(name) as removed in group \(groupId)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
                    }
                }
            }
            return
        }

        // Check for duplicate member INCLUDING removed ones (is_removed=1) to avoid
        // re-inserting a member who was previously removed and then re-invited
        let allMembers = repo.fetchMembersIncludingRemoved(forGroupId: groupId)
        if let existing = allMembers.first(where: { $0.userId == userId || (!email.isEmpty && $0.email == email) || ($0.role == role && role == .owner) }) {
            // Reactivate if removed, or update with better data from CloudKit
            var updated = existing
            updated.userId = userId
            updated.name = name
            updated.email = email
            updated.permissions = permissions
            updated.isRemoved = false
            if existing.userId != userId || existing.name != name || existing.isRemoved || existing.permissions != permissions {
                repo.updateMember(updated)
                logInfo("[Sync] Updated/reactivated GroupMember \(name) in group \(groupId) (permissions updated)")
            } else {
                logInfo("[Sync] GroupMember \(name) already exists in group \(groupId) — skipping")
            }
            return
        }

        let member = GroupMember(
            groupId: groupId,
            userId: userId,
            name: name,
            email: email,
            role: role,
            permissions: permissions,
            joinedAt: joinedAt
        )
        repo.insertMember(member)
        logInfo("[Sync] Inserted GroupMember \(name) into group \(groupId) from CloudKit")

        // Owner-side invitation cleanup: this member is now confirmed in the group, so their public
        // invitation record is obsolete. Only the owner (who created it) can delete it — the
        // invitee's own status update always fails — so without this the record lingers in the
        // world-readable public database forever, still marked "pending".
        if !email.isEmpty,
           userId != AuthenticationManager.shared.currentUser?.uid,
           let group = repo.fetchGroup(byId: groupId), group.isOwner {
            BudgetGroupService.shared.deletePublicInvitations(forGroupId: groupId, inviteeEmail: email)
        }

        // Clear the one-time repair flag so Fix 6a can re-attempt if another member joins later
        UserDefaults.standard.removeObject(forKey: "memberRepairAttempted-\(groupId)")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
        }
    }

    private func processGroupActivity(_ record: CKRecord) {
        let action = record["action"] as? String ?? "unknown"
        let actorName = record["actorName"] as? String ?? "unknown"
        logWarning("[Sync] processGroupActivity: action=\(action) actor=\(actorName) record=\(record.recordID.recordName)")
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
            let cloudDate = record["updatedAt"] as? Date ?? record.modificationDate ?? .distantPast

            if key == "personal" {
                let current = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
                let localTs = UserDefaults.standard.double(forKey: "balanceOffset_\(uid)_localTs")

                if current != offset {
                    // If local change is newer than the cloud record, keep local
                    if localTs > 0 && Date(timeIntervalSince1970: localTs) > cloudDate {
                        logInfo("Balance offset from sync: local personal (\(current)) is newer — keeping local")
                    } else {
                        UserDefaults.standard.set(offset, forKey: "balanceOffset_\(uid)")
                        UserDefaults.standard.removeObject(forKey: "balanceOffset_\(uid)_localTs")
                        logInfo("Balance offset updated from sync: personal = \(offset)")
                        didUpdate = true
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: "balanceOffset_\(uid)_localTs")
                }
            } else if key.hasPrefix("group-") {
                let groupId = String(key.dropFirst("group-".count))
                let current = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(groupId)")
                let localTs = UserDefaults.standard.double(forKey: "balanceOffset_group_\(groupId)_localTs")

                if current != offset {
                    if localTs > 0 && Date(timeIntervalSince1970: localTs) > cloudDate {
                        logInfo("Balance offset from sync: local group-\(groupId) (\(current)) is newer — keeping local")
                    } else {
                        UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(groupId)")
                        UserDefaults.standard.removeObject(forKey: "balanceOffset_group_\(groupId)_localTs")
                        logInfo("Balance offset updated from sync: \(key) = \(offset)")
                        didUpdate = true
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: "balanceOffset_group_\(groupId)_localTs")
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
        let repo = BudgetGroupRepository(db: db)
        let existingGroups = repo.fetchAllGroups()

        // Include soft-deleted group IDs so they aren't "rediscovered" during sync.
        // Only acceptInvitation should restore a deleted group.
        let allGroupRows = db.fetchBudgetGroupRows(
            "SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, ck_zone_owner, created_at, updated_at, is_deleted FROM BudgetGroups"
        )
        let allLocalGroupIds = Set(allGroupRows.map { $0.id })

        let currentUID = AuthenticationManager.shared.currentUser?.uid ?? "nil"
        logWarning("[GROUPDIAG] discoverGroupsFromAllZones: \(existingGroups.count) active, \(allLocalGroupIds.count) total local group(s), currentUID=\(currentUID)")
        for g in allGroupRows {
            logWarning("[GROUPDIAG] localGroup name='\(g.name)' id=\(g.id) owner=\(g.ownerId) isOwner=\(g.isOwner) isDeleted=\(g.isDeleted) ckRecord=\(g.ckRecordId ?? "nil") ckZoneOwner=\(g.ckZoneOwner ?? "nil") ckShare=\(g.ckShareUrl ?? "nil")")
        }

        var newGroupZoneIDs: [CKRecordZone.ID] = []
        var unfetchedZoneIDs: [CKRecordZone.ID] = []

        var allZoneNames: [String] = []

        cloudKitOps.fetchAllZones(database: .private) { [weak self, db] result in
            if case .success(let zoneIDs) = result {
                for zoneID in zoneIDs {
                    allZoneNames.append(zoneID.zoneName)
                    guard zoneID.zoneName.hasPrefix("Group-") else { continue }
                    let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
                    if !allLocalGroupIds.contains(groupId) {
                        newGroupZoneIDs.append(zoneID)
                        logWarning("[Sync] Discovered missing group zone: \(zoneID.zoneName)")
                    } else if self?.stateManager.changeToken(for: zoneID.zoneName, database: "private") == nil {
                        // Group exists locally but zone changes were never fetched
                        unfetchedZoneIDs.append(zoneID)
                        logWarning("[Sync] Group zone exists but never fetched: \(zoneID.zoneName)")
                    }
                }
            }
            switch result {
            case .success:
                logWarning("[GROUPDIAG] cloud private zones: \(allZoneNames)")
                logWarning("[GROUPDIAG] zone enumeration — \(newGroupZoneIDs.count) new, \(unfetchedZoneIDs.count) unfetched group zone(s)")

                // Detect local owned groups whose CloudKit zones are missing and need repair.
                // This covers two cases:
                // 1. Groups that previously had a CK record but lost their zone (ckRecordId != nil)
                // 2. Groups where createCloudKitShare failed entirely (ckRecordId == nil, no zone ever created)
                let foundGroupZoneIds = Set(
                    allZoneNames
                        .filter { $0.hasPrefix("Group-") }
                        .map { String($0.dropFirst("Group-".count)) }
                )
                let orphanedGroups = existingGroups.filter { group in
                    group.isOwner && !foundGroupZoneIds.contains(group.id)
                }
                if !orphanedGroups.isEmpty {
                    logWarning("[Sync] Found \(orphanedGroups.count) local group(s) with missing CloudKit zones — repairing")
                }

                // Fix 6a: Reset zone tokens for owned groups with incomplete member lists.
                // When a member writes a GroupMember record to the shared DB, CloudKit
                // propagates it to the owner's private zone — but if the zone token has
                // already advanced past that point, the record is never re-fetched.
                // Only attempt this once per group to avoid re-fetching 100+ records every sync.
                for group in existingGroups where group.isOwner && !group.isDeleted && foundGroupZoneIds.contains(group.id) {
                    let localMemberCount = repo.fetchMembers(forGroupId: group.id).count
                    let repairKey = "memberRepairAttempted-\(group.id)"
                    let alreadyAttempted = UserDefaults.standard.bool(forKey: repairKey)
                    if localMemberCount <= 1 && !alreadyAttempted {
                        UserDefaults.standard.set(true, forKey: repairKey)
                        let zoneKey = "Group-\(group.id)"
                        self?.stateManager.saveChangeToken(nil, for: zoneKey, database: "private")
                        let zoneID = CKRecordZone.ID(zoneName: zoneKey, ownerName: CKCurrentUserDefaultName)
                        if !unfetchedZoneIDs.contains(where: { $0.zoneName == zoneKey }) {
                            unfetchedZoneIDs.append(zoneID)
                        }
                        logWarning("[Sync] Reset zone token for \(zoneKey) — only \(localMemberCount) member(s), forcing re-fetch (one-time repair)")
                    }
                }

                // For owned groups, ensure pending invitations in the public DB have the share URL
                // Re-fetch groups from DB to get the latest ckShareUrl (may have been updated by prior sync)
                let freshGroups = BudgetGroupRepository(db: db).fetchAllGroups()
                for group in freshGroups where group.isOwner {
                    let hasZone = foundGroupZoneIds.contains(group.id)
                    logWarning("[Sync] Owner group '\(group.name)': hasZone=\(hasZone), ckShareUrl=\(group.ckShareUrl ?? "nil"), ckRecordId=\(group.ckRecordId ?? "nil")")

                    if hasZone, let shareUrl = group.ckShareUrl, !shareUrl.isEmpty {
                        logWarning("[Sync] Propagating share URL to invitations for group '\(group.name)'")
                        BudgetGroupService.shared.propagateShareUrl(groupId: group.id, newUrl: shareUrl)
                    } else if hasZone && (group.ckShareUrl == nil || group.ckShareUrl?.isEmpty == true) {
                        logWarning("[Sync] Group '\(group.name)' has zone but no share URL — creating share")
                        self?.fetchShareUrlFromZone(group: group, zoneIds: foundGroupZoneIds)
                    } else if !hasZone {
                        logWarning("[Sync] Group '\(group.name)' has NO zone — will be handled by repairMissingGroupZones")
                    }
                }

                let continueAfterRepair = {
                    let handleUnfetchedZones = {
                        guard !unfetchedZoneIDs.isEmpty else {
                            self?.discoverGroupsFromSharedDatabase(
                                existingGroupIds: allLocalGroupIds,
                                completion: completion
                            )
                            return
                        }
                        logWarning("[Sync] Fetching zone changes for \(unfetchedZoneIDs.count) previously unfetched group zone(s)")
                        self?.fetchZoneChanges(zoneIDs: unfetchedZoneIDs, database: .private) { _ in
                            self?.discoverGroupsFromSharedDatabase(
                                existingGroupIds: allLocalGroupIds,
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
                    existingGroupIds: allLocalGroupIds,
                    completion: completion
                )
            }
        }
    }

    /// Discovers group zones in the shared database (zones shared by other iCloud accounts).
    private func discoverGroupsFromSharedDatabase(
        existingGroupIds: Set<String>,
        completion: @escaping () -> Void
    ) {
        var sharedGroupZoneIDs: [CKRecordZone.ID] = []
        var sharedUnfetchedZoneIDs: [CKRecordZone.ID] = []
        var foundSharedGroupIds: Set<String> = []

        cloudKitOps.fetchAllZones(database: .shared) { [weak self, db] result in
            if case .success(let zoneIDs) = result {
                for zoneID in zoneIDs {
                    logWarning("[Sync] Shared DB zone found: \(zoneID.zoneName) (owner: \(zoneID.ownerName))")
                    guard zoneID.zoneName.hasPrefix("Group-") else { continue }
                    let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
                    foundSharedGroupIds.insert(groupId)
                    // Backfill: store zone owner name for existing groups that don't have it yet
                    BudgetGroupRepository(db: db).updateZoneOwner(groupId: groupId, zoneOwner: zoneID.ownerName)
                    if !existingGroupIds.contains(groupId) {
                        sharedGroupZoneIDs.append(zoneID)
                        logWarning("[Sync] Discovered missing shared group zone: \(zoneID.zoneName)")
                    } else if self?.stateManager.changeToken(for: zoneID.zoneName, database: "shared") == nil {
                        sharedUnfetchedZoneIDs.append(zoneID)
                        logWarning("[Sync] Shared group zone exists but never fetched: \(zoneID.zoneName)")
                    }
                }
            }
            switch result {
            case .success:
                // Check for member groups with accepted share but no data (empty group),
                // or placeholder groups that need their real data fetched.
                // This handles the case where the initial fetch after CKShare acceptance
                // only returned the share metadata due to CloudKit propagation delay.
                let repo = BudgetGroupRepository(db: db)
                let txRepo = TransactionRepository(db: db)
                let placeholderNames: Set<String> = ["Group", "Shared Group"]
                for groupId in foundSharedGroupIds {
                    if let group = repo.fetchGroup(byId: groupId),
                       !group.isOwner,
                       group.ckZoneOwner != nil {
                        let isPlaceholder = placeholderNames.contains(group.name)
                        let groupTxCount = txRepo.fetchTransactionsForGroup(groupId: groupId).count
                        if groupTxCount == 0 || isPlaceholder {
                            logWarning("[Sync] Member group '\(group.name)' needs re-fetch (txCount=\(groupTxCount), isPlaceholder=\(isPlaceholder)) — resetting token")
                            let zoneName = "Group-\(groupId)"
                            self?.stateManager.saveChangeToken(nil, for: zoneName, database: "shared")
                            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: group.ckZoneOwner!)
                            if !sharedUnfetchedZoneIDs.contains(where: { $0.zoneName == zoneName }) {
                                sharedUnfetchedZoneIDs.append(zoneID)
                            }
                        }
                    }
                }

                logWarning("[Sync] Shared DB zone enumeration complete — \(sharedGroupZoneIDs.count) new, \(sharedUnfetchedZoneIDs.count) unfetched group zone(s)")

                let finishDiscovery = {
                    // Fix 6c: For owned groups, query the shared DB directly for GroupMember
                    // records. This catches member writes that haven't propagated to the
                    // owner's private DB zone yet (CloudKit shared→private propagation delay).
                    self?.discoverMembersFromSharedDB {
                        // After all zone fetching, check for member groups that need CKShare repair
                        self?.repairMissingShareAcceptance(sharedZoneGroupIds: foundSharedGroupIds) {
                            completion()
                        }
                    }
                }

                let handleSharedUnfetched = {
                    guard !sharedUnfetchedZoneIDs.isEmpty else {
                        finishDiscovery()
                        return
                    }
                    logWarning("[Sync] Fetching zone changes for \(sharedUnfetchedZoneIDs.count) shared group zone(s)")
                    self?.fetchZoneChanges(zoneIDs: sharedUnfetchedZoneIDs, database: .shared) { _ in
                        finishDiscovery()
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
                // Still try share repair even if enumeration failed
                self?.repairMissingShareAcceptance(sharedZoneGroupIds: []) {
                    completion()
                }
            }
        }
    }

    /// Queries owned group zones directly for GroupMember records, catching member writes that the
    /// zone-level change token has already advanced past.
    ///
    /// These zones live in the OWNER's private database. The operation used to be added to
    /// `sharedDatabase`, which fails unconditionally with "Only shared zones can be accessed in the
    /// shared DB" — so this repair never actually ran a single time since it was written.
    private func discoverMembersFromSharedDB(completion: @escaping () -> Void) {
        let repo = BudgetGroupRepository(db: db)
        let ownedGroups = repo.fetchAllGroups().filter { $0.isOwner && !$0.isDeleted }

        guard !ownedGroups.isEmpty else {
            completion()
            return
        }

        let dispatchGroup = DispatchGroup()

        for group in ownedGroups {
            dispatchGroup.enter()

            let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
            // Private DB: `zoneID` above is the owner's own zone (ownerName == CKCurrentUserDefaultName),
            // and own zones are never reachable through the shared database.
            cloudKitOps.queryRecords(
                recordType: "GroupMember",
                zoneID: zoneID,
                database: .private,
                recordHandler: { [weak self] record in self?.processIncomingGroupMember(record) }
            ) { result in
                if case .failure(let error) = result {
                    logWarning("[Sync] Owned-zone member query failed for group \(group.id): \(error.localizedDescription)")
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .global(qos: .utility)) {
            completion()
        }
    }

    /// Re-creates CloudKit zones and BudgetGroup records for local groups whose zones
    /// have gone missing from CloudKit. This repairs the state so other devices can discover them.
    private func repairMissingGroupZones(_ groups: [BudgetGroup], completion: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()

        for group in groups {
            guard !group.isDeleted else {
                logWarning("[Sync] Skipping repair for soft-deleted group '\(group.name)'")
                continue
            }
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

                    // Zone-based share: shares ALL records in the zone
                    let share = CKShare(recordZoneID: zoneID)
                    share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
                    // SECURITY: invited participants only — `.readWrite` here would make the share
                    // URL a bearer token for the group's financial data. See
                    // BudgetGroupService.createShareRecord.
                    share.publicPermission = .none

                    let saveOp = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
                    // Fresh CKRecord with no recordChangeTag: the default `.ifServerRecordUnchanged`
                    // fails with `serverRecordChanged` if a BudgetGroup record already exists in the
                    // re-created zone, silently aborting the repair.
                    saveOp.savePolicy = .allKeys
                    saveOp.modifyRecordsResultBlock = { saveResult in
                        switch saveResult {
                        case .success:
                            // Update local share URL and ckRecordId
                            var updated = group
                            updated.ckRecordId = recordID.recordName
                            if let newShareURL = share.url?.absoluteString {
                                updated.ckShareUrl = newShareURL
                                logWarning("[Sync] Group '\(group.name)' repaired — new share URL: \(newShareURL)")

                                // Propagate new share URL to pending invitations in public DB
                                BudgetGroupService.shared.propagateShareUrl(groupId: group.id, newUrl: newShareURL)
                            } else {
                                logWarning("[Sync] Group '\(group.name)' repaired (no share URL returned)")
                            }
                            BudgetGroupRepository(db: self.db).updateGroup(updated)
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

    /// Retries CKShare acceptance for member groups that have no shared zone access.
    /// This handles the case where invitation acceptance succeeded locally but the CKShare
    /// acceptance failed (e.g., share URL was missing, network error, or stale URL).
    private func repairMissingShareAcceptance(
        sharedZoneGroupIds: Set<String>,
        completion: @escaping () -> Void
    ) {
        let repo = BudgetGroupRepository(db: db)
        let activeGroups = repo.fetchAllGroups()

        // Find member groups (not owner) that have no shared zone access
        let groupsNeedingRepair = activeGroups.filter { group in
            !group.isOwner && !sharedZoneGroupIds.contains(group.id)
        }

        guard !groupsNeedingRepair.isEmpty else {
            completion()
            return
        }

        logWarning("[Sync] Found \(groupsNeedingRepair.count) member group(s) without shared zone access — attempting CKShare repair")

        let dispatchGroup = DispatchGroup()

        for group in groupsNeedingRepair {
            dispatchGroup.enter()

            // Try to find the share URL: first from local group, then from local invitations, then from public DB
            let shareUrl = group.ckShareUrl
                ?? self.findLocalInvitationShareUrl(forGroupId: group.id)

            if let urlString = shareUrl, let url = URL(string: urlString) {
                logWarning("[Sync] Attempting CKShare acceptance for group '\(group.name)' with URL: \(urlString)")
                self.attemptShareRepair(url: url, group: group) {
                    dispatchGroup.leave()
                }
            } else {
                // No local share URL — query public DB
                logWarning("[Sync] No local share URL for group '\(group.name)' — querying public DB")
                self.fetchShareUrlFromPublicDB(forGroupId: group.id) { [weak self] fetchedUrl in
                    if let urlString = fetchedUrl, let url = URL(string: urlString) {
                        logWarning("[Sync] Found share URL from public DB for group '\(group.name)': \(urlString)")
                        self?.attemptShareRepair(url: url, group: group) {
                            dispatchGroup.leave()
                        }
                    } else {
                        logWarning("[Sync] No share URL found for group '\(group.name)' — cannot repair")
                        dispatchGroup.leave()
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .global(qos: .utility)) {
            completion()
        }
    }

    private func findLocalInvitationShareUrl(forGroupId groupId: String) -> String? {
        let query = """
            SELECT ck_share_url FROM GroupInvitations
            WHERE group_id = ? AND ck_share_url IS NOT NULL AND ck_share_url != ''
            ORDER BY created_at DESC LIMIT 1
            """
        // Use raw SQL fetch since we just need one string
        let invitations = db.fetchGroupInvitationRows(
            "SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at FROM GroupInvitations WHERE group_id = ? AND ck_share_url IS NOT NULL AND ck_share_url != ''",
            textBindings: [groupId]
        )
        return invitations.first?.ckShareUrl
    }

    private func fetchShareUrlFromPublicDB(forGroupId groupId: String, completion: @escaping (String?) -> Void) {
        guard let currentUser = AuthenticationManager.shared.currentUser,
              let email = currentUser.email else {
            completion(nil)
            return
        }

        // Fix 1c: Also query by Firebase UID to handle invitations stored with UID-based matching
        let uid = currentUser.uid
        let predicate = NSPredicate(format: "inviteeEmail == %@ OR inviteeId == %@", email, uid)
        let query = CKQuery(recordType: "GroupInvitation", predicate: predicate)

        CloudKitManager.shared.publicDatabase.fetch(withQuery: query, desiredKeys: ["ckShareUrl", "groupId"]) { result in
            switch result {
            case .success(let (matchResults, _)):
                for (_, recordResult) in matchResults {
                    if case .success(let record) = recordResult,
                       let recordGroupId = record["groupId"] as? String,
                       recordGroupId == groupId,
                       let url = record["ckShareUrl"] as? String, !url.isEmpty {
                        completion(url)
                        return
                    }
                }
                completion(nil)
            case .failure(let error):
                logError("[Sync] Failed to fetch share URL from public DB: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    private func attemptShareRepair(url: URL, group: BudgetGroup, completion: @escaping () -> Void) {
        CloudKitManager.shared.container.fetchShareMetadata(with: url) { [weak self, db] metadata, error in
            guard let metadata = metadata else {
                logError("[Sync] CKShare metadata fetch failed for group '\(group.name)': \(error?.localizedDescription ?? "unknown")")
                completion()
                return
            }

            CloudKitManager.shared.container.accept(metadata) { share, error in
                if let error = error {
                    logError("[Sync] CKShare acceptance failed for group '\(group.name)': \(error.localizedDescription)")
                } else if let share = share {
                    let ownerName = share.recordID.zoneID.ownerName
                    logWarning("[Sync] CKShare accepted for group '\(group.name)' — zone owner: \(ownerName)")

                    let repo = BudgetGroupRepository(db: db)
                    repo.updateZoneOwner(groupId: group.id, zoneOwner: ownerName)

                    // Also store the share URL locally
                    if var updated = repo.fetchGroup(byId: group.id) {
                        updated.ckShareUrl = url.absoluteString
                        repo.updateGroup(updated)
                    }

                    // Push member record so owner can see us
                    if let currentUser = AuthenticationManager.shared.currentUser {
                        let member = GroupMember(
                            groupId: group.id,
                            userId: currentUser.uid,
                            name: UserDefaultsManager.getUser()?.name ?? currentUser.displayName ?? "User",
                            email: currentUser.email ?? "",
                            role: .member,
                            permissions: .memberDefault,
                            lastActive: Date()
                        )
                        BudgetGroupService.shared.pushGroupMemberRecord(
                            member: member,
                            groupId: group.id,
                            zoneOwner: ownerName
                        ) { _ in }
                    }

                    // Fetch shared data from the group zone
                    self?.syncSharedGroupData(groupId: group.id, zoneOwner: ownerName)
                }
                completion()
            }
        }
    }

    /// Re-creates the CKShare for a group zone when `ckShareUrl` is nil.
    /// Runs entirely on the main queue to avoid CK callback nesting issues.
    private func fetchShareUrlFromZone(group: BudgetGroup, zoneIds: Set<String>) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)

        logWarning("[Sync] Creating zone share for group '\(group.name)' (zone exists but no share URL)")

        let recordID = CKRecord.ID(recordName: "budgetGroup-\(group.id)", zoneID: zoneID)
        let record = CKRecord(recordType: "BudgetGroup", recordID: recordID)
        record["name"] = group.name as CKRecordValue
        record["ownerId"] = group.ownerId as CKRecordValue
        record["ownerName"] = group.ownerName as CKRecordValue
        record["ownerEmail"] = group.ownerEmail as CKRecordValue

        let newShare = CKShare(recordZoneID: zoneID)
        newShare[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        // SECURITY: invited participants only — see BudgetGroupService.createShareRecord.
        newShare.publicPermission = .none

        let saveOp = CKModifyRecordsOperation(recordsToSave: [record, newShare], recordIDsToDelete: nil)
        saveOp.savePolicy = .allKeys
        var savedShareUrl: String?
        saveOp.perRecordSaveBlock = { _, result in
            switch result {
            case .success(let savedRecord):
                if let savedShare = savedRecord as? CKShare,
                   let url = savedShare.url?.absoluteString {
                    savedShareUrl = url
                    logWarning("[Sync] perRecordSave: got share URL for '\(group.name)': \(url)")
                }
            case .failure(let err):
                logError("[Sync] perRecordSave failed for '\(group.name)': \(err.localizedDescription)")
            }
        }
        saveOp.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                let url = savedShareUrl ?? newShare.url?.absoluteString
                if let url = url, !url.isEmpty {
                    logWarning("[Sync] Re-created CKShare for group '\(group.name)' — URL: \(url)")
                    var updated = group
                    updated.ckShareUrl = url
                    updated.ckRecordId = recordID.recordName
                    BudgetGroupRepository(db: self.db).updateGroup(updated)
                    BudgetGroupService.shared.propagateShareUrl(groupId: group.id, newUrl: url)
                } else {
                    logWarning("[Sync] CKShare saved for group '\(group.name)' but URL is nil (savedShareUrl=\(savedShareUrl ?? "nil"), newShare.url=\(newShare.url?.absoluteString ?? "nil"))")
                }
            case .failure(let err):
                logError("[Sync] Failed to create CKShare for group '\(group.name)': \(err.localizedDescription)")
            }
        }
        saveOp.qualityOfService = .userInitiated
        logWarning("[Sync] Adding CKShare save operation for group '\(group.name)'")
        CloudKitManager.shared.privateDatabase.add(saveOp)
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
                    // A SHARED zone with no readable BudgetGroup record still means real membership
                    // (we only see the zone because we accepted its CKShare), so make it visible.
                    //
                    // A PRIVATE zone with no BudgetGroup record is different: the record is deleted
                    // along with the zone when an owner deletes a group, so a leftover zone with no
                    // record is a group that's gone — inventing a "Group" placeholder for it
                    // resurrected phantom groups on every fresh install. Groups that legitimately
                    // exist locally but lost their record are handled by repairMissingGroupZones,
                    // which recreates it.
                    if database == .shared {
                        self?.createPlaceholderGroup(groupId: groupId, zoneID: zoneID)
                    } else {
                        logWarning("[Sync] Skipping placeholder for private zone '\(zoneID.zoneName)' — no BudgetGroup record means the group was deleted")
                    }
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
    /// Uses zone ownership to determine if the current user is the owner or a member.
    private func createPlaceholderGroup(groupId: String, zoneID: CKRecordZone.ID) {
        let repo = BudgetGroupRepository(db: db)
        guard repo.fetchGroup(byId: groupId) == nil else { return }
        guard let uid = AuthenticationManager.shared.currentUser?.uid else { return }

        let userName = UserDefaultsManager.getUser()?.name ?? "User"
        let userEmail = AuthenticationManager.shared.currentUser?.email ?? ""

        // Determine ownership: if the zone owner is the current user (CKCurrentUserDefaultName),
        // this device owns the group. Otherwise, this is a shared zone from another user.
        let isCurrentUserOwner = zoneID.ownerName == CKCurrentUserDefaultName

        var group = BudgetGroup(
            id: groupId,
            name: "Group",
            ownerId: isCurrentUserOwner ? uid : "",
            ownerName: isCurrentUserOwner ? userName : "",
            ownerEmail: isCurrentUserOwner ? userEmail : ""
        )

        // Set ckZoneOwner for shared zones so subsequent fetchSharedDatabaseChanges
        // can include this zone in the fetch list
        if !isCurrentUserOwner {
            group.ckZoneOwner = zoneID.ownerName
        }

        repo.insertGroup(group)

        // Add current user as member with correct role
        let allMembers = repo.fetchMembersIncludingRemoved(forGroupId: groupId)
        if let existing = allMembers.first(where: { $0.userId == uid }) {
            if existing.isRemoved {
                var updated = existing
                updated.isRemoved = false
                repo.updateMember(updated)
            }
        } else {
            let member = GroupMember(
                groupId: groupId,
                userId: uid,
                name: userName,
                email: userEmail,
                role: isCurrentUserOwner ? .owner : .member,
                permissions: isCurrentUserOwner ? .fullAccess : .memberDefault
            )
            repo.insertMember(member)
        }
        logInfo("[Sync] Created placeholder BudgetGroup for group \(groupId) (isOwner=\(isCurrentUserOwner), ckZoneOwner=\(isCurrentUserOwner ? "self" : zoneID.ownerName))")

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

        let repo = BudgetGroupRepository(db: db)
        let ownerEmail = record["ownerEmail"] as? String
            ?? (ownerId == AuthenticationManager.shared.currentUser?.uid
                ? (AuthenticationManager.shared.currentUser?.email ?? "")
                : "")

        // Check if group already exists locally
        if let existing = repo.fetchGroup(byId: groupId) {
            // Preserve soft-deleted state — only acceptInvitation should restore deleted groups
            if existing.isDeleted {
                logInfo("[Sync] Skipping BudgetGroup update for soft-deleted group: \(name) (\(groupId))")
                return
            }

            var updated = existing
            updated.name = name
            updated.ownerId = ownerId
            updated.ownerName = ownerName
            updated.ownerEmail = ownerEmail
            repo.updateGroup(updated)
            logInfo("[Sync] Updated BudgetGroup from CloudKit: \(name) (\(groupId))")
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

        // Set ckZoneOwner immediately so push/subscriptions work on first sync cycle
        let zoneOwner = record.recordID.zoneID.ownerName
        if zoneOwner != CKCurrentUserDefaultName && !zoneOwner.isEmpty {
            repo.updateZoneOwner(groupId: groupId, zoneOwner: zoneOwner)
            logInfo("[Sync] Set ckZoneOwner for group \(groupId): \(zoneOwner)")
        }

        // Ensure group members exist locally (include removed to prevent duplicates on re-join)
        let allMembers = repo.fetchMembersIncludingRemoved(forGroupId: groupId)

        // Ensure the owner exists as a GroupMember (needed on non-owner devices)
        // Check by userId OR email to avoid duplicates when acceptInvitation stored email as userId
        if let existingOwnerMember = allMembers.first(where: {
            $0.userId == ownerId || (!ownerEmail.isEmpty && $0.email == ownerEmail) || $0.role == .owner
        }) {
            // Update/reactivate if needed
            if existingOwnerMember.userId != ownerId || existingOwnerMember.name != ownerName || existingOwnerMember.isRemoved {
                var updated = existingOwnerMember
                updated.userId = ownerId
                updated.name = ownerName
                updated.email = ownerEmail
                updated.isRemoved = false
                repo.updateMember(updated)
                logInfo("[Sync] Updated owner GroupMember with correct data for group \(name) (\(groupId))")
            }
        } else {
            let ownerMember = GroupMember(
                groupId: groupId,
                userId: ownerId,
                name: ownerName,
                email: ownerEmail,
                role: .owner,
                permissions: .fullAccess
            )
            repo.insertMember(ownerMember)
            logInfo("[Sync] Added owner as GroupMember of group \(name) (\(groupId))")
        }

        // Ensure the current user is a member (owner or invited member)
        if let uid = AuthenticationManager.shared.currentUser?.uid {
            if let existingMember = allMembers.first(where: { $0.userId == uid }) {
                // Reactivate if removed
                if existingMember.isRemoved {
                    var updated = existingMember
                    updated.isRemoved = false
                    repo.updateMember(updated)
                    logInfo("[Sync] Reactivated current user as member of group \(name) (\(groupId))")
                }
            } else {
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
