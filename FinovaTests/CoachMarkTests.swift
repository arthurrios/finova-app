//
//  CoachMarkTests.swift
//  FinovaTests
//
//  The promises the guides make: a new user is guided, an existing user is never interrupted, and a
//  replay touches nothing.
//

import UIKit
import XCTest

@testable import Finova

final class CoachMarkGatingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: CoachMarkStateStore!
    private let suiteName = "CoachMarkGatingTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = CoachMarkStateStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var empty: CoachMarkFacts { CoachMarkFacts() }

    private func enrolledState() -> CoachMarkState {
        CoachMarkGating.enrolling(CoachMarkState(), facts: empty)
    }

    // MARK: - New user

    func testNewUserIsEnrolledAndStartsWithFirstBudget() {
        let state = enrolledState()
        XCTAssertEqual(state.isEnrolled, true)
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .firstBudget)
    }

    func testChainLeadsFromBudgetToAllocationsToSalaryThenEnds() {
        let state = enrolledState()
        var facts = CoachMarkFacts(hasAnyBudget: true, hasBudgetThisMonth: true)
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts), .allocations)

        facts.hasAnyAllocation = true
        XCTAssertEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: facts), .salaryAndExpenses)

        facts.hasRecurringTransaction = true
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts))
    }

    func testSavingTheFirstBudgetDoesNotEndTheUsersOwnChain() {
        // Enrollment is decided once. Recomputing it on data would treat the new user as an old one.
        let state = enrolledState()
        let afterBudget = CoachMarkGating.enrolling(
            state, facts: CoachMarkFacts(hasAnyBudget: true))
        XCTAssertEqual(afterBudget.isEnrolled, true)
    }

    func testAllocationsGuideWaitsForABudget() {
        var state = enrolledState()
        state.skipped.insert(.firstBudget)
        XCTAssertEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .salaryAndExpenses)
    }

    // MARK: - Existing user

    func testExistingUserIsNeverEnrolled() {
        for facts in [
            CoachMarkFacts(hasAnyBudget: true),
            CoachMarkFacts(hasAnyAllocation: true),
            CoachMarkFacts(hasAnyTransaction: true),
            CoachMarkFacts(hasCreditCard: true),
        ] {
            let state = CoachMarkGating.enrolling(CoachMarkState(), facts: facts)
            XCTAssertEqual(state.isEnrolled, false)
            XCTAssertTrue(CoachMarkGating.isPermanentlyQuiet(state))
            XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts))
        }
    }

    func testExistingUserStaysQuietEvenIfTheirDataGoesAway() {
        let state = CoachMarkGating.enrolling(
            CoachMarkState(), facts: CoachMarkFacts(hasAnyTransaction: true))
        let later = CoachMarkGating.enrolling(state, facts: empty)
        XCTAssertEqual(later.isEnrolled, false)
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: later, facts: empty))
    }

    // MARK: - New month and reinstall

    func testNewMonthWithoutABudgetDoesNotRestartTheGuide() {
        let lastMonthsBudget = CoachMarkFacts(hasAnyBudget: true, hasBudgetThisMonth: false)
        XCTAssertTrue(CoachMarkGating.isSetupDone(.firstBudget, facts: lastMonthsBudget))

        var state = enrolledState()
        state.completed = [.allocations, .salaryAndExpenses]
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: lastMonthsBudget))
    }

    func testReinstallWithDataStartsNoGuide() {
        // A reinstall loses the defaults, so this is a blank state meeting a full ledger.
        let facts = CoachMarkFacts(hasAnyBudget: true, hasAnyTransaction: true)
        store.clear(uid: "user")
        let state = CoachMarkGating.enrolling(store.load(uid: "user"), facts: facts)
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts))
    }

    func testLosingDataDoesNotRestartACompletedGuide() {
        var state = enrolledState()
        state.completed.insert(.firstBudget)
        XCTAssertEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .salaryAndExpenses)
    }

    // MARK: - Skipping

    func testSkipAllStopsEveryAutomaticGuide() {
        var state = enrolledState()
        state.isAutoDisabled = true
        XCTAssertTrue(CoachMarkGating.isPermanentlyQuiet(state))
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty))
    }

    func testSkipEndsOneGuideAndTheChainGoesOn() {
        var state = enrolledState()
        state.skipped.insert(.firstBudget)
        let facts = CoachMarkFacts(hasAnyBudget: true)
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts), .allocations)
    }

    func testAGuideTheUserKeepsLeavingStopsOffering() {
        var state = enrolledState()
        state.autoStarts[.firstBudget] = CoachMarkGating.maxAutoStarts - 1
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .firstBudget)

        state.autoStarts[.firstBudget] = CoachMarkGating.maxAutoStarts
        XCTAssertNotEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .firstBudget)
    }

    func testOnlyTheSetupChainIsAutomatic() {
        XCTAssertEqual(
            CoachMarkGuideID.automaticChain, [.firstBudget, .allocations, .salaryAndExpenses])
    }

    // MARK: - Per-user state

    func testStateIsPerUser() {
        var first = CoachMarkState()
        first.isEnrolled = true
        first.isAutoDisabled = true
        first.completed = [.firstBudget]
        store.save(first, uid: "first")

        XCTAssertEqual(store.load(uid: "first"), first)
        XCTAssertEqual(store.load(uid: "second"), CoachMarkState())
    }

    func testStateSurvivesLogOutAndBackIn() {
        var state = enrolledState()
        state.completed = [.firstBudget]
        state.autoStarts = [.firstBudget: 1]
        store.save(state, uid: "user")

        // Signing out removes the local user, not this key. A fresh store reads the same defaults.
        let reloaded = CoachMarkStateStore(defaults: defaults).load(uid: "user")
        XCTAssertEqual(reloaded, state)
    }

    func testCorruptStateIsABlankState() {
        defaults.set(Data("nonsense".utf8), forKey: "coachMarks.state.user")
        XCTAssertEqual(store.load(uid: "user"), CoachMarkState())
    }
}

