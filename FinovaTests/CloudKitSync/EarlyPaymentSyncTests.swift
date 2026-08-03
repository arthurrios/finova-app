//
//  EarlyPaymentSyncTests.swift
//  FinovaTests
//
//  The early-payment pointer crosses the wire as a UUID with no integer counterpart, so these tests
//  are about the thing that can actually go wrong: the receiving device linking the installment to
//  the WRONG local row, or to nothing at all.
//

import CloudKit
import XCTest

@testable import Finova

final class EarlyPaymentSyncTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!

    override func setUp() {
        super.setUp()
        userUID = "earlypay_sync_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        deviceA = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "A")
        deviceB = DeviceSimulator(userUID: userUID, mockCloud: mockCloud, label: "B")
    }

    override func tearDown() {
        deviceA.cleanup()
        deviceB.cleanup()
        mockCloud.reset()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// Creates an installment parent plus one child on `device`, returning (parentId, childId).
    private func makeInstallmentPair(on device: DeviceSimulator, fillerRows: Int = 0)
        -> (parent: Int, child: Int)
    {
        device.activate()

        // Filler pushes A's ids well past B's, so a leaked integer cannot be right by coincidence.
        for i in 0..<fillerRows {
            try! device.transactionRepo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(title: "Filler\(i)", amount: 100 + i))
        }

        let parentId = try! device.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Fridge", amount: 0, hasInstallments: true,
                totalInstallments: 3, originalAmount: 30000))
        let childId = try! device.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Fridge", amount: 10000, parentTransactionId: parentId,
                installmentNumber: 3, totalInstallments: 3, originalAmount: 30000))
        return (parentId, childId)
    }

    /// Pushes `device`'s autoincrement ahead with rows that exist ONLY on it.
    ///
    /// Filling on the sender does not separate the two devices: the receiver pulls those rows too, so
    /// its counter advances in step and the ids can land identically — which made the divergence
    /// assertions below pass or fail on the luck of the pull order. Rows that never leave the
    /// receiver are what actually offsets it, so every pulled row is guaranteed a different local id
    /// than the sender gave it.
    private func offsetLocalIds(on device: DeviceSimulator, by count: Int) {
        for i in 0..<count {
            try! device.transactionRepo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(
                    title: "LocalOnly\(i)", amount: 700 + i))
        }
    }

    private func transactionOnB(titled title: String, amount: Int) -> Transaction? {
        deviceB.transactionRepo.fetchAllTransactions()
            .first { $0.title == title && $0.amount == amount }
    }

    func testSettledPointerResolvesToTheReceivingDevicesOwnRow() {
        let pair = makeInstallmentPair(on: deviceA)

        let paymentId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Early payment — Fridge", category: "creditCard", amount: 10000))
        deviceA.db.setEarlyPayment(transactionId: paymentId, isEarlyPayment: true)
        deviceA.db.setSettledBy(transactionId: pair.child, settledByTransactionId: paymentId)

        deviceA.pushAll()
        deviceB.activate()
        // B's ids start ten ahead of A's, so a leaked integer cannot be right by coincidence.
        offsetLocalIds(on: deviceB, by: 10)
        deviceB.pullAll()
        deviceB.db.resolveUuidForeignKeys()

        guard let childOnB = transactionOnB(titled: "Fridge", amount: 10000) else {
            return XCTFail("Device B never received the installment")
        }
        guard let paymentOnB = transactionOnB(titled: "Early payment — Fridge", amount: 10000) else {
            return XCTFail("Device B never received the early-payment debit")
        }

        XCTAssertNotEqual(
            paymentId, paymentOnB.id,
            "Fixture is not exercising anything: the two devices happened to assign the same id")

        XCTAssertEqual(
            deviceB.db.settledByTransactionId(transactionId: childOnB.id ?? 0),
            paymentOnB.id,
            """
            B's installment must point at B's OWN copy of the debit, not at A's local id.
              A payment id = \(paymentId)
              B payment id = \(paymentOnB.id.map(String.init) ?? "nil")
              B installment points at = \
            \(deviceB.db.settledByTransactionId(transactionId: childOnB.id ?? 0).map(String.init) ?? "nil")
            """
        )
        XCTAssertTrue(
            deviceB.db.isEarlyPayment(transactionId: paymentOnB.id ?? 0),
            "The early-payment flag has to travel too, or B cannot show the breakdown or undo it")
    }

    func testInstallmentArrivingBeforeItsPaymentStillResolves() {
        let pair = makeInstallmentPair(on: deviceA, fillerRows: 3)
        let paymentId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Early payment — Fridge", category: "creditCard", amount: 10000))
        deviceA.db.setEarlyPayment(transactionId: paymentId, isEarlyPayment: true)
        deviceA.db.setSettledBy(transactionId: pair.child, settledByTransactionId: paymentId)

        deviceA.pushAll()
        deviceB.activate()
        // Resolution is a batch-end pass, so an installment that lands before its payer must link up
        // on a later pass rather than being permanently mis-linked.
        deviceB.pullTransactions()
        deviceB.db.resolveUuidForeignKeys()

        guard let childOnB = transactionOnB(titled: "Fridge", amount: 10000),
              let paymentOnB = transactionOnB(titled: "Early payment — Fridge", amount: 10000)
        else {
            return XCTFail("Device B did not receive the rows")
        }

        XCTAssertEqual(
            deviceB.db.settledByTransactionId(transactionId: childOnB.id ?? 0), paymentOnB.id)
    }

    func testSettledInstallmentIsExcludedFromLedgerTotalsOnTheReceivingDevice() {
        let pair = makeInstallmentPair(on: deviceA, fillerRows: 2)
        let paymentId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Early payment — Fridge", category: "creditCard", amount: 10000))
        deviceA.db.setEarlyPayment(transactionId: paymentId, isEarlyPayment: true)
        deviceA.db.setSettledBy(transactionId: pair.child, settledByTransactionId: paymentId)

        deviceA.pushAll()
        deviceB.activate()
        deviceB.pullAll()
        deviceB.db.resolveUuidForeignKeys()

        guard let childOnB = transactionOnB(titled: "Fridge", amount: 10000) else {
            return XCTFail("Device B never received the installment")
        }

        XCTAssertTrue(
            deviceB.db.settledInstallmentIds().contains(childOnB.id ?? -1),
            "B has to reach the same conclusion as A about what is already paid, or the same money "
                + "is counted on one device and not the other")
    }

    func testReversalPropagatesAsAClearedPointer() {
        let pair = makeInstallmentPair(on: deviceA, fillerRows: 2)
        let paymentId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Early payment — Fridge", category: "creditCard", amount: 10000))
        deviceA.db.setEarlyPayment(transactionId: paymentId, isEarlyPayment: true)
        deviceA.db.setSettledBy(transactionId: pair.child, settledByTransactionId: paymentId)

        deviceA.pushAll()
        deviceB.activate()
        deviceB.pullAll()
        deviceB.db.resolveUuidForeignKeys()

        guard let childOnB = transactionOnB(titled: "Fridge", amount: 10000) else {
            return XCTFail("Device B never received the installment")
        }
        XCTAssertNotNil(
            deviceB.db.settledByTransactionId(transactionId: childOnB.id ?? 0),
            "Precondition: B should see the installment as settled before the reversal")

        // A undoes the early payment. Only the installment row changes, so the cleared pointer is the
        // sole carrier of that fact.
        deviceA.activate()
        deviceA.db.setSettledBy(transactionId: pair.child, settledByTransactionId: nil)
        deviceA.pushAll()

        deviceB.activate()
        deviceB.pullAll()
        deviceB.db.resolveUuidForeignKeys()

        XCTAssertNil(
            deviceB.db.settledByTransactionId(transactionId: childOnB.id ?? 0),
            "Undoing an early payment must reach the other device — otherwise B keeps the "
                + "installment excluded from its totals forever")
    }

    func testCancellationPointerResolvesToTheReceivingDevicesOwnRow() {
        let pair = makeInstallmentPair(on: deviceA)

        let refundId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Cancellation refund — Fridge", category: "creditCard", amount: 10000,
                type: "income"))
        deviceA.db.setCancellationRefund(transactionId: refundId, isRefund: true)
        deviceA.db.setCancelledBy(transactionId: pair.child, cancelledByTransactionId: refundId)

        deviceA.pushAll()
        deviceB.activate()
        // B's ids start ten ahead of A's, so a leaked integer cannot be right by coincidence.
        offsetLocalIds(on: deviceB, by: 10)
        deviceB.pullAll()
        deviceB.db.resolveUuidForeignKeys()

        guard let childOnB = transactionOnB(titled: "Fridge", amount: 10000),
              let refundOnB = transactionOnB(titled: "Cancellation refund — Fridge", amount: 10000)
        else {
            return XCTFail("Device B did not receive the rows")
        }

        XCTAssertNotEqual(
            refundId, refundOnB.id,
            "Fixture is not exercising anything: both devices assigned the same id")
        XCTAssertEqual(
            deviceB.db.cancelledByTransactionId(transactionId: childOnB.id ?? 0), refundOnB.id,
            "B's installment must point at B's OWN copy of the credit, not at A's local id")
        XCTAssertTrue(
            deviceB.db.isCancellationRefund(transactionId: refundOnB.id ?? 0),
            "Without the flag, B cannot show what the credit covers or undo it")
    }

    func testPeerOnTheEarlyPaymentOnlySchemaDoesNotClearACancellation() {
        // A peer on the version that shipped early payment (schema 1) sends the settled keys but knows
        // nothing about cancellation. Reading that silence as "not cancelled" would un-cancel a
        // purchase — and let the user cancel it a second time, crediting them twice.
        deviceA.activate()
        let pair = makeInstallmentPair(on: deviceA)
        let refundId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Cancellation refund — Fridge", category: "creditCard", amount: 10000,
                type: "income"))
        deviceA.db.setCancellationRefund(transactionId: refundId, isRefund: true)
        deviceA.db.setCancelledBy(transactionId: pair.child, cancelledByTransactionId: refundId)

        deviceA.pushAll()
        guard let recordName = deviceA.transactionRepo.fetchCKRecordName(for: pair.child) else {
            return XCTFail("The installment was never assigned a CK record name")
        }

        let v1Record = CKRecord(
            recordType: "Transaction",
            recordID: CKRecord.ID(recordName: recordName, zoneID: MockCloudStore.zoneID))
        v1Record["title"] = "Fridge" as CKRecordValue
        v1Record["amount"] = 10000 as CKRecordValue
        v1Record["type"] = TransactionType.expense.rawValue as CKRecordValue
        v1Record["category"] = TransactionCategory.market.rawValue as CKRecordValue
        v1Record["date"] = Date() as CKRecordValue
        v1Record["budgetMonthDate"] = Date().monthAnchor as CKRecordValue
        // Declares early payment only — exactly what the previous release writes.
        v1Record["earlyPaymentSchema"] = 1 as CKRecordValue
        v1Record["isEarlyPayment"] = 0 as CKRecordValue

        guard let remote = Transaction.fromCKRecord(v1Record) else {
            return XCTFail("Could not build the v1 record fixture")
        }
        ConflictResolver(db: deviceA.db).resolveTransaction(remote: remote, ckRecord: v1Record)

        XCTAssertEqual(
            deviceA.db.cancelledByTransactionId(transactionId: pair.child), refundId,
            "A schema-1 record must leave the cancellation pointer untouched")
    }

    func testLegacyPeerWithoutTheFieldDoesNotClearALocalPointer() {
        // A peer on an older build sends no early-payment keys at all. Reading that absence as "not
        // settled" would silently un-settle installments every time such a peer re-pushed a row.
        deviceA.activate()
        let pair = makeInstallmentPair(on: deviceA)
        let paymentId = try! deviceA.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Early payment — Fridge", category: "creditCard", amount: 10000))
        deviceA.db.setEarlyPayment(transactionId: paymentId, isEarlyPayment: true)
        deviceA.db.setSettledBy(transactionId: pair.child, settledByTransactionId: paymentId)

        // Pushing is what gives the row a CK record name, which is how the resolver matches it back.
        deviceA.pushAll()
        guard let recordName = deviceA.transactionRepo.fetchCKRecordName(for: pair.child) else {
            return XCTFail("The installment was never assigned a CK record name")
        }

        // Rebuild the record the way a legacy client would: no earlyPaymentSchema, no pointer keys.
        let legacy = CKRecord(
            recordType: "Transaction",
            recordID: CKRecord.ID(recordName: recordName, zoneID: MockCloudStore.zoneID))
        legacy["title"] = "Fridge" as CKRecordValue
        legacy["amount"] = 10000 as CKRecordValue
        legacy["type"] = TransactionType.expense.rawValue as CKRecordValue
        legacy["category"] = TransactionCategory.market.rawValue as CKRecordValue
        legacy["date"] = Date() as CKRecordValue
        legacy["budgetMonthDate"] = Date().monthAnchor as CKRecordValue

        guard let remote = Transaction.fromCKRecord(legacy) else {
            return XCTFail("Could not build the legacy record fixture")
        }
        ConflictResolver(db: deviceA.db).resolveTransaction(remote: remote, ckRecord: legacy)

        XCTAssertEqual(
            deviceA.db.settledByTransactionId(transactionId: pair.child), paymentId,
            "A record from a peer that has never heard of early payment must leave the pointer alone")
    }
}
