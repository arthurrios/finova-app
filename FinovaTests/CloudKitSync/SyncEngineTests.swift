//
//  SyncEngineTests.swift
//  FinovaTests
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import XCTest

@testable import Finova

final class SyncEngineTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var mockOps: MockCloudKitOperations!
    private var mockPostSync: MockPostSyncActions!
    private var syncEngine: SyncEngine!
    private var txRepo: TransactionRepository!
    private var budgetRepo: BudgetRepository!

    override func setUp() {
        super.setUp()
        userUID = "test_sync_engine_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID

        mockCloud = MockCloudStore()
        mockOps = MockCloudKitOperations(mockCloud: mockCloud)
        mockPostSync = MockPostSyncActions()
        syncEngine = SyncEngine(cloudKitOps: mockOps, postSyncActions: mockPostSync)
        txRepo = TransactionRepository()
        budgetRepo = BudgetRepository()
    }

    override func tearDown() {
        txRepo.clearAllTransactionsForTesting()
        TransactionRepository.invalidateCache()
        for budget in budgetRepo.fetchBudgets() {
            try? budgetRepo.delete(monthDate: budget.monthDate)
        }
        mockCloud.reset()
        SyncStateManager.shared.resetAllTokens()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    private func performSyncAndWait() {
        let exp = expectation(description: "sync completes")
        syncEngine.performFullSync {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
    }

    private func makeTransaction(
        title: String,
        amount: Int,
        category: TransactionCategory = .market,
        type: TransactionType = .expense
    ) -> Transaction {
        let now = Date()
        let data = UITransactionData(
            id: nil,
            title: title,
            amount: amount,
            dateTimestamp: Int(now.timeIntervalSince1970),
            budgetMonthDate: now.monthAnchor,
            isRecurring: nil,
            hasInstallments: nil,
            parentTransactionId: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            category: category,
            type: type
        )
        return Transaction(data: data)
    }

    // MARK: - Full Sync Cycle

    func testFullSyncCycle_Success() {
        performSyncAndWait()

        XCTAssertEqual(mockOps.ensureZoneCallCount, 1, "Zone should be created")
        XCTAssertEqual(mockOps.setupSubscriptionsCallCount, 1, "Subscriptions should be set up")
        XCTAssertEqual(mockOps.fetchDatabaseChangesCallCount, 1, "Should fetch database changes")
        XCTAssertEqual(mockPostSync.performPostSyncFetchesCallCount, 1, "Post-sync actions should run")
        assertSynced()
    }

    func testFullSyncCycle_ConcurrencyGuard() {
        // Start first sync — it blocks until completion
        let exp1 = expectation(description: "sync 1 completes")
        let exp2 = expectation(description: "sync 2 completes")

        syncEngine.performFullSync {
            exp1.fulfill()
        }
        syncEngine.performFullSync {
            exp2.fulfill()
        }

        wait(for: [exp1, exp2], timeout: 5.0)

        // Zone creation should only happen once (second sync was rejected by isSyncing guard)
        XCTAssertEqual(mockOps.ensureZoneCallCount, 1, "Only one sync cycle should have run")
    }

    func testFullSyncCycle_AccountUnavailable() {
        mockOps.mockIsAvailable = false
        mockOps.mockAccountStatus = .noAccount

        performSyncAndWait()

        XCTAssertEqual(mockOps.checkAccountStatusCallCount, 1, "Should check account status when unavailable")
        XCTAssertEqual(mockOps.ensureZoneCallCount, 0, "Should not proceed when account unavailable")
        assertIdle()
    }

    func testFullSyncCycle_AccountCheckFallback() {
        mockOps.mockIsAvailable = false
        mockOps.mockAccountStatus = .available

        performSyncAndWait()

        XCTAssertEqual(mockOps.checkAccountStatusCallCount, 1, "Should check account status")
        XCTAssertEqual(mockOps.ensureZoneCallCount, 1, "Should proceed when account check returns available")
        assertSynced()
    }

    // MARK: - Push Flow

    func testPush_TransactionsCollectedAndSent() {
        for i in 1...3 {
            let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "TX \(i)", amount: i * 1000)
            try! txRepo.insertTransaction(model)
        }

        performSyncAndWait()

        XCTAssertEqual(mockOps.saveRecordsCallCount, 1, "Should save one batch")
        XCTAssertEqual(mockOps.lastSavedRecords.count, 3, "Should push 3 records")
        XCTAssertEqual(mockCloud.fetchAll().count, 3, "Mock cloud should have 3 records")
    }

    func testPush_BatchesOf50() {
        for i in 1...120 {
            let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "TX \(i)", amount: i * 100)
            try! txRepo.insertTransaction(model)
        }

        let exp = expectation(description: "sync completes")
        syncEngine.performFullSync {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 15.0)

        XCTAssertEqual(mockOps.saveRecordsCallCount, 3, "Should send 3 batches (50+50+20)")
    }

    func testPush_RecordsMarkedSyncedAfterPush() {
        for i in 1...3 {
            let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "TX \(i)", amount: i * 1000)
            try! txRepo.insertTransaction(model)
        }

        TransactionRepository.invalidateCache()
        XCTAssertEqual(txRepo.fetchPendingSync().count, 3, "Should have 3 pending before sync")

        performSyncAndWait()

        TransactionRepository.invalidateCache()
        let pendingAfter = TransactionRepository().fetchPendingSync()
        XCTAssertEqual(pendingAfter.count, 0, "Should have 0 pending after sync")
    }

    func testPush_SharedGroupIdIncluded() {
        let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "Group TX", amount: 5000)
        let txId = try! txRepo.insertTransactionAndGetId(model)

        // Set shared group ID on the transaction
        DBHelper.shared.executeSyncUpdate(
            "UPDATE Transactions SET shared_group_id = 'group-abc-123', sync_status = 'pending' WHERE id = ?;",
            intBindings: [txId]
        )
        TransactionRepository.invalidateCache()

        performSyncAndWait()

        XCTAssertEqual(mockOps.saveRecordsCallCount, 1)
        let savedRecord = mockOps.lastSavedRecords.first
        XCTAssertNotNil(savedRecord)
        XCTAssertEqual(savedRecord?["sharedGroupId"] as? String, "group-abc-123")
    }

    func testPush_DeletesSentAfterSaves() {
        // Insert and sync a transaction first
        let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "To Delete", amount: 3000)
        try! txRepo.insertTransaction(model)
        performSyncAndWait()

        // Now delete it locally
        let txs = txRepo.fetchAllTransactions()
        guard let txId = txs.first?.id else {
            XCTFail("No transaction to delete")
            return
        }
        try! txRepo.delete(id: txId)

        // Clear mock cloud so the second sync's pull phase doesn't re-process
        // the previously-pushed record (mock doesn't track change tokens)
        mockCloud.reset()

        // Create fresh engine for second sync (reset subscriptions flag)
        let engine2 = SyncEngine(cloudKitOps: mockOps, postSyncActions: mockPostSync)
        let exp = expectation(description: "sync 2 completes")
        engine2.performFullSync {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)

        XCTAssertGreaterThan(mockOps.deleteRecordsCallCount, 0, "Should push deletes to cloud")
    }

    func testPush_NoPendingRecords_SkipsPush() {
        performSyncAndWait()

        // No data was inserted, so no save/delete calls
        XCTAssertEqual(mockOps.saveRecordsCallCount, 0, "Should not call save when no pending records")
        XCTAssertEqual(mockOps.deleteRecordsCallCount, 0, "Should not call delete when no pending records")
    }

    // MARK: - Pull Flow

    func testPull_RecordsFromCloud_ProcessedLocally() {
        // Pre-populate mock cloud with 2 transactions
        let zoneID = CloudKitManager.privateZoneID
        for i in 1...2 {
            let transaction = makeTransaction(title: "Cloud TX \(i)", amount: i * 1000)
            mockCloud.save(transaction.toCKRecord(in: zoneID))
        }

        performSyncAndWait()

        XCTAssertEqual(mockOps.fetchZoneChangesCallCount, 1, "Should fetch zone changes")
        let localTxs = txRepo.fetchAllTransactions()
        XCTAssertEqual(localTxs.count, 2, "Should have 2 transactions locally after pull")
    }

    func testPull_DeletesFromCloud_ProcessedLocally() {
        let zoneID = CloudKitManager.privateZoneID

        // First, insert a transaction locally and sync to establish CK record name
        let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "Will Delete", amount: 5000)
        try! txRepo.insertTransaction(model)
        performSyncAndWait()

        let txs = txRepo.fetchAllTransactions()
        XCTAssertEqual(txs.count, 1)

        // Now simulate cloud deletion: remove from cloud and add to deleted list
        guard let savedRecord = mockCloud.fetchAll().first else {
            XCTFail("No record in mock cloud")
            return
        }
        mockCloud.delete(recordName: savedRecord.recordID.recordName)

        // Sync again with a fresh engine
        let engine2 = SyncEngine(cloudKitOps: mockOps, postSyncActions: mockPostSync)
        let exp = expectation(description: "sync 2 completes")
        engine2.performFullSync {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        let txsAfter = txRepo.fetchAllTransactions()
        XCTAssertEqual(txsAfter.count, 0, "Transaction should be soft-deleted after cloud deletion")
    }

    func testPull_MultipleRecordTypes() {
        let zoneID = CloudKitManager.privateZoneID

        // Add a transaction to mock cloud
        let tx = makeTransaction(title: "Cloud TX", amount: 5000)
        mockCloud.save(tx.toCKRecord(in: zoneID))

        // Add a budget to mock cloud (use unique month to avoid collisions)
        let cal = Calendar.current
        let uniqueMonth = cal.date(byAdding: .month, value: -10, to: Date())!
        let monthAnchor = uniqueMonth.monthAnchor
        let budget = BudgetModel(monthDate: monthAnchor, amount: 300000)
        mockCloud.save(budget.toCKRecord(in: zoneID))

        performSyncAndWait()

        let localTxs = txRepo.fetchAllTransactions()
        XCTAssertEqual(localTxs.count, 1, "Should have 1 transaction locally")

        let localBudgets = budgetRepo.fetchBudgets().filter { $0.monthDate == monthAnchor }
        XCTAssertEqual(localBudgets.count, 1, "Should have 1 budget locally")
        XCTAssertEqual(localBudgets.first?.amount, 300000)
    }

    // MARK: - Error Handling

    func testError_ZoneCreationFails() {
        mockOps.ensureZoneError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zone creation failed"])

        performSyncAndWait()

        assertError()
        XCTAssertEqual(mockOps.fetchDatabaseChangesCallCount, 0, "Should not fetch when zone creation fails")
    }

    func testError_FetchChangesFails() {
        mockOps.fetchChangesError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fetch failed"])

        performSyncAndWait()

        assertError()
        XCTAssertEqual(mockOps.saveRecordsCallCount, 0, "Should not push when fetch fails")
    }

    func testError_PushFails_StatusIsError() {
        // Insert a transaction so push has something to send
        let model = CloudKitSyncTestHelpers.makeTransactionModel(title: "Test", amount: 1000)
        try! txRepo.insertTransaction(model)

        mockOps.saveError = NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Save failed"])

        performSyncAndWait()

        assertError()
    }

    // MARK: - Edge Cases

    func testSubscriptions_SetupOnlyOnce() {
        performSyncAndWait()

        // Second sync with a fresh engine that has same mockOps
        let engine2 = SyncEngine(cloudKitOps: mockOps, postSyncActions: mockPostSync)
        let exp = expectation(description: "sync 2")
        engine2.performFullSync {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        // Each engine sets up subscriptions once on its first sync
        XCTAssertEqual(mockOps.setupSubscriptionsCallCount, 2, "Each engine sets up subscriptions once")

        // Now verify the same engine doesn't set up twice
        let engine3 = SyncEngine(cloudKitOps: mockOps, postSyncActions: mockPostSync)
        let exp2 = expectation(description: "sync 3a")
        engine3.performFullSync {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 5.0)

        let exp3 = expectation(description: "sync 3b")
        engine3.performFullSync {
            exp3.fulfill()
        }
        wait(for: [exp3], timeout: 5.0)

        // engine3 should have set up subscriptions only once (total is now 3: engine1 + engine2 + engine3)
        XCTAssertEqual(mockOps.setupSubscriptionsCallCount, 3, "Same engine should set up subscriptions only once across multiple syncs")
    }

    func testNoChangesInCloud_SkipsZoneFetch() {
        // Empty cloud — no records, no deletions
        performSyncAndWait()

        XCTAssertEqual(mockOps.fetchDatabaseChangesCallCount, 1, "Should still check for database changes")
        XCTAssertEqual(mockOps.fetchZoneChangesCallCount, 0, "Should skip zone fetch when no changes reported")
    }

    func testPull_ThenPush_FullRoundtrip() {
        let zoneID = CloudKitManager.privateZoneID

        // Pre-populate cloud with a transaction
        let cloudTx = makeTransaction(title: "From Cloud", amount: 7777)
        mockCloud.save(cloudTx.toCKRecord(in: zoneID))

        // Insert a local transaction
        let localModel = CloudKitSyncTestHelpers.makeTransactionModel(title: "From Local", amount: 8888)
        try! txRepo.insertTransaction(localModel)

        performSyncAndWait()

        // Local should now have both transactions
        let localTxs = txRepo.fetchAllTransactions()
        let titles = Set(localTxs.map { $0.title })
        XCTAssertTrue(titles.contains("From Cloud"), "Local should have cloud transaction")
        XCTAssertTrue(titles.contains("From Local"), "Local should still have local transaction")

        // Cloud should have the local transaction
        let cloudRecords = mockCloud.fetchAll(recordType: "Transaction")
        let cloudTitles = Set(cloudRecords.compactMap { $0["title"] as? String })
        XCTAssertTrue(cloudTitles.contains("From Local"), "Cloud should have local transaction")
    }

    // MARK: - Status Assertions

    private func assertSynced(file: StaticString = #file, line: UInt = #line) {
        if case .synced = syncEngine.status {
            // OK
        } else {
            XCTFail("Expected .synced, got \(syncEngine.status)", file: file, line: line)
        }
    }

    private func assertIdle(file: StaticString = #file, line: UInt = #line) {
        if case .idle = syncEngine.status {
            // OK
        } else {
            XCTFail("Expected .idle, got \(syncEngine.status)", file: file, line: line)
        }
    }

    private func assertError(file: StaticString = #file, line: UInt = #line) {
        if case .error = syncEngine.status {
            // OK
        } else {
            XCTFail("Expected .error, got \(syncEngine.status)", file: file, line: line)
        }
    }
}
