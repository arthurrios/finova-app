//
//  BudgetCardLayoutTests.swift
//  FinovaTests
//
//  The allocations card must keep its exact height and never let the projection blocks
//  collide with the donut. Both are load-bearing: `MonthCarouselCell` derives the allocations
//  table height from `budgetCard.bounds.height`, so any drift silently resizes the table.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class BudgetCardLayoutTests: XCTestCase {

    /// Narrowest card the app can render: 375pt screen (iPhone SE / 13 mini) minus the
    /// Metrics.spacing4 inset MonthCarouselCell applies on each side.
    private let narrowestCardWidth: CGFloat = 343
    private let widths: [CGFloat] = [343, 361, 370, 402]

    /// The required constraint chain inside BudgetCard:
    /// top 24 + header 36 + 12 + separator 1 + 20 + chart 170 + 24 + progressBar 8.
    private let expectedHeight: CGFloat = 295

    // MARK: - Fixtures

    private func makeAllocations() -> [BudgetAllocation] {
        [
            BudgetAllocation(
                dbId: 1, monthDate: 0, category: .meals,
                allocatedAmount: 60_000, usedAmount: 20_000),
            BudgetAllocation(
                dbId: 2, monthDate: 0, category: .savings,
                allocatedAmount: 40_000, usedAmount: 0),
        ]
    }

    /// Current month, so the card renders a projection.
    private var fixtureAnchor: Int { Int(Date().timeIntervalSince1970) }

    /// A nil `finalBalance` reproduces the pre-feature state, where the blocks stay hidden.
    ///
    /// `usedValue` and `budgetLimit` are parameters, not constants: they drive the spend gauge, so
    /// hardcoding `usedValue: 0` would leave every test exercising only the sub-0.75 colour branch.
    private func makeMonthData(
        _ finalBalance: Int?,
        anchor: Int,
        usedValue: Int = 100_000,
        budgetLimit: Int? = 350_000
    ) -> MonthBudgetCardType? {
        guard let finalBalance else { return nil }
        return MonthBudgetCardType(
            date: Date.fromMonthAnchor(anchor),
            month: "August",
            usedValue: usedValue,
            budgetLimit: budgetLimit,
            finalBalance: finalBalance,
            currentBalance: finalBalance,
            previousBalance: 0
        )
    }

    private func makeSummary(totalBudget: Int = 350_000) -> UnallocatedBudgetSummary {
        UnallocatedBudgetSummary(
            monthDate: 0,
            totalBudget: totalBudget,
            totalAllocated: 100_000,
            totalUsedInUnallocatedCategories: 15_000
        )
    }

    /// Builds a laid-out card at `width`. `finalBalance == nil` reproduces the pre-feature state,
    /// where both projection blocks stay hidden.
    ///
    /// The host pins three edges only — never a height — so the card's height stays its own
    /// fitting size, exactly as `MonthCarouselCell` leaves it.
    private func makeLaidOutCard(
        width: CGFloat,
        finalBalance: Int?,
        totalBudget: Int = 350_000,
        allocations: [BudgetAllocation]? = nil,
        contentSize: UIContentSizeCategory? = nil
    ) -> BudgetCard {
        let card = BudgetCard()
        card.translatesAutoresizingMaskIntoConstraints = false

        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        if let contentSize {
            host.traitOverrides.preferredContentSizeCategory = contentSize
        }

        card.configure(
            month: "August",
            year: "2026",
            allocations: allocations ?? makeAllocations(),
            unallocatedSummary: makeSummary(totalBudget: totalBudget),
            unallocatedSpending: [],
            monthAnchor: fixtureAnchor,
            monthData: makeMonthData(finalBalance, anchor: fixtureAnchor)
        )

        host.setNeedsLayout()
        host.layoutIfNeeded()
        return card
    }

    private func block(_ identifier: String, in card: BudgetCard) -> UIView? {
        card.subviews.first { $0.accessibilityIdentifier == identifier }
    }

    private func visibleProjectionBlocks(in card: BudgetCard) -> [UIView] {
        [BudgetCard.balanceBlockIdentifier, BudgetCard.projectionBlockIdentifier]
            .compactMap { block($0, in: card) }
            .filter { !$0.isHidden }
    }

    /// The chart container is the largest square subview; the donut is inscribed in it.
    private func chartContainer(in card: BudgetCard) -> UIView? {
        card.subviews
            .filter { $0.bounds.width > 1 && abs($0.bounds.width - $0.bounds.height) < 0.5 }
            .max { $0.bounds.width < $1.bounds.width }
    }

    // MARK: - Height invariance

    func testHeightIsUnchangedByTheProjectionBlocks() {
        for width in widths {
            let withProjection = makeLaidOutCard(width: width, finalBalance: 428_000)
            let withoutProjection = makeLaidOutCard(width: width, finalBalance: nil)

            XCTAssertFalse(
                visibleProjectionBlocks(in: withProjection).isEmpty,
                "fixture is not exercising the feature at width \(width)")

            XCTAssertEqual(
                withProjection.bounds.height, withoutProjection.bounds.height, accuracy: 0.5,
                "projection blocks changed the card height at width \(width)")
            XCTAssertEqual(
                withProjection.bounds.height, expectedHeight, accuracy: 0.5,
                "card height drifted from the required constraint chain at width \(width)")
        }
    }

    func testHeightSurvivesAccessibilityTextSizes() {
        // The blocks use UIFontMetrics-scaled fonts, so only their constant heightAnchors keep
        // the card from growing at large content sizes.
        let baseline = makeLaidOutCard(
            width: narrowestCardWidth, finalBalance: 428_000, contentSize: .large)
        let scaled = makeLaidOutCard(
            width: narrowestCardWidth, finalBalance: 428_000,
            contentSize: .accessibilityExtraExtraExtraLarge)

        XCTAssertFalse(visibleProjectionBlocks(in: scaled).isEmpty)
        XCTAssertEqual(
            scaled.bounds.height, baseline.bounds.height, accuracy: 0.5,
            "card height must not grow with Dynamic Type")
        XCTAssertEqual(scaled.bounds.height, expectedHeight, accuracy: 0.5)
    }

    func testOverCommittedStateDoesNotChangeHeight() {
        // Over-committed swaps colours and the delta string; neither may affect layout.
        let normal = makeLaidOutCard(width: narrowestCardWidth, finalBalance: 428_000)
        let overCommitted = makeLaidOutCard(width: narrowestCardWidth, finalBalance: 1_000)

        XCTAssertEqual(normal.bounds.height, overCommitted.bounds.height, accuracy: 0.5)
    }

    // MARK: - Donut clearance

    /// Shortest distance from `point` to `rect`; zero when the point is inside.
    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let nearestX = min(max(point.x, rect.minX), rect.maxX)
        let nearestY = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - nearestX, point.y - nearestY)
    }

    func testProjectionBlocksClearTheInscribedDonut() {
        for width in widths {
            let card = makeLaidOutCard(width: width, finalBalance: 428_000)

            guard let chart = chartContainer(in: card) else {
                XCTFail("could not locate the square chart container at width \(width)")
                continue
            }
            let center = CGPoint(x: chart.frame.midX, y: chart.frame.midY)
            let radius = chart.bounds.width / 2

            let blocks = visibleProjectionBlocks(in: card)
            XCTAssertEqual(blocks.count, 2, "expected two visible blocks at width \(width)")

            for projectionBlock in blocks {
                let name = projectionBlock.accessibilityIdentifier ?? "?"

                let clearance = distance(from: center, to: projectionBlock.frame) - radius
                XCTAssertGreaterThan(
                    clearance, 0,
                    "block \(name) at \(projectionBlock.frame) overlaps the donut (r=\(radius)) at \(width)")

                // The container clearing the donut is not enough: with .leading/.trailing stack
                // alignment, a label wider than its block expands past the block's bounds and
                // draws over the donut. Every descendant must clear it too.
                for child in projectionBlock.subviews {
                    let frameInCard = child.convert(child.bounds, to: card)
                    XCTAssertGreaterThan(
                        distance(from: center, to: frameInCard) - radius, 0,
                        """
                        child of \(name) at \(frameInCard) overlaps the donut (r=\(radius)) \
                        at card width \(width); text='\((child as? UILabel)?.text ?? "-")'
                        """)
                    XCTAssertTrue(
                        projectionBlock.bounds.insetBy(dx: -0.5, dy: -0.5).contains(child.frame),
                        """
                        child of \(name) escapes its block: child=\(child.frame) \
                        block=\(projectionBlock.bounds) at card width \(width); \
                        text='\((child as? UILabel)?.text ?? "-")'
                        """)
                }
            }
        }
    }

    func testLongCurrencyStringsDoNotEscapeTheirBlock() {
        // A large balance in pt-BR is the worst case for these narrow blocks.
        let card = makeLaidOutCard(
            width: narrowestCardWidth,
            finalBalance: 98_765_432,
            allocations: [
                BudgetAllocation(
                    dbId: 1, monthDate: 0, category: .meals,
                    allocatedAmount: 12_345_678, usedAmount: 1_234),
            ]
        )

        for projectionBlock in visibleProjectionBlocks(in: card) {
            for child in projectionBlock.subviews {
                XCTAssertTrue(
                    projectionBlock.bounds.insetBy(dx: -0.5, dy: -0.5).contains(child.frame),
                    """
                    long value escaped its block: child=\(child.frame) \
                    block=\(projectionBlock.bounds); text='\((child as? UILabel)?.text ?? "-")'
                    """)
            }
        }
    }

    func testProjectionBlocksStayInsideTheCard() {
        for width in widths {
            let card = makeLaidOutCard(width: width, finalBalance: 428_000)

            for projectionBlock in visibleProjectionBlocks(in: card) {
                let frame = projectionBlock.frame
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "escapes leading edge at \(width)")
                XCTAssertLessThanOrEqual(frame.maxX, width, "escapes trailing edge at \(width)")
                XCTAssertLessThanOrEqual(
                    frame.maxY, card.bounds.height, "escapes the card bottom at \(width)")
            }
        }
    }

    func testProjectionBlocksDoNotSwallowDonutTaps() {
        // The donut's own tap handling lives in the embedded chart; the blocks sit above it in
        // z-order, so they must stay transparent to touches.
        let card = makeLaidOutCard(width: narrowestCardWidth, finalBalance: 428_000)
        for projectionBlock in visibleProjectionBlocks(in: card) {
            XCTAssertFalse(
                projectionBlock.isUserInteractionEnabled,
                "\(projectionBlock.accessibilityIdentifier ?? "?") would intercept donut taps")
        }
    }

    // MARK: - Caption

    private func anchor(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return date.monthAnchor
    }

    private func leadingCaption(in card: BudgetCard) -> String? {
        guard let container = block(BudgetCard.balanceBlockIdentifier, in: card) else { return nil }
        return container.subviews.compactMap { ($0 as? UILabel)?.text }.first
    }

    /// Regression: `calendar.range(of:.day, in:.month)` returns `1..<32`, so reading `.upperBound`
    /// yields 32 and the caption claims a day the month does not have.
    func testLeadingCaptionNamesARealLastDayOfTheMonth() {
        let cases: [(year: Int, month: Int, expectedDay: Int)] = [
            (2026, 1, 31),   // 31-day
            (2026, 4, 30),   // 30-day
            (2026, 2, 28),   // February, common year
            (2024, 2, 29),   // February, leap year
        ]

        for probe in cases {
            let card = makeCard(anchor: anchor(year: probe.year, month: probe.month))
            guard let caption = leadingCaption(in: card) else {
                XCTFail("no caption for \(probe.year)-\(probe.month)")
                continue
            }
            XCTAssertTrue(
                caption.contains(String(probe.expectedDay)),
                "\(probe.year)-\(probe.month): caption '\(caption)' should name day \(probe.expectedDay)")
            XCTAssertFalse(
                caption.contains("32"),
                "\(probe.year)-\(probe.month): caption '\(caption)' names a day that does not exist")
        }
    }

    // MARK: - Footer

    /// The footer value labels are nested two levels down, so this searches the whole tree.
    private func label(_ identifier: String, in card: BudgetCard) -> UILabel? {
        func search(_ view: UIView) -> UILabel? {
            for child in view.subviews {
                if child.accessibilityIdentifier == identifier { return child as? UILabel }
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(card)
    }

    private func unallocatedValue(in card: BudgetCard) -> UILabel? {
        label(BudgetCard.unallocatedValueIdentifier, in: card)
    }

    private func usedValue(in card: BudgetCard) -> UILabel? {
        label(BudgetCard.usedValueIdentifier, in: card)
    }

    private func progressBar(in card: BudgetCard) -> RoundedProgressBar? {
        card.subviews.compactMap { $0 as? RoundedProgressBar }.first
    }

    private func makeCard(
        anchor: Int? = nil,
        allocations: [BudgetAllocation]? = nil,
        usedValue: Int = 100_000,
        budgetLimit: Int? = 350_000,
        finalBalance: Int? = 428_000,
        totalBudget: Int = 350_000,
        unallocatedSpending: Int = 0
    ) -> BudgetCard {
        let resolvedAnchor = anchor ?? fixtureAnchor
        let card = BudgetCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        let host = UIView(frame: CGRect(x: 0, y: 0, width: narrowestCardWidth, height: 1000))
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        card.configure(
            month: "August", year: "2026",
            allocations: allocations ?? makeAllocations(),
            unallocatedSummary: UnallocatedBudgetSummary(
                monthDate: 0, totalBudget: totalBudget, totalAllocated: 100_000,
                totalUsedInUnallocatedCategories: unallocatedSpending),
            unallocatedSpending: [],
            monthAnchor: resolvedAnchor,
            monthData: makeMonthData(
                finalBalance, anchor: resolvedAnchor,
                usedValue: usedValue, budgetLimit: budgetLimit)
        )
        host.layoutIfNeeded()
        return card
    }

    /// Footer-left is the cap not yet earmarked - a plan-structure figure. Deliberately not
    /// "left to spend": framing leftover budget as spendable nudges against the app's purpose.
    func testFooterLeftIsUnallocatedHeadroom() {
        let card = makeCard()  // summary: cap 350.000, allocated 100.000

        XCTAssertEqual(unallocatedValue(in: card)?.text, 250_000.currencyString)
        XCTAssertEqual(unallocatedValue(in: card)?.textColor, Colors.gray100)
    }

    /// The card's only warning that more has been earmarked than the cap allows.
    func testFooterLeftGoesAmberWhenOverAllocated() {
        let card = makeCard(totalBudget: 80_000)  // allocated 100.000 against an 80.000 cap

        XCTAssertEqual(unallocatedValue(in: card)?.text, "-" + 20_000.currencyString)
        XCTAssertEqual(unallocatedValue(in: card)?.textColor, Colors.warningAmber)
    }

    /// It comes from the summary, not the projection, so a missing ledger row must not blank it.
    func testFooterLeftStillRendersWhenTheLedgerRowIsMissing() {
        let card = makeCard(finalBalance: nil)

        XCTAssertTrue(visibleProjectionBlocks(in: card).isEmpty, "corner blocks must hide")
        XCTAssertEqual(unallocatedValue(in: card)?.text, 250_000.currencyString)
    }

    func testFooterRightIsTheMonthsTotalSpend() {
        let card = makeCard(usedValue: 259_600)

        XCTAssertEqual(usedValue(in: card)?.text, 259_600.currencyString)
    }

    func testBothFooterValuesMaskWithHideValues() {
        let previous = UserDefaultsManager.getHideValues()
        UserDefaultsManager.setHideValues(true)
        defer { UserDefaultsManager.setHideValues(previous) }

        let card = makeCard()
        XCTAssertEqual(unallocatedValue(in: card)?.text, "••••••")
        XCTAssertEqual(usedValue(in: card)?.text, "••••••")
    }

    // MARK: - Spend gauge

    /// The bar is a spend gauge, not allocation coverage: an identical bar sits in the identical
    /// position on the transaction face, and it means `usedValue / budgetLimit` there.
    func testGaugePlotsSpendAgainstTheBudgetLimit() {
        let card = makeCard(usedValue: 175_000, budgetLimit: 350_000)

        XCTAssertEqual(progressBar(in: card)?.progress ?? 0, 0.5, accuracy: 0.001)
    }

    func testGaugeStatusColoursMatchTheTransactionFace() {
        // Thresholds: > 1.0 red, >= 0.75 amber, else magenta. Boundaries included deliberately.
        let cases: [(used: Int, limit: Int, expected: UIColor, label: String)] = [
            (100_000, 350_000, Colors.mainMagenta, "29% — under"),
            (262_499, 350_000, Colors.mainMagenta, "just under 0.75"),
            (262_500, 350_000, Colors.warningAmber, "exactly 0.75"),
            (350_000, 350_000, Colors.warningAmber, "exactly 1.0 is not yet over"),
            (350_001, 350_000, Colors.mainRed, "just over 1.0"),
            (420_000, 350_000, Colors.mainRed, "120% — over"),
        ]

        for probe in cases {
            let card = makeCard(usedValue: probe.used, budgetLimit: probe.limit)
            XCTAssertEqual(
                progressBar(in: card)?.progressTintColor, probe.expected,
                "wrong colour for \(probe.label)")
        }
    }

    func testGaugeClampsFillButNotColourWhenOverBudget() {
        let card = makeCard(usedValue: 700_000, budgetLimit: 350_000)

        XCTAssertEqual(progressBar(in: card)?.progress ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(progressBar(in: card)?.progressTintColor, Colors.mainRed)
    }

    func testGaugeHidesWhenNoBudgetLimitIsKnown() {
        let card = makeCard(budgetLimit: nil)

        XCTAssertTrue(
            progressBar(in: card)?.isHidden ?? false,
            "no limit means no ratio to plot — mirrors the transaction face")
        XCTAssertEqual(
            card.bounds.height, expectedHeight, accuracy: 0.5,
            "hiding the bar must not collapse the height chain")
    }

    // MARK: - Budget margin

    private func marginLabel(in card: BudgetCard) -> UILabel? {
        label(BudgetCard.marginLabelIdentifier, in: card)
    }

    /// Row 4 is the net of the two quantities the bar compares. Never phrased as spendable money.
    ///
    /// Fixture: allocations leave 80.000 unspent, and the cap leaves 250.000 unallocated, so
    /// `totalSaved` is 330.000 before any off-plan spending.
    func testNetIsGreenWhenSavingAndRedWhenOverspending() {
        let saving = makeCard(unallocatedSpending: 0)
        XCTAssertEqual(marginLabel(in: saving)?.textColor, Colors.brightGreen)
        XCTAssertEqual(
            marginLabel(in: saving)?.text,
            "budget.net.saved.format".localized(330_000.compactCurrencyString))

        // 400.000 spent off-plan swamps the 330.000 saved.
        let overspending = makeCard(unallocatedSpending: 400_000)
        XCTAssertEqual(marginLabel(in: overspending)?.textColor, Colors.brightRed)
        XCTAssertEqual(
            marginLabel(in: overspending)?.text,
            "budget.net.overspent.format".localized(70_000.compactCurrencyString))
    }

    /// Funding an investments allocation debits the account, so it must *lower* the net - the money
    /// left, exactly like any other spend. Savings categories get no special treatment.
    func testFundingASavingsAllocationLowersTheNet() {
        let unfunded = makeCard(allocations: [
            BudgetAllocation(
                dbId: 1, monthDate: 0, category: .investments,
                allocatedAmount: 170_000, usedAmount: 0),
        ])
        let funded = makeCard(allocations: [
            BudgetAllocation(
                dbId: 1, monthDate: 0, category: .investments,
                allocatedAmount: 170_000, usedAmount: 170_000),
        ])

        // Unfunded: 170.000 still unspent, plus 250.000 headroom. Funded: headroom only.
        XCTAssertEqual(
            marginLabel(in: unfunded)?.text,
            "budget.net.saved.format".localized(420_000.compactCurrencyString))
        XCTAssertEqual(
            marginLabel(in: funded)?.text,
            "budget.net.saved.format".localized(250_000.compactCurrencyString))
    }

    func testNetMasksWithHideValues() {
        let previous = UserDefaultsManager.getHideValues()
        UserDefaultsManager.setHideValues(true)
        defer { UserDefaultsManager.setHideValues(previous) }

        XCTAssertEqual(marginLabel(in: makeCard())?.text, "••••••")
    }

    // MARK: - Past months

    func testClosedMonthKeepsBothBlocksButSwitchesWhatTheyReport() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let past = calendar.date(byAdding: .month, value: -3, to: Date())!

        let card = makeCard(anchor: past.monthAnchor)

        XCTAssertEqual(
            Set(visibleProjectionBlocks(in: card).compactMap { $0.accessibilityIdentifier }),
            [BudgetCard.balanceBlockIdentifier, BudgetCard.projectionBlockIdentifier],
            "a closed month still reports its outcome — both blocks stay")

        // Trailing caption switches from a forecast to a record.
        let caption = block(BudgetCard.projectionBlockIdentifier, in: card)?
            .subviews.compactMap { ($0 as? UILabel)?.text }.first
        XCTAssertEqual(caption, "budget.projection.budgetUsed.label".localized)

    }

    // MARK: - Visibility rules

    func testBlocksHideWhenNoBudgetIsSet() {
        // totalBudget == 0 drives the "define budget" empty state, which occupies the same
        // region as the projection blocks.
        let card = makeLaidOutCard(
            width: narrowestCardWidth, finalBalance: 428_000, totalBudget: 0, allocations: [])

        XCTAssertTrue(
            visibleProjectionBlocks(in: card).isEmpty,
            "projection blocks must hide behind the no-budget state")
    }

    func testBlocksHideWhenBalanceIsUnavailable() {
        let card = makeLaidOutCard(width: narrowestCardWidth, finalBalance: nil)

        XCTAssertTrue(
            visibleProjectionBlocks(in: card).isEmpty,
            "a nil balance must hide the blocks rather than render a zero")
    }
}
