package com.arthurrios.finova.domain.coachmarks

import com.arthurrios.finova.domain.coachmarks.CoachMarkAdvance.Event
import com.arthurrios.finova.domain.coachmarks.CoachMarkAdvance.Screen
import com.arthurrios.finova.domain.coachmarks.CoachMarkAdvance.TargetVisible
import com.arthurrios.finova.domain.coachmarks.CoachMarkEvent.FieldFilled
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId as Guide
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget as Target

/**
 * The step lists. Port of CoachMarkGuides.swift. Each guide reads the facts once, at start: when the
 * result of a step already exists its save step becomes a note that points at the result, which is
 * what keeps a replay on a user with data from ever asking them to write anything.
 */
object CoachMarkGuides {
    /** The budget history's route, which a step waits for. Set here so this file needs no UI. */
    const val HISTORY_ROUTE = "history?category={category}&month={month}"

    fun steps(guide: Guide, facts: CoachMarkFacts, mode: CoachMarkRunMode): List<CoachMarkStep> = when (guide) {
        Guide.FirstBudget -> firstBudget(facts)
        Guide.Allocations -> allocations(facts, mode)
        Guide.SalaryAndExpenses -> salaryAndExpenses(facts)
        Guide.FirstTransaction -> firstTransaction(facts)
        Guide.CreditCard -> creditCard(facts)
        Guide.BudgetHistory -> budgetHistory()
        Guide.DashboardTour -> dashboardTour()
    }

    private fun key(guide: Guide, step: String) = "coachMarks.${guide.key}.$step"

    private fun info(
        guide: Guide,
        id: String,
        target: Target?,
        optional: Boolean = false,
        tried: CoachMarkAdvance? = null,
        skipsWhenAbsent: Boolean = false,
        skipIfVisible: Target? = null,
    ) = CoachMarkStep(
        id = id, target = target, textKey = key(guide, id), kind = CoachMarkStepKind.Info,
        skipIfVisible = skipIfVisible, isTargetOptional = optional, triedBy = tried,
        skipsWhenAbsent = skipsWhenAbsent,
    )

    private fun tap(guide: Guide, id: String, target: Target, until: CoachMarkAdvance, skipIfVisible: Target? = null) =
        CoachMarkStep(
            id = id, target = target, textKey = key(guide, id), kind = CoachMarkStepKind.Action(until),
            skipIfVisible = skipIfVisible,
        )

    private fun form(guide: Guide, id: String, target: Target, until: CoachMarkEvent) = CoachMarkStep(
        id = id, target = target, textKey = key(guide, id), kind = CoachMarkStepKind.Action(Event(until)),
        ownsKeyboard = true,
    )

    /**
     * One step per field, each moving on when the field is filled or with Next. Saving stays the
     * user's own act: only a real save ends the form. Leaving the form goes back to `add`.
     */
    private fun formSteps(
        guide: Guide,
        fields: List<Pair<String, Target>>,
        waitsForNext: Set<Target> = emptySet(),
        save: Target,
        until: CoachMarkEvent,
    ): List<CoachMarkStep> = fields.map { (id, target) ->
        CoachMarkStep(
            id = id, target = target, textKey = key(guide, id), kind = CoachMarkStepKind.Info,
            returnTo = "add", ownsKeyboard = true,
            triedBy = if (target in waitsForNext) null else Event(FieldFilled(target)),
        )
    } + CoachMarkStep(
        id = "save", target = save, textKey = key(guide, "save"),
        kind = CoachMarkStepKind.Action(Event(until)), returnTo = "add", ownsKeyboard = true,
    )

    private fun transactionForm(guide: Guide) = formSteps(
        guide,
        fields = listOf(
            "title" to Target.TransactionTitle, "category" to Target.TransactionCategory,
            "amount" to Target.TransactionAmount, "date" to Target.TransactionDate,
            "dateRule" to Target.TransactionDateRule, "type" to Target.TransactionType,
        ),
        save = Target.TransactionSave,
        until = CoachMarkEvent.TransactionSaved,
    )

