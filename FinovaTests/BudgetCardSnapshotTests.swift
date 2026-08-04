//
//  BudgetCardSnapshotTests.swift
//  FinovaTests
//
//  Renders the allocations card to PNGs so the projection blocks can be reviewed without
//  signing in. Not an assertion suite - it writes attachments and a file per state.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class BudgetCardSnapshotTests: XCTestCase {

    private let cardWidth: CGFloat = 343  // 375pt device: the tightest layout

    private func allocations() -> [BudgetAllocation] {
        [
            BudgetAllocation(
                dbId: 1, monthDate: 0, category: .meals,
                allocatedAmount: 90_000, usedAmount: 52_000),
            BudgetAllocation(
                dbId: 2, monthDate: 0, category: .utilities,
                allocatedAmount: 60_000, usedAmount: 60_000),
            BudgetAllocation(
                dbId: 3, monthDate: 0, category: .transportation,
                allocatedAmount: 45_000, usedAmount: 12_000),
            BudgetAllocation(
                dbId: 4, monthDate: 0, category: .savings,
                allocatedAmount: 48_000, usedAmount: 0),
        ]
    }

    private func makeMonthData(
        _ finalBalance: Int?,
        anchor: Int,
        usedValue: Int,
        budgetLimit: Int?
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

    private func render(
        name: String,
        finalBalance: Int?,
        monthAnchor: Int,
        allocations: [BudgetAllocation],
        usedValue: Int = 150_000,
        budgetLimit: Int? = 350_000,
        unallocatedSpending: Int = 18_000,
        tagBreakdown: AllocationTagBreakdown = .empty
    ) {
        let card = BudgetCard()
        card.translatesAutoresizingMaskIntoConstraints = false

        // A real window is required: drawHierarchy / layer rendering of a detached view produces
        // offset or stale output, which silently misrepresents the layout being reviewed.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: cardWidth, height: 600))
        window.backgroundColor = Colors.gray700
        window.isHidden = false
        window.makeKeyAndVisible()

        let host = UIView(frame: window.bounds)
        host.backgroundColor = Colors.gray700
        window.addSubview(host)
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        card.configure(
            month: "August",
            year: "2026",
            allocations: allocations,
            unallocatedSummary: UnallocatedBudgetSummary(
                monthDate: 0,
                totalBudget: 350_000,
                totalAllocated: 243_000,
                totalUsedInUnallocatedCategories: unallocatedSpending
            ),
            unallocatedSpending: [],
            monthAnchor: monthAnchor,
            monthData: makeMonthData(
                finalBalance, anchor: monthAnchor,
                usedValue: usedValue, budgetLimit: budgetLimit),
            tagBreakdown: tagBreakdown
        )

        window.setNeedsLayout()
        window.layoutIfNeeded()
        // Let the embedded SwiftUI donut commit a frame before capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let size = CGSize(width: cardWidth, height: card.bounds.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            card.layer.render(in: context.cgContext)
        }

        guard let data = image.pngData() else {
            XCTFail("could not encode \(name)")
            return
        }

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // A host directory when one is given: tests run on a throwaway simulator clone whose sandbox
        // goes away with it, so NSTemporaryDirectory() output is gone before it can be looked at.
        let directory =
            ProcessInfo.processInfo.environment["FINOVA_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("budgetcard-\(name).png")
        do {
            try data.write(to: url)
            print("SNAPSHOT_WRITTEN \(name) -> \(url.path) (\(data.count) bytes)")
        } catch {
            XCTFail("could not write \(name): \(error)")
        }
    }

    private var currentMonthAnchor: Int {
        Int(Date().timeIntervalSince1970)
    }

    private var futureMonthAnchor: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let future = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        return Int(future.timeIntervalSince1970)
    }

    private var pastMonthAnchor: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let past = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        return Int(past.timeIntervalSince1970)
    }

    func testRenderProjectionStates() {
        // Healthy forecast: balance comfortably covers the plan; gauge in the magenta band.
        render(
            name: "projected", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations())

        // Over-committed: the plan promises more than the balance holds.
        render(
            name: "overcommitted", finalBalance: 90_000,
            monthAnchor: currentMonthAnchor, allocations: allocations())

        // Closed month: no projection, so the trailing block is gone and the footer says "Unused".
        render(
            name: "past-month", finalBalance: 512_000,
            monthAnchor: pastMonthAnchor, allocations: allocations())

        // Future month with an untouched plan: must report adherence, not a saved amount.
        render(
            name: "future-untouched", finalBalance: 429_000,
            monthAnchor: futureMonthAnchor,
            allocations: [
                BudgetAllocation(dbId: 1, monthDate: 0, category: .market,
                                 allocatedAmount: 200_000, usedAmount: 0),
                BudgetAllocation(dbId: 2, monthDate: 0, category: .meals,
                                 allocatedAmount: 150_000, usedAmount: 0),
            ],
            usedValue: 0, unallocatedSpending: 0)

        // Balance unavailable: corner blocks absent, footer still populated.
        render(
            name: "no-balance", finalBalance: nil,
            monthAnchor: currentMonthAnchor, allocations: allocations())
    }

    /// The spend gauge's three colour bands, plus the no-limit case that hides it.
    func testRenderSpendGaugeBands() {
        render(
            name: "gauge-amber", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations(),
            usedValue: 300_000)

        render(
            name: "gauge-red", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations(),
            usedValue: 400_000)

        render(
            name: "gauge-absent", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations(),
            usedValue: 300_000, budgetLimit: nil)
    }

    // MARK: - Tag ring

    /// Two tags over the four allocations, plus one category left untagged.
    private func twoTagBreakdown() -> AllocationTagBreakdown {
        let essentials = AllocationTag(
            id: "t-essentials", name: "Essentials", colorIndex: 5, sortOrder: 0)
        let wealth = AllocationTag(id: "t-wealth", name: "Wealth", colorIndex: 2, sortOrder: 1)

        return AllocationTagBreakdown(
            allocations: allocations(),
            unallocatedSpending: [],
            unallocatedHeadroom: 107_000,
            totalBudget: 350_000,
            tags: [essentials, wealth],
            categoryTagIds: [
                TransactionCategory.meals.key: essentials.id,
                TransactionCategory.utilities.key: essentials.id,
                TransactionCategory.savings.key: wealth.id,
                // .transportation deliberately left untagged
            ])
    }

    /// `tags-none` must be pixel-identical to `projected`: with no tags the category ring keeps its
    /// original 85...55pt geometry and no ring is drawn.
    ///
    /// That equality covers geometry, not slice order. `AllocationTagBreakdown` sorts allocations
    /// amount-desc, and this fixture deliberately passes them unsorted (transportation before savings),
    /// so these renders differ from a pre-tag build's - by exactly that reordering. See the note on
    /// `AllocationTagBreakdown.sortedSegments`.
    func testRenderTagRingStates() {
        render(
            name: "tags-none", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations())

        render(
            name: "tags-two", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations(),
            tagBreakdown: twoTagBreakdown())

        // One tag covering everything: the ring should be a single near-complete arc.
        let all = AllocationTag(id: "t-all", name: "Everything", colorIndex: 3, sortOrder: 0)
        render(
            name: "tags-one", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations(),
            tagBreakdown: AllocationTagBreakdown(
                allocations: allocations(),
                unallocatedSpending: [],
                unallocatedHeadroom: 107_000,
                totalBudget: 350_000,
                tags: [all],
                categoryTagIds: Dictionary(
                    uniqueKeysWithValues: allocations().map { ($0.category.key, all.id) })))
    }

    func testRenderHiddenValuesState() {
        let previous = UserDefaultsManager.getHideValues()
        UserDefaultsManager.setHideValues(true)
        defer { UserDefaultsManager.setHideValues(previous) }

        // Both amounts and the delta must mask; the bar shows proportions, so it stays.
        render(
            name: "hidden", finalBalance: 428_000,
            monthAnchor: currentMonthAnchor, allocations: allocations())
    }
}
