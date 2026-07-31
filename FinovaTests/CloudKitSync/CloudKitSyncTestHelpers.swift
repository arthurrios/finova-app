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

    /// Vends a COPY, never the stored instance.
    ///
    /// Real CloudKit deserializes a fresh `CKRecord` per fetch, per device. Returning the stored
    /// instance let one device's in-place mutations — `SyncEngine.remapCrossDeviceIDs` rewrites
    /// `creditCardId`/`statementId` on the record it is handed — leak into the "cloud" and corrupt
    /// what every other device subsequently reads. That made results order-dependent and produced
    /// failures that vanished when a test was run alone.
    private func copy(_ record: CKRecord) -> CKRecord {
        // swiftlint:disable:next force_cast
        record.copy() as! CKRecord
    }

    func fetchAll() -> [CKRecord] {
        records.values.map(copy)
    }

    func fetchAll(recordType: String) -> [CKRecord] {
        records.values.filter { $0.recordType == recordType }.map(copy)
    }

    func fetch(recordName: String) -> CKRecord? {
        records[recordName].map(copy)
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

/// One simulated device: its **own** SQLite database, its own repositories, and its own conflict
/// resolver, all sharing a single `MockCloudStore` that stands in for CloudKit.
///
/// Previously every `DeviceSimulator` used `DBHelper.shared` — one singleton on one fixed file — so
/// "device A" and "device B" were the same database, and `activate()` merely flipped a uid that was
/// identical for both. `testCreateOnA_SyncToB` therefore passed because the row had never gone
/// anywhere. The whole cross-device suite would pass with sync switched off.
final class DeviceSimulator {
    let userUID: String
    let mockCloud: MockCloudStore
    let db: DBHelper
    let dbPath: URL
    let transactionRepo: TransactionRepository
    let budgetRepo: BudgetRepository
    let groupRepo: BudgetGroupRepository
    let cardRepo: CreditCardRepository
    let statementRepo: StatementRepository
    let allocationRepo: BudgetAllocationRepository
    let resolver: ConflictResolver

    /// - Parameter label: distinguishes this device's database file; use "A"/"B".
    init(userUID: String, mockCloud: MockCloudStore, label: String = UUID().uuidString) {
        self.userUID = userUID
        self.mockCloud = mockCloud
        self.dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaTest-\(label)-\(UUID().uuidString).sqlite")
        self.db = DBHelper(path: dbPath)
        self.transactionRepo = TransactionRepository(db: db)
        self.budgetRepo = BudgetRepository(db: db)
        self.groupRepo = BudgetGroupRepository(db: db)
        self.cardRepo = CreditCardRepository(db: db)
        self.statementRepo = StatementRepository(db: db)
        self.allocationRepo = BudgetAllocationRepository(db: db)
        self.resolver = ConflictResolver(db: db)
    }

    /// Activates this device's user context.
    ///
    /// `TransactionRepository`'s cache is static, so it must be invalidated whenever the active
    /// device changes or one device will read the other's cached rows — the isolation is in the
    /// database, not in that cache.
    func activate() {
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        TransactionRepository.invalidateCache()
    }

    // MARK: - Convergence

    /// Every synced column of every synced row, ordered deterministically, for A-vs-B comparison.
    ///
    /// This is the assertion that matters: not "B received the record" but "A and B agree".
    /// Excludes columns that are legitimately device-local — the local autoincrement `id`, the
    /// integer foreign keys derived from it, and `sync_status`/`ck_modified_at` bookkeeping.
    func dataFingerprint() -> [String] {
        activate()
        var lines: [String] = []

        for tx in transactionRepo.fetchAllTransactions().sorted(by: { $0.title < $1.title }) {
            let ck = tx.id.flatMap { transactionRepo.fetchCKRecordName(for: $0) } ?? "-"
            lines.append("TX|\(ck)|\(tx.title)|\(tx.amount)|\(tx.budgetMonthDate)|\(tx.category.rawValue)|\(tx.type.rawValue)")
        }
        for b in budgetRepo.fetchBudgets().sorted(by: { $0.monthDate < $1.monthDate }) {
            lines.append("BUDGET|\(b.monthDate)|\(b.amount)")
        }
        for c in cardRepo.fetchAllCards(userId: userUID).sorted(by: { $0.name < $1.name }) {
            lines.append("CARD|\(c.name)|\(c.lastFourDigits)|\(c.closingDay)|\(c.dueDay)")
        }
        return lines.sorted()
    }

    // MARK: - Cleanup

    /// Closes and removes this device's database file.
    func destroy() {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: dbPath.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
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
            // `db:` is essential — the adapter reads this row's identity and its referents' CK
            // names, and defaulting to .shared would read the other device's database.
            let record = tx.toCKRecord(in: zoneID, storedRecordName: storedName, db: db)

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

    /// Push pending credit cards to mock cloud.
    func pushCards() {
        activate()
        let zoneID = MockCloudStore.zoneID
        for card in cardRepo.fetchPendingSync() {
            guard let cardId = card.id else { continue }
            let storedName = cardRepo.fetchCKRecordName(for: cardId)
            let record = card.toCKRecord(in: zoneID, storedRecordName: storedName, db: db)
            if storedName == nil {
                cardRepo.setCKRecordId(for: cardId, ckRecordName: record.recordID.recordName)
            }
            mockCloud.save(record)
            cardRepo.markAsSynced(ckRecordName: record.recordID.recordName)
        }
    }

    /// Push all pending data to mock cloud.
    ///
    /// Cards go FIRST: a transaction's `creditCardCKRecordName` is only populated once its card has
    /// a `ck_record_id`, so pushing transactions first would ship them with a nil card reference —
    /// the same ordering constraint the real `pushLocalChanges` enforces.
    func pushAll() {
        // Mirrors SyncEngine.pushLocalChanges: rows created since the last push need their uuid
        // foreign keys filled in before they can carry their relationships over the wire.
        activate()
        db.deriveUuidForeignKeys()
        pushCards()
        pushTransactions()
        pushBudgets()
    }

    // MARK: - Pull

    /// Pull transactions from mock cloud and resolve conflicts.
    func pullTransactions() {
        activate()
        let cloudRecords = mockCloud.fetchAll(recordType: "Transaction")

        for ckRecord in cloudRecords {
            // Faithfully reproduce the production pull path: SyncEngine rewrites the record's
            // foreign keys from the sender's local integers to this device's before parsing.
            // Omitting this would make the harness fail for a reason the real app doesn't have.
            SyncEngine.remapCrossDeviceIDs(in: ckRecord, db: db)
            guard let remote = Transaction.fromCKRecord(ckRecord) else { continue }
            resolver.resolveTransaction(remote: remote, ckRecord: ckRecord)
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
            resolver.resolveBudget(remote: remote, ckRecord: ckRecord)
        }
    }

    /// Pull credit cards from mock cloud and resolve conflicts.
    func pullCards() {
        activate()
        for ckRecord in mockCloud.fetchAll(recordType: "CreditCard") {
            guard let remote = CreditCard.fromCKRecord(ckRecord) else { continue }
            resolver.resolveCreditCard(remote: remote, ckRecord: ckRecord)
        }
    }

    /// Pull all data from mock cloud.
    ///
    /// Cards before transactions, mirroring `SyncRecordCategory` ordering in the real engine, so a
    /// transaction's card reference can resolve on arrival.
    func pullAll() {
        pullCards()
        pullTransactions()
        pullBudgets()
        // Mirrors SyncEngine.processBufferedRecords: resolve uuid pointers into local integer FKs
        // once the whole batch has landed.
        db.resolveUuidForeignKeys()
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
            transactionRepo.deleteFromCloud(ckRecordName: name)
        }
        TransactionRepository.invalidateCache()
    }

    // MARK: - Cleanup

    func cleanup() {
        activate()
        transactionRepo.clearAllTransactionsForTesting()
        TransactionRepository.invalidateCache()
        destroy()
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
