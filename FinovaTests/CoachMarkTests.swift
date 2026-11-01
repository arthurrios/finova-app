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

    func testNewUserIsEnrolledAndStartsWithSalary() {
        let state = enrolledState()
        XCTAssertEqual(state.isEnrolled, true)
        XCTAssertEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .salaryAndExpenses)
    }

    func testChainLeadsFromSalaryToBudgetToAllocationsThenEnds() {
        let state = enrolledState()
        var facts = CoachMarkFacts(hasRecurringTransaction: true, hasAnyTransaction: true)
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts), .firstBudget)

        facts.hasAnyBudget = true
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts), .allocations)

        facts.hasAnyAllocation = true
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: facts))
    }

    func testSavingTheFirstBudgetDoesNotEndTheUsersOwnChain() {
        // Enrollment is decided once. Recomputing it on data would treat the new user as an old one.
        let state = enrolledState()
        let afterBudget = CoachMarkGating.enrolling(
            state, facts: CoachMarkFacts(hasAnyBudget: true))
        XCTAssertEqual(afterBudget.isEnrolled, true)
    }

    func testAUserWithABudgetButNoIncomeStillGetsTheSalaryGuide() {
        var state = enrolledState()
        state.completed = [.firstBudget]
        let facts = CoachMarkFacts(hasAnyBudget: true, hasBudgetThisMonth: true)
        XCTAssertEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: facts), .salaryAndExpenses)
    }

    func testSkippingSalaryStillOffersTheBudgetWithNoSuggestionText() {
        var state = enrolledState()
        state.skipped = [.salaryAndExpenses]
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .firstBudget)
        let form = CoachMarkGuides.steps(for: .firstBudget, facts: empty, mode: .automatic)
            .first { $0.target == .budgetsForm }
        XCTAssertEqual(form?.textKey, "coachMarks.firstBudget.form")
    }

    func testAllocationsGuideWaitsForABudget() {
        var state = enrolledState()
        state.skipped = [.salaryAndExpenses, .firstBudget]
        XCTAssertNil(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty))
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
        state.completed = [.salaryAndExpenses, .allocations]
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
        state.completed.insert(.salaryAndExpenses)
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .firstBudget)
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
        state.skipped.insert(.salaryAndExpenses)
        XCTAssertEqual(CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .firstBudget)
    }

    func testAGuideTheUserKeepsLeavingStopsOffering() {
        var state = enrolledState()
        state.autoStarts[.salaryAndExpenses] = CoachMarkGating.maxAutoStarts - 1
        XCTAssertEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .salaryAndExpenses)

        state.autoStarts[.salaryAndExpenses] = CoachMarkGating.maxAutoStarts
        XCTAssertNotEqual(
            CoachMarkGating.nextAutomaticGuide(state: state, facts: empty), .salaryAndExpenses)
    }

    func testOnlyTheSetupChainIsAutomatic() {
        XCTAssertEqual(
            CoachMarkGuideID.automaticChain, [.salaryAndExpenses, .firstBudget, .allocations])
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
            CoachMarkGuides.steps(for: .allocations, facts: CoachMarkFacts(), mode: mode)
                .last?.target
        }
        XCTAssertNil(lastTarget(.automatic))
        XCTAssertNotNil(lastTarget(.replay))
    }

    // MARK: - Step rules

    func testBudgetFormNamesTheSuggestionOnlyWhenThereIsIncome() {
        func formKey(_ facts: CoachMarkFacts) -> String? {
            CoachMarkGuides.steps(for: .firstBudget, facts: facts, mode: .automatic)
                .first { $0.target == .budgetsForm }?.textKey
        }
        XCTAssertEqual(formKey(CoachMarkFacts()), "coachMarks.firstBudget.form")
        XCTAssertEqual(
            formKey(CoachMarkFacts(hasIncomeThisMonth: true)),
            "coachMarks.firstBudget.formWithIncome")
    }

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
        keys += ["next", "done", "skip", "skipAll", "close", "gotIt"].map { "coachMarks.button.\($0)" }
        for guide in CoachMarkGuideID.allCases {
            for facts in [CoachMarkFacts(), CoachMarkFacts(hasIncomeThisMonth: true), everything] {
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
        XCTAssertTrue(overlay.hitTest(CGPoint(x: 20, y: 20), with: nil) === overlay)
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

    private func makeTallSheetOverlay(keyboardTop: CGFloat? = nil) -> CoachMarkOverlayView {
        let overlay = CoachMarkOverlayView(frame: bounds)
        overlay.bubble.configure(
            .init(caption: "Guide · 1/3", message: "Message", nextTitle: nil, skipTitle: "Skip",
                  skipAllTitle: nil))
        overlay.isActive = true
        overlay.show(
            hole: bounds, touchable: true, keyboardTop: keyboardTop, animated: false, plain: true)
        overlay.layoutIfNeeded()
        return overlay
    }

    func testCardWithNoRoomIsStillShownOnce() {
        let overlay = makeTallSheetOverlay()
        XCTAssertFalse(overlay.bubble.isHidden)
        XCTAssertEqual(overlay.bubble.frame.midY, bounds.midY, accuracy: 60)
        let point = CGPoint(x: overlay.bubble.frame.midX, y: overlay.bubble.frame.midY)
        XCTAssertNotNil(overlay.hitTest(point, with: nil))
    }

    func testGotItClearsTheSheetForTheRestOfTheStep() {
        let overlay = makeTallSheetOverlay()
        let point = CGPoint(x: overlay.bubble.frame.midX, y: overlay.bubble.frame.midY)

        overlay.dismissCard()
        overlay.show(hole: bounds, touchable: true, keyboardTop: nil, animated: false, plain: true)

        XCTAssertTrue(overlay.bubble.isHidden)
        XCTAssertNil(overlay.hitTest(point, with: nil))
    }

    func testNextStepBringsTheCardBack() {
        let overlay = makeTallSheetOverlay()
        overlay.dismissCard()
        overlay.resetCard()
        overlay.layoutBubble(animated: false)
        XCTAssertFalse(overlay.bubble.isHidden)
    }

    func testCardStaysHiddenWhileTypingInASheetWithNoRoom() {
        XCTAssertTrue(makeTallSheetOverlay(keyboardTop: 540).bubble.isHidden)
    }

    private func buttons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { subview -> [UIButton] in
            if let button = subview as? UIButton { return button.isHidden ? [] : [button] }
            return buttons(in: subview)
        }
    }

    private func layOutCard(width: CGFloat, skipAll: String?, next: String?) -> CoachMarkBubbleView {
        let bubble = CoachMarkBubbleView()
        bubble.configure(
            .init(caption: "Primeiro orçamento · 1/3", message: "Mensagem", nextTitle: next,
                  skipTitle: "Pular", skipAllTitle: skipAll))
        bubble.frame = CGRect(origin: .zero, size: bubble.fittingSize(width: width))
        bubble.layoutIfNeeded()
        return bubble
    }

    func testEveryCardButtonIsARealButtonWithAFullTapTarget() {
        let bubble = layOutCard(width: 370, skipAll: "Pular todos", next: "Próximo")
        let found = buttons(in: bubble)
        XCTAssertEqual(found.count, 3)
        for button in found {
            XCTAssertNotNil(button.configuration?.baseBackgroundColor)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    func testNextOutranksTheQuietButtons() {
        let found = buttons(in: layOutCard(width: 370, skipAll: "Pular todos", next: "Próximo"))
        let next = found.first { $0.configuration?.title == "Próximo" }
        let skip = found.first { $0.configuration?.title == "Pular" }
        XCTAssertEqual(next?.configuration?.baseBackgroundColor, Colors.mainMagenta)
        XCTAssertEqual(skip?.configuration?.baseBackgroundColor, Colors.gray200)
    }

    func testLongestButtonsStayInsideTheCardOnTheNarrowestPhone() {
        let bubble = layOutCard(width: 288, skipAll: "Pular todos", next: "Próximo")
        for button in buttons(in: bubble) {
            let frame = button.convert(button.bounds, to: bubble)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, bubble.bounds.width)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
        }
    }

    func testButtonsStackWithoutOverlapWhenARowCannotHoldThem() {
        let bubble = layOutCard(width: 200, skipAll: "Pular todos", next: "Próximo")
        let frames = buttons(in: bubble)
            .map { $0.convert($0.bounds, to: bubble) }
            .sorted { $0.minY < $1.minY }
        XCTAssertEqual(frames.count, 3)
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(upper.maxY, lower.minY)
        }
        XCTAssertLessThanOrEqual(frames[2].maxY, bubble.bounds.height)
    }

    func testANearFitLeavesTheRowInsteadOfClipping() {
        XCTAssertTrue(CoachMarkBubbleView.fitsOneRow(buttonWidths: [120, 70, 90], width: 338))
        // 130 + 80 + 110 + 2 gaps is 336, which fits a 338 row only by 2pt.
        XCTAssertFalse(CoachMarkBubbleView.fitsOneRow(buttonWidths: [130, 80, 110], width: 338))
    }

    func testNextKeepsItsTitleWhenAnActionStepLeadsToANote() {
        let bubble = CoachMarkBubbleView()
        bubble.configure(
            .init(caption: "Guide · 2/5", message: "Tap here", nextTitle: nil, skipTitle: "Close",
                  skipAllTitle: nil))
        bubble.frame = CGRect(origin: .zero, size: bubble.fittingSize(width: 370))
        bubble.layoutIfNeeded()

        bubble.configure(
            .init(caption: "Guide · 3/5", message: "Tap here", nextTitle: "Next", skipTitle: "Close",
                  skipAllTitle: nil))
        let size = bubble.fittingSize(width: 370)
        bubble.frame = CGRect(origin: .zero, size: size)
        bubble.layoutIfNeeded()

        let next = buttons(in: bubble).first { $0.configuration?.title == "Next" }
        let fullWidth = next?.sizeThatFits(UIView.layoutFittingExpandedSize).width ?? 0
        XCTAssertGreaterThanOrEqual(next?.frame.width ?? 0, fullWidth - 1)
        XCTAssertEqual(next?.titleLabel?.text, "Next")
    }

    func testASingleButtonCardLooksTheSame() {
        let found = buttons(in: layOutCard(width: 370, skipAll: nil, next: nil))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.configuration?.baseBackgroundColor, Colors.gray200)
    }

    func testSheetOnTheSmallestPhoneGetsACentredCardWithAWayToClearIt() {
        let phone = CGRect(x: 0, y: 0, width: 320, height: 568)
        let sheet = CGRect(x: 0, y: 60, width: 320, height: 508)
        let overlay = CoachMarkOverlayView(frame: phone)
        overlay.bubble.configure(
            .init(caption: "Salário e despesas principais · 3/4",
                  message: "Preencha nome, categoria, valor e data. Escolha Entrada e salve.",
                  nextTitle: nil, skipTitle: "Pular", skipAllTitle: "Pular todos"))
        overlay.isActive = true
        overlay.show(hole: sheet, touchable: true, keyboardTop: nil, animated: false, plain: true)
        overlay.layoutIfNeeded()

        XCTAssertFalse(overlay.bubble.isHidden)
        XCTAssertTrue(phone.contains(overlay.bubble.frame))
        let titles = buttons(in: overlay.bubble).compactMap { $0.configuration?.title }
        XCTAssertTrue(titles.contains("Pular"))
        XCTAssertEqual(titles.count, 3)
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

final class BudgetSuggestionTests: XCTestCase {
    private let month = 1_000
    private let otherMonth = 2_000

    private func transaction(
        amount: Int, type: TransactionType, month: Int, creditCardId: Int? = nil
    ) -> Transaction {
        Transaction(
            data: UITransactionData(
                id: nil, title: "Row", amount: amount, dateTimestamp: month, budgetMonthDate: month,
                isRecurring: nil, hasInstallments: nil, parentTransactionId: nil,
                installmentNumber: nil, totalInstallments: nil, originalAmount: nil,
                creditCardId: creditCardId, category: .salary, type: type))
    }

    func testSumsEveryIncomeOfTheMonth() {
        let rows = [
            transaction(amount: 800_000, type: .income, month: month),
            transaction(amount: 50_000, type: .income, month: month),
        ]
        XCTAssertEqual(BudgetsViewModel.monthlyIncome(of: rows, monthAnchor: month), 850_000)
    }

    func testLeavesOutExpensesOtherMonthsAndCardRefunds() {
        let rows = [
            transaction(amount: 100_000, type: .income, month: month),
            transaction(amount: 30_000, type: .expense, month: month),
            transaction(amount: 900_000, type: .income, month: otherMonth),
            transaction(amount: 20_000, type: .income, month: month, creditCardId: 7),
        ]
        XCTAssertEqual(BudgetsViewModel.monthlyIncome(of: rows, monthAnchor: month), 100_000)
    }

    private func views<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        view.subviews.flatMap { subview -> [T] in
            (subview as? T).map { [$0] } ?? views(of: type, in: subview)
        }
    }

    func testHidingValuesAlsoHidesTheSuggestedIncome() throws {
        let wasHidden = ValueVisibilityStore.shared.isHidden
        if wasHidden { ValueVisibilityStore.shared.toggle() }
        defer {
            if ValueVisibilityStore.shared.isHidden != wasHidden {
                ValueVisibilityStore.shared.toggle()
            }
        }

        let view = BudgetsView()
        view.suggestedAmount = { _ in 800_000 }
        view.updateUI(with: [], selectedDate: Date())

        let suggestion = try XCTUnwrap(
            views(of: UIButton.self, in: view).first {
                $0.title(for: .normal)?.contains(800_000.currencyString) == true
            })
        XCTAssertFalse(suggestion.isHidden)

        try XCTUnwrap(views(of: HideValuesButton.self, in: view).first)
            .sendActions(for: .touchUpInside)

        XCTAssertEqual(suggestion.title(for: .normal)?.contains(ValueMask.placeholder), true)
        XCTAssertEqual(suggestion.title(for: .normal)?.contains(800_000.currencyString), false)
    }

    func testNoIncomeSuggestsNothing() {
        XCTAssertEqual(BudgetsViewModel.monthlyIncome(of: [], monthAnchor: month), 0)
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

    func testGotItOnASheetClearsTheCardAndNeverAdvancesTheStep() throws {
        let steps = CoachMarkGuides.steps(
            for: .creditCard, facts: CoachMarkFacts(), mode: .replay)
        let form = try XCTUnwrap(steps.first { $0.target == .addCardForm })
        XCTAssertEqual(CoachMarkCenter.nextButtonEffect(for: form), .dismissCard)

        let note = try XCTUnwrap(steps.last)
        XCTAssertEqual(CoachMarkCenter.nextButtonEffect(for: note), .advance)
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
