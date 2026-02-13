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
    }

    // MARK: - Public API

    func performFullSync() {
        syncQueue.async { [weak self] in
            self?.executeSyncCycle()
        }
    }

    @objc private func handleRemoteNotification() {
        performFullSync()
    }

    @objc private func handleLocalDataChange() {
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
                                self.status = .synced
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
            switch result {
            case .success:
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
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

    private static let batchSize = 400

    private func pushLocalChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        let transactionRepo = TransactionRepository()
        let pendingTransactions = transactionRepo.fetchPendingSync()

        guard !pendingTransactions.isEmpty else {
            completion?(.success(()))
            return
        }

        let records = pendingTransactions.map {
            $0.toCKRecord(in: CloudKitManager.privateZoneID)
        }

        let batches = stride(from: 0, to: records.count, by: Self.batchSize).map {
            Array(records[$0..<min($0 + Self.batchSize, records.count)])
        }

        pushBatches(batches, index: 0, completion: completion)
    }

    private func pushBatches(
        _ batches: [[CKRecord]],
        index: Int,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard index < batches.count else {
            completion?(.success(()))
            return
        }

        let batch = batches[index]
        let operation = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.isAtomic = false

        operation.perRecordSaveBlock = { recordID, result in
            switch result {
            case .success:
                TransactionRepository().markAsSynced(ckRecordName: recordID.recordName)
            case .failure(let error):
                logError("Failed to push record \(recordID): \(error)")
            }
        }

        operation.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.pushBatches(batches, index: index + 1, completion: completion)
            case .failure(let error):
                completion?(.failure(error))
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
            break
        case "CreditCard":
            break
        case "GroupActivity":
            processGroupActivity(record)
        default:
            logWarning("Unknown record type received: \(record.recordType)")
        }
    }

    private func processDeletedRecord(recordID: CKRecord.ID, recordType: String) {
        switch recordType {
        case "Transaction":
            TransactionRepository().softDeleteByCKRecordName(recordID.recordName)
        default:
            break
        }
    }

    private func processGroupActivity(_ record: CKRecord) {
        GroupNotificationManager.shared.handleIncomingActivity(record)
    }
}
