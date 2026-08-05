//
//  AllocationTagScenesSnapshotTests.swift
//  FinovaTests
//
//  Renders the tag management screens to PNGs so their layout can be reviewed without signing in.
//  Not an assertion suite beyond "it laid out at all" - it writes attachments and a file per state.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class AllocationTagScenesSnapshotTests: XCTestCase {

    private let deviceSize = CGSize(width: 393, height: 852)

    private func render(_ name: String, view: UIView, height: CGFloat? = nil) {
        // A real window, for the same reason BudgetCardSnapshotTests uses one: rendering a detached
        // view produces offset or stale output that misrepresents the layout under review.
        let window = UIWindow(frame: CGRect(origin: .zero, size: deviceSize))
        window.backgroundColor = Colors.gray200
        window.isHidden = false
        window.makeKeyAndVisible()

        view.frame = window.bounds
        window.addSubview(view)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let size = CGSize(width: deviceSize.width, height: height ?? deviceSize.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }

        guard let data = image.pngData() else {
            XCTFail("could not encode \(name)")
            return
        }

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // A host directory, not NSTemporaryDirectory(): tests run on a throwaway simulator clone whose
        // sandbox is deleted with it, so anything written there is gone before it can be looked at.
        // Set FINOVA_SNAPSHOT_DIR to collect the PNGs; the attachment above is always available.
        guard let directory = ProcessInfo.processInfo.environment["FINOVA_SNAPSHOT_DIR"] else {
            print("SNAPSHOT_ATTACHED \(name) (\(data.count) bytes); set FINOVA_SNAPSHOT_DIR to save)")
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("allocationtags-\(name).png")
        do {
            try data.write(to: url)
            print("SNAPSHOT_WRITTEN \(name) -> \(url.path) (\(data.count) bytes)")
        } catch {
            XCTFail("could not write \(name): \(error)")
        }
    }

    /// An isolated service so these renders never read or write the developer's own tag book.
    private func makeService(tagNames: [String], categoriesPerTag: [[TransactionCategory]])
        -> AllocationTagService
    {
        let defaults = UserDefaults(suiteName: "AllocationTagScenesSnapshots.\(UUID().uuidString)")!
        let uid = "snapshot-uid"
        let store = UserDefaultsAllocationTagStore(defaults: defaults, uidProvider: { uid })
        let service = AllocationTagService(store: store, uidProvider: { uid })

        for (index, name) in tagNames.enumerated() {
            guard let tag = service.createTag(name: name) else { continue }
            for category in categoriesPerTag[index] {
                service.assign(categoryKey: category.key, toTagId: tag.id)
            }
        }
        return service
    }

    func testRenderTagList() {
        let service = makeService(
            tagNames: ["Essentials", "Wealth", "Lifestyle"],
            categoriesPerTag: [
                [.homeMaintenance, .utilities, .groceries, .transportation],
                [.investments],
                [.entertainment, .subscriptions],
            ])

        let view = AllocationTagsView()
        let viewModel = AllocationTagsViewModel(tagService: service)
        let controller = AllocationTagsViewController(
            contentView: view, viewModel: viewModel, flowDelegate: StubFlowDelegate.shared)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: deviceSize)

        render("list", view: controller.view)

        XCTAssertEqual(viewModel.tags.count, 3)
        XCTAssertEqual(viewModel.categoryCount(for: viewModel.tags[0]), 4)
    }

    func testRenderTagListEmptyState() {
        let service = makeService(tagNames: [], categoriesPerTag: [])

        let view = AllocationTagsView()
        let viewModel = AllocationTagsViewModel(tagService: service)
        let controller = AllocationTagsViewController(
            contentView: view, viewModel: viewModel, flowDelegate: StubFlowDelegate.shared)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: deviceSize)

        render("list-empty", view: controller.view)

        XCTAssertTrue(viewModel.isEmpty)
    }

    func testRenderTagEditForm() {
        let service = makeService(
            tagNames: ["Essentials"],
            categoriesPerTag: [[.homeMaintenance, .utilities, .groceries, .transportation]])
        guard let tag = service.tags.first else { return XCTFail("no tag") }

        let view = AllocationTagEditView()
        let controller = AllocationTagEditViewController(
            contentView: view, tag: tag, tagService: service,
            flowDelegate: StubFlowDelegate.shared)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: deviceSize)
        controller.viewWillAppear(false)

        render("edit", view: controller.view)

        // The colour and icon rows must actually be populated - an empty selector row would still
        // render as a plausible-looking form.
        XCTAssertEqual(view.selectedColorIndex, tag.colorIndex)
        XCTAssertFalse(AllocationTagEditView.iconAssetNames.isEmpty)
    }

    func testRenderCategoryLinking() {
        let service = makeService(
            tagNames: ["Essentials", "Wealth"],
            categoriesPerTag: [
                [.homeMaintenance, .utilities, .groceries],
                [.investments],
            ])
        guard let essentials = service.tags.first else { return XCTFail("no tag") }

        let view = AllocationTagCategoriesView()
        let controller = AllocationTagCategoriesViewController(
            contentView: view, tag: essentials, tagService: service,
            flowDelegate: StubFlowDelegate.shared)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: deviceSize)

        render("categories", view: controller.view)
    }

    /// Every category offered as a tag icon must resolve to a real asset, or the picker shows blanks.
    func testEveryOfferedIconAssetExists() {
        for assetName in AllocationTagEditView.iconAssetNames {
            XCTAssertNotNil(UIImage(named: assetName), "missing asset \(assetName)")
        }
        XCTAssertNotNil(UIImage(systemName: AllocationTag.defaultSymbolName))
    }
}

/// Snapshot renders never navigate, so one shared no-op conformer covers all three flows.
private final class StubFlowDelegate: AllocationTagsFlowDelegate, AllocationTagEditFlowDelegate,
    AllocationTagCategoriesFlowDelegate
{
    static let shared = StubFlowDelegate()
    func dismissAllocationTags() {}
    func navigateToAllocationTagEdit(tag: AllocationTag) {}
    func dismissAllocationTagEdit() {}
    func navigateToAllocationTagCategories(tag: AllocationTag) {}
    func dismissAllocationTagCategories() {}
}
