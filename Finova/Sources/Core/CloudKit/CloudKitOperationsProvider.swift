//
//  CloudKitOperationsProvider.swift
//  Finova
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import Foundation

protocol CloudKitOperationsProvider {
    var isAvailable: Bool { get }
    func checkAccountStatus(completion: @escaping (CloudKitAccountStatus) -> Void)
    func ensureZoneExists(completion: @escaping (Result<Void, Error>) -> Void)
    func setupSubscriptions(email: String?)

    func fetchDatabaseChanges(
        token: CKServerChangeToken?,
        changedZoneHandler: @escaping (CKRecordZone.ID) -> Void,
        completion: @escaping (Result<CKServerChangeToken?, Error>) -> Void
    )

    /// Database-level changes for either scope. The shared database's variant was previously issued
    /// straight against `CloudKitManager.shared.sharedDatabase`, which is why the sync cycle could
    /// never complete under test: the operation simply never called back.
    func fetchDatabaseChanges(
        database: CKDatabase.Scope,
        token: CKServerChangeToken?,
        changedZoneHandler: @escaping (CKRecordZone.ID) -> Void,
        completion: @escaping (Result<CKServerChangeToken?, Error>) -> Void
    )

    /// Every zone in a database. Used by group discovery, which is on the sync cycle's critical
    /// path — so it has to be mockable or the cycle hangs waiting for it.
    func fetchAllZones(
        database: CKDatabase.Scope,
        completion: @escaping (Result<[CKRecordZone.ID], Error>) -> Void
    )

