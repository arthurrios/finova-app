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
        perRecordHandler: @escaping (CKRecord.ID, Result<CKRecord, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func deleteRecords(
        _ recordIDs: [CKRecord.ID],
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
        cloudKit.privateDatabase.add(operation)
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
        db.add(operation)
    }

    func saveRecords(
        _ records: [CKRecord],
        perRecordHandler: @escaping (CKRecord.ID, Result<CKRecord, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged
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

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    func deleteRecords(
        _ recordIDs: [CKRecord.ID],
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

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }
}