final class CoachMarkGuideTests: XCTestCase {
    private let everything = CoachMarkFacts(
        hasAnyBudget: true, hasBudgetThisMonth: true, hasAnyAllocation: true,
        hasAllocationThisMonth: true, hasRecurringTransaction: true, hasAnyTransaction: true,
        hasCreditCard: true)

    private static let saveEvents: [CoachMarkEvent] = [
        .budgetSaved, .allocationSaved, .transactionSaved, .creditCardSaved,
    ]

    private func writesData(_ step: CoachMarkStep) -> Bool {
        Self.saveEvents.contains { step.kind == .action(until: .event($0)) }
    }

    // MARK: - Replay

    func testReplayOnAUserWithDataNeverAsksThemToSave() {
        for guide in CoachMarkGuideID.allCases {
            let steps = CoachMarkGuides.steps(for: guide, facts: everything, mode: .replay)
            XCTAssertFalse(steps.contains(where: writesData), "\(guide) asks to save")
            XCTAssertFalse(steps.isEmpty)
        }
    }

    func testReplayOnANewUserAsksForTheRealAction() {
        let steps = CoachMarkGuides.steps(
            for: .firstBudget, facts: CoachMarkFacts(), mode: .replay)
        XCTAssertTrue(steps.contains(where: writesData))
    }

    func testAllSetCardOnlyEndsTheAutomaticChain() {
        func lastTarget(_ mode: CoachMarkRunMode) -> CoachMarkTarget? {
            CoachMarkGuides.steps(for: .salaryAndExpenses, facts: CoachMarkFacts(), mode: mode)
                .last?.target
        }
        XCTAssertNil(lastTarget(.automatic))
        XCTAssertNotNil(lastTarget(.replay))
    }

    // MARK: - Step rules

    func testEverySaveStepAdvancesOnlyOnItsEvent() {
        let steps = CoachMarkGuides.steps(
            for: .firstBudget, facts: CoachMarkFacts(), mode: .automatic)
        var session = CoachMarkSession(guide: .firstBudget, mode: .automatic, steps: steps)
        XCTAssertTrue(session.advance())
        XCTAssertEqual(session.step.id, "form")

        XCTAssertFalse(session.isSatisfied(by: .transactionSaved))
        XCTAssertTrue(session.isSatisfied(by: .budgetSaved))
    }