    /** The `+` button adds a transaction only on the card's month face. */
    private fun monthFace(guide: Guide) = tap(
        guide, "monthFace", Target.DashboardFlipBack,
        until = TargetVisible(Target.DashboardBudgetToggle),
        skipIfVisible = Target.DashboardBudgetToggle,
    )

    private fun firstBudget(facts: CoachMarkFacts): List<CoachMarkStep> {
        val guide = Guide.FirstBudget
        val backToDashboard = tap(guide, "back", Target.BudgetsBack, until = TargetVisible(Target.DashboardAdd))
        if (!facts.hasBudgetThisMonth) {
            return listOf(
                tap(guide, "define", Target.DashboardDefineBudget, until = TargetVisible(Target.BudgetsForm)),
                form(
                    guide, if (facts.hasIncomeThisMonth) "formWithIncome" else "form", Target.BudgetsForm,
                    until = CoachMarkEvent.BudgetSaved,
                ),
                backToDashboard,
            )
        }
        return listOf(
            info(guide, "existingCard", Target.DashboardMonthCard),
            tap(guide, "existingConfig", Target.DashboardConfig, until = TargetVisible(Target.BudgetsForm)),
            info(guide, "existingForm", Target.BudgetsForm),
            info(guide, "existingList", Target.BudgetsList, optional = true),
            backToDashboard,
        )
    }

    private fun allocations(facts: CoachMarkFacts, mode: CoachMarkRunMode): List<CoachMarkStep> {
        val guide = Guide.Allocations
        val budgetFace = tap(
            guide, "budgetFace", Target.DashboardBudgetToggle,
            until = TargetVisible(Target.DashboardFlipBack),
            skipIfVisible = Target.DashboardFlipBack,
        )
        val steps = mutableListOf(budgetFace)
        if (facts.hasAllocationThisMonth) {
            steps += info(guide, "existingList", Target.DashboardAllocations, optional = true)
            steps += info(guide, "existingAdd", Target.DashboardAdd)
        } else {
            steps += tap(guide, "add", Target.DashboardAdd, until = TargetVisible(Target.AllocationSheet))
            steps += formSteps(
                guide,
                fields = listOf(
                    "category" to Target.AllocationCategory, "amount" to Target.AllocationAmount,
                    "recurring" to Target.AllocationRecurring,
                ),
                // Turning this on opens more options, which moving on would hide.
                waitsForNext = setOf(Target.AllocationRecurring),
                save = Target.AllocationSave,
                until = CoachMarkEvent.AllocationSaved,
            )
            steps += info(guide, "note", Target.DashboardAllocations, optional = true)
        }
        // The chain ends here, so this is where a new user learns the guides have not gone away.
        if (mode == CoachMarkRunMode.Automatic) steps += info(guide, "allSet", null)
        return steps
    }

    private fun salaryAndExpenses(facts: CoachMarkFacts): List<CoachMarkStep> {
        val guide = Guide.SalaryAndExpenses
        val steps = mutableListOf(monthFace(guide))
        if (facts.hasRecurringTransaction) {
            steps += info(guide, "existingList", Target.DashboardTransactions, optional = true)
            steps += info(guide, "existingAdd", Target.DashboardAdd)
        } else {
            steps += tap(guide, "add", Target.DashboardAdd, until = TargetVisible(Target.TransactionSheet))
            steps += tap(guide, "mode", Target.TransactionMode, until = Event(CoachMarkEvent.TransactionModeRecurring))
            steps += transactionForm(guide)
            steps += info(guide, "note", Target.DashboardAdd)
        }
        return steps
    }

