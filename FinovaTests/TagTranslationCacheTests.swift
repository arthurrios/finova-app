//
//  TagTranslationCacheTests.swift
//  FinovaTests
//
//  The per-device store behind a tag's display name: machine translations, source languages, and the
//  names a user typed to replace a translation.
//

import Foundation
import XCTest

@testable import Finova

final class TagTranslationCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var uid: String!
    private var cache: TagTranslationCache!

    override func setUp() {
        super.setUp()
        suiteName = "TagTranslationCacheTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        uid = "uid-\(UUID().uuidString)"
        cache = TagTranslationCache(defaults: defaults, uidProvider: { [uid] in uid })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        cache = nil
        super.tearDown()
    }

    // MARK: - Translations

    func testATranslationRoundTrips() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertEqual(cache.translation(forTagId: "t1", name: "Essentials", language: "pt"), "Essenciais")
    }

    func testATranslationEqualToTheInputIsNotStored() {
        // Caching this would look like a success and stop the pass ever trying again.
        cache.store("Essentials", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertNil(cache.translation(forTagId: "t1", name: "Essentials", language: "pt"))
    }

    func testABlankTranslationIsNotStored() {
        cache.store("   ", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertNil(cache.translation(forTagId: "t1", name: "Essentials", language: "pt"))
    }

    func testRenamingMissesTheCache() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertNil(
            cache.translation(forTagId: "t1", name: "Essential expenses", language: "pt"),
            "the name is part of the key, so a rename re-queues with no invalidation hook")
    }

    // MARK: - Source language

    func testASourceLanguageRoundTrips() {
        cache.storeSourceLanguage("en", forTagId: "t1", name: "Essentials")

        XCTAssertEqual(cache.sourceLanguage(forTagId: "t1", name: "Essentials"), "en")
    }

    // MARK: - Overrides

    func testAnOverrideRoundTripsAndClears() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")
        XCTAssertEqual(cache.override(forTagId: "t1", language: "pt"), "Básicos")

        cache.setOverride(nil, forTagId: "t1", language: "pt")
        XCTAssertNil(cache.override(forTagId: "t1", language: "pt"))
    }

    func testABlankOverrideClears() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")
        cache.setOverride("   ", forTagId: "t1", language: "pt")

        XCTAssertNil(cache.override(forTagId: "t1", language: "pt"))
    }

    func testAnOverrideSurvivesARename() {
        // Pins a deliberate decision, so a future refactor that "helpfully" adds the name to the
        // override key fails here rather than silently discarding what the user typed.
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertEqual(
            cache.override(forTagId: "t1", language: "pt"), "Básicos",
            "an override is attached to the tag, not to the name it happened to have")
    }

    func testAnOverrideIsPerLanguage() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertNil(
            cache.override(forTagId: "t1", language: "es"),
            "a Portuguese override must not leak onto the same account's Spanish phone")
    }

    func testAnOverrideEqualToTheTagNameIsAllowed() {
        // This is how a user says "leave this one alone" for a single tag without turning the whole
        // feature off, so unlike a machine translation it must not be rejected as a no-op.
        cache.setOverride("Essentials", forTagId: "t1", language: "pt")

        XCTAssertEqual(cache.override(forTagId: "t1", language: "pt"), "Essentials")
    }

    func testAMachineTranslationNeverOverwritesAnOverride() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertNil(
            cache.translation(forTagId: "t1", name: "Essentials", language: "pt"),
            "the pass filters overridden tags out, but the invariant has to hold here too")
        XCTAssertEqual(cache.override(forTagId: "t1", language: "pt"), "Básicos")
    }

    func testAnOverrideShieldsTheTagAcrossRegionVariants() {
        // The pass targets a minimalIdentifier, which can be bare "pt" while the override was typed
        // against "pt-PT". Both must count as "the user has spoken".
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt-PT")

        XCTAssertNil(cache.translation(forTagId: "t1", name: "Essentials", language: "pt-PT"))
    }

    // MARK: - Housekeeping

    func testForgettingATagDropsItsTranslationSourceAndOverride() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        cache.storeSourceLanguage("en", forTagId: "t1", name: "Essentials")
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")
        cache.store("Lazer", forTagId: "t2", name: "Leisure", language: "pt")

        cache.forget(tagId: "t1")

        XCTAssertNil(cache.translation(forTagId: "t1", name: "Essentials", language: "pt"))
        XCTAssertNil(cache.sourceLanguage(forTagId: "t1", name: "Essentials"))
        XCTAssertNil(
            cache.override(forTagId: "t1", language: "pt"),
            "an override outlives a rename, so without this a reused id would inherit it")
        XCTAssertEqual(
            cache.translation(forTagId: "t2", name: "Leisure", language: "pt"), "Lazer",
            "other tags are untouched")
    }

    func testClearAllEmptiesEveryPrefix() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        cache.storeSourceLanguage("en", forTagId: "t1", name: "Essentials")
        cache.setOverride("Básicos", forTagId: "t2", language: "pt")

        cache.clearAll()

        XCTAssertNil(cache.translation(forTagId: "t1", name: "Essentials", language: "pt"))
        XCTAssertNil(cache.sourceLanguage(forTagId: "t1", name: "Essentials"))
        XCTAssertNil(cache.override(forTagId: "t2", language: "pt"))
    }

    // MARK: - Isolation

    func testEntriesDoNotLeakBetweenUsers() {
        var currentUid = "uid-a"
        let shared = TagTranslationCache(defaults: defaults, uidProvider: { currentUid })
        shared.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        currentUid = "uid-b"
        XCTAssertNil(shared.translation(forTagId: "t1", name: "Essentials", language: "pt"))

        currentUid = "uid-a"
        XCTAssertEqual(
            shared.translation(forTagId: "t1", name: "Essentials", language: "pt"), "Essenciais",
            "switching back must reload rather than serve the other user's in-memory copy")
    }

    func testWithoutAUidEveryReadMissesAndEveryWriteIsDropped() {
        let anonymous = TagTranslationCache(defaults: defaults, uidProvider: { nil })

        anonymous.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        anonymous.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertNil(anonymous.translation(forTagId: "t1", name: "Essentials", language: "pt"))
        XCTAssertNil(anonymous.override(forTagId: "t1", language: "pt"))
    }

    // MARK: - Generation

    func testTheGenerationAdvancesOnEveryMutation() {
        let start = cache.generation

        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        let afterStore = cache.generation
        XCTAssertGreaterThan(afterStore, start)

        cache.storeSourceLanguage("en", forTagId: "t1", name: "Essentials")
        let afterSource = cache.generation
        XCTAssertGreaterThan(afterSource, afterStore)

        cache.setOverride("Básicos", forTagId: "t1", language: "pt")
        let afterOverride = cache.generation
        XCTAssertGreaterThan(afterOverride, afterSource)

        cache.forget(tagId: "t1")
        XCTAssertGreaterThan(cache.generation, afterOverride)
    }

    func testTheGenerationDoesNotAdvanceOnAReadOrANoOpWrite() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")
        let settled = cache.generation

        _ = cache.override(forTagId: "t1", language: "pt")
        _ = cache.translation(forTagId: "t9", name: "Nothing", language: "pt")
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")  // same value
        cache.setOverride(nil, forTagId: "t2", language: "pt")  // was never set

        XCTAssertEqual(
            cache.generation, settled,
            "a memo keyed on this would be thrown away on every layout pass otherwise")
    }

    func testChangingUserAdvancesTheGeneration() {
        var currentUid = "uid-a"
        let shared = TagTranslationCache(defaults: defaults, uidProvider: { currentUid })
        let start = shared.generation

        currentUid = "uid-b"

        XCTAssertGreaterThan(
            shared.generation, start,
            "resolved names memoised for one account must not be served to the next")
    }

    // MARK: - Concurrency

    func testConcurrentWritesDoNotLoseAnEntry() {
        // Fails before the lock: every setter is a read-modify-write over a whole dictionary, and the
        // cache is reached from the @MainActor coordinator *and* from the non-isolated
        // AllocationTagService, so two writers could each flush a copy missing the other's entry.
        let count = 200
        DispatchQueue.concurrentPerform(iterations: count) { i in
            cache.store("v\(i)", forTagId: "t\(i)", name: "n\(i)", language: "pt")
        }

        for i in 0..<count {
            XCTAssertEqual(
                cache.translation(forTagId: "t\(i)", name: "n\(i)", language: "pt"), "v\(i)",
                "entry \(i) was lost to a concurrent write")
        }
    }

    func testConcurrentMixedWritesAcrossAllThreeMapsDoNotLoseAnEntry() {
        let count = 120
        DispatchQueue.concurrentPerform(iterations: count) { i in
            switch i % 3 {
            case 0: cache.store("v\(i)", forTagId: "t\(i)", name: "n\(i)", language: "pt")
            case 1: cache.storeSourceLanguage("en", forTagId: "t\(i)", name: "n\(i)")
            default: cache.setOverride("o\(i)", forTagId: "t\(i)", language: "pt")
            }
        }

        for i in 0..<count {
            switch i % 3 {
            case 0:
                XCTAssertEqual(cache.translation(forTagId: "t\(i)", name: "n\(i)", language: "pt"), "v\(i)")
            case 1:
                XCTAssertEqual(cache.sourceLanguage(forTagId: "t\(i)", name: "n\(i)"), "en")
            default:
                XCTAssertEqual(cache.override(forTagId: "t\(i)", language: "pt"), "o\(i)")
            }
        }
    }
}
