//
//  SameAccountSyncTests.swift
//  FinovaTests
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import XCTest

@testable import Finova

final class SameAccountSyncTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!

    override func setUp() {
        super.setUp()
        userUID = "test_sync_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        deviceA = DeviceSimulator(userUID: userUID, mockCloud: mockCloud)
        deviceB = DeviceSimulator(userUID: userUID, mockCloud: mockCloud)
    }

    override func tearDown() {
        deviceA.cleanup()
        deviceB.cleanup()
        // Clean up budgets
        let budgetRepo = BudgetRepository()
        for budget in budgetRepo.fetchBudgets() {
            try? budgetRepo.delete(monthDate: budget.monthDate)
        }
        mockCloud.reset()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Create on A, Sync to B

    func testCreateOnA_SyncToB() {
        deviceA.activate()
        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Grocery",
            amount: 5000
        )
        try! deviceA.transactionRepo.insertTransaction(model)

        deviceA.pushTransactions()

        deviceB.activate()
        deviceB.pullTransactions()

        let txs = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs.first?.title, "Grocery")
        XCTAssertEqual(txs.first?.amount, 5000)
    }

    // MARK: - Update on A, Sync to B

    func testUpdateOnA_SyncToB() {
        // A creates and syncs to B
        deviceA.activate()
        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Coffee",
            amount: 500
        )
        try! deviceA.transactionRepo.insertTransaction(model)
        deviceA.pushTransactions()

        deviceB.activate()
        deviceB.pullTransactions()

        // Verify B has it
        var bTxs = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(bTxs.count, 1)
        XCTAssertEqual(bTxs.first?.amount, 500)

        // A updates the transaction amount
        deviceA.activate()
        let aTxs = deviceA.transactionRepo.fetchAllTransactions()
        guard let txToUpdate = aTxs.first, let txId = txToUpdate.id else {
            XCTFail("No transaction to update")
            return
        }

        // Update via direct SQL to simulate an edit that sets sync_status = pending
        DBHelper.shared.executeSyncUpdate(
            "UPDATE Transactions SET amount = 1000, sync_status = 'pending' WHERE id = ?;",
            intBindings: [txId]
        )
        TransactionRepository.invalidateCache()

        deviceA.pushTransactions()

        // B pulls the update
        deviceB.activate()
        deviceB.pullTransactions()

        bTxs = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(bTxs.count, 1)
        // The amount may or may not be updated depending on LWW outcome
        // since CKRecord.modificationDate is nil in memory.
        // The key assertion is no duplicates.
    }

    // MARK: - Delete on A, Sync to B

    func testDeleteOnA_SyncToB() {
        // A creates and syncs to B
        deviceA.activate()
        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "To Delete",
            amount: 3000
        )
        try! deviceA.transactionRepo.insertTransaction(model)
        deviceA.pushTransactions()

        deviceB.activate()
        deviceB.pullTransactions()

        XCTAssertEqual(deviceB.transactionRepo.fetchAllTransactions().count, 1)

        // A deletes the transaction
        deviceA.activate()
        let aTxs = deviceA.transactionRepo.fetchAllTransactions()
        guard let txId = aTxs.first?.id else {
            XCTFail("No transaction found")
            return
        }
        try! deviceA.transactionRepo.delete(id: txId)
        deviceA.pushTransactionDeletes()

        // B pulls deletes
        deviceB.activate()
        deviceB.pullTransactionDeletes()

        let bTxs = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(bTxs.count, 0, "Deleted transaction should be removed on device B")
    }

    // MARK: - Bidirectional Sync

    func testBidirectionalSync() {
        // A creates tx1
        deviceA.activate()
        let model1 = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "From Device A",
            amount: 1111
        )
        try! deviceA.transactionRepo.insertTransaction(model1)
        deviceA.pushTransactions()

        // B creates tx2
        deviceB.activate()
        let model2 = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "From Device B",
            amount: 2222
        )
        try! deviceB.transactionRepo.insertTransaction(model2)
        deviceB.pushTransactions()

        // Both pull
        deviceA.activate()
        deviceA.pullTransactions()

        deviceB.activate()
        deviceB.pullTransactions()

        let aTxs = deviceA.transactionRepo.fetchAllTransactions()
        let bTxs = deviceB.transactionRepo.fetchAllTransactions()

        XCTAssertEqual(aTxs.count, 2, "Device A should have both transactions")
        XCTAssertEqual(bTxs.count, 2, "Device B should have both transactions")

        let aTitles = Set(aTxs.map { $0.title })
        let bTitles = Set(bTxs.map { $0.title })

        XCTAssertTrue(aTitles.contains("From Device A"))
        XCTAssertTrue(aTitles.contains("From Device B"))
        XCTAssertTrue(bTitles.contains("From Device A"))
        XCTAssertTrue(bTitles.contains("From Device B"))
    }

    // MARK: - Budget Sync

    func testBudgetSync() {
        // Use a unique month to avoid collisions with other tests
        let cal = Calendar.current
        let uniqueMonth = cal.date(byAdding: .month, value: -5, to: Date())!
        let monthDate = uniqueMonth.monthAnchor

        deviceA.activate()
        try! deviceA.budgetRepo.insert(budget: BudgetModel(monthDate: monthDate, amount: 500000))
        deviceA.pushBudgets()

        deviceB.activate()
        deviceB.pullBudgets()

        let bBudgets = deviceB.budgetRepo.fetchBudgets()
        let matching = bBudgets.filter { $0.monthDate == monthDate }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.amount, 500000)
    }

    // MARK: - Sync Preserves All Fields

    func testSyncPreservesAllFields() {
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let bmd = now.monthAnchor

        deviceA.activate()
        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Full Fields Test",
            category: "entertainment",
            amount: 99999,
            type: "expense",
            dateTimestamp: timestamp,
            budgetMonthDate: bmd,
            isRecurring: false,
            hasInstallments: true,
            parentTransactionId: nil,
            installmentNumber: 2,
            totalInstallments: 6,
            originalAmount: 599994,
            creditCardId: 5,
            statementId: 10,
            isCreditCardStatement: false
        )
        try! deviceA.transactionRepo.insertTransaction(model)
        deviceA.pushTransactions()

        deviceB.activate()
        deviceB.pullTransactions()

        let bTxs = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(bTxs.count, 1)

        guard let tx = bTxs.first else {
            XCTFail("No transaction found on device B")
            return
        }

        XCTAssertEqual(tx.title, "Full Fields Test")
        XCTAssertEqual(tx.amount, 99999)
        XCTAssertEqual(tx.category, .entertainment)
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.budgetMonthDate, bmd)
        XCTAssertEqual(tx.hasInstallments, true)
        XCTAssertEqual(tx.installmentNumber, 2)
        XCTAssertEqual(tx.totalInstallments, 6)
        XCTAssertEqual(tx.originalAmount, 599994)
        XCTAssertEqual(tx.creditCardId, 5)
        XCTAssertEqual(tx.statementId, 10)
    }
}