    func testClosingASheetUnsavedReturnsToTheButtonThatOpenedIt() {
        let steps = CoachMarkGuides.steps(
            for: .allocations, facts: CoachMarkFacts(hasAnyBudget: true), mode: .automatic)
        var session = CoachMarkSession(guide: .allocations, mode: .automatic, steps: steps)
        while session.step.id != "sheet" { XCTAssertTrue(session.advance()) }

        session.goBack(to: session.step.returnTo ?? "")
        XCTAssertEqual(session.step.id, "add")
    }

    func testAdvancingPastTheLastStepFinishes() {
        var session = CoachMarkSession(
            guide: .budgetHistory, mode: .replay,
            steps: CoachMarkGuides.steps(
                for: .budgetHistory, facts: CoachMarkFacts(), mode: .replay))
        XCTAssertTrue(session.advance())
        XCTAssertTrue(session.isLastStep)
        XCTAssertFalse(session.advance())
    }

    func testCounterLeavesOutStepsThatWereSkipped() {
        let steps = CoachMarkGuides.steps(
            for: .dashboardTour, facts: CoachMarkFacts(), mode: .replay)
        var session = CoachMarkSession(guide: .dashboardTour, mode: .replay, steps: steps)
        XCTAssertTrue(session.skipStep())
        XCTAssertEqual(session.shownPosition, 1)
        XCTAssertEqual(session.shownTotal, steps.count - 1)

        XCTAssertTrue(session.advance())
        XCTAssertEqual(session.shownPosition, 2)
    }

    // MARK: - Sheets

    private var allSteps: [CoachMarkStep] {
        CoachMarkGuideID.allCases.flatMap { guide in
            CoachMarkGuides.steps(for: guide, facts: CoachMarkFacts(), mode: .automatic)
                + CoachMarkGuides.steps(for: guide, facts: everything, mode: .replay)
        }
    }

    func testEveryWholeSheetStepIsPlain() {
        let sheets: [CoachMarkTarget] = [.allocationSheet, .transactionSheet, .addCardForm]
        let sheetSteps = allSteps.filter { $0.target.map(sheets.contains) ?? false }
        XCTAssertFalse(sheetSteps.isEmpty)
        XCTAssertTrue(sheetSteps.allSatisfy(\.isPlain))
    }

    func testAControlInsideASheetKeepsItsHighlight() {
        let mode = allSteps.first { $0.target == .transactionMode }
        XCTAssertEqual(mode?.isPlain, false)
    }

    func testNothingElseIsPlain() {
        let others = allSteps.filter { $0.isPlain && !$0.ownsKeyboard }
        XCTAssertTrue(others.isEmpty)
        XCTAssertEqual(allSteps.first { $0.target == .budgetsForm }?.isPlain, false)
    }

    func testFullScreenCardFormIsToldBeforeItOpensUp() {
        let steps = CoachMarkGuides.steps(
            for: .creditCard, facts: CoachMarkFacts(), mode: .replay)
        let form = steps.firstIndex { $0.target == .addCardForm }
        XCTAssertEqual(form.map { steps[$0].isSilent }, true)
        XCTAssertEqual(form.map { steps[$0 - 1].textKey }, form.map { steps[$0].textKey })
        XCTAssertEqual(form.map { steps[$0 - 1].kind }, .info)
    }

    func testCounterLeavesOutASilentStep() {
        let steps = CoachMarkGuides.steps(
            for: .creditCard, facts: CoachMarkFacts(), mode: .replay)
        var session = CoachMarkSession(guide: .creditCard, mode: .replay, steps: steps)
        XCTAssertEqual(session.shownTotal, steps.count - 1)
        while session.advance() {}
        XCTAssertEqual(session.shownPosition, session.shownTotal)
    }

    func testOnlyFormStepsOwnTheKeyboard() {
        for guide in CoachMarkGuideID.allCases {
            for step in CoachMarkGuides.steps(for: guide, facts: CoachMarkFacts(), mode: .automatic)
            where step.ownsKeyboard {
                XCTAssertTrue(writesData(step), "\(guide).\(step.id)")
            }
        }
    }

    // MARK: - Text

