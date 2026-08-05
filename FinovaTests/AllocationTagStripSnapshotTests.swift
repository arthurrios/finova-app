//
//  AllocationTagStripSnapshotTests.swift
//  FinovaTests
//
//  Renders the chip strip in place between the allocations header and the table, so the three-part
//  rounded card, the borders and the filtered list can be reviewed without signing in.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class AllocationTagStripSnapshotTests: XCTestCase {

    private let width: CGFloat = 343  // 375pt device: the tightest layout

    private let essentials = AllocationTag(
        id: "t-essentials", name: "Essentials", colorIndex: 5, sortOrder: 0)
    private let wealth = AllocationTag(id: "t-wealth", name: "Wealth", colorIndex: 2, sortOrder: 1)
    private let lifestyle = AllocationTag(
        id: "t-lifestyle", name: "Lifestyle", colorIndex: 3, sortOrder: 2)

    private func allocations() -> [BudgetAllocation] {
        [
            BudgetAllocation(
                dbId: 1, monthDate: 0, category: .investments,
                allocatedAmount: 560_000, usedAmount: 560_000),
            BudgetAllocation(
                dbId: 2, monthDate: 0, category: .homeMaintenance,
                allocatedAmount: 200_000, usedAmount: 200_000),
            BudgetAllocation(
                dbId: 3, monthDate: 0, category: .groceries,
                allocatedAmount: 60_000, usedAmount: 48_000),
            BudgetAllocation(
                dbId: 4, monthDate: 0, category: .entertainment,
                allocatedAmount: 50_000, usedAmount: 42_000),
            BudgetAllocation(
                dbId: 5, monthDate: 0, category: .travel,
                allocatedAmount: 30_000, usedAmount: 5_000),
        ]
    }

    private func breakdown() -> AllocationTagBreakdown {
        AllocationTagBreakdown(
            allocations: allocations(),
            unallocatedSpending: [],
            unallocatedHeadroom: 100_000,
            totalBudget: 1_000_000,
            tags: [essentials, wealth, lifestyle],
            categoryTagIds: [
                TransactionCategory.investments.key: wealth.id,
                TransactionCategory.homeMaintenance.key: essentials.id,
                TransactionCategory.groceries.key: essentials.id,
                TransactionCategory.entertainment.key: lifestyle.id,
                // .travel deliberately untagged, so the Untagged chip appears
            ])
    }

    /// Builds the header + strip + table stack the way `MonthCarouselCell` does, without the carousel.
    private func render(_ name: String, selectedTagId: String?, singleTag: Bool = false) {
        let model = singleTag ? singleTagBreakdown() : breakdown()

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.backgroundColor = Colors.gray100
        header.layer.cornerRadius = CornerRadius.extraLarge
        header.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        header.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing5, bottom: 0, right: Metrics.spacing4)
        header.isLayoutMarginsRelativeArrangement = true
        header.distribution = .equalSpacing
        header.translatesAutoresizingMaskIntoConstraints = false

        // Mirrors the cell: title + count grouped at the leading edge, Tags button at the trailing one.
        let leading = UIStackView()
        leading.axis = .horizontal
        leading.alignment = .center
        leading.spacing = Metrics.spacing2

        let title = UILabel()
        title.fontStyle = Fonts.title2XS
        title.textColor = Colors.gray500
        title.text = "budget.allocations.title".localized
        title.applyStyle()
        leading.addArrangedSubview(title)

        let visibleAllocations =
            selectedTagId == nil
            ? allocations().sorted { $0.allocatedAmount > $1.allocatedAmount }
            : allocations()
                .sorted { $0.allocatedAmount > $1.allocatedAmount }
                .filter { model.segment("alloc-\($0.category.key)", belongsTo: selectedTagId!) }

        // The real count pill, not a bare label: re-parenting it into the leading group could have
        // broken the circular background, whose radius is derived from its own bounds.
        let countPill = UIStackView()
        countPill.axis = .horizontal
        countPill.distribution = .fillEqually
        countPill.alignment = .center
        countPill.backgroundColor = Colors.gray300
        countPill.clipsToBounds = true
        countPill.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing2, bottom: 0, right: Metrics.spacing2)
        countPill.isLayoutMarginsRelativeArrangement = true
        countPill.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let countLabel = UILabel()
        countLabel.font = Fonts.titleXS.font
        countLabel.textColor = Colors.gray600
        countLabel.textAlignment = .center
        countLabel.text = "\(visibleAllocations.count)"
        countPill.addArrangedSubview(countLabel)
        leading.addArrangedSubview(countPill)
        header.addArrangedSubview(leading)

        let tagsButton = UIButton(type: .system)
        tagsButton.setTitle("budgets.tags.manage".localized, for: .normal)
        tagsButton.titleLabel?.font = Fonts.titleXS.font
        tagsButton.setTitleColor(Colors.mainMagenta, for: .normal)
        header.addArrangedSubview(tagsButton)

        let strip = AllocationTagStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        let hasStrip = strip.configure(
            breakdown: model, selectedTagId: selectedTagId, isValuesHidden: false)
        XCTAssertTrue(hasStrip, "three tags should produce a strip")

        let table = UITableView()
        table.backgroundColor = Colors.gray100
        table.layer.borderWidth = 1
        table.layer.borderColor = Colors.gray300.cgColor
        table.layer.cornerRadius = CornerRadius.extraLarge
        table.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        table.separatorStyle = .singleLine
        table.separatorInset = .zero
        table.separatorColor = Colors.gray300
        table.clipsToBounds = true
        table.isScrollEnabled = false
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(AllocationCell.self, forCellReuseIdentifier: AllocationCell.reuseIdentifier)

        let source = StubTableSource(allocations: visibleAllocations)
        table.dataSource = source
        table.delegate = source

        let tableHeight = CGFloat(visibleAllocations.count) * 68
        let totalHeight = Metrics.spacing11 + AllocationTagStripView.preferredHeight + tableHeight

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: totalHeight + 40))
        window.backgroundColor = Colors.gray200
        window.isHidden = false
        window.makeKeyAndVisible()

        let host = UIView(frame: window.bounds)
        host.backgroundColor = Colors.gray200
        window.addSubview(host)
        [header, strip, table].forEach { host.addSubview($0) }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Metrics.spacing11),

            strip.topAnchor.constraint(equalTo: header.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: AllocationTagStripView.preferredHeight),

            table.topAnchor.constraint(equalTo: strip.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            table.heightAnchor.constraint(equalToConstant: tableHeight),
        ])

        window.setNeedsLayout()
        window.layoutIfNeeded()
        table.reloadData()
        window.layoutIfNeeded()
        countPill.layer.cornerRadius = countPill.bounds.height / 2
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let size = CGSize(width: width, height: totalHeight + 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }

        guard let data = image.pngData() else { return XCTFail("could not encode \(name)") }

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["FINOVA_SNAPSHOT_DIR"] else { return }
        try? data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("tagstrip-\(name).png"))
        print("SNAPSHOT_WRITTEN \(name)")
    }

    /// One tag, so the Untagged chip and the trailing `+` both fit on screen without scrolling - the
    /// three- and four-chip cases push the `+` past the right edge, which is why the header also carries
    /// a Tags button.
    private func singleTagBreakdown() -> AllocationTagBreakdown {
        AllocationTagBreakdown(
            allocations: allocations(),
            unallocatedSpending: [],
            unallocatedHeadroom: 100_000,
            totalBudget: 1_000_000,
            tags: [essentials],
            categoryTagIds: [TransactionCategory.homeMaintenance.key: essentials.id])
    }

    func testRenderStripStates() {
        render("unfiltered", selectedTagId: nil)
        render("filtered", selectedTagId: essentials.id)
        render("single-tag", selectedTagId: nil, singleTag: true)
    }

    /// A month with no tags must produce no strip, so the caller collapses its height to zero and the
    /// table sits directly under the header exactly as it did before.
    func testNoTagsProducesNoStrip() {
        let strip = AllocationTagStripView()
        let tagless = AllocationTagBreakdown(
            allocations: allocations(),
            unallocatedSpending: [],
            unallocatedHeadroom: 100_000,
            totalBudget: 1_000_000,
            tags: [],
            categoryTagIds: [:])

        XCTAssertFalse(
            strip.configure(breakdown: tagless, selectedTagId: nil, isValuesHidden: false))
    }
}

private final class StubTableSource: NSObject, UITableViewDataSource, UITableViewDelegate {
    private let allocations: [BudgetAllocation]

    init(allocations: [BudgetAllocation]) {
        self.allocations = allocations
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        allocations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AllocationCell.reuseIdentifier, for: indexPath) as? AllocationCell
        else { return UITableViewCell() }
        cell.configure(with: allocations[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 68 }
}
