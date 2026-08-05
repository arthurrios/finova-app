//
//  AllocationTagStoreTests.swift
//  FinovaTests
//
//  Persistence of the allocation tag book, and the rules that keep a bad read from becoming data loss.
//

import Foundation
import XCTest

@testable import Finova

final class AllocationTagStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var uid: String!

    override func setUp() {
        super.setUp()
        // A private suite, never `.standard`: the rest of the app hardcodes standard defaults, and a
        // test run must not mutate the developer's own state.
        suiteName = "AllocationTagStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        uid = "uid-\(UUID().uuidString)"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        uid = nil
        super.tearDown()
    }

    private func makeStore(uid overrideUid: String? = nil) -> UserDefaultsAllocationTagStore {
        let resolved = overrideUid ?? uid!
        return UserDefaultsAllocationTagStore(defaults: defaults, uidProvider: { resolved })
    }

    private func key(for uid: String) -> String { "allocationTagBook_v1_\(uid)" }

    private func book(
        tags: [AllocationTag],
        map: [String: String] = [:]
    ) -> AllocationTagBook {
        AllocationTagBook(
            schemaVersion: AllocationTagBook.currentSchemaVersion,
            tags: tags,
            categoryTagIds: map,
            updatedAt: .distantPast)
    }

    private func tag(
        _ id: String,
        name: String = "Essentials",
        colorIndex: Int = 0,
        icon: String? = nil,
        sortOrder: Int = 0
    ) -> AllocationTag {
        AllocationTag(
            id: id, name: name, colorIndex: colorIndex, iconAssetName: icon, sortOrder: sortOrder)
    }

    // MARK: - Round trip

    func testEmptyWhenNothingHasBeenSaved() {
        XCTAssertEqual(makeStore().load(), .empty)
    }

    func testRoundTripsTagsAndTheCategoryMap() {
        let store = makeStore()
        let saved = book(
            tags: [tag("t1", name: "Essentials", colorIndex: 2, sortOrder: 0)],
            map: [TransactionCategory.groceries.key: "t1"])

        store.save(saved)
        let loaded = makeStore().load()

        XCTAssertEqual(loaded.tags.count, 1)
        XCTAssertEqual(loaded.tags.first?.name, "Essentials")
        XCTAssertEqual(loaded.tags.first?.colorIndex, 2)
        XCTAssertEqual(loaded.categoryTagIds[TransactionCategory.groceries.key], "t1")
    }

    func testSaveStampsUpdatedAt() {
        let store = makeStore()
        store.save(book(tags: [tag("t1")]))

        XCTAssertGreaterThan(store.load().updatedAt, .distantPast)
    }

    func testBooksAreIsolatedPerUid() {
        let other = "uid-other"
        makeStore().save(book(tags: [tag("t1", name: "Mine")]))
        makeStore(uid: other).save(book(tags: [tag("t2", name: "Theirs")]))

        XCTAssertEqual(makeStore().load().tags.first?.name, "Mine")
        XCTAssertEqual(makeStore(uid: other).load().tags.first?.name, "Theirs")
    }

    /// Signed out, there is no book. Falling back to an unkeyed slot would leak one account's grouping
    /// into the next account that signs in on the device.
    func testNoUidReadsAndWritesNothing() {
        let store = UserDefaultsAllocationTagStore(defaults: defaults, uidProvider: { nil })

        store.save(book(tags: [tag("t1")]))

        XCTAssertEqual(store.load(), .empty)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.allSatisfy {
            !$0.hasPrefix("allocationTagBook_v1_")
        })
    }

    // MARK: - Sanitisation

    func testDropsTagsWithBlankNames() {
        makeStore().save(book(tags: [tag("t1", name: "  "), tag("t2", name: "Real", sortOrder: 1)]))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.tags.map { $0.id }, ["t2"])
    }

    func testTrimsWhitespaceFromNames() {
        makeStore().save(book(tags: [tag("t1", name: "  Essentials  ")]))

        XCTAssertEqual(makeStore().load().tags.first?.name, "Essentials")
    }

    func testClampsAnOutOfRangeColorIndex() {
        makeStore().save(book(tags: [tag("t1", colorIndex: 99), tag("t2", colorIndex: -3, sortOrder: 1)]))

        let loaded = makeStore().load()
        for tag in loaded.tags {
            XCTAssertTrue((0..<AllocationTagPalette.count).contains(tag.colorIndex))
        }
    }

    func testNullsOutAnIconAssetThatNoLongerExists() {
        makeStore().save(book(tags: [tag("t1", icon: "lucide_iconThatDoesNotExist")]))

        let loaded = makeStore().load()
        XCTAssertNil(loaded.tags.first?.iconAssetName)
        XCTAssertEqual(loaded.tags.first?.icon, .systemSymbol(AllocationTag.defaultSymbolName))
    }

    func testKeepsAnIconAssetThatDoesExist() {
        makeStore().save(book(tags: [tag("t1", icon: "lucide_iconHomeMaintenance")]))

        XCTAssertEqual(makeStore().load().tags.first?.iconAssetName, "lucide_iconHomeMaintenance")
    }

    func testDropsMapEntriesForUnknownCategories() {
        makeStore().save(
            book(
                tags: [tag("t1")],
                map: ["notARealCategory": "t1", TransactionCategory.groceries.key: "t1"]))

        let loaded = makeStore().load()
        XCTAssertEqual(Array(loaded.categoryTagIds.keys), [TransactionCategory.groceries.key])
    }

    /// The corruption most worth designing out: a link left behind by an interrupted delete.
    func testDropsMapEntriesPointingAtAMissingTag() {
        makeStore().save(
            book(
                tags: [tag("t1")],
                map: [
                    TransactionCategory.groceries.key: "t1",
                    TransactionCategory.travel.key: "t-deleted",
                ]))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.categoryTagIds[TransactionCategory.groceries.key], "t1")
        XCTAssertNil(loaded.categoryTagIds[TransactionCategory.travel.key])
    }

    func testDensifiesSortOrderWhileKeepingRelativeOrder() {
        makeStore().save(
            book(tags: [
                tag("t1", name: "Third", sortOrder: 90),
                tag("t2", name: "First", sortOrder: 3),
                tag("t3", name: "Second", sortOrder: 40),
            ]))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.orderedTags.map { $0.name }, ["First", "Second", "Third"])
        XCTAssertEqual(loaded.orderedTags.map { $0.sortOrder }, [0, 1, 2])
    }

    func testDropsDuplicateTagIds() {
        makeStore().save(
            book(tags: [tag("t1", name: "Keep"), tag("t1", name: "Dupe", sortOrder: 1)]))

        XCTAssertEqual(makeStore().load().tags.count, 1)
    }

    // MARK: - Untrusted reads

    /// A decode failure must never destroy the bytes it could not read - they may be a newer format or
    /// the victim of a bug about to be fixed.
    func testCorruptBlobReadsEmptyAndIsNeverOverwritten() {
        let corrupt = Data("this is not a tag book".utf8)
        defaults.set(corrupt, forKey: key(for: uid))

        let store = makeStore()
        XCTAssertEqual(store.load(), .empty)
        XCTAssertTrue(store.isReadOnly)

        store.save(book(tags: [tag("t1")]))

        XCTAssertEqual(defaults.data(forKey: key(for: uid)), corrupt, "the unreadable bytes were replaced")
    }

    /// Only reachable by installing an older build over a newer one.
    func testANewerSchemaVersionIsReadOnly() throws {
        let future = AllocationTagBook(
            schemaVersion: AllocationTagBook.currentSchemaVersion + 1,
            tags: [tag("t1", name: "FromTheFuture")],
            categoryTagIds: [:],
            updatedAt: Date())
        let encoded = try JSONEncoder().encode(future)
        defaults.set(encoded, forKey: key(for: uid))

        let store = makeStore()
        let loaded = store.load()

        XCTAssertEqual(loaded.tags.first?.name, "FromTheFuture", "readable content should still show")
        XCTAssertTrue(store.isReadOnly)

        store.save(book(tags: []))
        XCTAssertEqual(defaults.data(forKey: key(for: uid)), encoded)
    }

    func testReadOnlyClearsOnceTheStoredBookIsValidAgain() {
        defaults.set(Data("garbage".utf8), forKey: key(for: uid))
        let store = makeStore()
        _ = store.load()
        XCTAssertTrue(store.isReadOnly)

        defaults.removeObject(forKey: key(for: uid))
        _ = store.load()

        XCTAssertFalse(store.isReadOnly)
        store.save(book(tags: [tag("t1")]))
        XCTAssertEqual(store.load().tags.count, 1)
    }

    func testRemoveBookDeletesOnlyThatUid() {
        let other = "uid-other"
        makeStore().save(book(tags: [tag("t1")]))
        makeStore(uid: other).save(book(tags: [tag("t2")]))

        makeStore().removeBook(forUid: uid)

        XCTAssertEqual(makeStore().load(), .empty)
        XCTAssertEqual(makeStore(uid: other).load().tags.count, 1)
    }

    // MARK: - Colour assignment

    func testColoursAreClaimedInAssignmentOrder() {
        var tags: [AllocationTag] = []
        var assigned: [Int] = []

        for index in 0..<AllocationTagPalette.count {
            let next = AllocationTagPalette.nextColorIndex(existing: tags)
            assigned.append(next)
            tags.append(tag("t\(index)", colorIndex: next, sortOrder: index))
        }

        XCTAssertEqual(assigned, AllocationTagPalette.assignmentOrder)
    }

    func testPastTheEndOfThePaletteColoursWrapToTheLeastUsed() {
        var tags: [AllocationTag] = []
        for index in 0..<AllocationTagPalette.count {
            tags.append(tag("t\(index)", colorIndex: AllocationTagPalette.assignmentOrder[index]))
        }

        // Every colour used once, so the ninth tag reuses the first in assignment order.
        let ninth = AllocationTagPalette.nextColorIndex(existing: tags)
        XCTAssertEqual(ninth, AllocationTagPalette.assignmentOrder.first)

        tags.append(tag("t8", colorIndex: ninth))
        let tenth = AllocationTagPalette.nextColorIndex(existing: tags)
        XCTAssertEqual(tenth, AllocationTagPalette.assignmentOrder[1])
    }

    /// Deleting a tag frees its colour, which is what a user expects when they delete and recreate.
    func testDeletingATagFreesItsColourForTheNextOne() {
        var tags = (0..<4).map {
            tag("t\($0)", colorIndex: AllocationTagPalette.assignmentOrder[$0], sortOrder: $0)
        }
        let freed = tags[2].colorIndex
        tags.remove(at: 2)

        XCTAssertEqual(AllocationTagPalette.nextColorIndex(existing: tags), freed)
    }

    func testColourAssignmentIgnoresOutOfRangeStoredIndexes() {
        let tags = [tag("t1", colorIndex: AllocationTagPalette.count)]  // clamps to 0

        XCTAssertNotEqual(
            AllocationTagPalette.nextColorIndex(existing: tags), 0,
            "an index that clamps to 0 must still count as using colour 0")
    }
}
