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
        case .allocations: return allocations(facts, mode: mode)
        case .salaryAndExpenses: return salaryAndExpenses(facts)
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
        _ guide: CoachMarkGuideID, _ id: String, _ target: CoachMarkTarget?, optional: Bool = false,
        tried: CoachMarkStep.Advance? = nil, skipsWhenAbsent: Bool = false,
        skipIfVisible: CoachMarkTarget? = nil
    ) -> CoachMarkStep {
        CoachMarkStep(
            id: id, target: target, textKey: key(guide, id), kind: .info,
            skipIfVisible: skipIfVisible, isTargetOptional: optional, triedBy: tried,
            skipsWhenAbsent: skipsWhenAbsent)
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
        until event: CoachMarkEvent
    ) -> CoachMarkStep {
        CoachMarkStep(
            id: id, target: target, textKey: key(guide, id), kind: .action(until: .event(event)),
            ownsKeyboard: true)
    }

    /// One step per field, each moving on when the field is filled or with Next. Saving stays the
    /// user's own act: only a real save ends the form. Leaving the form goes back to `add`.
    private static func formSteps(
        _ guide: CoachMarkGuideID, fields: [(id: String, target: CoachMarkTarget)],
        waitsForNext: Set<CoachMarkTarget> = [], save: CoachMarkTarget, until event: CoachMarkEvent
    ) -> [CoachMarkStep] {
        let steps = fields.map { field in
            CoachMarkStep(
                id: field.id, target: field.target, textKey: key(guide, field.id), kind: .info,
                returnTo: "add", ownsKeyboard: true,
                triedBy: waitsForNext.contains(field.target) ? nil : .event(.fieldFilled(field.target)))
        }
        return steps + [
            CoachMarkStep(
                id: "save", target: save, textKey: key(guide, "save"),
                kind: .action(until: .event(event)), returnTo: "add", ownsKeyboard: true),
        ]
    }

    private static func transactionForm(_ guide: CoachMarkGuideID) -> [CoachMarkStep] {
        formSteps(
            guide,
            fields: [
                ("title", .transactionTitle), ("category", .transactionCategory),
                ("amount", .transactionAmount), ("date", .transactionDate),
                ("dateRule", .transactionDateRule), ("type", .transactionType),
            ],
            save: .transactionSave, until: .transactionSaved)
    }

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
                form(
                    guide, facts.hasIncomeThisMonth ? "formWithIncome" : "form", .budgetsForm,
                    until: .budgetSaved),
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

    private static func allocations(
        _ facts: CoachMarkFacts, mode: CoachMarkRunMode
    ) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.allocations
        let budgetFace = tap(
            guide, "budgetFace", .dashboardBudgetToggle, until: .targetVisible(.dashboardFlipBack),
            skipIfVisible: .dashboardFlipBack)

        var steps = [budgetFace]
        if facts.hasAllocationThisMonth {
            steps += [
                info(guide, "existingList", .dashboardAllocations, optional: true),
                info(guide, "existingAdd", .dashboardAdd),
            ]
        } else {
            steps += [
                tap(guide, "add", .dashboardAdd, until: .targetVisible(.allocationSheet)),
            ]
            steps += formSteps(
                guide,
                fields: [
                    ("category", .allocationCategory), ("amount", .allocationAmount),
                    ("recurring", .allocationRecurring),
                ],
                // Turning this on opens more options, which moving on would hide.
                waitsForNext: [.allocationRecurring],
                save: .allocationSave, until: .allocationSaved)
            steps.append(info(guide, "note", .dashboardAllocations, optional: true))
        }
        // The chain ends here, so this is where a new user learns the guides have not gone away.
        if mode == .automatic {
            steps.append(info(guide, "allSet", nil))
        }
        return steps
    }

    private static func salaryAndExpenses(_ facts: CoachMarkFacts) -> [CoachMarkStep] {
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
            ]
            steps += transactionForm(guide)
            steps.append(info(guide, "note", .dashboardAdd))
        }
        return steps
    }

    private static func firstTransaction(_ facts: CoachMarkFacts) -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.firstTransaction
        guard facts.hasAnyTransaction else {
            return [
                monthFace(guide),
                tap(guide, "add", .dashboardAdd, until: .targetVisible(.transactionSheet)),
            ] + transactionForm(guide) + [
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
        if facts.hasCreditCard {
            steps.append(info(guide, "existingList", .creditCardsList))
        } else {
            steps += [
                tap(guide, "add", .creditCardsAdd, until: .targetVisible(.addCardForm)),
            ]
            steps += formSteps(
                guide,
                fields: [
                    ("name", .addCardName), ("lastFour", .addCardLastFour), ("brand", .addCardBrand),
                    ("closingDay", .addCardClosingDay), ("dueDay", .addCardDueDay),
                    ("limit", .addCardLimit),
                ],
                save: .addCardSave, until: .creditCardSaved)
            steps.append(info(guide, "note", .creditCardsList, optional: true))
        }
        return steps
    }

    private static func budgetHistory() -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.budgetHistory
        return [
            tap(guide, "open", .dashboardHistory, until: .screen("BudgetHistoryViewController")),
            info(guide, "chart", .budgetHistoryChart, tried: .event(.historyMonthPicked), skipsWhenAbsent: true),
            info(guide, "filter", .budgetHistoryFilter, tried: .event(.historyFilterChanged), skipsWhenAbsent: true),
            info(guide, "range", .budgetHistoryRange, tried: .event(.historyRangeChanged), skipsWhenAbsent: true),
            // Before the projected months: opening one replaces the savings card.
            info(guide, "savings", .budgetHistorySavings, tried: .event(.historySavingsChanged), skipsWhenAbsent: true),
            info(
                guide, "projected", .budgetHistoryProjected, tried: .event(.historyProjectedMonthPicked),
                skipsWhenAbsent: true, skipIfVisible: .budgetHistoryForecastCard),
            info(guide, "projectedCard", .budgetHistoryForecastCard, skipsWhenAbsent: true),
            info(guide, "note", nil),
        ]
    }

    private static func dashboardTour() -> [CoachMarkStep] {
        let guide = CoachMarkGuideID.dashboardTour
        return [
            monthFace(guide),
            info(guide, "months", .dashboardMonthSelector, tried: .event(.dashboardMonthChanged)),
            info(guide, "card", .dashboardMonthCard, tried: .event(.dashboardDayChanged)),
            info(guide, "budgetToggle", .dashboardBudgetToggle, tried: .targetVisible(.dashboardFlipBack)),
            monthFace(guide),
            info(guide, "transactions", .dashboardTransactions, optional: true),
            info(guide, "add", .dashboardAdd),
            info(guide, "notifications", .dashboardNotifications),
            info(guide, "avatar", .dashboardAvatar),
        ]
    }
}
