//
//  CKRecordAdapterTests.swift
//  FinovaTests
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import XCTest

@testable import Finova

final class CKRecordAdapterTests: XCTestCase {
    private var testUID: String!

    override func setUp() {
        super.setUp()
        testUID = "test_adapter_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = testUID
    }

    override func tearDown() {
        let repo = TransactionRepository()
        repo.clearAllTransactionsForTesting()
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Transaction Roundtrip

    func testTransactionRoundtrip() {
        let zoneID = MockCloudStore.zoneID
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let bmd = now.monthAnchor

        let uiData = UITransactionData(
            id: 1,
            title: "Grocery Shopping",
            amount: 15000,
            dateTimestamp: timestamp,
            budgetMonthDate: bmd,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            creditCardId: nil,
            statementId: nil,
            isCreditCardStatement: false,
            category: .market,
            type: .expense
        )
        let original = Transaction(data: uiData)

        let record = original.toCKRecord(in: zoneID)
        guard let restored = Transaction.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertEqual(restored.title, "Grocery Shopping")
        XCTAssertEqual(restored.amount, 15000)
        XCTAssertEqual(restored.type, .expense)
        XCTAssertEqual(restored.category, .market)
        XCTAssertEqual(restored.budgetMonthDate, bmd)
        XCTAssertEqual(restored.isRecurring, false)
        XCTAssertEqual(restored.hasInstallments, false)
    }

    func testTransactionOptionalFields() {
        let zoneID = MockCloudStore.zoneID
        let now = Date()

        let uiData = UITransactionData(
            id: 2,
            title: "Simple Payment",
            amount: 3000,
            dateTimestamp: Int(now.timeIntervalSince1970),
            budgetMonthDate: now.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            creditCardId: nil,
            statementId: nil,
            isCreditCardStatement: nil,
            category: .meals,
            type: .expense
        )
        let original = Transaction(data: uiData)

        let record = original.toCKRecord(in: zoneID)
        guard let restored = Transaction.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertNil(restored.creditCardId)
        XCTAssertNil(restored.statementId)
        XCTAssertNil(restored.parentTransactionId)
        XCTAssertNil(restored.installmentNumber)
        XCTAssertNil(restored.totalInstallments)
        XCTAssertEqual(restored.title, "Simple Payment")
        XCTAssertEqual(restored.amount, 3000)
    }

    func testTransactionWithCreditCardFields() {
        let zoneID = MockCloudStore.zoneID
        let now = Date()

        let uiData = UITransactionData(
            id: 3,
            title: "Credit Card Purchase",
            amount: 25000,
            dateTimestamp: Int(now.timeIntervalSince1970),
            budgetMonthDate: now.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            creditCardId: 42,
            statementId: 99,
            isCreditCardStatement: true,
            category: .creditCard,
            type: .expense
        )
        let original = Transaction(data: uiData)

        let record = original.toCKRecord(in: zoneID)
        guard let restored = Transaction.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertEqual(restored.creditCardId, 42)
        XCTAssertEqual(restored.statementId, 99)
        XCTAssertEqual(restored.isCreditCardStatement, true)
    }

    func testRecurringTransactionFields() {
        let zoneID = MockCloudStore.zoneID
        let now = Date()

        let uiData = UITransactionData(
            id: 4,
            title: "Monthly Rent",
            amount: 100000,
            dateTimestamp: Int(now.timeIntervalSince1970),
            budgetMonthDate: now.monthAnchor,
            isRecurring: true,
            hasInstallments: false,
            parentTransactionId: 10,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            creditCardId: nil,
            statementId: nil,
            isCreditCardStatement: false,
            category: .utilities,
            type: .expense
        )
        let original = Transaction(data: uiData)

        let record = original.toCKRecord(in: zoneID)
        guard let restored = Transaction.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertEqual(restored.isRecurring, true)
        XCTAssertEqual(restored.parentTransactionId, 10)
    }

    func testInstallmentTransactionFields() {
        let zoneID = MockCloudStore.zoneID
        let now = Date()

        let uiData = UITransactionData(
            id: 5,
            title: "Phone Purchase",
            amount: 50000,
            dateTimestamp: Int(now.timeIntervalSince1970),
            budgetMonthDate: now.monthAnchor,
            isRecurring: false,
            hasInstallments: true,
            parentTransactionId: 20,
            installmentNumber: 3,
            totalInstallments: 12,
            originalAmount: 600000,
            creditCardId: nil,
            statementId: nil,
            isCreditCardStatement: false,
            category: .entertainment,
            type: .expense
        )
        let original = Transaction(data: uiData)

        let record = original.toCKRecord(in: zoneID)
        guard let restored = Transaction.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertEqual(restored.installmentNumber, 3)
        XCTAssertEqual(restored.totalInstallments, 12)
        XCTAssertEqual(restored.originalAmount, 600000)
        XCTAssertEqual(restored.hasInstallments, true)
    }

    // MARK: - Budget Roundtrip

    func testBudgetRoundtrip() {
        let zoneID = MockCloudStore.zoneID
        let budget = BudgetModel(monthDate: 1738368000, amount: 300000)

        let record = budget.toCKRecord(in: zoneID)
        guard let restored = BudgetModel.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertEqual(restored.monthDate, 1738368000)
        XCTAssertEqual(restored.amount, 300000)
    }

    func testBudgetWithSharedGroupId() {
        let zoneID = MockCloudStore.zoneID
        let budget = BudgetModel(monthDate: 1738368000, amount: 150000, sharedGroupId: "group-abc-123")

        let record = budget.toCKRecord(in: zoneID)

        // Verify the CKRecord contains the sharedGroupId
        XCTAssertEqual(record["sharedGroupId"] as? String, "group-abc-123")

        guard let restored = BudgetModel.fromCKRecord(record) else {
            XCTFail("fromCKRecord returned nil")
            return
        }

        XCTAssertEqual(restored.sharedGroupId, "group-abc-123")
        XCTAssertEqual(restored.amount, 150000)
    }

    // MARK: - Record Name Generation

    func testRecordNameGeneration() {
        let zoneID = MockCloudStore.zoneID
        let now = Date()

        let uiData = UITransactionData(
            id: 100,
            title: "Test",
            amount: 1000,
            dateTimestamp: Int(now.timeIntervalSince1970),
            budgetMonthDate: now.monthAnchor,
            isRecurring: false,
            hasInstallments: false,
            parentTransactionId: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            creditCardId: nil,
            statementId: nil,
            isCreditCardStatement: false,
            category: .miscellaneous,
            type: .expense
        )
        let tx = Transaction(data: uiData)

        // New record (no stored name) should get a UUID-based name
        let record1 = tx.toCKRecord(in: zoneID, storedRecordName: nil)
        XCTAssertTrue(record1.recordID.recordName.hasPrefix("transaction-"))

        // Stored name should be reused
        let storedName = "transaction-existing-12345"
        let record2 = tx.toCKRecord(in: zoneID, storedRecordName: storedName)
        XCTAssertEqual(record2.recordID.recordName, storedName)
    }

    func testRecordNameDeterministic() {
        let zoneID = MockCloudStore.zoneID
        let monthDate = 1738368000
        let budget = BudgetModel(monthDate: monthDate, amount: 100000)

        // Budget records use deterministic names based on monthDate
        let record1 = budget.toCKRecord(in: zoneID)
        let record2 = budget.toCKRecord(in: zoneID)

        XCTAssertEqual(record1.recordID.recordName, "budget-\(monthDate)")
        XCTAssertEqual(record1.recordID.recordName, record2.recordID.recordName)
    }
}