    func testEveryStepHasTextInBothLanguages() throws {
        var keys = CoachMarkGuideID.allCases.flatMap { [$0.titleKey, $0.subtitleKey] }
        for guide in CoachMarkGuideID.allCases {
            for facts in [CoachMarkFacts(), everything] {
                for mode in [CoachMarkRunMode.automatic, .replay] {
                    keys += CoachMarkGuides.steps(for: guide, facts: facts, mode: mode).map(\.textKey)
                }
            }
        }

        let bundle = Bundle(for: CoachMarkCenter.self)
        for language in ["en", "pt-BR"] {
            let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"))
            let localized = try XCTUnwrap(Bundle(path: path))
            for key in Set(keys) {
                let value = localized.localizedString(forKey: key, value: "MISSING", table: nil)
                XCTAssertNotEqual(value, "MISSING", "\(language): \(key)")
            }
        }
    }

    func testNoGuideMentionsWhatThisVersionDoesNotHave() throws {
        let bundle = Bundle(for: CoachMarkCenter.self)
        let forbidden = ["sync", "family", "famíl", "group", "grupo", "import", "icloud"]
        for language in ["en", "pt-BR"] {
            let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"))
            let localized = try XCTUnwrap(Bundle(path: path))
            for guide in CoachMarkGuideID.allCases {
                for step in CoachMarkGuides.steps(for: guide, facts: CoachMarkFacts(), mode: .automatic)
                    + CoachMarkGuides.steps(for: guide, facts: everything, mode: .replay) {
                    let text = localized.localizedString(forKey: step.textKey, value: nil, table: nil)
                        .lowercased()
                    for word in forbidden {
                        XCTAssertFalse(text.contains(word), "\(step.textKey) says \(word)")
                    }
                }
            }
        }
    }
}

