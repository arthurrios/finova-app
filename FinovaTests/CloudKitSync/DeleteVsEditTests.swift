//
//  DeleteVsEditTests.swift
//  FinovaTests
//
//  Delete versus concurrent edit — the conflict class that destroys data when it goes wrong.
//
//  All five repositories implement the same rule, in `deleteFromCloud`: an inbound deletion is
//  SKIPPED when the local row has unpushed edits (`sync_status = 'pending'`). The local change then
//  re-pushes and the record comes back. Recreation wins.
//
//  It cannot be resolved by `rev` the way an ordinary edit is, and that is not an oversight: a
//  CloudKit deletion carries no record — `recordDeletedBlock` hands over a record ID and nothing
//  else, so there is no version to compare against. Ordering a delete against an edit would require
//  tombstones on the wire (`isDeleted` as a field, pushed as an update rather than a delete), which
//  only `CreditCard` currently has.
//
//  Recreation-wins is therefore a deliberate choice under genuine ambiguity: the two operations are
//  concurrent, either outcome is defensible, and keeping the record is the recoverable one. A
//  resurrected transaction is a visible row the user can delete again; a swallowed edit is money that
//  silently is not there.
//
//  The rule was uniform and documented but untested. These tests pin it, and — more importantly —
//  check that it CONVERGES: a rule that keeps the row on one device and drops it on the other is
//  worse than either outcome.
//

import CloudKit
import XCTest

@testable import Finova

final class DeleteVsEditTests: XCTestCase {
    private var userUID: String!
    private var mockCloud: MockCloudStore!
    private var deviceA: DeviceSimulator!
    private var deviceB: DeviceSimulator!

    override func setUp() {
        super.setUp()
        userUID = "delvsedit_\(UUID().uuidString)"
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

    /// Both devices holding one synced transaction.
    private func seedSyncedOnBoth(title: String = "Rent", amount: Int = 250_000) {
        deviceA.activate()
        try? deviceA.transactionRepo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: title, amount: amount))
        deviceA.pushAll()
        deviceB.pullAll()
    }

    private func liveCount(_ device: DeviceSimulator) -> Int {
        device.activate()
        return device.db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? -1
    }

    private func amount(on device: DeviceSimulator, title: String = "Rent") -> Int? {
        device.activate()
        return device.db.fetchSingleInt(
            "SELECT amount FROM Transactions WHERE title = ? AND (is_deleted IS NULL OR is_deleted = 0);",
            textBinding: title)
    }

    /// Edits `title`'s amount on `device`, leaving the row pending as a real user edit would.
    private func edit(on device: DeviceSimulator, title: String = "Rent", to newAmount: Int) {
        device.activate()
        guard let id = device.db.fetchSingleInt(
            "SELECT id FROM Transactions WHERE title = ?;", textBinding: title) else {
            return XCTFail("setup: row not found to edit")
        }
        try? device.db.executeGroupWriteChecked(
            """
            UPDATE Transactions SET amount = ?, sync_status = 'pending',
                   updated_at = ? WHERE id = ?;
            """,
            orderedBindings: [newAmount, Int(Date().timeIntervalSince1970), id])
        TransactionRepository.invalidateCache()
    }

    // MARK: - No conflict: the delete simply applies

    func testDeleteWithNoCompetingEditRemovesTheRowEverywhere() {
        seedSyncedOnBoth()

        deviceA.activate()
        guard let id = deviceA.db.fetchSingleInt("SELECT id FROM Transactions WHERE title = 'Rent';")
        else { return XCTFail("setup: row missing on A") }
        try? deviceA.transactionRepo.delete(id: id)
        deviceA.pushTransactionDeletes()

        deviceB.pullTransactionDeletes()

        XCTAssertEqual(liveCount(deviceA), 0, "A deleted it")
        XCTAssertEqual(liveCount(deviceB), 0, "B had no competing edit, so the delete applies")
    }

    // MARK: - The conflict

    /// A deletes; B has edited the same row and not yet pushed. B must keep its edit.
    func testConcurrentEditSurvivesAnInboundDelete() {
        seedSyncedOnBoth()

        edit(on: deviceB, to: 999_000)

        deviceA.activate()
        guard let id = deviceA.db.fetchSingleInt("SELECT id FROM Transactions WHERE title = 'Rent';")
        else { return XCTFail("setup: row missing on A") }
        try? deviceA.transactionRepo.delete(id: id)
        deviceA.pushTransactionDeletes()

        deviceB.pullTransactionDeletes()

        XCTAssertEqual(
            amount(on: deviceB), 999_000,
            """
            B's unpushed edit was swallowed by a concurrent delete from A. The two operations are \
            concurrent and a CloudKit deletion carries no version to order them by, so the choice is \
            made on which failure is recoverable: a resurrected row the user can delete again, or \
            money that silently is not there.
            """
        )
    }

    /// And the outcome must be the SAME on both devices. A rule that keeps the row on one device and
    /// drops it on the other is worse than either answer — that is divergence, which is the thing
    /// this whole effort exists to remove.
    func testTheOutcomeConvergesOnBothDevices() {
        seedSyncedOnBoth()
        edit(on: deviceB, to: 999_000)

        deviceA.activate()
        guard let id = deviceA.db.fetchSingleInt("SELECT id FROM Transactions WHERE title = 'Rent';")
        else { return XCTFail("setup: row missing on A") }
        try? deviceA.transactionRepo.delete(id: id)
        deviceA.pushTransactionDeletes()

        // B declines the delete and re-publishes its edit; A then receives the resurrection.
        deviceB.pullTransactionDeletes()
        deviceB.pushAll()
        deviceA.pullAll()

        XCTAssertEqual(
            liveCount(deviceB), 1, "B kept the row")
        XCTAssertEqual(
            liveCount(deviceA), 1,
            """
            A did not accept the resurrection, so A shows no row while B shows one — the devices \
            disagree. A tombstone left behind by A's own delete is the likely cause: it must not \
            block a record that has legitimately come back.
            """
        )
        XCTAssertEqual(amount(on: deviceA), 999_000, "and both must show B's edit")
        XCTAssertEqual(deviceA.dataFingerprint(), deviceB.dataFingerprint(), "Devices must agree")
    }

    /// The other order: B pushes its edit BEFORE A's delete reaches it. The edit is then already in
    /// the cloud, so nothing is pending locally and the delete applies cleanly — the record really
    /// was deleted after the edit was published, which is not a conflict at all.
    func testAnAlreadyPublishedEditDoesNotBlockALaterDelete() {
        seedSyncedOnBoth()

        edit(on: deviceB, to: 999_000)
        deviceB.pushAll()
        deviceA.pullAll()

        deviceA.activate()
        guard let id = deviceA.db.fetchSingleInt("SELECT id FROM Transactions WHERE title = 'Rent';")
        else { return XCTFail("setup: row missing on A") }
        try? deviceA.transactionRepo.delete(id: id)
        deviceA.pushTransactionDeletes()
        deviceB.pullTransactionDeletes()

        XCTAssertEqual(
            liveCount(deviceB), 0,
            "With nothing pending locally the delete is unambiguous and must apply"
        )
    }
}
