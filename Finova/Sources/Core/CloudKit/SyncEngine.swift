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
    private(set) var currentPushProgress: SyncPushProgress?
    private var isInitialPush = false
    private var isLargeSyncCycle = false
    private var isRecoverySync = false
    /// Cooldown: prevents notification-triggered sync loops where our own push
    /// triggers a CK notification → another sync → another push → repeat.
    private var lastSyncCompletedAt: Date?
    private static let syncCooldownInterval: TimeInterval = 10
    private static let largeSyncThreshold = 100
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

    /// Recovery sync: directly fetches ALL records from every private-DB zone using nil zone tokens.
    /// Fetches FinovaPrivateZone PLUS all owned group zones (which hold mirror-mode records).
    /// This bypasses the DB-level CKFetchDatabaseChangesOperation which can return an empty
    /// changedZoneIDs even with a nil token, causing the zone fetch to be silently skipped.
    /// After fetching, fires all data change notifications and saves updated zone tokens.
    func performPrivateZoneRecovery(completion: (() -> Void)? = nil) {
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
            let allGroups = BudgetGroupRepository().fetchAllGroups()
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
                zoneTokenHandler: { [weak self] zoneID, token in
                    self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: "private")
                },
                completion: { [weak self] result in
                    guard let self = self else { completion?(); return }

                    guard case .success = result else {
                        if case .failure(let error) = result {
                            logError("[Sync] Recovery private fetch failed: \(error.localizedDescription)")
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
                        zoneTokenHandler: { [weak self] zoneID, token in
                            self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: "shared")
                        },
                        completion: { [weak self] result in
                            guard self != nil else { completion?(); return }
                            let sharedCount = bufferedRecords.count - privateCount
                            logWarning("[Sync] Recovery: shared fetch got \(sharedCount) record(s)")
                            // Process even if shared fetch fails — private data is more important
                            if case .failure(let error) = result {
                                logWarning("[Sync] Recovery: shared fetch failed (non-fatal): \(error.localizedDescription)")
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
        let cardRepo = CreditCardRepository()
        let stmtRepo = StatementRepository()

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
        let db = DBHelper.shared

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
    func syncSharedGroupData(groupId: String, zoneOwner: String) {
        let delays: [Double] = [2.0, 5.0, 10.0, 20.0, 40.0, 60.0]

        func attemptFetch(index: Int) {
            guard index < delays.count else {
                logWarning("[Sync] Shared group data: exhausted all \(delays.count) retries for group \(groupId)")
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delays[index]) { [weak self] in
                self?.fetchSharedGroupZone(groupId: groupId, zoneOwner: zoneOwner) { count in
                    // count > 1 because the CKShare record itself counts as 1
                    if count > 1 {
                        logWarning("[Sync] Shared group data fetched (\(count) records) on attempt \(index + 1)")
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
                Self.resetLocalModificationTimestamps()
                self.stateManager.resetAllTokens()
                self.isFullRefetch = true
                self.pulledCKRecordNames = []
                UserDefaults.standard.removeObject(forKey: Self.fullPullVerifiedKey)
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

    @objc private func handleLocalDataChange() {
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
            guard let self = self, !self.isSyncing else { return }
            self.pushLocalChanges()
        }
    }

    /// Deletes every previously-synced row (ck_record_id IS NOT NULL) from all sync tables
    /// before a clean-slate recovery pull. Local-only rows (ck_record_id IS NULL) are preserved
    /// so pending new records are re-pushed on the next sync cycle.
    private func clearSyncedLocalData() {
        let db = DBHelper.shared
        // Delete dependents before their parents to respect any FK ordering.
        db.executeSyncUpdate("DELETE FROM CreditCardStatements WHERE ck_record_id IS NOT NULL;")
        db.executeSyncUpdate("DELETE FROM Transactions WHERE ck_record_id IS NOT NULL;")
        // Also clear tombstones (is_deleted=1, ck_record_id=NULL) left by hardDeleteLocal
        // for recurring instances. Without this, restoreTombstoneForInstance blocks legitimate
        // re-insertion of live records from CloudKit during recovery.
        db.executeSyncUpdate("DELETE FROM Transactions WHERE is_deleted = 1;")
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
        guard hasToken else { return } // No token = first sync, will do full pull naturally

        logWarning("[SyncLife] Device has not completed a verified full pull — resetting tokens for complete pull")
        stateManager.resetAllTokens()
        isLargeSyncCycle = true
    }

    /// Called after a successful sync that pulled records, marking this device as having
    /// a complete dataset. Future syncs will use incremental tokens normally.
    private func markFullPullVerified() {
        if !UserDefaults.standard.bool(forKey: Self.fullPullVerifiedKey) {
            UserDefaults.standard.set(true, forKey: Self.fullPullVerifiedKey)
            logWarning("[SyncLife] Full pull verified — future syncs will be incremental")
        }
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

        isSyncing = true
        syncStartedAt = Date()
        postSyncPushCycleCount = 0
        didReceiveBalanceOffsetDuringPull = false
        isLargeSyncCycle = false
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
                            self.postPhaseProgress(progress: 0.50, phaseKey: "sync.phase.processing")
                            MirrorModeManager.shared.reconcileMirrorData()
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
                                    // Re-run reconciliation to tag any transactions pulled during zone discovery
                                    if MirrorModeManager.shared.isEnabled {
                                        let changed = MirrorModeManager.shared.reconcileMirrorData()
                                        if changed > 0 {
                                            logWarning("[SyncLife] Post-push reconcile tagged \(changed) records — scheduling drain push")
                                            self.needsPostSyncPush = true
                                        }
                                    }
                                    logWarning("[SyncLife] Starting postSyncActions.performPostSyncFetches")
                                    self.postSyncActions.performPostSyncFetches {
                                        logWarning("[SyncLife] postSyncActions completed — entering syncQueue for finishSync")
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

                    if changedZoneIDs.isEmpty {
                        // When the token was nil (forceFullFetch/reset), an empty changedZoneIDs
                        // is unexpected — it likely means the DB-level fetch returned before the
                        // zone handler fired (e.g. async delivery edge case).  Fall back to a
                        // direct zone fetch for the private zone so the recovery pull is not skipped.
                        if token == nil {
                            logWarning("[Sync] No changed zones with nil token — falling back to direct private zone fetch to ensure recovery")
                            self?.fetchZoneChanges(zoneIDs: [CloudKitManager.privateZoneID], database: .private, completion: completion)
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
                if self?.isFullRefetch == true {
                    self?.pulledCKRecordNames.insert(record.recordID.recordName)
                }
                self?.processIncomingRecord(record)

                // Detect large sync early — as soon as threshold is crossed during pull
                if pulledRecordCount == Self.largeSyncThreshold + 1,
                   self?.isLargeSyncCycle == false {
                    self?.isLargeSyncCycle = true
                    logWarning("[SyncLife] Large sync detected during pull (\(pulledRecordCount) records so far)")
                    self?.postPhaseProgress(progress: pullBaseProgress + 0.05, phaseKey: pullPhaseKey)
                }

                // Incremental pull progress every 25 records (capped at next phase boundary)
                if pulledRecordCount % 25 == 0 {
                    let increment = Float(pulledRecordCount) * 0.001
                    let nextBoundary: Float = database == .private ? 0.40 : 0.50
                    let pullProgress = min(pullBaseProgress + increment, nextBoundary - 0.01)
                    self?.postPhaseProgress(progress: pullProgress, phaseKey: pullPhaseKey)
                }
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
                    logWarning("[Sync] Pull complete — \(pulledRecordCount) record(s), \(pulledDeleteCount) delete(s), largeSync=\(self?.isLargeSyncCycle ?? false)")
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

        let group = BudgetGroupRepository().fetchGroup(byId: groupId)
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

    /// One-time migration: marks group-tagged synced records as pending and clears their
    /// system fields so they get re-pushed to group zones instead of FinovaPrivateZone.
    /// v2: also clears ck_system_fields to prevent buildCKRecord from using the old zone.
    private func migrateGroupRecordsToGroupZones() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedGroupZoneMigration_v2") else { return }

        // Tables with shared_group_id column
        let groupTables = ["Transactions", "Budgets", "CreditCards", "BudgetAllocations"]
        for table in groupTables {
            DBHelper.shared.executeSyncUpdate(
                "UPDATE \(table) SET sync_status = 'pending', ck_system_fields = NULL WHERE sync_status = 'synced' AND shared_group_id IS NOT NULL AND shared_group_id != '';",
                textBindings: []
            )
        }

        // CreditCardStatements don't have shared_group_id — mark them pending
        // if their parent credit card belongs to a group
        DBHelper.shared.executeSyncUpdate(
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

        // If the record has moved zones (e.g., from private default zone to a group zone),
        // the archived system fields have the OLD zone baked in. Discard them and use
        // the fresh record so the push targets the correct zone.
        if archived.recordID.zoneID != fresh.recordID.zoneID {
            logWarning("[Sync] Zone mismatch for '\(fresh.recordID.recordName)': archived=\(archived.recordID.zoneID.zoneName) vs fresh=\(fresh.recordID.zoneID.zoneName) — using fresh record")
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
        var privateRecords: [CKRecord] = []
        var sharedRecords: [CKRecord] = []
        var privateDeleteIDs: [CKRecord.ID] = []
        var sharedDeleteIDs: [CKRecord.ID] = []
        var orphanDeleteNames: Set<String> = []
        pendingCKIdAssignments = [:]

        // Repair: any soft-deleted transaction whose sync_status was corrupted (e.g. overwritten
        // by a previous pull before the pendingDelete could be pushed) gets re-queued here.
        // This covers installments/recurring batches deleted before the ConflictResolver fix,
        // without requiring a full reset sync to trigger the per-record repair path.
        let repairedCount = DBHelper.shared.repairCorruptedPendingDeletes()
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

        // Transactions — use stored ck_record_id to avoid creating duplicate CK records
        let txRepo = TransactionRepository()
        let cardRepo = CreditCardRepository()
        TransactionRepository.invalidateCache()
        let allTxCount = txRepo.fetchAllTransactions().count
        let pendingTransactions = txRepo.fetchPendingSync()
        logWarning("[Sync] Transactions: \(allTxCount) total, \(pendingTransactions.count) pending")
        for tx in pendingTransactions {
            // Guard: skip credit card transactions whose card has no ck_record_name yet.
            // The card must be pushed first so other devices can remap IDs correctly.
            if let ccId = tx.creditCardId, cardRepo.fetchCKRecordName(for: ccId) == nil {
                // Check if the card even exists — if not, detach the transaction from
                // the non-existent card so it can be pushed as a regular transaction.
                if let uid = UIDUserDefaultsManager.shared.currentUserUID {
                    let cardExists = cardRepo.fetchAllCards(userId: uid).contains { $0.id == ccId }
                    if !cardExists, let txId = tx.id {
                        logWarning("[Sync] Detaching transaction \(txId) from non-existent credit card \(ccId)")
                        DBHelper.shared.executeSyncUpdate(
                            "UPDATE Transactions SET credit_card_id = NULL, statement_id = NULL WHERE id = ?;",
                            intBindings: [txId]
                        )
                        // Continue processing — the transaction will be pushed without a credit card reference
                    } else {
                        logWarning("[Sync] Skipping transaction \(tx.id ?? -1): credit card \(ccId) has no ck_record_name yet")
                        continue
                    }
                } else {
                    logWarning("[Sync] Skipping transaction \(tx.id ?? -1): credit card \(ccId) has no ck_record_name yet")
                    continue
                }
            }
            let storedName = tx.id.flatMap { txRepo.fetchCKRecordName(for: $0) }
            let groupId = tx.id.flatMap { txRepo.fetchSharedGroupId(for: $0) }
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
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "Transactions")
            }
            appendRecord(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields), database: dest.database)
            // Clean up orphaned FinovaPrivateZone copy when pushing to Group zone
            if let name = storedName, groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: name, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Transaction deletes
        for pending in txRepo.fetchPendingDeletes() {
            let groupId = txRepo.fetchSharedGroupId(for: pending.localId)
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            // Also delete orphaned copy from FinovaPrivateZone to prevent ghost resurrection
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Budgets (uses monthDate as key — deterministic across devices)
        let budgetRepo = BudgetRepository()
        let pendingBudgets = budgetRepo.fetchPendingSync()
        for budget in pendingBudgets {
            let dest = destination(forGroupId: budget.sharedGroupId)
            let freshRecord = budget.toCKRecord(in: dest.zoneID)
            let budgetRecordName = freshRecord.recordID.recordName
            let systemFields = DBHelper.shared.fetchSystemFields(ckRecordName: budgetRecordName, table: "Budgets")
            appendRecord(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields), database: dest.database)
            if let gid = budget.sharedGroupId, !gid.isEmpty, dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: budgetRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Budget deletes
        for pending in budgetRepo.fetchPendingDeletes() {
            let groupId = DBHelper.shared.fetchSingleString(
                "SELECT shared_group_id FROM Budgets WHERE month_date = ?;",
                intBinding: pending.monthDate
            )
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
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
            let dest = destination(forGroupId: groupId)

            let freshRecord = card.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            if let cardId = card.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "creditCard", localId: cardId)
            }
            if let groupId = groupId {
                freshRecord["sharedGroupId"] = groupId as CKRecordValue
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "CreditCards")
            }
            appendRecord(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields), database: dest.database)
            if let name = storedName, let gid = groupId, !gid.isEmpty, dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: name, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Credit Card deletes
        for pending in cardRepo.fetchPendingDeletes() {
            let groupId = cardRepo.fetchSharedGroupId(for: pending.localId)
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Credit Card Statements — use stored ck_record_id
        // Statements inherit their group zone from their parent credit card
        let stmtRepo = StatementRepository()
        let pendingStmts = stmtRepo.fetchPendingSync()
        for stmt in pendingStmts {
            // Guard: skip statements whose parent card has no ck_record_name yet.
            if cardRepo.fetchCKRecordName(for: stmt.creditCardId) == nil {
                logWarning("[Sync] Skipping statement \(stmt.id ?? -1): credit card \(stmt.creditCardId) has no ck_record_name yet")
                continue
            }
            let storedName = stmt.id.flatMap { stmtRepo.fetchCKRecordName(for: $0) }
            let parentGroupId = cardRepo.fetchSharedGroupId(for: stmt.creditCardId)
            let dest = destination(forGroupId: parentGroupId)

            let freshRecord = stmt.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            if let stmtId = stmt.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "statement", localId: stmtId)
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "CreditCardStatements")
            }
            appendRecord(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields), database: dest.database)
            if let name = storedName, parentGroupId != nil && !(parentGroupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: name, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Statement deletes
        for pending in stmtRepo.fetchPendingDeletes() {
            let parentCardId = DBHelper.shared.fetchSingleInt(
                "SELECT credit_card_id FROM CreditCardStatements WHERE id = ?;",
                intBinding: pending.localId
            )
            let parentGroupId = parentCardId.flatMap { cardRepo.fetchSharedGroupId(for: $0) }
            let dest = destination(forGroupId: parentGroupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if parentGroupId != nil && !(parentGroupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Budget Allocations — use stored ck_record_id
        let allocRepo = BudgetAllocationRepository()
        let pendingAllocs = allocRepo.fetchPendingSync()
        for alloc in pendingAllocs {
            let storedName = alloc.id.flatMap { allocRepo.fetchCKRecordName(for: $0) }
            let dest = destination(forGroupId: alloc.sharedGroupId)

            let freshRecord = alloc.toCKRecord(in: dest.zoneID, storedRecordName: storedName)
            if let allocId = alloc.id, storedName == nil {
                pendingCKIdAssignments[freshRecord.recordID.recordName] = (type: "allocation", localId: allocId)
            }
            let systemFields = storedName.flatMap {
                DBHelper.shared.fetchSystemFields(ckRecordName: $0, table: "BudgetAllocations")
            }
            appendRecord(buildCKRecord(fresh: freshRecord, systemFieldsData: systemFields), database: dest.database)
            if let name = storedName, let gid = alloc.sharedGroupId, !gid.isEmpty, dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: name, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        // Allocation deletes
        for pending in allocRepo.fetchPendingDeletes() {
            let groupId = DBHelper.shared.fetchSingleString(
                "SELECT shared_group_id FROM BudgetAllocations WHERE id = ?;",
                intBinding: pending.localId
            )
            let dest = destination(forGroupId: groupId)
            appendDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: dest.zoneID), database: dest.database)
            if groupId != nil && !(groupId?.isEmpty ?? true) && dest.zoneID != CloudKitManager.privateZoneID {
                appendOrphanDeleteID(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID), database: .private)
            }
        }

        let totalRecords = privateRecords.count + sharedRecords.count
        let totalDeletes = privateDeleteIDs.count + sharedDeleteIDs.count
        let groupZoneRecords = privateRecords.filter { $0.recordID.zoneID.zoneName.hasPrefix("Group-") }
        let defaultZoneRecords = privateRecords.filter { !$0.recordID.zoneID.zoneName.hasPrefix("Group-") }
        logWarning("[Sync] Push: \(totalRecords) record(s) to save (\(defaultZoneRecords.count) private-default, \(groupZoneRecords.count) private-group, \(sharedRecords.count) shared), \(totalDeletes) to delete")

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

        // Push private DB records first, then shared DB records
        pushBatches(privateBatches, deleteIDs: privateDeleteIDs, database: .private, index: 0, orphanNames: orphanDeleteNames) { [weak self] result in
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

        cloudKitOps.saveRecords(batch, database: database) { [weak self] recordID, result in
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
                        // Re-queue all statements for this CC so they are re-pushed on the
                        // next sync cycle with creditCardCKRecordName now filled in.
                        // Without this, statements pushed in the same batch as a new CC lack
                        // creditCardCKRecordName (the CC's ck_record_id wasn't stored yet when
                        // the statement CKRecord was being built), causing cross-device remapping
                        // to fail and statements to be inserted with the wrong local creditCardId.
                        StatementRepository().markStatementsPending(forCardId: assignment.localId)
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
                logWarning("[Sync] Stopping save batches due to schema error. Deploy schema via CloudKit Dashboard, then sync again.")
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
            cloudKitOps.deleteRecords(batch, database: database) { [weak self] recordID, result in
                let name = recordID.recordName
                // Orphan deletes clean up private-zone copies of group-zone records.
                // If the private-zone copy was absent, hardDeleteLocal must NOT run —
                // the actual record lives in the group zone and is still active locally.
                let isOrphan = orphanNames.contains(name)
                switch result {
                case .success:
                    logWarning("[Sync] ✓ Deleted record \(name) from CloudKit")
                    if !isOrphan { Self.hardDeleteLocal(recordName: name) }
                case .failure(let error):
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .unknownItem:
                            if isOrphan {
                                logWarning("[Sync] Orphan record \(name) not found in private zone — skipping local delete (record lives in group zone)")
                            } else {
                                logWarning("[Sync] Record \(name) already deleted from CloudKit — hard-deleting locally")
                                Self.hardDeleteLocal(recordName: name)
                            }
                        case .permissionFailure:
                            // Member doesn't have permission to delete this record from the shared zone.
                            // Hard-delete locally to stop the loop — the CK record stays until the owner removes it.
                            logWarning("[Sync] ⚠️ Permission denied deleting \(name) — removing locally to stop loop")
                            if !isOrphan { Self.hardDeleteLocal(recordName: name) }
                        case .userDeletedZone, .zoneNotFound:
                            // Zone no longer exists — record is effectively gone; clean up locally.
                            logWarning("[Sync] ⚠️ Zone gone for \(name) — removing locally")
                            if !isOrphan { Self.hardDeleteLocal(recordName: name) }
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

    private static func hardDeleteLocal(recordName name: String) {
        if name.hasPrefix("transaction-") {
            // For installment/recurring instances (parent_transaction_id IS NOT NULL),
            // leave a tombstone row (is_deleted=1, ck_record_id=NULL) instead of a full DELETE.
            // This prevents lazy generation from recreating the deleted instance on the next
            // dashboard refresh — the tombstone's anchor is visible to fetchDeletedChildAnchors().
            // ck_record_id is cleared so repairCorruptedPendingDeletes (which requires IS NOT NULL)
            // will never re-queue it, and processDeletedRecord's deleteFromCloud won't match it.
            let isInstance = DBHelper.shared.fetchSingleInt(
                "SELECT 1 FROM Transactions WHERE ck_record_id = ? AND parent_transaction_id IS NOT NULL;",
                textBinding: name
            ) != nil
            if isInstance {
                DBHelper.shared.executeSyncUpdate(
                    "UPDATE Transactions SET is_deleted = 1, sync_status = 'synced', ck_record_id = NULL WHERE ck_record_id = ?;",
                    textBindings: [name]
                )
                TransactionRepository.invalidateCache()
            } else {
                TransactionRepository().hardDeleteByCKRecordName(name)
            }
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
        // Only log CC-related and non-Transaction types to reduce noise
        if record.recordType != "Transaction" && record.recordType != "Budget" && record.recordType != "BudgetAllocation" {
            logWarning("[Sync] Processing incoming record: type=\(record.recordType), name=\(record.recordID.recordName), zone=\(record.recordID.zoneID.zoneName)")
        }

        // Extract group ID from zone name (e.g. "Group-ABC123" → "ABC123")
        // and inject into the record so ConflictResolver can tag it.
        // Skip injection for soft-deleted groups — their data has been untagged
        // and should stay personal.
        let zoneName = record.recordID.zoneID.zoneName
        if zoneName.hasPrefix("Group-"), record["sharedGroupId"] == nil {
            let groupId = String(zoneName.dropFirst("Group-".count))
            let group = BudgetGroupRepository().fetchGroup(byId: groupId)
            if group == nil || !group!.isDeleted {
                record["sharedGroupId"] = groupId as CKRecordValue
            }
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
            ConflictResolver.shared.resolveTransaction(remote: transaction, ckRecord: record)
        case "Budget":
            guard let budget = BudgetModel.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveBudget(remote: budget, ckRecord: record)
        case "CreditCard":
            guard let card = CreditCard.fromCKRecord(record) else { return }
            logWarning("[StmtSync] Incoming CreditCard: name=\(card.name), ckLocalId=\(card.id ?? -1), ckName=\(record.recordID.recordName)")
            ConflictResolver.shared.resolveCreditCard(remote: card, ckRecord: record)
        case "CreditCardStatement":
            guard let stmt = CreditCardStatement.fromCKRecord(record) else {
                logWarning("[StmtSync] Failed to parse CreditCardStatement from \(record.recordID.recordName)")
                return
            }
            let hasCKCardName = record["creditCardCKRecordName"] as? String
            logWarning("[StmtSync] Incoming statement: ckName=\(record.recordID.recordName), creditCardId=\(stmt.creditCardId), creditCardCKRecordName=\(hasCKCardName ?? "nil"), closingDate=\(stmt.closingDate)")
            ConflictResolver.shared.resolveCreditCardStatement(remote: stmt, ckRecord: record)
        case "BudgetAllocation":
            guard let alloc = BudgetAllocationModel.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveBudgetAllocation(remote: alloc, ckRecord: record)
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
        let cardRepo = CreditCardRepository()
        let stmtRepo = StatementRepository()

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

        // Safety: count total local synced records across all tables.
        let totalLocalSynced = tables.reduce(0) { $0 + DBHelper.shared.fetchAllCKRecordNames(table: $1).count }

        // Guard against partial CloudKit fetches (network issues, zone unavailability, schema errors).
        // If CK returned significantly fewer records than we have locally, the pull was likely incomplete —
        // running cleanup would incorrectly delete valid local data. Allow up to 25% discrepancy for
        // records that are legitimately only local (newly created, not yet pushed). Hard limit: never
        // delete more than 30% of local records in a single cleanup pass.
        if totalLocalSynced > 0 {
            let orphanCandidates = tables.reduce(0) { count, table in
                let localNames = DBHelper.shared.fetchAllCKRecordNames(table: table)
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

        let repo = BudgetGroupRepository()

        // Handle removal flag
        if isRemoved {
            let currentUserId = AuthenticationManager.shared.currentUser?.uid
            if userId == currentUserId {
                // Current user was removed — soft-delete the group locally
                logInfo("[Sync] Current user was removed from group \(groupId) — cleaning up")
                repo.softDeleteGroup(id: groupId)
                repo.removeMember(id: record.recordID.recordName.replacingOccurrences(of: "groupMember-", with: ""))

                // Disable mirror mode if linked to this group
                DispatchQueue.main.async {
                    if MirrorModeManager.shared.isEnabled,
                       MirrorModeManager.shared.linkedGroupId == groupId {
                        MirrorModeManager.shared.disableMirrorMode()
                    }
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
            updated.isRemoved = false
            if existing.userId != userId || existing.name != name || existing.isRemoved {
                repo.updateMember(updated)
                logInfo("[Sync] Updated/reactivated GroupMember \(name) in group \(groupId)")
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
            permissions: role == .owner ? .fullAccess : .memberDefault,
            joinedAt: joinedAt
        )
        repo.insertMember(member)
        logInfo("[Sync] Inserted GroupMember \(name) into group \(groupId) from CloudKit")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
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

        // Include soft-deleted group IDs so they aren't "rediscovered" during sync.
        // Only acceptInvitation should restore a deleted group.
        let allGroupRows = DBHelper.shared.fetchBudgetGroupRows(
            "SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, ck_zone_owner, created_at, updated_at, is_deleted FROM BudgetGroups"
        )
        let allLocalGroupIds = Set(allGroupRows.map { $0.id })

        logWarning("[Sync] discoverGroupsFromAllZones: \(existingGroups.count) active, \(allLocalGroupIds.count) total local group(s)")
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
                    if !allLocalGroupIds.contains(groupId) {
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

                // For owned groups, ensure pending invitations in the public DB have the share URL
                // Re-fetch groups from DB to get the latest ckShareUrl (may have been updated by prior sync)
                let freshGroups = BudgetGroupRepository().fetchAllGroups()
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
        var foundSharedGroupIds: Set<String> = []

        operation.perRecordZoneResultBlock = { [weak self] zoneID, result in
            switch result {
            case .success:
                logWarning("[Sync] Shared DB zone found: \(zoneID.zoneName) (owner: \(zoneID.ownerName))")
                if zoneID.zoneName.hasPrefix("Group-") {
                    let groupId = String(zoneID.zoneName.dropFirst("Group-".count))
                    foundSharedGroupIds.insert(groupId)
                    // Backfill: store zone owner name for existing groups that don't have it yet
                    BudgetGroupRepository().updateZoneOwner(groupId: groupId, zoneOwner: zoneID.ownerName)
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
                // Check for member groups with accepted share but no data (empty group).
                // This handles the case where the initial fetch after CKShare acceptance
                // only returned the share metadata due to CloudKit propagation delay.
                let repo = BudgetGroupRepository()
                let txRepo = TransactionRepository()
                for groupId in foundSharedGroupIds {
                    if let group = repo.fetchGroup(byId: groupId),
                       !group.isOwner,
                       group.ckZoneOwner != nil {
                        let groupTxCount = txRepo.fetchTransactionsForGroup(groupId: groupId).count
                        if groupTxCount == 0 {
                            logWarning("[Sync] Member group '\(group.name)' has shared zone but 0 transactions — resetting token for re-fetch")
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
                    // After all zone fetching, check for member groups that need CKShare repair
                    self?.repairMissingShareAcceptance(sharedZoneGroupIds: foundSharedGroupIds) {
                        completion()
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

        operation.qualityOfService = .userInitiated
        CloudKitManager.shared.sharedDatabase.add(operation)
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
                    share.publicPermission = .readWrite

                    let saveOp = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
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
                            BudgetGroupRepository().updateGroup(updated)
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
        let repo = BudgetGroupRepository()
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
        let invitations = DBHelper.shared.fetchGroupInvitationRows(
            "SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at FROM GroupInvitations WHERE group_id = ? AND ck_share_url IS NOT NULL AND ck_share_url != ''",
            textBindings: [groupId]
        )
        return invitations.first?.ckShareUrl
    }

    private func fetchShareUrlFromPublicDB(forGroupId groupId: String, completion: @escaping (String?) -> Void) {
        guard let email = AuthenticationManager.shared.currentUser?.email else {
            completion(nil)
            return
        }

        let predicate = NSPredicate(format: "inviteeEmail == %@", email)
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
        CloudKitManager.shared.container.fetchShareMetadata(with: url) { [weak self] metadata, error in
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

                    let repo = BudgetGroupRepository()
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
        newShare.publicPermission = .readWrite

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
                    BudgetGroupRepository().updateGroup(updated)
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

        // Check for existing member (including removed) to avoid duplicates
        let allMembers = repo.fetchMembersIncludingRemoved(forGroupId: groupId)
        if let existing = allMembers.first(where: { $0.userId == uid }) {
            if existing.isRemoved {
                var updated = existing
                updated.isRemoved = false
                repo.updateMember(updated)
            }
        } else {
            let ownerMember = GroupMember(
                groupId: groupId,
                userId: uid,
                name: userName,
                email: userEmail,
                role: .owner,
                permissions: .fullAccess
            )
            repo.insertMember(ownerMember)
        }
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
