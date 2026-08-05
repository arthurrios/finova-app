//
//  AllocationTagDisplayNameTests.swift
//  FinovaTests
//
//  Which of a tag's several possible names wins on screen, and when the pass considers one settled.
//

import Foundation
import XCTest

@testable import Finova

final class AllocationTagDisplayNameTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cache: TagTranslationCache!

    private let pt = Locale.Language(identifier: "pt-BR")
    private let en = Locale.Language(identifier: "en-US")

    override func setUp() {
        super.setUp()
        suiteName = "AllocationTagDisplayNameTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cache = TagTranslationCache(defaults: defaults, uidProvider: { "uid" })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        cache = nil
        super.tearDown()
    }

    private func tag(_ name: String, id: String = "t1") -> AllocationTag {
        AllocationTag(id: id, name: name, colorIndex: 0, iconAssetName: nil, sortOrder: 0)
    }

    private func resolve(_ tag: AllocationTag, _ language: Locale.Language, enabled: Bool = true) -> String {
        tag.displayName(in: language, cache: cache, isEnabled: enabled)
    }

    // MARK: - Machine tiers

    func testFallsBackToTheTypedNameWithNothingCached() {
        XCTAssertEqual(resolve(tag("Essentials"), pt), "Essentials")
    }

    func testACachedTranslationIsUsed() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertEqual(resolve(tag("Essentials"), pt), "Essenciais")
    }

    func testAnExactRegionMatchWins() {
        cache.store("Essenciais BR", forTagId: "t1", name: "Essentials", language: "pt-PT")
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertEqual(
            resolve(tag("Essentials"), Locale.Language(identifier: "pt-PT")), "Essenciais BR")
    }

    func testALanguageCodeEntryServesAnUnmatchedRegion() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertEqual(
            resolve(tag("Essentials"), Locale.Language(identifier: "pt-PT")), "Essenciais",
            "a cached pt is a better answer for a pt-PT phone than the English name")
    }

    func testATagAuthoredInTheTargetLanguageKeepsItsTypedName() {
        cache.storeSourceLanguage("pt-BR", forTagId: "t1", name: "Moradia")
        // A stale entry from when the phone was in another language must not resurface.
        cache.store("Housing", forTagId: "t1", name: "Moradia", language: "pt")

        XCTAssertEqual(resolve(tag("Moradia"), pt), "Moradia")
    }

    func testDisablingTranslationShowsTheTypedName() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertEqual(resolve(tag("Essentials"), pt, enabled: false), "Essentials")
    }

    // MARK: - Override tier

    func testAnOverrideBeatsAMachineTranslation() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertEqual(resolve(tag("Essentials"), pt), "Básicos")
    }

    func testAnOverrideSurvivesTurningTranslationOff() {
        // The switch means "don't let a machine rename my tags". Discarding a name the user typed by
        // hand is a different thing, and not what they asked for.
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertEqual(resolve(tag("Essentials"), pt, enabled: false), "Básicos")
    }

    func testAnOverrideSurvivesARename() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertEqual(
            resolve(tag("Essential expenses"), pt), "Básicos",
            "the override is attached to the tag, not to the name it had when it was typed")
    }

    func testClearingAnOverrideFallsBackToTheTranslation() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")
        cache.setOverride(nil, forTagId: "t1", language: "pt")

        XCTAssertEqual(resolve(tag("Essentials"), pt), "Essenciais")
    }

    func testAnOverrideIsScopedToItsLanguage() {
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertEqual(resolve(tag("Essentials"), en), "Essentials")
    }

    // MARK: - needsTranslation

    func testATagWithNothingCachedNeedsTranslation() {
        XCTAssertTrue(tag("Essentials").needsTranslation(for: pt, cache: cache))
    }

    func testATagWithACachedTranslationDoesNot() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertFalse(tag("Essentials").needsTranslation(for: pt, cache: cache))
    }

    func testATagAuthoredInTheTargetLanguageDoesNot() {
        cache.storeSourceLanguage("pt-BR", forTagId: "t1", name: "Moradia")

        XCTAssertFalse(tag("Moradia").needsTranslation(for: pt, cache: cache))
    }

    func testRenamingRequeuesATag() {
        cache.store("Essenciais", forTagId: "t1", name: "Essentials", language: "pt")

        XCTAssertTrue(
            tag("Essential expenses").needsTranslation(for: pt, cache: cache),
            "the translation key includes the name, so a rename is a fresh question")
    }

    func testNeedsTranslationIgnoresAnOverride() {
        // Skipping overridden tags is the pass's decision to make explicitly. Burying it here would
        // conflate "the user has spoken" with "a translation exists", and those want different
        // handling the moment the override is cleared.
        cache.setOverride("Básicos", forTagId: "t1", language: "pt")

        XCTAssertTrue(tag("Essentials").needsTranslation(for: pt, cache: cache))
    }

    // MARK: - Memo

    /// The memo only engages on the shared cache, so these drive that instance directly. The tests
    /// above deliberately use an injected cache and bypass it.
    func testTheMemoReturnsAFreshAnswerAfterAStore() {
        let resolver = TagDisplayNameResolver.shared
        let shared = TagTranslationCache.shared
        let id = "memo-\(UUID().uuidString)"
        defer { shared.forget(tagId: id) }

        let first = resolver.displayName(
            id: id, name: "Essentials", in: pt, cache: shared, isEnabled: true)
        XCTAssertEqual(first, "Essentials")

        shared.store("Essenciais", forTagId: id, name: "Essentials", language: "pt")

        XCTAssertEqual(
            resolver.displayName(id: id, name: "Essentials", in: pt, cache: shared, isEnabled: true),
            "Essenciais",
            "a store bumps the generation, which must discard the memo")
    }

    func testTheMemoDoesNotServeOneLanguagesAnswerToAnother() {
        let resolver = TagDisplayNameResolver.shared
        let shared = TagTranslationCache.shared
        let id = "memo-\(UUID().uuidString)"
        defer { shared.forget(tagId: id) }

        shared.store("Essenciais", forTagId: id, name: "Essentials", language: "pt")

        XCTAssertEqual(
            resolver.displayName(id: id, name: "Essentials", in: pt, cache: shared, isEnabled: true),
            "Essenciais")
        XCTAssertEqual(
            resolver.displayName(id: id, name: "Essentials", in: en, cache: shared, isEnabled: true),
            "Essentials")
    }

    func testTheMemoDoesNotServeAnEnabledAnswerWhenDisabled() {
        let resolver = TagDisplayNameResolver.shared
        let shared = TagTranslationCache.shared
        let id = "memo-\(UUID().uuidString)"
        defer { shared.forget(tagId: id) }

        shared.store("Essenciais", forTagId: id, name: "Essentials", language: "pt")

        XCTAssertEqual(
            resolver.displayName(id: id, name: "Essentials", in: pt, cache: shared, isEnabled: true),
            "Essenciais")
        XCTAssertEqual(
            resolver.displayName(id: id, name: "Essentials", in: pt, cache: shared, isEnabled: false),
            "Essentials")
    }

    func testConcurrentResolutionIsSafeAndConsistent() {
        let resolver = TagDisplayNameResolver.shared
        let shared = TagTranslationCache.shared
        let id = "memo-\(UUID().uuidString)"
        defer { shared.forget(tagId: id) }
        shared.store("Essenciais", forTagId: id, name: "Essentials", language: "pt")

        let results = NSMutableArray()
        let guard_ = NSLock()
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let name = resolver.displayName(
                id: id, name: "Essentials", in: pt, cache: shared, isEnabled: true)
            guard_.lock()
            results.add(name)
            guard_.unlock()
        }

        XCTAssertEqual(Set(results.map { $0 as! String }), ["Essenciais"])
    }
}
