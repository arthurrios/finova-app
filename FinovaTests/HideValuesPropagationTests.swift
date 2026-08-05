//
//  HideValuesPropagationTests.swift
//  FinovaTests
//
//  Regressions for the four ways the hide-values state used to get lost. Each test names the
//  specific defect it guards, because none of them are obvious from the assertion alone.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class HideValuesPropagationTests: XCTestCase {

    private var previous: Bool = false

    override func setUp() {
        super.setUp()
        previous = UserDefaultsManager.getHideValues()
        UserDefaultsManager.setHideValues(false)
    }

    override func tearDown() {
        UserDefaultsManager.setHideValues(previous)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeMonthData(
        usedValue: Int = 100_000,
        budgetLimit: Int? = 350_000
    ) -> MonthBudgetCardType {
        MonthBudgetCardType(
            date: Date(),
            month: "August",
            usedValue: usedValue,
            budgetLimit: budgetLimit,
            finalBalance: 250_000,
            currentBalance: 250_000,
            previousBalance: 0
        )
    }

    private func hideValuesButtons(in view: UIView) -> [HideValuesButton] {
        var found: [HideValuesButton] = []
        if let button = view as? HideValuesButton { found.append(button) }
        view.subviews.forEach { found.append(contentsOf: hideValuesButtons(in: $0)) }
        return found
    }

    /// The button the user can actually reach: the other one is `isHidden`.
    private func visibleHideValuesButton(in view: UIView) -> HideValuesButton? {
        hideValuesButtons(in: view).first { !$0.isHidden }
    }

    // MARK: - Defect: the toggle vanished after a filter was cleared

    /// `updateFilteredState(isActive: true)` hid the balance-row toggle, and the `isActive: false`
    /// branch had no counterpart to show it again — so filtering a month left the eye button gone
    /// until a month swipe reconfigured the card. This is the "loses reference" symptom.
    func testToggleSurvivesAFilterRoundTrip() {
        let card = MonthBudgetCard()
        card.configure(data: makeMonthData())

        XCTAssertNotNil(visibleHideValuesButton(in: card), "precondition: a toggle is reachable")

        card.updateFilteredState(isActive: true, sum: 42_000)
        card.clearFilteredState()

        XCTAssertNotNil(
            visibleHideValuesButton(in: card),
            "the eye button must come back when the filter is cleared")
    }

    /// While filtering, the balance is replaced by a filtered sum. The toggle moves to the header
    /// rather than disappearing, so there is always something to tap.
    func testAToggleStaysReachableWhileFiltering() {
        let card = MonthBudgetCard()
        card.configure(data: makeMonthData())

        card.updateFilteredState(isActive: true, sum: 42_000)

        XCTAssertNotNil(visibleHideValuesButton(in: card))
    }

    /// With no budget set there is no balance row, so the header toggle is the reachable one.
    func testExactlyOneToggleIsVisibleInEitherBudgetState() {
        let withBudget = MonthBudgetCard()
        withBudget.configure(data: makeMonthData(budgetLimit: 350_000))
        XCTAssertEqual(hideValuesButtons(in: withBudget).filter { !$0.isHidden }.count, 1)

        let withoutBudget = MonthBudgetCard()
        withoutBudget.configure(data: makeMonthData(budgetLimit: nil))
        XCTAssertEqual(hideValuesButtons(in: withoutBudget).filter { !$0.isHidden }.count, 1)
    }

    // MARK: - Defect: crash when tapped before configure

    /// `toggleHideValues` force-unwrapped `currentMonthData`, so tapping the eye on a card that had
    /// not been configured yet trapped.
    func testTappingTheToggleBeforeConfigureDoesNotCrash() {
        let card = MonthBudgetCard()
        let button = hideValuesButtons(in: card).first
        XCTAssertNotNil(button)

        button?.sendActions(for: .touchUpInside)

        XCTAssertTrue(ValueVisibilityStore.shared.isHidden, "the tap still records the intent")
    }

    // MARK: - Defect: only visible carousel cells were updated

    /// The old fan-out walked `monthCarousel.visibleCells`, so an off-screen or recycled card came
    /// back showing real amounts. Nothing here is in a window or a carousel.
    func testAnOffScreenCardMasksOnAStoreChange() {
        let card = MonthBudgetCard()
        card.configure(data: makeMonthData(usedValue: 259_600))
        XCTAssertNil(card.window, "precondition: never added to a window")

        ValueVisibilityStore.shared.setHidden(true)

        XCTAssertEqual(
            label(withIdentifier: MonthBudgetCard.usedValueIdentifier, in: card)?.text,
            ValueMask.placeholder)
    }

    /// A card configured while the flag is already set must render masked on its first pass, with
    /// no toggle and no notification involved. This is what makes cell reuse safe by construction.
    func testACardConfiguredWhileHiddenRendersMasked() {
        ValueVisibilityStore.shared.setHidden(true)

        let card = MonthBudgetCard()
        card.configure(data: makeMonthData(usedValue: 259_600))

        XCTAssertEqual(
            label(withIdentifier: MonthBudgetCard.usedValueIdentifier, in: card)?.text,
            ValueMask.placeholder)
    }

    // MARK: - Allocation rows

    /// The user's explicit ask: the amounts under each allocation row were never masked.
    func testAllocationCellMasksBothAmountLabels() {
        let allocation = BudgetAllocation(
            dbId: 1, monthDate: 0, category: .meals,
            allocatedAmount: 60_000, usedAmount: 20_000)

        let visible = AllocationCell(style: .default, reuseIdentifier: nil)
        visible.configure(with: allocation)
        let usageVisible = label(withIdentifier: "allocationCell.usage", in: visible)?.text
        XCTAssertNotNil(usageVisible)
        XCTAssertFalse(usageVisible!.contains("•"))

        ValueVisibilityStore.shared.setHidden(true)

        let hidden = AllocationCell(style: .default, reuseIdentifier: nil)
        hidden.configure(with: allocation)

        // One placeholder for the ratio line, not "•••••• / ••••••".
        XCTAssertEqual(
            label(withIdentifier: "allocationCell.usage", in: hidden)?.text,
            ValueMask.placeholder)
        XCTAssertEqual(
            label(withIdentifier: "allocationCell.remaining", in: hidden)?.text,
            ValueMask.placeholder)
    }

    // MARK: - Button appearance

    /// The icon shows the action, not the state: while values are hidden the open eye offers
    /// "reveal". The accessibility label must say which.
    func testButtonAccessibilityLabelFollowsTheStore() {
        let button = HideValuesButton(style: .onHeader)
        XCTAssertEqual(button.accessibilityLabel, "hideValues.a11y.hide".localized)

        ValueVisibilityStore.shared.setHidden(true)

        XCTAssertEqual(button.accessibilityLabel, "hideValues.a11y.show".localized)
    }

    /// A button created after the flag was already set must start in the right state — it cannot
    /// rely on having received a notification.
    func testButtonCreatedWhileHiddenStartsCorrect() {
        ValueVisibilityStore.shared.setHidden(true)

        let button = HideValuesButton(style: .onCard)

        XCTAssertEqual(button.accessibilityLabel, "hideValues.a11y.show".localized)
    }

    // MARK: - Hit testing

    /// `sendActions(for:)` bypasses hit-testing, so it cannot catch a subview stealing the touch —
    /// which is exactly what the header style's decorative glass layer did. Both styles must resolve
    /// a tap at their centre to the button itself.
    func testBothStylesReceiveTapsAtTheirCentre() {
        for style in [HideValuesButton.Style.onCard, .onHeader] {
            let button = HideValuesButton(style: style)
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            host.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            ])
            host.layoutIfNeeded()

            let hit = host.hitTest(button.center, with: nil)

            XCTAssertTrue(
                hit === button,
                "\(style) must receive its own taps, got \(String(describing: hit))")
        }
    }

    /// End-to-end through the real gesture path: a tap on a header-style button flips the store.
    func testTappingAHeaderStyleButtonFlipsTheStore() {
        let button = HideValuesButton(style: .onHeader)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        host.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
        host.layoutIfNeeded()

        XCTAssertTrue(host.hitTest(button.center, with: nil) === button)
        button.sendActions(for: .touchUpInside)

        XCTAssertTrue(ValueVisibilityStore.shared.isHidden)
    }

    // MARK: - Helpers

    private func label(withIdentifier identifier: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.accessibilityIdentifier == identifier {
            return label
        }
        for subview in view.subviews {
            if let found = label(withIdentifier: identifier, in: subview) { return found }
        }
        return nil
    }
}