final class CoachMarkOverlayTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
    private let small = CGRect(x: 0, y: 0, width: 320, height: 568)
    private let safe = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
    private let size = CGSize(width: 370, height: 120)

    // MARK: - Touches

    private func makeOverlay(hole: CGRect?, touchable: Bool) -> CoachMarkOverlayView {
        let overlay = CoachMarkOverlayView(frame: bounds)
        overlay.bubble.configure(
            .init(caption: "Guide · 1/3", message: "Message", nextTitle: nil, skipTitle: "Skip",
                  skipAllTitle: nil))
        overlay.isActive = true
        overlay.show(hole: hole, touchable: touchable, keyboardTop: nil, animated: false)
        overlay.layoutIfNeeded()
        return overlay
    }

    func testActionStepLetsOnlyTheTargetTakeTouches() {
        let hole = CGRect(x: 170, y: 700, width: 60, height: 60)
        let overlay = makeOverlay(hole: hole, touchable: true)

        XCTAssertNil(overlay.hitTest(CGPoint(x: hole.midX, y: hole.midY), with: nil))
        XCTAssertTrue(overlay.hitTest(CGPoint(x: 20, y: 300), with: nil) === overlay)
    }

    func testInfoStepHoleTakesNoTouches() {
        let hole = CGRect(x: 170, y: 700, width: 60, height: 60)
        let overlay = makeOverlay(hole: hole, touchable: false)
        XCTAssertTrue(overlay.hitTest(CGPoint(x: hole.midX, y: hole.midY), with: nil) === overlay)
    }

    func testPlainStepDrawsNothingButStillTakesTouches() {
        let sheet = CGRect(x: 0, y: 400, width: 402, height: 474)
        let overlay = CoachMarkOverlayView(frame: bounds)
        overlay.isActive = true
        overlay.show(hole: sheet, touchable: true, keyboardTop: nil, animated: false, plain: true)
        overlay.layoutIfNeeded()

        XCTAssertFalse(overlay.isDimVisible)
        XCTAssertFalse(overlay.isRingVisible)
        XCTAssertNil(overlay.hitTest(CGPoint(x: 200, y: 600), with: nil))
        XCTAssertTrue(overlay.hitTest(CGPoint(x: 20, y: 300), with: nil) === overlay)
    }

    func testNormalStepKeepsDimAndRing() {
        let overlay = makeOverlay(hole: CGRect(x: 170, y: 700, width: 60, height: 60), touchable: true)
        XCTAssertTrue(overlay.isDimVisible)
        XCTAssertTrue(overlay.isRingVisible)
    }

    func testPlainStepCardNeverCoversTheSheet() throws {
        let sheet = CGRect(x: 0, y: 400, width: 402, height: 474)
        let bubble = try XCTUnwrap(
            CoachMarkLayout.bubbleFrame(
                size: size, hole: sheet, bounds: bounds, safeArea: safe, keyboardTop: nil,
                mayCoverHole: false))
        XCTAssertFalse(bubble.intersects(sheet))

        let tall = CGRect(x: 0, y: 90, width: 402, height: 784)
        XCTAssertNil(
            CoachMarkLayout.bubbleFrame(
                size: size, hole: tall, bounds: bounds, safeArea: safe, keyboardTop: nil,
                mayCoverHole: false))
    }

    func testBubbleIsAlwaysReachable() {
        let overlay = makeOverlay(hole: CGRect(x: 170, y: 700, width: 60, height: 60), touchable: true)
        let center = CGPoint(x: overlay.bubble.frame.midX, y: overlay.bubble.frame.midY)
        let hit = overlay.hitTest(center, with: nil)
        XCTAssertNotNil(hit)
        XCTAssertFalse(hit === overlay)
    }

    func testAnInactiveOverlayNeverEatsATouch() {
        let overlay = makeOverlay(hole: nil, touchable: false)
        overlay.isActive = false
        XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 100), with: nil))
    }

    func testTheWindowPassesATouchInTheHoleToTheAppWindow() throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = CoachMarkOverlayWindow(windowScene: scene)
        window.frame = bounds
        window.overlay.frame = bounds
        let hole = CGRect(x: 170, y: 700, width: 60, height: 60)
        window.overlay.isActive = true
        window.overlay.show(hole: hole, touchable: true, keyboardTop: nil, animated: false)
        window.isHidden = false
        defer { window.isHidden = true }

        XCTAssertNil(window.hitTest(CGPoint(x: hole.midX, y: hole.midY), with: nil))
        XCTAssertNotNil(window.hitTest(CGPoint(x: 20, y: 300), with: nil))
        XCTAssertFalse(window.canBecomeKey)
    }

    // MARK: - Glass

    func testHoleReachesAGlassControlThroughRealHitTesting() {
        // The app's own window answers, so the control behind the hole wins the way it does with no
        // overlay. `sendActions` would pass even if the glass had swallowed the touch.
        let host = UIView(frame: bounds)
        let container = UIView(frame: CGRect(x: 170, y: 700, width: 60, height: 60))
        container.applyClearGlass(cornerRadius: 30)
        let button = UIButton(frame: container.bounds)
        container.addSubview(button)
        host.addSubview(container)

        let overlay = makeOverlay(hole: container.frame, touchable: true)
        let point = CGPoint(x: container.frame.midX, y: container.frame.midY)

        XCTAssertNil(overlay.hitTest(point, with: nil))
        XCTAssertTrue(host.hitTest(point, with: nil) === button)
    }

    // MARK: - Layout

    private func frame(
        hole: CGRect?, in bounds: CGRect, keyboardTop: CGFloat? = nil
    ) -> CGRect? {
        CoachMarkLayout.bubbleFrame(
            size: size, hole: hole, bounds: bounds, safeArea: safe, keyboardTop: keyboardTop)
    }

    func testBubbleGoesBelowATargetNearTheTop() throws {
        let hole = CGRect(x: 16, y: 120, width: 370, height: 180)
        let bubble = try XCTUnwrap(frame(hole: hole, in: bounds))
        XCTAssertGreaterThan(bubble.minY, hole.maxY)
    }

    func testBubbleGoesAboveATargetNearTheBottom() throws {
        let hole = CGRect(x: 170, y: 780, width: 60, height: 60)
        let bubble = try XCTUnwrap(frame(hole: hole, in: bounds))
        XCTAssertLessThan(bubble.maxY, hole.minY)
    }

    func testBubbleStaysClearOfTheKeyboard() throws {
        let hole = CGRect(x: 16, y: 120, width: 370, height: 180)
        let bubble = try XCTUnwrap(frame(hole: hole, in: bounds, keyboardTop: 540))
        XCTAssertLessThanOrEqual(bubble.maxY, 540)
    }

    func testBubbleHidesRatherThanCoverAFormBeingTyped() {
        let sheet = CGRect(x: 0, y: 100, width: 402, height: 500)
        XCTAssertNil(frame(hole: sheet, in: bounds, keyboardTop: 600))
    }

    func testBubbleSitsOverATallSheetWhenNothingIsBeingTyped() throws {
        let sheet = CGRect(x: 0, y: 90, width: 402, height: 784)
        let bubble = try XCTUnwrap(frame(hole: sheet, in: bounds))
        XCTAssertEqual(bubble.minY, safe.top + CoachMarkLayout.margin)
    }

    func testCardWithNoTargetIsCentred() throws {
        let bubble = try XCTUnwrap(frame(hole: nil, in: bounds))
        XCTAssertEqual(bubble.midY, (safe.top + bounds.height - safe.bottom) / 2, accuracy: 20)
    }

    func testBubbleFitsOnTheSmallestPhone() throws {
        let hole = CGRect(x: 16, y: 100, width: 288, height: 60)
        let narrow = CGSize(width: 288, height: 150)
        let bubble = try XCTUnwrap(
            CoachMarkLayout.bubbleFrame(
                size: narrow, hole: hole, bounds: small, safeArea: .zero, keyboardTop: nil))
        XCTAssertTrue(small.contains(bubble))
    }

    // MARK: - Finding targets

    func testResolverPicksTheCopyOnScreenAndIgnoresHiddenOnes() {
        let window = UIWindow(frame: bounds)
        let root = UIView(frame: bounds)
        window.addSubview(root)
        let id = CoachMarkTarget.dashboardAdd.rawValue

        let offScreen = UIView(frame: CGRect(x: 500, y: 100, width: 50, height: 50))
        let hidden = UIView(frame: CGRect(x: 10, y: 100, width: 50, height: 50))
        hidden.isHidden = true
        let visible = UIView(frame: CGRect(x: 100, y: 100, width: 50, height: 50))
        [offScreen, hidden, visible].forEach {
            $0.accessibilityIdentifier = id
            root.addSubview($0)
        }

        XCTAssertTrue(
            CoachMarkTargetResolver.find(.dashboardAdd, in: root, within: window) === visible)
        visible.isHidden = true
        XCTAssertNil(CoachMarkTargetResolver.find(.dashboardAdd, in: root, within: window))
    }

    func testResolverSkipsATransparentSubtree() {
        let window = UIWindow(frame: bounds)
        let root = UIView(frame: bounds)
        window.addSubview(root)
        let faded = UIView(frame: bounds)
        faded.alpha = 0
        let child = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        child.accessibilityIdentifier = CoachMarkTarget.dashboardAdd.rawValue
        faded.addSubview(child)
        root.addSubview(faded)

        XCTAssertNil(CoachMarkTargetResolver.find(.dashboardAdd, in: root, within: window))
    }

    func testTopScreenIsThePresentedOneNotTheDashboardBehindIt() {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        XCTAssertTrue(CoachMarkTargetResolver.topViewController(from: navigation) === root)
    }
}

final class CoachMarkCenterTests: XCTestCase {
    private struct Facts: CoachMarkDataProviding {
        var facts: CoachMarkFacts
        func currentFacts() -> CoachMarkFacts { facts }
    }

    func testEventsWithNoGuideRunningDoNothing() {
        let center = CoachMarkCenter(
            store: CoachMarkStateStore(defaults: UserDefaults(suiteName: "CoachMarkCenterTests")!),
            dataProvider: Facts(facts: CoachMarkFacts()))
        center.post(.budgetSaved)
        XCTAssertNil(center.session)
    }

    func testCaptionAndButtonsDifferBetweenAutomaticAndReplay() {
        let steps = CoachMarkGuides.steps(for: .dashboardTour, facts: CoachMarkFacts(), mode: .replay)

        let automatic = CoachMarkCenter.content(
            for: CoachMarkSession(guide: .dashboardTour, mode: .automatic, steps: steps))
        XCTAssertNotNil(automatic.skipAllTitle)

        let replay = CoachMarkCenter.content(
            for: CoachMarkSession(guide: .dashboardTour, mode: .replay, steps: steps))
        XCTAssertNil(replay.skipAllTitle)
    }
}
