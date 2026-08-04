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
        budgetLimit: Int? = 350_000
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
                totalUsedInUnallocatedCategories: 18_000
            ),
            unallocatedSpending: [],
            monthAnchor: monthAnchor,
            monthData: makeMonthData(
                finalBalance, anchor: monthAnchor,
                usedValue: usedValue, budgetLimit: budgetLimit)
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

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
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
