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

    func performFullSync(forceFullFetch: Bool = false, forceRePush: Bool = false, completion: (() -> Void)? = nil) {
        syncQueue.async { [weak self] in
            if forceFullFetch {
                self?.stateManager.resetAllTokens()
            }
            if forceRePush {
                Self.resetAllSyncStatuses()
            }
            self?.executeSyncCycle(completion: completion)
        }
    }

    /// Resets all sync_status values to 'pending' so everything gets re-pushed to CloudKit.
    private static func resetAllSyncStatuses() {
        logWarning("[Sync] Resetting all sync statuses to 'pending' for re-push")
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            DBHelper.shared.executeSyncUpdate(
                "UPDATE \(table) SET sync_status = 'pending' WHERE sync_status = 'synced' AND (is_deleted IS NULL OR is_deleted = 0);",
                textBindings: []
            )
        }
        TransactionRepository.invalidateCache()
    }

    @objc private func handleRemoteNotification() {
        // Also fetch invitations immediately (public DB notifications don't trigger private DB changes)
        BudgetGroupService.shared.fetchRemoteInvitations {}
        performFullSync()
    }

    @objc private func handleLocalDataChange() {
        guard !isProcessingCloudData else { return }
        syncQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.pushLocalChanges()
        }
    }

    // MARK: - Sync Cycle

    private func executeSyncCycle(completion: (() -> Void)? = nil) {
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
                        self.pushLocalChanges { pushResult in
                            switch pushResult {
                            case .success:
                                self.stateManager.updateLastSyncDate(for: "privateDB")
                                self.postSyncActions.performPostSyncFetches {
                                    self.syncQueue.async {
                                        logWarning("[Sync] Sync cycle complete — status: synced")
                                        self.status = .synced
                                        self.isSyncing = false
                                        completion?()
                                    }
                                }
                            case .failure(let error):
                                logError("[Sync] Push failed: \(error.localizedDescription)")
                                self.status = .error(error)
                                self.isSyncing = false
                                completion?()
                            }
                        }
                    case .failure(let error):
                        logError("[Sync] Fetch changes failed: \(error.localizedDescription)")
                        self.status = .error(error)
                        self.isSyncing = false
                        completion?()
                    }
                }
            case .failure(let error):
                logError("[Sync] Zone creation failed: \(error.localizedDescription)")
                self.status = .error(error)
                self.isSyncing = false
                completion?()
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
                    logWarning("[Sync] Database changes fetched — \(changedZoneIDs.count) changed zone(s)")
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
                    TransactionRepository().fixAndDeduplicateAfterSync()

                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
                        NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
                        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
                        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
                    }
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

    // MARK: - Push Local Changes

    private static let batchSize = 50

    private func pushLocalChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Respect CloudKit throttle window
        if let throttledUntil = pushThrottledUntil, Date() < throttledUntil {
            let remaining = Int(throttledUntil.timeIntervalSinceNow)
            logWarning("Push throttled — retrying in \(remaining)s")
            completion?(.success(()))
            return
        }
        var allRecords: [CKRecord] = []
        var allDeleteIDs: [CKRecord.ID] = []

        // Transactions — use stored ck_record_id to avoid creating duplicate CK records
        let txRepo = TransactionRepository()
        TransactionRepository.invalidateCache()
        let allTxCount = txRepo.fetchAllTransactions().count
        let pendingTransactions = txRepo.fetchPendingSync()
        logWarning("[Sync] Transactions: \(allTxCount) total, \(pendingTransactions.count) pending")
        for tx in pendingTransactions {
            let storedName = tx.id.flatMap { txRepo.fetchCKRecordName(for: $0) }
            let record = tx.toCKRecord(in: CloudKitManager.privateZoneID, storedRecordName: storedName)
            // Phase 3B: Store CK record name before push
            if let txId = tx.id, storedName == nil {
                txRepo.setCKRecordId(for: txId, ckRecordName: record.recordID.recordName)
            }
            // Mirror mode: include shared_group_id in CK record
            if let txId = tx.id, let groupId = txRepo.fetchSharedGroupId(for: txId) {
                record["sharedGroupId"] = groupId as CKRecordValue
            }
            allRecords.append(record)
        }

        // Transaction deletes
        for pending in txRepo.fetchPendingDeletes() {
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID))
        }

        // Budgets (uses monthDate as key — deterministic across devices)
        let budgetRepo = BudgetRepository()
        let pendingBudgets = budgetRepo.fetchPendingSync()
        allRecords += pendingBudgets.map {
            $0.toCKRecord(in: CloudKitManager.privateZoneID)
        }

        // Budget deletes
        for pending in budgetRepo.fetchPendingDeletes() {
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID))
        }

        // Credit Cards — use stored ck_record_id
        let cardRepo = CreditCardRepository()
        let pendingCards = cardRepo.fetchPendingSync()
        for card in pendingCards {
            let storedName = card.id.flatMap { cardRepo.fetchCKRecordName(for: $0) }
            let record = card.toCKRecord(in: CloudKitManager.privateZoneID, storedRecordName: storedName)
            if let cardId = card.id, storedName == nil {
                cardRepo.setCKRecordId(for: cardId, ckRecordName: record.recordID.recordName)
            }
            allRecords.append(record)
        }

        // Credit Card deletes
        for pending in cardRepo.fetchPendingDeletes() {
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID))
        }

        // Credit Card Statements — use stored ck_record_id
        let stmtRepo = StatementRepository()
        let pendingStmts = stmtRepo.fetchPendingSync()
        for stmt in pendingStmts {
            let storedName = stmt.id.flatMap { stmtRepo.fetchCKRecordName(for: $0) }
            let record = stmt.toCKRecord(in: CloudKitManager.privateZoneID, storedRecordName: storedName)
            if let stmtId = stmt.id, storedName == nil {
                stmtRepo.setCKRecordId(for: stmtId, ckRecordName: record.recordID.recordName)
            }
            allRecords.append(record)
        }

        // Statement deletes
        for pending in stmtRepo.fetchPendingDeletes() {
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID))
        }

        // Budget Allocations — use stored ck_record_id
        let allocRepo = BudgetAllocationRepository()
        let pendingAllocs = allocRepo.fetchPendingSync()
        for alloc in pendingAllocs {
            let storedName = alloc.id.flatMap { allocRepo.fetchCKRecordName(for: $0) }
            let record = alloc.toCKRecord(in: CloudKitManager.privateZoneID, storedRecordName: storedName)
            if let allocId = alloc.id, storedName == nil {
                allocRepo.setCKRecordId(for: allocId, ckRecordName: record.recordID.recordName)
            }
            allRecords.append(record)
        }

        // Allocation deletes
        for pending in allocRepo.fetchPendingDeletes() {
            allDeleteIDs.append(CKRecord.ID(recordName: pending.ckRecordName, zoneID: CloudKitManager.privateZoneID))
        }

        logWarning("[Sync] Push: \(allRecords.count) record(s) to save, \(allDeleteIDs.count) to delete")

        guard !allRecords.isEmpty || !allDeleteIDs.isEmpty else {
            completion?(.success(()))
            return
        }

        let batches = stride(from: 0, to: allRecords.count, by: Self.batchSize).map {
            Array(allRecords[$0..<min($0 + Self.batchSize, allRecords.count)])
        }

        pushBatches(batches, deleteIDs: allDeleteIDs, index: 0, completion: completion)
    }

    private func pushBatches(
        _ batches: [[CKRecord]],
        deleteIDs: [CKRecord.ID] = [],
        index: Int,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard index < batches.count else {
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

        var batchSuccessCount = 0
        var batchFailureCount = 0

        cloudKitOps.saveRecords(batch) { [weak self] recordID, result in
            let name = recordID.recordName
            switch result {
            case .success:
                batchSuccessCount += 1
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
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    if !hitQuotaLimit {
                        hitQuotaLimit = true
                        let retryAfter = ckError.retryAfterSeconds ?? 300
                        self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                        logWarning("[Sync] ⚠️ CloudKit quota exceeded — throttling for \(Int(retryAfter))s. Pending records will sync on next launch.")
                    }
                } else {
                    logWarning("[Sync] ❌ Failed to push record \(name): \(error.localizedDescription)")
                }
            }
        } completion: { [weak self] result in
            logWarning("[Sync] Batch \(index + 1)/\(batches.count) result: \(batchSuccessCount) succeeded, \(batchFailureCount) failed")

            if hitQuotaLimit {
                // Stop processing remaining batches — pending records will sync on next launch
                logWarning("[Sync] Stopping push due to quota limit. Remaining records will sync later.")
                completion?(.success(()))
                return
            }
            switch result {
            case .success:
                self?.pushBatches(batches, deleteIDs: deleteIDs, index: index + 1, completion: completion)
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    let retryAfter = ckError.retryAfterSeconds ?? 300
                    self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                    logWarning("[Sync] ⚠️ CloudKit quota exceeded (batch level) — throttling for \(Int(retryAfter))s")
                    completion?(.success(()))
                } else {
                    logWarning("[Sync] ❌ Batch \(index + 1)/\(batches.count) failed: \(error.localizedDescription)")
                    completion?(.failure(error))
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
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    let retryAfter = ckError.retryAfterSeconds ?? 300
                    self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                } else {
                    logWarning("[Sync] ❌ Failed to delete record \(recordID.recordName): \(error.localizedDescription)")
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

    // MARK: - Process Incoming Records

    private func processIncomingRecord(_ record: CKRecord) {
        logWarning("[Sync] Processing incoming record: type=\(record.recordType), name=\(record.recordID.recordName)")
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
            // BudgetGroup records are managed via shared database/invitations — no conflict resolution needed
            break
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
            TransactionRepository().softDeleteByCKRecordName(recordID.recordName)
        case "Budget":
            BudgetRepository().softDeleteByCKRecordName(recordID.recordName)
        case "CreditCard":
            CreditCardRepository().softDeleteByCKRecordName(recordID.recordName)
        case "CreditCardStatement":
            StatementRepository().softDeleteByCKRecordName(recordID.recordName)
        case "BudgetAllocation":
            BudgetAllocationRepository().softDeleteByCKRecordName(recordID.recordName)
        default:
            break
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

        DispatchQueue.main.async {
            var didUpdate = false
            if key == "personal" {
                let current = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
                if current != offset {
                    UserDefaults.standard.set(offset, forKey: "balanceOffset_\(uid)")
                    logInfo("Balance offset updated from sync: personal = \(offset)")
                    didUpdate = true
                }
            } else if key.hasPrefix("group-") {
                let groupId = String(key.dropFirst("group-".count))
                let current = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(groupId)")
                if current != offset {
                    UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(groupId)")
                    logInfo("Balance offset updated from sync: \(key) = \(offset)")
                    didUpdate = true
                }
            }
            if didUpdate {
                NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            }
        }
    }
}