    /// All records of one type in one zone. Used by member discovery and group-record backfill.
    func queryRecords(
        recordType: String,
        zoneID: CKRecordZone.ID,
        database: CKDatabase.Scope,
        recordHandler: @escaping (CKRecord) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func fetchZoneChanges(
        zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope,
        tokenForZone: @escaping (CKRecordZone.ID) -> CKServerChangeToken?,
        recordHandler: @escaping (CKRecord) -> Void,
        deleteHandler: @escaping (CKRecord.ID, String) -> Void,
        zoneTokenHandler: @escaping (CKRecordZone.ID, CKServerChangeToken?) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func saveRecords(
        _ records: [CKRecord],
        database: CKDatabase.Scope,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        perRecordHandler: @escaping (CKRecord.ID, Result<CKRecord, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func deleteRecords(
        _ recordIDs: [CKRecord.ID],
        database: CKDatabase.Scope,
        perRecordHandler: @escaping (CKRecord.ID, Result<Void, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

// MARK: - RealCloudKitOperations

final class RealCloudKitOperations: CloudKitOperationsProvider {
    private let cloudKit = CloudKitManager.shared

    var isAvailable: Bool {
        cloudKit.isCloudKitAvailable
    }

    func checkAccountStatus(completion: @escaping (CloudKitAccountStatus) -> Void) {
        cloudKit.checkAccountStatus(completion: completion)
    }

    func ensureZoneExists(completion: @escaping (Result<Void, Error>) -> Void) {
        cloudKit.createPrivateZoneIfNeeded(completion: completion)
    }

    func setupSubscriptions(email: String?) {
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
        if let email = email {
            cloudKit.setupPublicInvitationSubscription(email: email) { result in
                if case .failure(let error) = result {
                    logError("Failed to setup public invitation subscription: \(error.localizedDescription)")
                }
            }
        }
        cloudKit.setupGroupActivitySubscriptions()
    }

    func fetchDatabaseChanges(
        token: CKServerChangeToken?,
        changedZoneHandler: @escaping (CKRecordZone.ID) -> Void,
        completion: @escaping (Result<CKServerChangeToken?, Error>) -> Void
    ) {
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)

        operation.recordZoneWithIDChangedBlock = { zoneID in
            changedZoneHandler(zoneID)
        }

        operation.fetchDatabaseChangesResultBlock = { result in
            switch result {
            case .success(let (newToken, _)):
                completion(.success(newToken))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        operation.qualityOfService = .userInitiated
        Self.applyTimeouts(to: operation)
        cloudKit.privateDatabase.add(operation)
    }

    private func database(_ scope: CKDatabase.Scope) -> CKDatabase {
        scope == .shared ? cloudKit.sharedDatabase : cloudKit.privateDatabase
    }

    func fetchDatabaseChanges(
        database scope: CKDatabase.Scope,
        token: CKServerChangeToken?,
        changedZoneHandler: @escaping (CKRecordZone.ID) -> Void,
        completion: @escaping (Result<CKServerChangeToken?, Error>) -> Void
    ) {
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
        operation.recordZoneWithIDChangedBlock = { changedZoneHandler($0) }
        operation.fetchDatabaseChangesResultBlock = { result in
            switch result {
            case .success(let (newToken, _)): completion(.success(newToken))
            case .failure(let error): completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        Self.applyTimeouts(to: operation)
        database(scope).add(operation)
    }

    func fetchAllZones(
        database scope: CKDatabase.Scope,
        completion: @escaping (Result<[CKRecordZone.ID], Error>) -> Void
    ) {
        let operation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
        var zoneIDs: [CKRecordZone.ID] = []
        operation.perRecordZoneResultBlock = { zoneID, result in
            if case .success = result { zoneIDs.append(zoneID) }
        }
        operation.fetchRecordZonesResultBlock = { result in
            switch result {
            case .success: completion(.success(zoneIDs))
            case .failure(let error): completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        Self.applyTimeouts(to: operation)
        database(scope).add(operation)
    }

    func queryRecords(
        recordType: String,
        zoneID: CKRecordZone.ID,
        database scope: CKDatabase.Scope,
        recordHandler: @escaping (CKRecord) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // FOLLOWS THE CURSOR. `queryResultBlock` yields `Result<CKQueryOperation.Cursor?, Error>`, and
        // CloudKit pages a query at roughly 100 records — so ignoring that cursor silently returns
        // only the FIRST PAGE and reports success. On a ledger of 1300 transactions that is not a
        // partial answer, it is a wrong one that looks complete: a caller diffing cloud against local
        // would conclude ~1200 records were missing from CloudKit.
        func run(_ operation: CKQueryOperation) {
            operation.zoneID = zoneID
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result { recordHandler(record) }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    if let cursor = cursor {
                        run(CKQueryOperation(cursor: cursor))
                    } else {
                        completion(.success(()))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            operation.qualityOfService = .userInitiated
            Self.applyTimeouts(to: operation)
            database(scope).add(operation)
        }

        run(CKQueryOperation(query: CKQuery(recordType: recordType, predicate: NSPredicate(value: true))))
    }

    func fetchZoneChanges(
        zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope,
        tokenForZone: @escaping (CKRecordZone.ID) -> CKServerChangeToken?,
        recordHandler: @escaping (CKRecord) -> Void,
        deleteHandler: @escaping (CKRecord.ID, String) -> Void,
        zoneTokenHandler: @escaping (CKRecordZone.ID, CKServerChangeToken?) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for zoneID in zoneIDs {
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = tokenForZone(zoneID)
            configurations[zoneID] = config
        }

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: zoneIDs,
            configurationsByRecordZoneID: configurations
        )

        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case .success(let record):
                recordHandler(record)
            case .failure(let error):
                logError("Failed to fetch record \(recordID): \(error)")
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, recordType in
            deleteHandler(recordID, recordType)
        }

        operation.recordZoneFetchResultBlock = { zoneID, result in
            switch result {
            case .success(let (token, _, _)):
                zoneTokenHandler(zoneID, token)
            case .failure(let error):
                logError("Zone fetch failed for \(zoneID.zoneName): \(error)")
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        let db = database == .private ? cloudKit.privateDatabase : cloudKit.sharedDatabase
        operation.qualityOfService = .userInitiated
        Self.applyTimeouts(to: operation)
        db.add(operation)
    }

    func saveRecords(
        _ records: [CKRecord],
        database: CKDatabase.Scope,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged,
        perRecordHandler: @escaping (CKRecord.ID, Result<CKRecord, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = savePolicy
        operation.isAtomic = false

        operation.perRecordSaveBlock = { recordID, result in
            perRecordHandler(recordID, result)
        }

        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        let db = database == .private ? cloudKit.privateDatabase : cloudKit.sharedDatabase
        operation.qualityOfService = .userInitiated
        Self.applyTimeouts(to: operation)
        db.add(operation)
    }

    func deleteRecords(
        _ recordIDs: [CKRecord.ID],
        database: CKDatabase.Scope,
        perRecordHandler: @escaping (CKRecord.ID, Result<Void, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        operation.isAtomic = false

        operation.perRecordDeleteBlock = { recordID, result in
            perRecordHandler(recordID, result)
        }

        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        let db = database == .private ? cloudKit.privateDatabase : cloudKit.sharedDatabase
        operation.qualityOfService = .userInitiated
        Self.applyTimeouts(to: operation)
        db.add(operation)
    }

    // MARK: - Timeout Configuration

    private static func applyTimeouts(to operation: CKOperation) {
        operation.configuration.timeoutIntervalForRequest = 30
        operation.configuration.timeoutIntervalForResource = 60
    }
}
