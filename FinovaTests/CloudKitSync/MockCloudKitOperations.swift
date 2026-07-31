//
//  MockCloudKitOperations.swift
//  FinovaTests
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import XCTest

@testable import Finova

// MARK: - MockCloudKitOperations

final class MockCloudKitOperations: CloudKitOperationsProvider {
    let mockCloud: MockCloudStore

    var mockIsAvailable: Bool = true
    var mockAccountStatus: CloudKitAccountStatus = .available

    // Error injection
    var ensureZoneError: Error?
    var fetchChangesError: Error?
    var saveError: Error?
    var deleteError: Error?
    var perRecordSaveErrors: [String: Error] = [:]

    // Call tracking
    private(set) var ensureZoneCallCount = 0
    private(set) var setupSubscriptionsCallCount = 0
    private(set) var fetchDatabaseChangesCallCount = 0
    private(set) var fetchZoneChangesCallCount = 0
    private(set) var saveRecordsCallCount = 0
    private(set) var deleteRecordsCallCount = 0
    private(set) var checkAccountStatusCallCount = 0

    // Saved data tracking
    private(set) var lastSavedRecords: [CKRecord] = []
    private(set) var lastDeletedRecordIDs: [CKRecord.ID] = []
    private(set) var lastSavePolicy: CKModifyRecordsOperation.RecordSavePolicy?
    private(set) var fetchAllZonesCallCount = 0
    private(set) var queryRecordsCallCount = 0

    init(mockCloud: MockCloudStore) {
        self.mockCloud = mockCloud
    }

    var isAvailable: Bool {
        mockIsAvailable
    }

    func checkAccountStatus(completion: @escaping (CloudKitAccountStatus) -> Void) {
        checkAccountStatusCallCount += 1
        completion(mockAccountStatus)
    }

    func ensureZoneExists(completion: @escaping (Result<Void, Error>) -> Void) {
        ensureZoneCallCount += 1
        if let error = ensureZoneError {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    func setupSubscriptions(email: String?) {
        setupSubscriptionsCallCount += 1
    }

    func fetchDatabaseChanges(
        token: CKServerChangeToken?,
        changedZoneHandler: @escaping (CKRecordZone.ID) -> Void,
        completion: @escaping (Result<CKServerChangeToken?, Error>) -> Void
    ) {
        fetchDatabaseChangesCallCount += 1

        if let error = fetchChangesError {
            completion(.failure(error))
            return
        }

        // Report the private zone as changed if mock cloud has records or deletions
        let hasRecords = !mockCloud.fetchAll().isEmpty
        let hasDeletions = !mockCloud.fetchDeleted().isEmpty
        if hasRecords || hasDeletions {
            changedZoneHandler(CloudKitManager.privateZoneID)
        }

        completion(.success(nil))
    }

    /// The shared database has nothing in it unless a test says otherwise, and — critically — it
    /// CALLS BACK. The real implementation was issued straight against
    /// `CloudKitManager.shared.sharedDatabase`, which on a simulator with no iCloud account never
    /// completes, so `executeSyncCycle` hung with `isSyncing = true` and every test timed out.
    func fetchDatabaseChanges(
        database: CKDatabase.Scope,
        token: CKServerChangeToken?,
        changedZoneHandler: @escaping (CKRecordZone.ID) -> Void,
        completion: @escaping (Result<CKServerChangeToken?, Error>) -> Void
    ) {
        guard database == .private else {
            completion(.success(nil))
            return
        }
        fetchDatabaseChanges(
            token: token, changedZoneHandler: changedZoneHandler, completion: completion)
    }

    /// Zones the mock cloud actually holds records in. Group discovery walks this, and it is on the
    /// sync cycle's critical path.
    func fetchAllZones(
        database: CKDatabase.Scope,
        completion: @escaping (Result<[CKRecordZone.ID], Error>) -> Void
    ) {
        fetchAllZonesCallCount += 1
        guard database == .private else {
            completion(.success([]))
            return
        }
        var zoneIDs = Set([CloudKitManager.privateZoneID, MockCloudStore.zoneID])
        for record in mockCloud.fetchAll() { zoneIDs.insert(record.recordID.zoneID) }
        completion(.success(Array(zoneIDs)))
    }

    func queryRecords(
        recordType: String,
        zoneID: CKRecordZone.ID,
        database: CKDatabase.Scope,
        recordHandler: @escaping (CKRecord) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queryRecordsCallCount += 1
        for record in mockCloud.fetchAll(inZone: zoneID) where record.recordType == recordType {
            recordHandler(record)
        }
        completion(.success(()))
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
        fetchZoneChangesCallCount += 1

        if let error = fetchChangesError {
            completion(.failure(error))
            return
        }

        // Deliver all records from mock cloud
        for record in mockCloud.fetchAll() {
            recordHandler(record)
        }

        // Deliver all deletions from mock cloud
        for deletedName in mockCloud.fetchDeleted() {
            let recordID = CKRecord.ID(recordName: deletedName, zoneID: CloudKitManager.privateZoneID)
            // Infer record type from name prefix
            let recordType = Self.inferRecordType(from: deletedName)
            deleteHandler(recordID, recordType)
        }

        // Report zone token
        for zoneID in zoneIDs {
            zoneTokenHandler(zoneID, nil)
        }

        completion(.success(()))
    }

    func saveRecords(
        _ records: [CKRecord],
        database: CKDatabase.Scope,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        perRecordHandler: @escaping (CKRecord.ID, Result<CKRecord, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        saveRecordsCallCount += 1
        lastSavedRecords = records
        lastSavePolicy = savePolicy

        if let error = saveError {
            completion(.failure(error))
            return
        }

        for record in records {
            if let perRecordError = perRecordSaveErrors[record.recordID.recordName] {
                perRecordHandler(record.recordID, .failure(perRecordError))
            } else {
                mockCloud.save(record)
                perRecordHandler(record.recordID, .success(record))
            }
        }

        completion(.success(()))
    }

    func deleteRecords(
        _ recordIDs: [CKRecord.ID],
        database: CKDatabase.Scope,
        perRecordHandler: @escaping (CKRecord.ID, Result<Void, Error>) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        deleteRecordsCallCount += 1
        lastDeletedRecordIDs = recordIDs

        if let error = deleteError {
            completion(.failure(error))
            return
        }

        for recordID in recordIDs {
            mockCloud.delete(recordName: recordID.recordName)
            perRecordHandler(recordID, .success(()))
        }

        completion(.success(()))
    }

    // MARK: - Helpers

    static func inferRecordType(from recordName: String) -> String {
        if recordName.hasPrefix("transaction-") { return "Transaction" }
        if recordName.hasPrefix("budget-") { return "Budget" }
        if recordName.hasPrefix("creditCard-") { return "CreditCard" }
        if recordName.hasPrefix("statement-") { return "CreditCardStatement" }
        if recordName.hasPrefix("allocation-") { return "BudgetAllocation" }
        return "Unknown"
    }
}

// MARK: - MockPostSyncActions

final class MockPostSyncActions: PostSyncActions {
    private(set) var performPostSyncFetchesCallCount = 0

    func performPostSyncFetches(completion: @escaping () -> Void) {
        performPostSyncFetchesCallCount += 1
        completion()
    }
}
