//
//  RevOrderingTests.swift
//  FinovaTests
//
//  Which side wins a conflict.
//
//  Timestamp last-writer-wins reads `updatedAt`, a WALL CLOCK value set by whichever device made the
//  edit. A device whose clock runs ten minutes fast therefore wins every conflict against every other
//  device, silently, for as long as the skew lasts — and the loser's edits vanish with no error
//  anywhere. That is the failure this replaces.
//
//  `rev` is a logical clock: monotonic per record, incremented on push, immune to what any device
//  thinks the time is. `revDevice` breaks exact ties the same way on every device, which is what
//  makes the outcome CONVERGENT — both sides independently reach the same answer.
//
//  Worth being clear about what this does NOT do: it does not preserve more data. Two devices editing
//  from rev 5 both push rev 6, one loses, and the losing edit is dropped exactly as under LWW. What
//  changes is that the choice no longer depends on clock accuracy, and both devices agree on it.
//

import CloudKit
import XCTest

@testable import Finova

final class RevOrderingTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var resolver: ConflictResolver!
    private var repo: TransactionRepository!
    private var userUID: String!

    private let recordName = "transaction-REV-TEST"
    private let localAmount = 1000
    private let remoteAmount = 9999

    override func setUp() {
        super.setUp()
        userUID = "rev_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaRev-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        repo = TransactionRepository(db: db)
        resolver = ConflictResolver(db: db)
        TransactionRepository.invalidateCache()
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// A synced local row at a known version, edited `localEditedAt`.
    private func seedLocal(rev: Int, device: String, localEditedAt: Date) {
        try? repo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Contested", amount: localAmount))
        guard let id = db.fetchSingleInt(
            "SELECT id FROM Transactions WHERE title = 'Contested';") else {
            return XCTFail("setup: insert failed")
        }
        repo.setCKRecordId(for: id, ckRecordName: recordName)
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET updated_at = ?, sync_status = 'synced' WHERE id = ?;",
            orderedBindings: [Int(localEditedAt.timeIntervalSince1970), id])
        if rev > 0 {
            db.setRev(table: "Transactions", ckRecordName: recordName, rev: rev, device: device)
        }
        TransactionRepository.invalidateCache()
    }

    /// An inbound record for the same row, at `rev`, claiming to have been edited `remoteEditedAt`.
    /// Built from the seeded local row so it is genuinely the same record, differing only in the
    /// amount and the version metadata — which is what a real conflicting edit looks like.
    private func inbound(rev: Int?, device: String, remoteEditedAt: Date) -> (Transaction, CKRecord)? {
        TransactionRepository.invalidateCache()
        guard let local = repo.fetchAllTransactions().first(where: { $0.title == "Contested" }) else {
            XCTFail("setup: seeded row not found")
            return nil
        }
        let record = local.toCKRecord(in: MockCloudStore.zoneID, storedRecordName: recordName, db: db)
        record["amount"] = remoteAmount as CKRecordValue
        record["updatedAt"] = remoteEditedAt as CKRecordValue
        if let rev { record["rev"] = rev as CKRecordValue }
        record["revDevice"] = device as CKRecordValue

        // `updatedAt` is read from the record during parsing, so setting it above is sufficient —
        // the property itself is get-only.
        guard let remote = Transaction.fromCKRecord(record) else {
            XCTFail("setup: could not parse inbound record")
            return nil
        }
        return (remote, record)
    }

    private func amountNow() -> Int? {
        db.fetchSingleInt("SELECT amount FROM Transactions WHERE ck_record_id = ?;",
                          textBinding: recordName)
    }

    // MARK: - The logical clock decides

    func testHigherRemoteRevWins() {
        seedLocal(rev: 5, device: "deviceLocal", localEditedAt: Date())
        guard let (remote, record) = inbound(rev: 7, device: "deviceRemote", remoteEditedAt: Date()) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(amountNow(), remoteAmount, "rev 7 is newer than rev 5")
    }

    func testLowerRemoteRevLoses() {
        seedLocal(rev: 9, device: "deviceLocal", localEditedAt: Date())
        guard let (remote, record) = inbound(rev: 4, device: "deviceRemote", remoteEditedAt: Date()) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(amountNow(), localAmount, "rev 4 is older than rev 9 and must not overwrite")
    }

    /// THE test. The remote edit is genuinely newer by rev, but its wall clock is an hour BEHIND —
    /// which is all it took for the old comparator to discard it.
    func testRevBeatsAMisleadingClock() {
        let now = Date()
        seedLocal(rev: 2, device: "deviceLocal", localEditedAt: now)
        guard let (remote, record) = inbound(rev: 8, device: "deviceRemote", remoteEditedAt: now.addingTimeInterval(-3600)) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(
            amountNow(), remoteAmount,
            """
            A newer edit was discarded because the sending device's clock was behind. Under timestamp \
            ordering a device with a fast clock wins every conflict against every other device, \
            silently and indefinitely. rev is a logical clock and does not care what time anyone \
            thinks it is.
            """
        )
    }

    /// The mirror image: an OLDER edit whose clock runs fast must not win.
    func testAFastClockCannotWinWithAnOlderRev() {
        let now = Date()
        seedLocal(rev: 8, device: "deviceLocal", localEditedAt: now.addingTimeInterval(-3600))
        guard let (remote, record) = inbound(rev: 2, device: "deviceRemote", remoteEditedAt: now) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(
            amountNow(), localAmount,
            "A fast clock must not let a stale edit overwrite a newer one"
        )
    }

    // MARK: - Ties converge

    /// Two devices editing from the same rev both push rev+1. The tie-break has to be a value both
    /// compute identically, or the two devices reach OPPOSITE conclusions and never converge.
    func testEqualRevsResolveDeterministicallyOnDeviceIdentity() {
        seedLocal(rev: 6, device: "deviceAAA", localEditedAt: Date())
        guard let (remote, record) = inbound(rev: 6, device: "deviceZZZ", remoteEditedAt: Date()) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(
            amountNow(), remoteAmount,
            "On an exact tie the higher device identifier wins — arbitrary, but the SAME arbitrary "
                + "answer on both devices, which is what convergence requires"
        )
    }

    func testEqualRevsWithLowerRemoteDeviceLoses() {
        seedLocal(rev: 6, device: "deviceZZZ", localEditedAt: Date())
        guard let (remote, record) = inbound(rev: 6, device: "deviceAAA", remoteEditedAt: Date()) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(amountNow(), localAmount, "The tie-break must be antisymmetric")
    }

    // MARK: - Mixed-version peers

    /// A peer on an older build sends no `rev` at all. Ordering must fall back to timestamps rather
    /// than treating the absent field as rev 0 and always losing to us.
    func testPeerWithoutRevFallsBackToTimestamps() {
        let now = Date()
        seedLocal(rev: 4, device: "deviceLocal", localEditedAt: now.addingTimeInterval(-600))
        guard let (remote, record) = inbound(rev: nil, device: "", remoteEditedAt: now) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(
            amountNow(), remoteAmount,
            "With no rev on the wire the only ordering available is the timestamp, and the remote's "
                + "is newer — an old peer's edits must still be able to land"
        )
    }

    func testPeerWithoutRevAndOlderTimestampLoses() {
        let now = Date()
        seedLocal(rev: 4, device: "deviceLocal", localEditedAt: now)
        guard let (remote, record) = inbound(rev: nil, device: "", remoteEditedAt: now.addingTimeInterval(-600)) else { return }

        resolver.resolveTransaction(remote: remote, ckRecord: record)

        XCTAssertEqual(amountNow(), localAmount)
    }
}
