//
//  HideValuesHeaderHitTests.swift
//  FinovaTests
//
//  The eye toggle is only useful if a tap actually reaches it. These tests lay out the real screen
//  headers at device width and hit-test the button's centre, which is the one thing
//  `sendActions(for:)` cannot verify.
//
//  The diagnostic tests below are deliberately split one-assertion-per-method so a failure name
//  alone says which stage broke: present, sized, on-screen, or hit-testable.
//

import Foundation
import UIKit
import XCTest

@testable import Finova

final class HideValuesHeaderHitTests: XCTestCase {

    private let deviceSize = CGSize(width: 402, height: 874)

    private func layOut(_ view: UIView) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: deviceSize))
        window.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: window.topAnchor),
            view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ])
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func hideValuesButton(in view: UIView) -> HideValuesButton? {
        if let button = view as? HideValuesButton { return button }
        for subview in view.subviews {
            if let found = hideValuesButton(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Diagnostic stages, on one representative screen

    func testStage1_ButtonIsInTheHierarchy() {
        let view = TransactionDetailsView()
        _ = layOut(view)
        XCTAssertNotNil(hideValuesButton(in: view))
    }

    func testStage2_ButtonHasANonEmptyFrame() {
        let view = TransactionDetailsView()
        _ = layOut(view)
        let button = hideValuesButton(in: view)
        XCTAssertEqual(button?.bounds.width, Metrics.hideValuesButtonSize)
        XCTAssertEqual(button?.bounds.height, Metrics.hideValuesButtonSize)
    }

    func testStage3_ButtonIsVisibleAndInteractive() {
        let view = TransactionDetailsView()
        _ = layOut(view)
        guard let button = hideValuesButton(in: view) else { return XCTFail("missing") }
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertTrue(button.isEnabled)
        XCTAssertGreaterThan(button.alpha, 0.01)
    }

    func testStage4_EveryAncestorIsInteractiveAndContainsTheButton() {
        let view = TransactionDetailsView()
        let window = layOut(view)
        guard let button = hideValuesButton(in: view) else { return XCTFail("missing") }

        var node: UIView = button
        while let parent = node.superview {
            XCTAssertTrue(
                parent.isUserInteractionEnabled,
                "\(type(of: parent)) has interaction disabled")
            XCTAssertGreaterThan(parent.alpha, 0.01, "\(type(of: parent)) is transparent")
            XCTAssertFalse(parent.isHidden, "\(type(of: parent)) is hidden")

            let centreInParent = node.superview!.convert(node.center, to: parent)
            XCTAssertTrue(
                parent.bounds.contains(centreInParent),
                """
                \(type(of: parent)) bounds \(parent.bounds) do not contain the button centre \
                \(centreInParent) — hitTest stops here even without clipsToBounds
                """)
            node = parent
            if parent === window { break }
        }
    }

    func testStage5_HitTestResolvesToTheButton() {
        let view = TransactionDetailsView()
        let window = layOut(view)
        guard let button = hideValuesButton(in: view) else { return XCTFail("missing") }

        let centre = button.superview!.convert(button.center, to: window)
        let hit = window.hitTest(centre, with: nil)

        XCTAssertTrue(
            hit === button,
            "tap resolved to \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
    }

    // MARK: - Every screen that carries the button

    private func assertTappable(
        _ view: UIView, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let window = layOut(view)
        guard let button = hideValuesButton(in: view) else {
            return XCTFail("\(name): no HideValuesButton in the hierarchy", file: file, line: line)
        }
        let centre = button.superview!.convert(button.center, to: window)
        let hit = window.hitTest(centre, with: nil)
        XCTAssertTrue(
            hit === button,
            "\(name): tap resolved to \(hit.map { String(describing: type(of: $0)) } ?? "nil")",
            file: file, line: line)
    }

    func testTransactionDetailsHeaderButtonIsTappable() {
        assertTappable(TransactionDetailsView(), "TransactionDetailsView")
    }

    func testStatementDetailsHeaderButtonIsTappable() {
        assertTappable(StatementDetailsView(), "StatementDetailsView")
    }

    func testBudgetAllocationDetailsHeaderButtonIsTappable() {
        assertTappable(BudgetAllocationDetailsView(), "BudgetAllocationDetailsView")
    }

    func testBudgetsHeaderButtonIsTappable() {
        assertTappable(BudgetsView(), "BudgetsView")
    }

    func testCreditCardsHeaderButtonIsTappable() {
        assertTappable(CreditCardsView(), "CreditCardsView")
    }

    func testEarlyPaymentHeaderButtonIsTappable() {
        assertTappable(EarlyPaymentView(), "EarlyPaymentView")
    }
}
