//
//  ConvergenceTests.swift
//  FinovaTests
//
//  The assertion that matters for sync is not "device B received the record" but
//  "device A and device B agree". These tests compare full data fingerprints after
//  syncing in both directions.
//
//  They are expected to FAIL against the current implementation — that is the point.
//  They encode the reported bugs (personal data differing between devices, records
//  losing their relationships in transit) so the refactor has something to satisfy.
//

import CloudKit
import XCTest

@testable import Finova

final class ConvergenceTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!

    override func setUp() {
        super.setUp()
        userUID = "converge_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        // Same account, two devices — each with its OWN database.
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

    /// Syncs until both devices have seen everything: A pushes, B pulls, B pushes, A pulls.
    private func converge() {
        deviceA.pushAll()
        deviceB.pullAll()
        deviceB.pushAll()
        deviceA.pullAll()
    }

    private func assertConverged(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let a = deviceA.dataFingerprint()
        let b = deviceB.dataFingerprint()
        XCTAssertEqual(
            a, b,
            """
            \(message)
            Devices diverged.
              A (\(a.count) rows): \(a)
              B (\(b.count) rows): \(b)
            """,
            file: file, line: line
        )
    }

    // MARK: - The devices really are separate

    /// Guards the harness itself. If this fails, the two simulators are sharing a database
    /// again and every other test in this file is meaningless.
    func testDevicesAreIsolatedBeforeAnySync() {
        deviceA.activate()
        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "OnlyOnA", amount: 111)
        )

        deviceB.activate()
        let onB = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertTrue(
            onB.isEmpty,
            "Device B must not see device A's row before any sync — the databases are not isolated"
        )
    }

    // MARK: - Convergence

    func testCreateOnA_ConvergesBothWays() {
        deviceA.activate()
        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Grocery", amount: 5000)
        )

        converge()

        XCTAssertEqual(deviceB.transactionRepo.fetchAllTransactions().count, 1, "B should have the row")
        assertConverged("A single create must converge")
    }

    func testConcurrentDistinctCreates_Converge() {
        deviceA.activate()
        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "FromA", amount: 1000)
        )
        deviceB.activate()
        try! deviceB.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "FromB", amount: 2000)
        )

        converge()

        assertConverged("Two distinct records created concurrently must both survive")
        XCTAssertEqual(deviceA.dataFingerprint().count, 2, "Both records should exist, not one")
    }

    /// The reported symptom: two devices on one account showing different personal data.
    func testRepeatedSync_IsStable() {
        deviceA.activate()
        for i in 1...3 {
            try! deviceA.transactionRepo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(title: "Tx\(i)", amount: i * 1000)
            )
        }

        converge()
        let afterFirst = deviceA.dataFingerprint()

        converge()
        converge()

        XCTAssertEqual(
            deviceA.dataFingerprint(), afterFirst,
            "Syncing repeatedly with no user action must not change the data"
        )
        assertConverged("Repeated syncs must stay converged")
    }

    /// Idempotence: the single best regression detector for the automatic repair passes.
    /// A sync cycle with no user action must have nothing to push.
    func testSecondSyncPushesNothing() {
        deviceA.activate()
        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Stable", amount: 4200)
        )

        converge()

        deviceA.activate()
        XCTAssertTrue(
            deviceA.transactionRepo.fetchPendingSync().isEmpty,
            "After a full sync, device A must have nothing pending — anything here is a repair pass "
                + "rewriting rows behind the user's back, which is what makes two devices fight"
        )
        deviceB.activate()
        XCTAssertTrue(
            deviceB.transactionRepo.fetchPendingSync().isEmpty,
            "After a full sync, device B must have nothing pending"
        )
    }

    /// Edits must not be lost, and must not resurrect the old value.
    func testEditOnA_ReachesB() {
        deviceA.activate()
        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Coffee", amount: 500)
        )
        converge()

        deviceA.activate()
        guard let tx = deviceA.transactionRepo.fetchAllTransactions().first, let id = tx.id else {
            return XCTFail("setup: transaction missing on A")
        }
        let template = CloudKitSyncTestHelpers.makeTransactionModel(title: "Coffee", amount: 900)
        let edited = TransactionModel(
            id: id,
            title: "Coffee",
            category: template.data.category,
            amount: 900,
            type: template.data.type,
            dateTimestamp: template.data.dateTimestamp,
            budgetMonthDate: template.data.budgetMonthDate
        )
        try! deviceA.transactionRepo.updateTransactionDirectly(edited)

        converge()

        deviceB.activate()
        let onB = deviceB.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(onB.count, 1, "The edit must not create a duplicate")
        XCTAssertEqual(onB.first?.amount, 900, "Device B must see the edited amount")
        assertConverged("An edit must converge")
    }

    // MARK: - Relationships survive the wire

    /// The core identity defect: foreign keys are local autoincrement integers, so a
    /// referenced row's id means nothing on the receiving device.
    func testCreditCardTransactionKeepsItsCard() {
        deviceA.activate()
        let cardId = deviceA.cardRepo.insertCard(
            CreditCard(
                name: "Visa", lastFourDigits: "4242", cardBrand: .visa,
                closingDay: 5, dueDay: 12, creditLimit: 500_000,
                cardColor: .blue, userId: userUID,
                isDeleted: false, isDefault: false,
                createdAt: Date(), updatedAt: Date()
            )
        )
        XCTAssertNotNil(cardId, "setup: card insert failed")

        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "CardPurchase", amount: 7500, creditCardId: cardId
            )
        )

        converge()

        deviceB.activate()
        guard let txOnB = deviceB.transactionRepo.fetchAllTransactions()
            .first(where: { $0.title == "CardPurchase" })
        else {
            return XCTFail("Device B never received the credit-card transaction")
        }
        guard let cardOnB = deviceB.cardRepo.fetchAllCards(userId: userUID)
            .first(where: { $0.name == "Visa" })
        else {
            return XCTFail("Device B never received the credit card")
        }

        XCTAssertEqual(
            txOnB.creditCardId, cardOnB.id,
            "On device B the transaction must point at B's OWN local id for that card. A mismatch "
                + "means the sender's local integer was written straight into B's database."
        )
    }

    /// The real F1 failure mode: the transaction arrives BEFORE its credit card.
    ///
    /// CloudKit does not guarantee that a record and its referent land in the same fetch — the
    /// engine's sort only orders records *within* one buffer. When the referent hasn't arrived,
    /// `remapCrossDeviceIDs` cannot resolve `creditCardCKRecordName`, and the current code falls
    /// through leaving the SENDER's local integer in place. That integer is meaningless on the
    /// receiving device: it either dangles or, worse, silently points at an unrelated row.
    ///
    /// Nothing repairs it afterwards, because `ck_parent_record_name` and the CK-name side channels
    /// are never re-read once the row is inserted.
    func testTransactionArrivingBeforeItsCard_StillResolves() {
        deviceA.activate()
        // Force a high local id on A so the sender's integer cannot coincidentally be valid on B.
        for i in 1...5 {
            _ = deviceA.cardRepo.insertCard(
                CreditCard(
                    name: "Filler\(i)", lastFourDigits: "000\(i)", cardBrand: .other,
                    closingDay: 1, dueDay: 2, creditLimit: 1000,
                    cardColor: .blue, userId: userUID,
                    isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date()
                )
            )
        }
        let cardId = deviceA.cardRepo.insertCard(
            CreditCard(
                name: "RealCard", lastFourDigits: "4242", cardBrand: .visa,
                closingDay: 5, dueDay: 12, creditLimit: 500_000,
                cardColor: .blue, userId: userUID,
                isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date()
            )
        )
        try! deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(
                title: "OutOfOrder", amount: 3300, creditCardId: cardId
            )
        )
        deviceA.pushAll()

        // Device B receives the transaction FIRST, its card only afterwards.
        deviceB.activate()
        deviceB.pullTransactions()
        deviceB.pullCards()

        guard let txOnB = deviceB.transactionRepo.fetchAllTransactions()
            .first(where: { $0.title == "OutOfOrder" })
        else {
            return XCTFail("Device B never received the transaction")
        }
        guard let cardOnB = deviceB.cardRepo.fetchAllCards(userId: userUID)
            .first(where: { $0.name == "RealCard" })
        else {
            return XCTFail("Device B never received the card")
        }

        XCTAssertEqual(
            txOnB.creditCardId, cardOnB.id,
            """
            Out-of-order arrival lost the relationship.
            B's transaction points at card id \(txOnB.creditCardId.map(String.init) ?? "nil") \
            but B's own "RealCard" is id \(cardOnB.id.map(String.init) ?? "nil").
            The reference must be resolvable regardless of arrival order — that is what a stable, \
            device-independent record identity buys.
            """
        )
    }
}
