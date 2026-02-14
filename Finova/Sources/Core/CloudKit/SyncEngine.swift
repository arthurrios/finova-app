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

    private let cloudKit = CloudKitManager.shared
    private let stateManager = SyncStateManager.shared
    private let syncQueue = DispatchQueue(label: "com.finova.syncengine", qos: .utility)
    private var isSyncing = false
    private var hasSetupSubscriptions = false
    private var isProcessingCloudData = false
    private var pushThrottledUntil: Date?

    private init() {
        setupObservers()
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

    func performFullSync() {
        syncQueue.async { [weak self] in
            self?.executeSyncCycle()
        }
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

    private func executeSyncCycle() {
        guard !isSyncing else { return }

        if cloudKit.isCloudKitAvailable {
            startSyncOperations()
        } else {
            // Check account status first — isCloudKitAvailable may not be set yet
            cloudKit.checkAccountStatus { [weak self] accountStatus in
                guard let self = self else { return }
                guard accountStatus == .available else {
                    self.status = .idle
                    return
                }
                self.syncQueue.async {
                    self.startSyncOperations()
                }
            }
        }
    }

    private func startSyncOperations() {
        guard !isSyncing else { return }

        isSyncing = true
        status = .syncing
        ensureZoneExists { [weak self] result in
            guard let self = self else { return }

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
                                // Fetch balance offsets and invitations in parallel
                                let group = DispatchGroup()
                                group.enter()
                                UIDUserDefaultsManager.shared.fetchBalanceOffsetsFromCloud {
                                    group.leave()
                                }
                                group.enter()
                                BudgetGroupService.shared.fetchRemoteInvitations {
                                    group.leave()
                                }
                                group.notify(queue: self.syncQueue) {
                                    self.status = .synced
                                }
                            case .failure(let error):
                                self.status = .error(error)
                            }
                            self.isSyncing = false
                        }
                    case .failure(let error):
                        self.status = .error(error)
                        self.isSyncing = false
                    }
                }
            case .failure(let error):
                self.status = .error(error)
                self.isSyncing = false
            }
        }
    }

    private func ensureZoneExists(completion: @escaping (Result<Void, Error>) -> Void) {
        cloudKit.createPrivateZoneIfNeeded(completion: completion)
    }

    private func setupSubscriptionsIfNeeded() {
        guard !hasSetupSubscriptions else { return }
        hasSetupSubscriptions = true

        cloudKit.setupPrivateDatabaseSubscription { result in
            if case .failure(let error) = result {
                logError("Failed to setup private subscription: \(error.localizedDescription)")
            }
        }
        cloudKit.setupSharedDatabaseSubscription { result in
            if case .failure(let error) = result {
                logError("Failed to setup shared subscription: \(error.localizedDescription)")
            }
        }
        // Public DB subscription for group invitations
        if let email = AuthenticationManager.shared.currentUser?.email {
            cloudKit.setupPublicInvitationSubscription(email: email) { result in
                if case .failure(let error) = result {
                    logError("Failed to setup public invitation subscription: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Fetch Changes (Pull)

    private func fetchPrivateDatabaseChanges(completion: @escaping (Result<Void, Error>) -> Void) {
        let token = stateManager.changeToken(for: "privateDB", database: "private")

        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
        var changedZoneIDs: [CKRecordZone.ID] = []

        operation.recordZoneWithIDChangedBlock = { zoneID in
            changedZoneIDs.append(zoneID)
        }

        operation.fetchDatabaseChangesResultBlock = { [weak self] result in
            switch result {
            case .success(let (token, _)):
                self?.stateManager.saveChangeToken(token, for: "privateDB", database: "private")
                if changedZoneIDs.isEmpty {
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

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    private func fetchZoneChanges(
        zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]

        for zoneID in zoneIDs {
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = stateManager.changeToken(
                for: zoneID.zoneName,
                database: database == .private ? "private" : "shared"
            )
            configurations[zoneID] = config
        }

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: zoneIDs,
            configurationsByRecordZoneID: configurations
        )

        self.isProcessingCloudData = true

        operation.recordWasChangedBlock = { [weak self] recordID, result in
            switch result {
            case .success(let record):
                self?.processIncomingRecord(record)
            case .failure(let error):
                logError("Failed to fetch record \(recordID): \(error)")
            }
        }

        operation.recordWithIDWasDeletedBlock = { [weak self] recordID, recordType in
            self?.processDeletedRecord(recordID: recordID, recordType: recordType)
        }

        operation.recordZoneFetchResultBlock = { [weak self] zoneID, result in
            switch result {
            case .success(let (token, _, _)):
                let dbKey = database == .private ? "private" : "shared"
                self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: dbKey)
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                    let dbKey = database == .private ? "private" : "shared"
                    logWarning("Zone change token expired for \(zoneID.zoneName) — resetting")
                    self?.stateManager.saveChangeToken(nil, for: zoneID.zoneName, database: dbKey)
                } else {
                    logError("Zone fetch failed for \(zoneID.zoneName): \(error)")
                }
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { [weak self] result in
            self?.isProcessingCloudData = false
            switch result {
            case .success:
                // Post-sync fix: remap orphaned parent IDs + deduplicate recurring instances
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

        let db = database == .private ? cloudKit.privateDatabase : cloudKit.sharedDatabase
        operation.qualityOfService = .userInitiated
        db.add(operation)
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
        let pendingTransactions = txRepo.fetchPendingSync()
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
        let operation = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.isAtomic = false

        var hitQuotaLimit = false

        operation.perRecordSaveBlock = { [weak self] recordID, result in
            let name = recordID.recordName
            switch result {
            case .success:
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
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    if !hitQuotaLimit {
                        hitQuotaLimit = true
                        let retryAfter = ckError.retryAfterSeconds ?? 300
                        self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                        logWarning("CloudKit quota exceeded — throttling pushes for \(Int(retryAfter))s. Pending records will sync later.")
                        // Schedule a retry after the cooldown
                        self?.syncQueue.asyncAfter(deadline: .now() + retryAfter + 5) {
                            self?.pushThrottledUntil = nil
                            self?.pushLocalChanges()
                        }
                    }
                } else {
                    logError("Failed to push record \(recordID): \(error)")
                }
            }
        }

        operation.modifyRecordsResultBlock = { [weak self] result in
            if hitQuotaLimit {
                // Stop processing remaining batches — will retry after cooldown
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
                    logWarning("CloudKit quota exceeded (batch level) — throttling for \(Int(retryAfter))s")
                    self?.syncQueue.asyncAfter(deadline: .now() + retryAfter + 5) {
                        self?.pushThrottledUntil = nil
                        self?.pushLocalChanges()
                    }
                    completion?(.success(()))
                } else {
                    completion?(.failure(error))
                }
            }
        }

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    private func pushDeletes(_ deleteIDs: [CKRecord.ID], completion: ((Result<Void, Error>) -> Void)?) {
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: deleteIDs)
        operation.isAtomic = false

        operation.perRecordDeleteBlock = { [weak self] recordID, result in
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
                    logError("Failed to delete record \(recordID) from CloudKit: \(error)")
                }
            }
        }

        operation.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                    let retryAfter = ckError.retryAfterSeconds ?? 300
                    self?.pushThrottledUntil = Date().addingTimeInterval(retryAfter)
                    logWarning("CloudKit quota exceeded during deletes — will retry in \(Int(retryAfter))s")
                    self?.syncQueue.asyncAfter(deadline: .now() + retryAfter + 5) {
                        self?.pushThrottledUntil = nil
                        self?.pushLocalChanges()
                    }
                    completion?(.success(()))
                } else {
                    completion?(.failure(error))
                }
            }
        }

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    // MARK: - Process Incoming Records

    private func processIncomingRecord(_ record: CKRecord) {
        switch record.recordType {
        case "Transaction":
            guard let transaction = Transaction.fromCKRecord(record) else { return }
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
