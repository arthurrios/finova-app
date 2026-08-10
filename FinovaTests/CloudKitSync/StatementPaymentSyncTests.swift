//
//  StatementPaymentSyncTests.swift
//  FinovaTests
//
//  The statement-payment pointer crosses the wire as a UUID with no integer counterpart, so these
//  tests are about what can actually go wrong: the receiving device linking the credit to the WRONG
//  local debit, or an older peer wiping a pointer it has simply never heard of.
//

import CloudKit
import XCTest

@testable import Finova

final class StatementPaymentSyncTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!

    override func setUp() {
        super.setUp()
        userUID = "stmtpay_sync_\(UUID().uuidString)"
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

    /// Creates the debit/credit pair a statement payment produces, on `device`.
    private func makePaymentPair(on device: DeviceSimulator) -> (debit: Int, credit: Int) {
        device.activate()
        let debitId = try! device.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Statement payment — TestCard", category: "creditCard", amount: 100_000))
        let creditId = try! device.transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "Payment received", category: "creditCard", amount: 100_000,
                type: "income"))
        device.db.setStatementPaymentFlag(transactionId: debitId, isStatementPayment: true)
        device.db.setStatementPaymentLink(transactionId: creditId, paymentId: debitId)
        return (debitId, creditId)
    }

    private func offsetLocalIds(on device: DeviceSimulator, by count: Int) {
        for i in 0..<count {
            try! device.transactionRepo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(
                    title: "LocalOnly\(i)", amount: 700 + i))
        }
    }

    private func transactionOnB(titled title: String) -> Transaction? {
        deviceB.transactionRepo.fetchAllTransactions().first { $0.title == title }
    }

    /// The pointer is written as a uuid at the moment it is made, so `resolveUuidForeignKeys` on the
    /// receiver can rebuild it against that device's own row ids.
    ///
    /// Note this exercises the DB and resolve layer, not the wire format: while
    /// `CloudKitSchemaFlags.statementPaymentFieldsDeployed` is `false` the adapter deliberately
    /// withholds the fields, which `testFieldsAreWithheldUntilTheSchemaIsDeployed` covers.
    func testStatementPaymentPointerResolvesToTheReceivingDevicesOwnRow() {
        let pair = makePaymentPair(on: deviceA)

        deviceA.pushAll()
        deviceB.activate()
        // B's ids start ten ahead of A's, so a leaked integer cannot be right by coincidence.
        offsetLocalIds(on: deviceB, by: 10)
        deviceB.pullAll()

        guard let creditOnB = transactionOnB(titled: "Payment received") else {
            return XCTFail("Device B never received the statement credit")
        }
        guard let debitOnB = transactionOnB(titled: "Statement payment — TestCard") else {
            return XCTFail("Device B never received the payment debit")
        }
        XCTAssertNotEqual(
            pair.debit, debitOnB.id,
            "Fixture is not exercising anything: the two devices happened to assign the same id")

        // Simulate the wire carrying the uuid, which is all that ever travels, then resolve.
        let creditUuid = deviceA.db.statementPaymentUuid(transactionId: pair.credit)
        XCTAssertNotNil(
            creditUuid,
            "setStatementPaymentLink must write the uuid alongside the integer — a push that happened "
                + "first would otherwise carry a nil pointer the receiver could never resolve")

        if let recordName = deviceB.transactionRepo.fetchCKRecordName(for: creditOnB.id ?? 0) {
            deviceB.db.applyInboundInstallmentPointers(
                ckRecordName: recordName,
                settled: nil,
                cancelled: nil,
                statementPayment: (uuid: creditUuid, isPayer: false))
        }
        deviceB.db.resolveUuidForeignKeys()

        XCTAssertEqual(
            deviceB.db.statementPaymentId(transactionId: creditOnB.id ?? 0),
            debitOnB.id,
            """
            B's credit must point at B's OWN copy of the debit, not at A's local id.
              A debit id = \(pair.debit)
              B debit id = \(debitOnB.id.map(String.init) ?? "nil")
              B credit points at = \
            \(deviceB.db.statementPaymentId(transactionId: creditOnB.id ?? 0).map(String.init) ?? "nil")
            """
        )
    }

    func testAPeerOnTheCancellationSchemaDoesNotClearAStatementPayment() {
        // A peer on the version that shipped cancellation (schema 2) knows nothing about statement
        // payments. Reading that silence as "no payment" would unlink the credit from its debit, and
        // deleting either one there would then leave the other stranded.
        let pair = makePaymentPair(on: deviceA)
        deviceA.pushAll()

        guard let recordName = deviceA.transactionRepo.fetchCKRecordName(for: pair.credit) else {
            return XCTFail("The credit was never assigned a CK record name")
        }

        let v2Record = CKRecord(
            recordType: "Transaction",
            recordID: CKRecord.ID(recordName: recordName, zoneID: MockCloudStore.zoneID))
        v2Record["title"] = "Payment received" as CKRecordValue
        v2Record["amount"] = 100_000 as CKRecordValue
        v2Record["type"] = TransactionType.income.rawValue as CKRecordValue
        v2Record["category"] = TransactionCategory.creditCard.rawValue as CKRecordValue
        v2Record["date"] = Date() as CKRecordValue
        v2Record["budgetMonthDate"] = Date().monthAnchor as CKRecordValue
        // Declares early payment and cancellation only — exactly what the previous release writes.
        v2Record["earlyPaymentSchema"] = 2 as CKRecordValue
        v2Record["isEarlyPayment"] = 0 as CKRecordValue
        v2Record["isCancellationRefund"] = 0 as CKRecordValue

        guard let remote = Transaction.fromCKRecord(v2Record) else {
            return XCTFail("Could not build the v2 record fixture")
        }
        ConflictResolver(db: deviceA.db).resolveTransaction(remote: remote, ckRecord: v2Record)

        XCTAssertEqual(
            deviceA.db.statementPaymentId(transactionId: pair.credit), pair.debit,
            "A schema-2 record must leave the statement-payment pointer untouched")
        XCTAssertTrue(
            deviceA.db.isStatementPayment(transactionId: pair.debit),
            "And it must leave the payer flag alone too")
    }

    /// Guards the ship order that `CloudKitSchemaFlags` documents.
    ///
    /// Writing an undeployed field makes the server reject the whole record and `SyncEngine` abandon
    /// every remaining save batch — one feature's field breaks syncing for all data. Claiming schema 3
    /// while withholding the fields is the subtler half of the same mistake: the receiver would read
    /// their absence as a deliberate clear.
    ///
    /// When the fields are deployed and the flag flips, this test flips with it.
    func testFieldsAreWithheldUntilTheSchemaIsDeployed() {
        let pair = makePaymentPair(on: deviceA)
        guard let credit = deviceA.transactionRepo.fetchAllTransactions()
            .first(where: { $0.id == pair.credit })
        else { return XCTFail("Could not read back the credit") }

        // `db:` explicitly — the adapter reads this row's pointer columns, and defaulting to `.shared`
        // would read the wrong database under the two-device harness.
        let record = credit.toCKRecord(
            in: MockCloudStore.zoneID, storedRecordName: "transaction-test", db: deviceA.db)

        if CloudKitSchemaFlags.statementPaymentFieldsDeployed {
            XCTAssertEqual(record["earlyPaymentSchema"] as? Int, 3)
            XCTAssertNotNil(record["statementPaymentUuid"])
        } else {
            XCTAssertEqual(
                record["earlyPaymentSchema"] as? Int, 2,
                "The schema version must not claim 3 while the fields are withheld")
            XCTAssertNil(
                record["statementPaymentUuid"],
                "An undeployed field halts every remaining save batch, for all data")
            XCTAssertNil(record["isStatementPayment"])
        }
    }
}