    private fun firstTransaction(facts: CoachMarkFacts): List<CoachMarkStep> {
        val guide = Guide.FirstTransaction
        if (!facts.hasAnyTransaction) {
            return listOf(
                monthFace(guide),
                tap(guide, "add", Target.DashboardAdd, until = TargetVisible(Target.TransactionSheet)),
            ) + transactionForm(guide) + info(guide, "note", Target.DashboardTransactions, optional = true)
        }
        return listOf(
            monthFace(guide),
            info(guide, "existingList", Target.DashboardTransactions, optional = true),
            info(guide, "existingAdd", Target.DashboardAdd),
        )
    }

    private fun creditCard(facts: CoachMarkFacts): List<CoachMarkStep> {
        val guide = Guide.CreditCard
        val steps = mutableListOf(
            tap(guide, "avatar", Target.DashboardAvatar, until = TargetVisible(Target.ProfileCreditCards)),
            tap(guide, "row", Target.ProfileCreditCards, until = TargetVisible(Target.CreditCardsAdd)),
        )
        if (facts.hasCreditCard) {
            steps += info(guide, "existingList", Target.CreditCardsList)
        } else {
            steps += tap(guide, "add", Target.CreditCardsAdd, until = TargetVisible(Target.AddCardForm))
            steps += formSteps(
                guide,
                fields = listOf(
                    "name" to Target.AddCardName, "lastFour" to Target.AddCardLastFour,
                    "brand" to Target.AddCardBrand, "closingDay" to Target.AddCardClosingDay,
                    "dueDay" to Target.AddCardDueDay, "limit" to Target.AddCardLimit,
                ),
                save = Target.AddCardSave,
                until = CoachMarkEvent.CreditCardSaved,
            )
            steps += info(guide, "note", Target.CreditCardsList, optional = true)
        }
        return steps
    }

    private fun budgetHistory(): List<CoachMarkStep> {
        val guide = Guide.BudgetHistory
        return listOf(
            tap(guide, "open", Target.DashboardHistory, until = Screen(HISTORY_ROUTE)),
            info(guide, "chart", Target.BudgetHistoryChart, tried = Event(CoachMarkEvent.HistoryMonthPicked), skipsWhenAbsent = true),
            info(guide, "filter", Target.BudgetHistoryFilter, tried = Event(CoachMarkEvent.HistoryFilterChanged), skipsWhenAbsent = true),
            info(guide, "range", Target.BudgetHistoryRange, tried = Event(CoachMarkEvent.HistoryRangeChanged), skipsWhenAbsent = true),
            // Before the projected months: opening one replaces the savings card.
            info(guide, "savings", Target.BudgetHistorySavings, tried = Event(CoachMarkEvent.HistorySavingsChanged), skipsWhenAbsent = true),
            info(
                guide, "projected", Target.BudgetHistoryProjected,
                tried = Event(CoachMarkEvent.HistoryProjectedMonthPicked),
                skipsWhenAbsent = true, skipIfVisible = Target.BudgetHistoryForecastCard,
            ),
            info(guide, "projectedCard", Target.BudgetHistoryForecastCard, skipsWhenAbsent = true),
            info(guide, "note", null),
        )
    }

    private fun dashboardTour(): List<CoachMarkStep> {
        val guide = Guide.DashboardTour
        return listOf(
            monthFace(guide),
            info(guide, "months", Target.DashboardMonthSelector, tried = Event(CoachMarkEvent.DashboardMonthChanged)),
            info(guide, "card", Target.DashboardMonthCard, tried = Event(CoachMarkEvent.DashboardDayChanged)),
            info(guide, "budgetToggle", Target.DashboardBudgetToggle, tried = TargetVisible(Target.DashboardFlipBack)),
            monthFace(guide),
            info(guide, "transactions", Target.DashboardTransactions, optional = true),
            info(guide, "add", Target.DashboardAdd),
            info(guide, "notifications", Target.DashboardNotifications),
            info(guide, "avatar", Target.DashboardAvatar),
        )
    }
}
