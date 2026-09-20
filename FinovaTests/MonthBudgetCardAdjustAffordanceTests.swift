//
//  MonthBudgetCardAdjustAffordanceTests.swift
//  FinovaTests
//
//  The balance adjustment used to be reachable only by a half-second press on the number, with
//  nothing on the card to suggest it existed. The pencil is what makes it findable, so its
//  presence is a behaviour worth pinning: the cases below are the ones where it must NOT appear,
//  and each of them was a way for the old long press to respond and then do nothing.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class MonthBudgetCardAdjustAffordanceTests: XCTestCase {

    /// Narrowest card the app renders: 375pt screen (iPhone SE / 13 mini) minus the
    /// `Metrics.spacing4` inset `MonthCarouselCell` applies on each side.
    private let widths: [CGFloat] = [343, 361, 370, 402]

    // MARK: - Fixtures

    private func makeMonthData(budgetLimit: Int? = 350_000) -> MonthBudgetCardType {
        MonthBudgetCardType(
            date: Date(),
            month: "August",
            usedValue: 100_000,
            budgetLimit: budgetLimit,
            finalBalance: 428_000,
            currentBalance: 428_000,
            previousBalance: 0
        )
    }

    private func makeGroup() -> BudgetGroup {
        BudgetGroup(
            name: "House",
            ownerId: "someone-else",
            ownerName: "Someone Else",
            ownerEmail: "someone@else.com")
    }

    /// Builds a laid-out card. The host pins three edges only — never a height — so the card keeps
    /// its own fitting size, exactly as `MonthCarouselCell` leaves it.
    private func makeLaidOutCard(
        width: CGFloat,
        budgetLimit: Int? = 350_000,
        context: DataContext = .personal,
        filterActive: Bool = false
    ) -> MonthBudgetCard {
        let card = MonthBudgetCard()
        card.translatesAutoresizingMaskIntoConstraints = false

        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        card.dataContext = context
        card.configure(data: makeMonthData(budgetLimit: budgetLimit))
        if filterActive {
            card.updateFilteredState(isActive: true, sum: 42_000)
        }

        host.setNeedsLayout()
        host.layoutIfNeeded()
        return card
    }

    /// Found by identifier rather than by type: the button is private, and the identifier is the
    /// contract the card publishes for exactly this.
    private func adjustButton(in card: MonthBudgetCard) -> UIView? {
        func walk(_ view: UIView) -> UIView? {
            if view.accessibilityIdentifier == MonthBudgetCard.adjustBalanceIdentifier {
                return view
            }
            for subview in view.subviews {
                if let found = walk(subview) { return found }
            }
            return nil
        }
        return walk(card)
    }

    // MARK: - Where the pencil belongs

    func testPencilIsShownOnAPersonalCardWithABudget() {
        for width in widths {
            let card = makeLaidOutCard(width: width)
            let button = adjustButton(in: card)

            XCTAssertNotNil(button, "no adjust affordance at width \(width)")
            XCTAssertFalse(button?.isHidden ?? true, "pencil hidden at width \(width)")
            XCTAssertGreaterThan(
                button?.bounds.width ?? 0, 0, "pencil collapsed at width \(width)")
        }
    }

    // MARK: - Where it must not appear

    /// A group member who is not the owner may not rewrite the balance. The version this replaces
    /// left the long press wired up for them: it fired the haptic and then returned silently,
    /// which reads as a broken card.
    ///
    /// `BudgetGroup.isOwner` resolves false with no signed-in Firebase user, which is the state
    /// under test — the assertion holds for the same reason it does for a real member.
    func testPencilIsCollapsedForAGroupMemberWhoIsNotTheOwner() {
        let card = makeLaidOutCard(width: 402, context: .group(makeGroup()))
        let button = adjustButton(in: card)

        XCTAssertTrue(button?.isHidden ?? false, "a non-owner was offered the adjustment")
        XCTAssertEqual(
            button?.bounds.width ?? -1, 0,
            "the collapsed pencil still holds width the balance could use")
    }

    /// Filtering swaps the balance for a filtered sum. Reconciling against that figure would write
    /// an offset derived from a number that is not a balance.
    func testPencilIsCollapsedWhileAFilterIsActive() {
        let card = makeLaidOutCard(width: 402, filterActive: true)
        let button = adjustButton(in: card)

        XCTAssertTrue(button?.isHidden ?? false, "the pencil survived a filter")
    }

    /// With no budget the balance row is replaced by the define-budget button, so there is nothing
    /// for the pencil to sit beside.
    func testPencilIsCollapsedWithNoBudgetDefined() {
        let card = makeLaidOutCard(width: 402, budgetLimit: nil)
        let button = adjustButton(in: card)

        XCTAssertTrue(button?.isHidden ?? false, "the pencil survived a card with no budget")
    }

    // MARK: - Layout

    /// The pencil sits between the balance and the eye. If the balance can reach under it, the two
    /// overlap on the narrow widths first — which is where this would ship unnoticed.
    func testBalanceNeverOverlapsThePencil() {
        for width in widths {
            let card = makeLaidOutCard(width: width)
            guard let button = adjustButton(in: card), let row = button.superview else {
                XCTFail("no adjust affordance at width \(width)")
                continue
            }

            // Everything left of the pencil is a balance renderer: the plain masked label and the
            // SwiftUI host share the slot. The eye sits to its right and is not in scope.
            let balanceViews = row.subviews.filter {
                $0 !== button && !$0.isHidden && $0.frame.minX < button.frame.minX
            }
            for view in balanceViews where view.bounds.width > 0 {
                XCTAssertLessThanOrEqual(
                    view.frame.maxX, button.frame.minX + 0.5,
                    "balance runs under the pencil at width \(width)")
            }
        }
    }
}
