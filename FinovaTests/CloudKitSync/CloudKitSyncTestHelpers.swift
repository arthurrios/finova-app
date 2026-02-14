//
//  CloudKitSyncTestHelpers.swift
//  FinovaTests
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import XCTest

@testable import Finova

// MARK: - MockCloudStore

/// In-memory CKRecord storage simulating CloudKit.
final class MockCloudStore {
    private var records: [String: CKRecord] = [:]
    private var deletedRecordNames: Set<String> = []

    private static let testZoneID = CKRecordZone.ID(
        zoneName: "TestZone",
        ownerName: CKCurrentUserDefaultName
    )

    static var zoneID: CKRecordZone.ID { testZoneID }

    func save(_ record: CKRecord) {
        records[record.recordID.recordName] = record
        deletedRecordNames.remove(record.recordID.recordName)
    }

    func save(_ records: [CKRecord]) {
        for record in records {
            save(record)
        }
    }

    func delete(recordName: String) {
        records.removeValue(forKey: recordName)
        deletedRecordNames.insert(recordName)
    }

    func fetchAll() -> [CKRecord] {
        Array(records.values)
    }

    func fetchAll(recordType: String) -> [CKRecord] {
        records.values.filter { $0.recordType == recordType }
    }

    func fetch(recordName: String) -> CKRecord? {
        records[recordName]
    }

    func fetchChanges(since date: Date?) -> [CKRecord] {
        guard let date = date else { return fetchAll() }
        return records.values.filter { record in
            guard let modDate = record.modificationDate else { return true }
            return modDate > date
        }
    }

    func fetchDeleted() -> [String] {
        Array(deletedRecordNames)
    }

    func reset() {
        records.removeAll()
        deletedRecordNames.removeAll()
    }
}

// MARK: - DeviceSimulator

/// Encapsulates a "device" with its own user context for sync testing.
final class DeviceSimulator {
    let userUID: String
    let mockCloud: MockCloudStore
    let transactionRepo: TransactionRepository
    let budgetRepo: BudgetRepository
    let groupRepo: BudgetGroupRepository

    init(userUID: String, mockCloud: MockCloudStore) {
        self.userUID = userUID
        self.mockCloud = mockCloud
        self.transactionRepo = TransactionRepository()
        self.budgetRepo = BudgetRepository()
        self.groupRepo = BudgetGroupRepository()
    }

    /// Activates this device's user context.
    func activate() {
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        TransactionRepository.invalidateCache()
    }

    // MARK: - Push

    /// Push pending transactions to mock cloud.
    func pushTransactions() {
        activate()
        let pending = transactionRepo.fetchPendingSync()
        let zoneID = MockCloudStore.zoneID

        for tx in pending {
            guard let txId = tx.id else { continue }

            let storedName = transactionRepo.fetchCKRecordName(for: txId)
            let record = tx.toCKRecord(in: zoneID, storedRecordName: storedName)

            // Store the CK record name locally before saving to cloud
            if storedName == nil {
                transactionRepo.setCKRecordId(for: txId, ckRecordName: record.recordID.recordName)
            }

            // Include shared_group_id in the CKRecord
            if let groupId = transactionRepo.fetchSharedGroupId(for: txId) {
                record["sharedGroupId"] = groupId as CKRecordValue
            }

            mockCloud.save(record)
            transactionRepo.markAsSynced(ckRecordName: record.recordID.recordName)
        }
    }

    /// Push pending budgets to mock cloud.
    func pushBudgets() {
        activate()
        let pending = budgetRepo.fetchPendingSync()
        let zoneID = MockCloudStore.zoneID

        for budget in pending {
            let record = budget.toCKRecord(in: zoneID)

            // Store the CK record name locally
            budgetRepo.setCKRecordId(forMonthDate: budget.monthDate, ckRecordName: record.recordID.recordName)

            mockCloud.save(record)
            budgetRepo.markAsSynced(ckRecordName: record.recordID.recordName)
        }
    }

    /// Push all pending data to mock cloud.
    func pushAll() {
        pushTransactions()
        pushBudgets()
    }

    // MARK: - Pull

    /// Pull transactions from mock cloud and resolve conflicts.
    func pullTransactions() {
        activate()
        let cloudRecords = mockCloud.fetchAll(recordType: "Transaction")

        for ckRecord in cloudRecords {
            guard let remote = Transaction.fromCKRecord(ckRecord) else { continue }
            ConflictResolver.shared.resolveTransaction(remote: remote, ckRecord: ckRecord)
        }

        transactionRepo.fixAndDeduplicateAfterSync()
        TransactionRepository.invalidateCache()
    }

