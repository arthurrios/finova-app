//
//  CoachMarkModels.swift
//  Finova
//

import Foundation

/// The guides the app can run. The raw value is what `CoachMarkState` persists, so renaming a case
/// would forget every user's progress on it.
enum CoachMarkGuideID: String, Codable, CaseIterable {
    case firstBudget
    case allocations
    case salaryAndExpenses
    case firstTransaction
    case creditCard
    case budgetHistory
    case dashboardTour

    /// The setup chain a new user is walked through, in order. Each one ends where the next begins.
    /// Everything else is Settings-only: a card or a tour is not setup every user needs.
    static let automaticChain: [CoachMarkGuideID] = [.firstBudget, .allocations, .salaryAndExpenses]

    var titleKey: String { "coachMarks.guide.\(rawValue).title" }
    var subtitleKey: String { "coachMarks.guide.\(rawValue).subtitle" }
}

/// Views a step can point at. The raw value is set as the view's `accessibilityIdentifier`, which is
/// the only coupling between a scene and this engine: a scene names its control and knows nothing
/// else, and a control that is gone simply fails to resolve.
enum CoachMarkTarget: String {
    case dashboardDefineBudget = "coachMark.dashboard.defineBudget"
    case dashboardBudgetToggle = "coachMark.dashboard.budgetToggle"
    case dashboardFlipBack = "coachMark.dashboard.flipBack"
    case dashboardHistory = "coachMark.dashboard.history"
    case dashboardConfig = "coachMark.dashboard.config"
    case dashboardAdd = "coachMark.dashboard.add"
    case dashboardAvatar = "coachMark.dashboard.avatar"
    case dashboardNotifications = "coachMark.dashboard.notifications"
    case dashboardMonthSelector = "coachMark.dashboard.monthSelector"
    case dashboardMonthCard = "coachMark.dashboard.monthCard"
    case dashboardTransactions = "coachMark.dashboard.transactions"
    case dashboardAllocations = "coachMark.dashboard.allocations"

    case budgetsForm = "coachMark.budgets.form"
    case budgetsList = "coachMark.budgets.list"
    case budgetsBack = "coachMark.budgets.back"

    case allocationSheet = "coachMark.allocation.sheet"

    case transactionSheet = "coachMark.transaction.sheet"
    case transactionMode = "coachMark.transaction.mode"

    case profileCreditCards = "coachMark.profile.creditCards"
    case creditCardsAdd = "coachMark.creditCards.add"
    case creditCardsList = "coachMark.creditCards.list"
    case addCardForm = "coachMark.addCard.form"

    /// Owned by the budget history screen. Optional: when it is missing the note there is centred.
    case budgetHistoryContent = "coachMark.budgetHistory.content"
}

/// Things only the user can make happen. Scenes post these through `CoachMarkCenter.post` at the
/// moment the action really succeeded, so a mark never moves on because of a tap alone.
enum CoachMarkEvent: Equatable {
    case budgetSaved
    case allocationSaved
    case transactionSaved
    case transactionModeRecurring
    case creditCardSaved
}

struct CoachMarkStep: Equatable {
    enum Kind: Equatable {
        /// Explains something. Moves on with the bubble's Next button; the target takes no touches.
        case info
        /// The user does it. Only the target takes touches until the condition is met.
        case action(until: Advance)
    }

    enum Advance: Equatable {
        case event(CoachMarkEvent)
        case targetVisible(CoachMarkTarget)
        /// The top view controller's class name. For a screen with no identifier of its own.
        case screen(String)
    }

    let id: String
    /// nil shows a centred card with no hole.
    var target: CoachMarkTarget?
    let textKey: String
    let kind: Kind
    /// The state this step would produce already holds, so it is passed without being shown. The
    /// dashboard card has two faces and a guide can start on either.
    var skipIfVisible: CoachMarkTarget?
    /// Where to go back to if the target goes away unfinished, such as a sheet closed without saving.
    var returnTo: String?
    /// The step is a form, so its keyboard belongs to it and must not hide the mark.
    var ownsKeyboard = false
    /// The target is a whole sheet or form. It already stands out from what is behind it, so it gets
    /// no ring and no dim layer: only the message card, which must then stay off it.
    var isPlain = false
    /// A form with no free space around it. A note before it carries the message, and this step only
    /// waits. The form's own back button is the way out.
    var isSilent = false
    /// Show the text centred if the target is missing, rather than skipping the step.
    var isTargetOptional = false

    var isAction: Bool {
        if case .action = kind { return true }
        return false
    }
}

/// What the ledger says right now. Gating and step lists are pure functions of this.
struct CoachMarkFacts: Equatable {
    var hasAnyBudget = false
    var hasBudgetThisMonth = false
    var hasAnyAllocation = false
    var hasAllocationThisMonth = false
    var hasRecurringTransaction = false
    var hasAnyTransaction = false
    var hasCreditCard = false

    var hasAnyData: Bool {
        hasAnyBudget || hasAnyAllocation || hasAnyTransaction || hasCreditCard
    }
}

enum CoachMarkRunMode: Equatable {
    /// Started by the app for a new user. Finishing or skipping is remembered.
    case automatic
    /// Started from Settings. Leaves no trace in the user's state.
    case replay
}

/// One run through one guide. No UIKit, so every transition can be tested directly.
struct CoachMarkSession: Equatable {
    let guide: CoachMarkGuideID
    let mode: CoachMarkRunMode
    let steps: [CoachMarkStep]
    private(set) var index = 0
    /// Steps passed without being shown. The counter on the card must not include them.
    private(set) var skippedStepCount = 0

    init(guide: CoachMarkGuideID, mode: CoachMarkRunMode, steps: [CoachMarkStep]) {
        self.guide = guide
        self.mode = mode
        self.steps = steps
    }

    var step: CoachMarkStep { steps[index] }
    var isLastStep: Bool { index == steps.count - 1 }
    var shownPosition: Int {
        index + 1 - skippedStepCount - steps[..<index].filter(\.isSilent).count
    }
    var shownTotal: Int { steps.count - skippedStepCount - steps.filter(\.isSilent).count }

    /// Passes a step whose result already holds. Returns false when it was the last one.
    mutating func skipStep() -> Bool {
        skippedStepCount += 1
        return advance()
    }

    /// Returns false when there was no next step, which means the guide is finished.
    mutating func advance() -> Bool {
        guard index + 1 < steps.count else { return false }
        index += 1
        return true
    }

    func isSatisfied(by event: CoachMarkEvent) -> Bool {
        step.kind == .action(until: .event(event))
    }

    mutating func goBack(to stepID: String) {
        guard let target = steps.firstIndex(where: { $0.id == stepID }) else { return }
        index = target
    }
}
