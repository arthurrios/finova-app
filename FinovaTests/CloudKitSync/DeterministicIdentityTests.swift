//
//  DeterministicIdentityTests.swift
//  FinovaTests
//
//  Generated rows — recurring instances, installment children, statements — are materialised lazily
//  on whichever device opens the month first, and the insert trigger gives each a RANDOM v4 uuid. Two
//  devices that both render March before either syncs therefore minted two different identities for
//  the same logical row, and the receiver could only guess they were the same by comparing content.
//
//  These tests pin the property that removes the guessing: the same logical row derives the same
//  identity on every device, computed from data both already hold.
//

import XCTest

@testable import Finova

final class DeterministicIdentityTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!

    override func setUp() {
        super.setUp()
        userUID = "detid_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaDetId-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - The derivation itself

    /// The whole point: no coordination, no network, same answer.
    func testSameInputsDeriveTheSameIdentity() {
        let a = DeterministicIdentity.recurringInstance(parentUuid: "PARENT-1", monthDate: 1_700_000_000)
        let b = DeterministicIdentity.recurringInstance(parentUuid: "PARENT-1", monthDate: 1_700_000_000)

        XCTAssertEqual(a, b, "Two devices must derive the same uuid for the same (series, month)")
    }

    func testDifferentMonthsAndParentsDiffer() {
        let base = DeterministicIdentity.recurringInstance(parentUuid: "P1", monthDate: 100)

        XCTAssertNotEqual(base, DeterministicIdentity.recurringInstance(parentUuid: "P1", monthDate: 200))
        XCTAssertNotEqual(base, DeterministicIdentity.recurringInstance(parentUuid: "P2", monthDate: 100))
    }

    /// The prefixes keep the keyspaces apart. Without them a transaction instance and an allocation
    /// instance for the same parent uuid and month would collide — and a collision between two
    /// different record types is unrecoverable, because both would claim the same CloudKit name.
    func testKeyspacesDoNotCollideAcrossRecordTypes() {
        let parent = "SHARED-PARENT-UUID"
        let month = 1_700_000_000
        let derived = [
            DeterministicIdentity.recurringInstance(parentUuid: parent, monthDate: month),
            DeterministicIdentity.allocationInstance(parentUuid: parent, monthDate: month),
            DeterministicIdentity.statement(cardUuid: parent, statementMonth: month),
            DeterministicIdentity.installment(parentUuid: parent, installmentNumber: month),
        ]

        XCTAssertEqual(Set(derived).count, derived.count, "Each record type needs its own keyspace")
    }

    /// It must be a well-formed RFC 4122 v5 uuid, indistinguishable in shape from the v4s the insert
    /// trigger produces — the two live in the same column and are parsed by the same code.
    func testIsAWellFormedVersion5Uuid() {
        let value = DeterministicIdentity.recurringInstance(parentUuid: "P", monthDate: 1)

        XCTAssertNotNil(UUID(uuidString: value), "Must parse as a UUID: \(value)")
        XCTAssertEqual(value, value.uppercased(), "Canonical form is uppercase, like UUID().uuidString")

        let groups = value.split(separator: "-").map(\.count)
        XCTAssertEqual(groups, [8, 4, 4, 4, 12])
        XCTAssertEqual(value[value.index(value.startIndex, offsetBy: 14)], "5", "Version nibble must be 5")
        XCTAssertTrue(
            "89AB".contains(value[value.index(value.startIndex, offsetBy: 19)]),
            "Variant bits must be RFC 4122"
        )
    }

    /// Pinned so the namespace can never be changed casually. Every derived uuid in every user's
    /// database and in CloudKit is a function of it — changing it silently re-keys everything.
    func testDerivationIsStableAcrossBuilds() {
        XCTAssertEqual(
            DeterministicIdentity.recurringInstance(parentUuid: "STABLE-PARENT", monthDate: 1_700_000_000),
            DeterministicIdentity.v5("txinstance|STABLE-PARENT|1700000000"),
            "The key format is part of the contract, not an implementation detail"
        )
    }

    // MARK: - Assignment, and the guard that makes it safe

    private func insertTransaction(title: String) -> Int {
        let repo = TransactionRepository(db: db)
        try? repo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: title, amount: 1000))
        return db.fetchSingleInt("SELECT id FROM Transactions WHERE title = ?;", textBinding: title) ?? 0
    }

    private func uuid(ofTransaction id: Int) -> String? {
        db.fetchSingleInt("SELECT COUNT(*) FROM Transactions WHERE id = ?;", intBinding: id) == 1
            ? db.fetchSingleString("SELECT uuid FROM Transactions WHERE id = ?;", intBinding: id)
            : nil
    }

    func testAssignsDerivedIdentityToAnUnpushedRow() {
        let id = insertTransaction(title: "Instance")
        let random = uuid(ofTransaction: id)
        let derived = DeterministicIdentity.recurringInstance(parentUuid: "P1", monthDate: 42)

        XCTAssertTrue(db.assignDeterministicUuid(table: "Transactions", localId: id, uuid: derived))

        XCTAssertEqual(uuid(ofTransaction: id), derived)
        XCTAssertNotEqual(uuid(ofTransaction: id), random, "The trigger's random uuid must be replaced")
    }

    /// The guard the whole design rests on. A pushed row's CloudKit name is `<type>-<uuid>` and
    /// CKRecord names are IMMUTABLE — so re-keying means delete plus create, which a device on an
    /// older build receives as a deletion and faithfully applies. Re-keying is data loss.
    func testRefusesToRekeyARowThatHasAlreadyBeenPushed() {
        let id = insertTransaction(title: "AlreadyPushed")
        TransactionRepository(db: db).setCKRecordId(for: id, ckRecordName: "transaction-PUSHED")
        let before = uuid(ofTransaction: id)

        let assigned = db.assignDeterministicUuid(
            table: "Transactions", localId: id,
            uuid: DeterministicIdentity.recurringInstance(parentUuid: "P1", monthDate: 42))

        XCTAssertFalse(assigned, "A pushed row must be refused")
        XCTAssertEqual(
            uuid(ofTransaction: id), before,
            """
            Re-keyed a row that is already in CloudKit. Its record name is derived from the uuid and \
            CKRecord names are immutable, so this becomes delete + create — which a device on an \
            older build applies as a deletion.
            """
        )
    }

    // MARK: - The behaviour this buys

    /// Two devices generating the same month independently now produce ONE identity, so the row
    /// converges on record name alone and never reaches the content matchers.
    func testTwoDevicesGeneratingTheSameMonthAgreeOnIdentity() {
        let cloud = MockCloudStore()
        let deviceA = DeviceSimulator(userUID: userUID, mockCloud: cloud, label: "A")
        let deviceB = DeviceSimulator(userUID: userUID, mockCloud: cloud, label: "B")
        defer { deviceA.cleanup(); deviceB.cleanup() }

        // The same logical series on both devices — same parent identity, same month.
        let parentUuid = "SERIES-PARENT-UUID"
        let month = 1_700_000_000

        var identities: [String] = []
        for device in [deviceA, deviceB] {
            device.activate()
            let repo = TransactionRepository(db: device.db)
            try? repo.insertTransaction(
                CloudKitSyncTestHelpers.makeTransactionModel(title: "Netflix", amount: 5490))
            guard let id = device.db.fetchSingleInt(
                "SELECT id FROM Transactions WHERE title = 'Netflix';") else {
                return XCTFail("setup: insert failed")
            }
            device.db.assignDeterministicUuid(
                table: "Transactions", localId: id,
                uuid: DeterministicIdentity.recurringInstance(parentUuid: parentUuid, monthDate: month))
            identities.append(
                device.db.fetchSingleString("SELECT uuid FROM Transactions WHERE id = ?;", intBinding: id) ?? "")
        }

        XCTAssertEqual(
            identities[0], identities[1],
            """
            Two devices materialising the same month must arrive at the same identity. When they did \
            not, the receiver had to decide whether two rows with the same title, amount and month \
            were the same record — which merges genuinely distinct purchases and duplicates identical \
            ones.
            """
        )
        XCTAssertFalse(identities[0].isEmpty)
    }
}
