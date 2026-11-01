//
//  CoachMarkGuides.swift
//  Finova
//

import Foundation

/// The step lists. Each guide reads the facts once, at start: when the result of a step already
/// exists its save step becomes a note that points at the result, which is what keeps a replay on a
/// user with data from ever asking them to write anything.
enum CoachMarkGuides {

    static func steps(
        for guide: CoachMarkGuideID, facts: CoachMarkFacts, mode: CoachMarkRunMode
    ) -> [CoachMarkStep] {
        switch guide {
        case .firstBudget: return firstBudget(facts)
        case .allocations: return allocations(facts)
        case .salaryAndExpenses: return salaryAndExpenses(facts, mode: mode)
        case .firstTransaction: return firstTransaction(facts)
        case .creditCard: return creditCard(facts)
        case .budgetHistory: return budgetHistory()
        case .dashboardTour: return dashboardTour()
        }
    }

    // MARK: - Shared steps

    private static func key(_ guide: CoachMarkGuideID, _ step: String) -> String {
        "coachMarks.\(guide.rawValue).\(step)"
    }

    private static func info(
        _ guide: CoachMarkGuideID, _ id: String, _ target: CoachMarkTarget?, optional: Bool = false
    ) -> CoachMarkStep {
        CoachMarkStep(
            id: id, target: target, textKey: key(guide, id), kind: .info, isTargetOptional: optional)
    }

    private static func tap(
        _ guide: CoachMarkGuideID, _ id: String, _ target: CoachMarkTarget,
        until advance: CoachMarkStep.Advance, skipIfVisible: CoachMarkTarget? = nil
    ) -> CoachMarkStep {
        CoachMarkStep(
            id: id, target: target, textKey: key(guide, id), kind: .action(until: advance),
            skipIfVisible: skipIfVisible)
    }

    private static func form(
        _ guide: CoachMarkGuideID, _ id: String, _ target: CoachMarkTarget,
        until event: CoachMarkEvent, returnTo: String? = nil
    ) -> CoachMarkStep {
        CoachMarkStep(
            id: id, target: target, textKey: key(guide, id), kind: .action(until: .event(event)),
            returnTo: returnTo, ownsKeyboard: true, isPlain: Self.sheets.contains(target))
    }

    private static let sheets: Set<CoachMarkTarget> = [
        .allocationSheet, .transactionSheet, .addCardForm,
    ]

    /// The `+` button adds a transaction only on the card's month face, so any guide that needs that
    /// meaning first brings the card back to it.
    private static func monthFace(_ guide: CoachMarkGuideID) -> CoachMarkStep {
        tap(
            guide, "monthFace", .dashboardFlipBack, until: .targetVisible(.dashboardBudgetToggle),
            skipIfVisible: .dashboardBudgetToggle)
    }

    // MARK: - Guides

    private static func firstBudget(_ facts: CoachMarkFacts) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.firstBudget
        let backToDashboard = tap(guide, "back", .budgetsBack, until: .targetVisible(.dashboardAdd))

        guard facts.hasBudgetThisMonth else {
            return [
                tap(guide, "define", .dashboardDefineBudget, until: .targetVisible(.budgetsForm)),
                form(guide, "form", .budgetsForm, until: .budgetSaved),
                backToDashboard,
            ]
        }
        return [
            info(guide, "existingCard", .dashboardMonthCard),
            tap(guide, "existingConfig", .dashboardConfig, until: .targetVisible(.budgetsForm)),
            info(guide, "existingForm", .budgetsForm),
            info(guide, "existingList", .budgetsList, optional: true),
            backToDashboard,
        ]
    }

    private static func allocations(_ facts: CoachMarkFacts) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.allocations
        let budgetFace = tap(
            guide, "budgetFace", .dashboardBudgetToggle, until: .targetVisible(.dashboardFlipBack),
            skipIfVisible: .dashboardFlipBack)

        guard facts.hasAllocationThisMonth else {
            return [
                budgetFace,
                tap(guide, "add", .dashboardAdd, until: .targetVisible(.allocationSheet)),
                form(guide, "sheet", .allocationSheet, until: .allocationSaved, returnTo: "add"),
                info(guide, "note", .dashboardAllocations, optional: true),
            ]
        }
        return [
            budgetFace,
            info(guide, "existingList", .dashboardAllocations, optional: true),
            info(guide, "existingAdd", .dashboardAdd),
        ]
    }

    private static func salaryAndExpenses(
        _ facts: CoachMarkFacts, mode: CoachMarkRunMode
    ) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.salaryAndExpenses
        var steps = [monthFace(guide)]

        if facts.hasRecurringTransaction {
            steps += [
                info(guide, "existingList", .dashboardTransactions, optional: true),
                info(guide, "existingAdd", .dashboardAdd),
            ]
        } else {
            steps += [
                tap(guide, "add", .dashboardAdd, until: .targetVisible(.transactionSheet)),
                tap(guide, "mode", .transactionMode, until: .event(.transactionModeRecurring)),
                form(guide, "sheet", .transactionSheet, until: .transactionSaved, returnTo: "add"),
                info(guide, "note", .dashboardAdd),
            ]
        }
        // The chain ends here, so this is where a new user learns the guides have not gone away.
        if mode == .automatic {
            steps.append(info(guide, "allSet", nil))
        }
        return steps
    }

    private static func firstTransaction(_ facts: CoachMarkFacts) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.firstTransaction
        guard facts.hasAnyTransaction else {
            return [
                monthFace(guide),
                tap(guide, "add", .dashboardAdd, until: .targetVisible(.transactionSheet)),
                form(guide, "sheet", .transactionSheet, until: .transactionSaved, returnTo: "add"),
                info(guide, "note", .dashboardTransactions, optional: true),
            ]
        }
        return [
            monthFace(guide),
            info(guide, "existingList", .dashboardTransactions, optional: true),
            info(guide, "existingAdd", .dashboardAdd),
        ]
    }

    private static func creditCard(_ facts: CoachMarkFacts) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.creditCard
        var steps = [
            tap(guide, "avatar", .dashboardAvatar, until: .targetVisible(.profileCreditCards)),
            tap(guide, "row", .profileCreditCards, until: .targetVisible(.creditCardsAdd)),
        ]
        var formWithoutCard = form(
            guide, "form", .addCardForm, until: .creditCardSaved, returnTo: "add")
        formWithoutCard.isSilent = true

        if facts.hasCreditCard {
            steps.append(info(guide, "existingList", .creditCardsList))
        } else {
            steps += [
                tap(guide, "add", .creditCardsAdd, until: .targetVisible(.addCardForm)),
                CoachMarkStep(
                    id: "formNote", target: nil, textKey: key(guide, "form"), kind: .info),
                formWithoutCard,
                info(guide, "note", .creditCardsList, optional: true),
            ]
        }
        return steps
    }

    private static func budgetHistory() -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.budgetHistory
        return [
            tap(guide, "open", .dashboardHistory, until: .screen("BudgetHistoryViewController")),
            info(guide, "note", .budgetHistoryContent, optional: true),
        ]
    }

    private static func dashboardTour() -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.dashboardTour
        return [
            monthFace(guide),
            info(guide, "months", .dashboardMonthSelector),
            info(guide, "card", .dashboardMonthCard),
            info(guide, "budgetToggle", .dashboardBudgetToggle),
            info(guide, "transactions", .dashboardTransactions, optional: true),
            info(guide, "add", .dashboardAdd),
            info(guide, "notifications", .dashboardNotifications),
            info(guide, "avatar", .dashboardAvatar),
        ]
    }
}