    /// Pull budgets from mock cloud and resolve conflicts.
    func pullBudgets() {
        activate()
        let cloudRecords = mockCloud.fetchAll(recordType: "Budget")

        for ckRecord in cloudRecords {
            guard let remote = BudgetModel.fromCKRecord(ckRecord) else { continue }
            ConflictResolver.shared.resolveBudget(remote: remote, ckRecord: ckRecord)
        }
    }

    /// Pull all data from mock cloud.
    func pullAll() {
        pullTransactions()
        pullBudgets()
    }

    // MARK: - Push Deletes

    /// Push pending deletes to mock cloud.
    func pushTransactionDeletes() {
        activate()
        let pendingDeletes = transactionRepo.fetchPendingDeletes()
        for pending in pendingDeletes {
            mockCloud.delete(recordName: pending.ckRecordName)
            transactionRepo.hardDeleteByCKRecordName(pending.ckRecordName)
        }
    }

    // MARK: - Pull Deletes

    /// Pull deletions from mock cloud.
    func pullTransactionDeletes() {
        activate()
        let deletedNames = mockCloud.fetchDeleted()
        for name in deletedNames {
            transactionRepo.softDeleteByCKRecordName(name)
        }
        TransactionRepository.invalidateCache()
    }

    // MARK: - Cleanup

    func cleanup() {
        activate()
        transactionRepo.clearAllTransactionsForTesting()
        TransactionRepository.invalidateCache()
    }
}

// MARK: - Factory Methods

extension CloudKitSyncTestHelpers {

    static func makeTransactionModel(
        title: String = "Test Transaction",
        category: String = "market",
        amount: Int = 5000,
        type: String = "expense",
        dateTimestamp: Int? = nil,
        budgetMonthDate: Int? = nil,
        isRecurring: Bool? = nil,
        hasInstallments: Bool? = nil,
        parentTransactionId: Int? = nil,
        installmentNumber: Int? = nil,
        totalInstallments: Int? = nil,
        originalAmount: Int? = nil,
        creditCardId: Int? = nil,
        statementId: Int? = nil,
        isCreditCardStatement: Bool? = nil
    ) -> TransactionModel {
        let now = Date()
        let ts = dateTimestamp ?? Int(now.timeIntervalSince1970)
        let bmd = budgetMonthDate ?? now.monthAnchor

        return TransactionModel(
            title: title,
            category: category,
            amount: amount,
            type: type,
            dateTimestamp: ts,
            budgetMonthDate: bmd,
            isRecurring: isRecurring,
            hasInstallments: hasInstallments,
            parentTransactionId: parentTransactionId,
            originalAmount: originalAmount,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            creditCardId: creditCardId,
            statementId: statementId,
            isCreditCardStatement: isCreditCardStatement
        )
    }

    static func makeBudgetModel(
        monthDate: Int? = nil,
        amount: Int = 200000,
        sharedGroupId: String? = nil
    ) -> BudgetModel {
        let md = monthDate ?? Date().monthAnchor
        return BudgetModel(monthDate: md, amount: amount, sharedGroupId: sharedGroupId)
    }

    static func makeGroup(
        name: String = "Test Group",
        ownerId: String,
        ownerName: String = "Owner",
        ownerEmail: String = "owner@test.com"
    ) -> BudgetGroup {
        return BudgetGroup(
            name: name,
            ownerId: ownerId,
            ownerName: ownerName,
            ownerEmail: ownerEmail
        )
    }

    static func makeInvitation(
        groupId: String,
        groupName: String = "Test Group",
        inviterName: String = "Owner",
        inviterEmail: String = "owner@test.com",
        inviteeEmail: String = "member@test.com"
    ) -> GroupInvitation {
        return GroupInvitation(
            groupId: groupId,
            groupName: groupName,
            inviterName: inviterName,
            inviterEmail: inviterEmail,
            inviteeEmail: inviteeEmail
        )
    }

    /// Create a CKRecord for a transaction with controlled modificationDate.
    static func makeCKRecord(
        from transaction: Transaction,
        recordName: String? = nil,
        modificationDate: Date = Date(),
        sharedGroupId: String? = nil
    ) -> CKRecord {
        let zoneID = MockCloudStore.zoneID
        let name = recordName ?? "transaction-\(UUID().uuidString)"
        let record = transaction.toCKRecord(in: zoneID, storedRecordName: name)

        if let groupId = sharedGroupId {
            record["sharedGroupId"] = groupId as CKRecordValue
        }

        // Simulate CloudKit setting the modificationDate by creating a new record
        // with the same data (CKRecord modificationDate is read-only, but in tests
        // we work around this by using the record directly)
        return record
    }

    static func makeBudgetCKRecord(
        from budget: BudgetModel,
        modificationDate: Date = Date()
    ) -> CKRecord {
        let zoneID = MockCloudStore.zoneID
        return budget.toCKRecord(in: zoneID)
    }
}

/// Namespace for test helpers.
enum CloudKitSyncTestHelpers {}
