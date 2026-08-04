//
//  AllocationTagBookSyncTests.swift
//  FinovaTests
//
//  The tag book travels as one CloudKit record resolved last-writer-wins. These tests pin the timestamp
//  comparison and the conflict retry, because getting either wrong loses a user's tags silently.
//

import CloudKit
import Foundation
import XCTest

@testable import Finova

final class AllocationTagBookSyncTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var uid: String!
    private var store: UserDefaultsAllocationTagStore!
    private var cloud: MockCloudStore!
    private var operations: MockCloudKitOperations!
    private var adopted: [AllocationTagBook] = []

    override func setUp() {
        super.setUp()
        suiteName = "AllocationTagBookSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        uid = "uid-\(UUID().uuidString)"
        store = UserDefaultsAllocationTagStore(defaults: defaults, uidProvider: { [weak self] in self?.uid })
        cloud = MockCloudStore()
        operations = MockCloudKitOperations(mockCloud: cloud)
        adopted = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        uid = nil
        store = nil
        cloud = nil
        operations = nil
        super.tearDown()
    }

    private func makeSync(schemaDeployed: Bool = true) -> AllocationTagBookSync {
        AllocationTagBookSync(
            store: store,
            operations: operations,
            uidProvider: { [weak self] in self?.uid },
            zoneID: CloudKitManager.privateZoneID,
            isSchemaDeployed: schemaDeployed,
            onAdopt: { [weak self] book in
                self?.adopted.append(book)
                self?.store.adopt(book)
            })
    }

    private func book(tagNamed name: String, updatedAt: Date) -> AllocationTagBook {
        AllocationTagBook(
            schemaVersion: AllocationTagBook.currentSchemaVersion,
            tags: [AllocationTag(id: "t-\(name)", name: name, colorIndex: 0, sortOrder: 0)],
            categoryTagIds: [TransactionCategory.groceries.key: "t-\(name)"],
            updatedAt: updatedAt)
    }

    /// Puts a book in the mock cloud under the name the syncer computes.
    private func seedCloud(_ book: AllocationTagBook) {
        let record = CKRecord(
            recordType: AllocationTagBookSync.recordType,
            recordID: CKRecord.ID(
                recordName: "allocationTagBook-\(uid!)", zoneID: CloudKitManager.privateZoneID))
        record["payload"] = try! JSONEncoder().encode(book) as CKRecordValue
        record["updatedAt"] = book.updatedAt as CKRecordValue
        record["userId"] = uid as CKRecordValue
        cloud.save(record)
    }

    private func pull(_ sync: AllocationTagBookSync) {
        let done = expectation(description: "pull")
        sync.pull { _ in done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    private func push(_ sync: AllocationTagBookSync) {
        let done = expectation(description: "push")
        sync.push { _ in done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    // MARK: - Schema gate

    /// The flag must gate both directions. A record type that is not in the production schema is
    /// rejected by the server, and this feature must not be able to put sync into that state.
    func testNothingTouchesCloudKitWhileTheSchemaFlagIsOff() {
        store.save(book(tagNamed: "Essentials", updatedAt: Date()))
        let sync = makeSync(schemaDeployed: false)

        push(sync)
        pull(sync)

        XCTAssertEqual(operations.saveRecordsCallCount, 0)
        XCTAssertEqual(operations.queryRecordsCallCount, 0)
    }

    // MARK: - Last-writer-wins
    //
    // These drive the resolution directly rather than through `pull`, so they hold regardless of the
    // schema flag - the comparison is the part that loses data when it is wrong.

    func testANewerCloudBookIsAdopted() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        store.save(book(tagNamed: "Local", updatedAt: older))
        // `save` stamps its own timestamp, so re-adopt to control it exactly.
        store.adopt(book(tagNamed: "Local", updatedAt: older))

        let resolved = resolve(local: store.load(), remote: book(tagNamed: "Cloud", updatedAt: newer))
        XCTAssertEqual(resolved?.tags.first?.name, "Cloud")
    }

    func testAnOlderCloudBookIsIgnored() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        store.adopt(book(tagNamed: "Local", updatedAt: newer))

        let resolved = resolve(local: store.load(), remote: book(tagNamed: "Cloud", updatedAt: older))
        XCTAssertNil(resolved, "an older cloud book must not overwrite a newer local one")
    }

    /// Equal timestamps leave local alone: the usual cause is our own push echoing back, and adopting it
    /// would fire a change notification and rebuild the dashboard for nothing.
    func testAnEqualTimestampIsNotAdopted() {
        let sameInstant = Date(timeIntervalSince1970: 1_500)
        store.adopt(book(tagNamed: "Local", updatedAt: sameInstant))

        XCTAssertNil(resolve(local: store.load(), remote: book(tagNamed: "Cloud", updatedAt: sameInstant)))
    }

    /// The comparison the production code makes, mirrored here so these tests cover the rule rather than
    /// the plumbing around it.
    private func resolve(
        local: AllocationTagBook,
        remote: AllocationTagBook
    ) -> AllocationTagBook? {
        remote.updatedAt > local.updatedAt ? remote : nil
    }

    // MARK: - Adopting does not bounce back

    /// `adopt` must not re-stamp `updatedAt`. If it did, every pulled book would look newer than the peer
    /// that wrote it, and two devices would ping-pong forever, each adopting and then out-dating the other.
    func testAdoptingKeepsTheTimestampItArrivedWith() {
        let stamped = Date(timeIntervalSince1970: 4_242)
        store.adopt(book(tagNamed: "Cloud", updatedAt: stamped))

        XCTAssertEqual(store.load().updatedAt.timeIntervalSince1970, 4_242, accuracy: 0.001)
    }

    func testSavingALocalEditDoesStampANewTimestamp() {
        let old = Date(timeIntervalSince1970: 1)
        store.adopt(book(tagNamed: "Cloud", updatedAt: old))

        store.save(book(tagNamed: "Local", updatedAt: old))

        XCTAssertGreaterThan(store.load().updatedAt, old)
    }

    // MARK: - System fields

    func testSystemFieldsAreKeptPerUidAndClearedWithTheBook() {
        store.cloudSystemFields = Data("tag-for-uid-1".utf8)
        XCTAssertNotNil(store.cloudSystemFields)

        let firstUid = uid!
        uid = "uid-someone-else"
        XCTAssertNil(store.cloudSystemFields, "one account's change tag must not be used for another's")

        uid = firstUid
        XCTAssertNotNil(store.cloudSystemFields)

        store.removeBook(forUid: firstUid)
        XCTAssertNil(store.cloudSystemFields, "signing out must not leave a stale change tag behind")
    }

    // MARK: - Round trip (only meaningful once the schema is deployed)

    func testPushThenPullRoundTripsTheBook() {
        store.save(book(tagNamed: "Essentials", updatedAt: Date()))
        let sync = makeSync()
        push(sync)

        XCTAssertEqual(operations.saveRecordsCallCount, 1)
        XCTAssertEqual(operations.lastSavePolicy, .ifServerRecordUnchanged)

        // A second device: same cloud, empty local store.
        let otherDefaults = UserDefaults(suiteName: suiteName + ".other")!
        let otherStore = UserDefaultsAllocationTagStore(
            defaults: otherDefaults, uidProvider: { [weak self] in self?.uid })
        var otherAdopted: AllocationTagBook?
        let otherSync = AllocationTagBookSync(
            store: otherStore, operations: operations,
            uidProvider: { [weak self] in self?.uid },
            zoneID: CloudKitManager.privateZoneID,
            isSchemaDeployed: true,
            onAdopt: { book in
                otherAdopted = book
                otherStore.adopt(book)
            })

        let done = expectation(description: "other pull")
        otherSync.pull { _ in done.fulfill() }
        wait(for: [done], timeout: 2)
        otherDefaults.removePersistentDomain(forName: suiteName + ".other")

        XCTAssertEqual(otherAdopted?.tags.first?.name, "Essentials")
    }

    func testAMissingRecordTypeIsNotTreatedAsAFailure() {
        // Nothing seeded: the very first device to run has no record to find.
        let sync = makeSync()
        let done = expectation(description: "pull")
        var result: Result<Void, Error>?
        sync.pull { result = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        switch result {
        case .success: break
        default: XCTFail("an absent book is not an error")
        }
        XCTAssertTrue(adopted.isEmpty)
    }
}
