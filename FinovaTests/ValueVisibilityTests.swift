//
//  ValueVisibilityTests.swift
//  FinovaTests
//
//  The hide-values flag used to live in four places at once and drift between them. These tests
//  pin down the properties that make one owner work: a single writer, no redundant broadcasts,
//  observations that die with their owner, and a formatter that masking cannot leak into.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class ValueVisibilityTests: XCTestCase {

    private var previous: Bool = false

    override func setUp() {
        super.setUp()
        // Same save/restore discipline as BudgetCardLayoutTests: the store reads through to the
        // real UserDefaults, so leaving it flipped would leak into other suites.
        previous = UserDefaultsManager.getHideValues()
        UserDefaultsManager.setHideValues(false)
    }

    override func tearDown() {
        UserDefaultsManager.setHideValues(previous)
        super.tearDown()
    }

    // MARK: - Store

    func testSetHiddenPersistsAndBroadcastsOnce() {
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: .valueVisibilityDidChange, object: nil, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        ValueVisibilityStore.shared.setHidden(true)

        XCTAssertTrue(ValueVisibilityStore.shared.isHidden)
        XCTAssertTrue(UserDefaultsManager.getHideValues(), "must persist, not just broadcast")
        XCTAssertEqual(posts, 1)
    }

    /// A double-tap must not cause two table reloads.
    func testSettingTheSameValueBroadcastsNothing() {
        ValueVisibilityStore.shared.setHidden(true)

        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: .valueVisibilityDidChange, object: nil, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        ValueVisibilityStore.shared.setHidden(true)

        XCTAssertEqual(posts, 0)
    }

    func testToggleFlipsTheStoredValue() {
        XCTAssertFalse(ValueVisibilityStore.shared.isHidden)
        ValueVisibilityStore.shared.toggle()
        XCTAssertTrue(ValueVisibilityStore.shared.isHidden)
        ValueVisibilityStore.shared.toggle()
        XCTAssertFalse(ValueVisibilityStore.shared.isHidden)
    }

    func testObservationReceivesTheCurrentValue() {
        var received: [Bool] = []
        let observation = ValueVisibilityStore.shared.observe { received.append($0) }

        ValueVisibilityStore.shared.setHidden(true)
        ValueVisibilityStore.shared.setHidden(false)

        XCTAssertEqual(received, [true, false])
        XCTAssertNotNil(observation, "held so the token is not deallocated mid-test")
    }

    /// The regression for the two views that registered a `NotificationCenter` observer and never
    /// removed it. Releasing the token must be enough.
    func testReleasedObservationStopsFiring() {
        var fired = 0
        var observation: ValueVisibilityObservation? =
            ValueVisibilityStore.shared.observe { _ in fired += 1 }

        ValueVisibilityStore.shared.setHidden(true)
        XCTAssertEqual(fired, 1)

        observation = nil
        ValueVisibilityStore.shared.setHidden(false)

        XCTAssertEqual(fired, 1, "a released observation must not keep receiving")
        XCTAssertNil(observation)
    }

    // MARK: - Mask

    func testUnmaskedHelpersMatchTheUnderlyingFormatter() {
        XCTAssertEqual(120_00.maskedCurrencyString(hidden: false), 120_00.currencyString)
        XCTAssertEqual(
            1_500_00.maskedCompactCurrencyString(hidden: false), 1_500_00.compactCurrencyString)
        XCTAssertEqual("R$ 1,00".maskedIfHidden(false), "R$ 1,00")
    }

    func testMaskedHelpersAllUseTheOnePlaceholder() {
        XCTAssertEqual(120_00.maskedCurrencyString(hidden: true), ValueMask.placeholder)
        XCTAssertEqual(120_00.maskedCompactCurrencyString(hidden: true), ValueMask.placeholder)
        XCTAssertEqual(120_00.maskedSignedCompactString(hidden: true), ValueMask.placeholder)
        XCTAssertEqual((-120_00).maskedSignedCompactString(hidden: true), ValueMask.placeholder)
        XCTAssertEqual("R$ 1,00".maskedIfHidden(true), ValueMask.placeholder)
    }

    /// A masked negative must not keep its sign — a red `-••••••` still reports "over budget".
    func testMaskedSignedCompactDropsTheSign() {
        XCTAssertFalse((-120_00).maskedSignedCompactString(hidden: true).hasPrefix("-"))
    }

    func testSignedCompactPrefixesNegativesWhenVisible() {
        let negative = (-1_500_00).maskedSignedCompactString(hidden: false)
        XCTAssertTrue(negative.hasPrefix("-"), "got \(negative)")
        XCTAssertFalse(negative.hasPrefix("--"), "must not double the minus")
    }

    /// The masked attributed string must be one uniform font run: there is no currency symbol in
    /// the placeholder, so a smaller `symbolFont` on part of the bullets would look like a bug.
    func testMaskedAttributedStringIsOneUniformFontRun() {
        let attributed = 120_00.maskedCurrencyAttributedString(
            symbolFont: Fonts.textXS.font, font: Fonts.titleMD, hidden: true)

        XCTAssertEqual(attributed.string, ValueMask.placeholder)

        var runs = 0
        attributed.enumerateAttribute(
            .font, in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            runs += 1
            XCTAssertEqual(value as? UIFont, Fonts.titleMD.font)
            XCTAssertEqual(range.length, attributed.length)
        }
        XCTAssertEqual(runs, 1)
    }

    /// The reason masking is a separate layer rather than something `CurrencyUtils` knows about:
    /// `Int.currencyString` also builds push-notification bodies and delete-confirmation alerts,
    /// which must keep showing real numbers while values are hidden on screen.
    func testCurrencyStringIsUnaffectedByTheStore() {
        let visible = 120_00.currencyString

        ValueVisibilityStore.shared.setHidden(true)

        XCTAssertEqual(120_00.currencyString, visible)
        XCTAssertEqual(120_00.compactCurrencyString, 120_00.compactCurrencyString)
        XCTAssertFalse(120_00.currencyString.contains("•"))
    }

    func testIsActiveTracksTheStore() {
        XCTAssertFalse(ValueMask.isActive)
        ValueVisibilityStore.shared.setHidden(true)
        XCTAssertTrue(ValueMask.isActive)
    }
}
