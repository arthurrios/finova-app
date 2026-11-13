package com.arthurrios.finova.domain.coachmarks

/**
 * The guides the app can run. [key] is what [CoachMarkState] persists, so renaming one would forget
 * every user's progress on it. Port of CoachMarkModels.swift.
 */
enum class CoachMarkGuideId(val key: String) {
    SalaryAndExpenses("salaryAndExpenses"),
    FirstBudget("firstBudget"),
    Allocations("allocations"),
    FirstTransaction("firstTransaction"),
    CreditCard("creditCard"),
    BudgetHistory("budgetHistory"),
    DashboardTour("dashboardTour");

    val titleKey: String get() = "coachMarks.guide.$key.title"
    val subtitleKey: String get() = "coachMarks.guide.$key.subtitle"

    companion object {
        /**
         * The setup chain a new user is walked through, in order. Income comes first because the
         * budget form suggests it; everything else is Settings-only.
         */
        val automaticChain = listOf(SalaryAndExpenses, FirstBudget, Allocations)

        fun fromKey(key: String?): CoachMarkGuideId? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Controls a step can point at. A screen marks its control with `Modifier.coachMarkTarget`, which is
 * the only coupling between a screen and the engine: a control that is gone simply fails to resolve.
 */
enum class CoachMarkTarget {
    DashboardDefineBudget, DashboardBudgetToggle, DashboardFlipBack, DashboardHistory, DashboardConfig,
    DashboardAdd, DashboardAvatar, DashboardNotifications, DashboardMonthSelector, DashboardMonthCard,
    DashboardTransactions, DashboardAllocations,

    BudgetsForm, BudgetsList, BudgetsBack,

    AllocationSheet, TransactionSheet, TransactionMode,

    ProfileCreditCards, CreditCardsAdd, CreditCardsList, AddCardForm,

    TransactionTitle, TransactionCategory, TransactionAmount, TransactionDate, TransactionDateRule,
    TransactionType, TransactionSave,

    AllocationCategory, AllocationAmount, AllocationRecurring, AllocationSave,

    AddCardName, AddCardLastFour, AddCardBrand, AddCardClosingDay, AddCardDueDay, AddCardLimit, AddCardSave,

    BudgetHistoryChart,

    /** The same chart, marked only while there are months ahead to show. */
    BudgetHistoryProjected,
    BudgetHistoryForecastCard, BudgetHistoryFilter, BudgetHistoryRange, BudgetHistorySavings,
}

/** Things only the user can make happen. Screens post these the moment the action really succeeded. */
sealed interface CoachMarkEvent {
    data object BudgetSaved : CoachMarkEvent
    data object AllocationSaved : CoachMarkEvent
    data object TransactionSaved : CoachMarkEvent
    data object TransactionModeRecurring : CoachMarkEvent

    /** A form field now holds a value. Says nothing about whether it is valid. */
    data class FieldFilled(val target: CoachMarkTarget) : CoachMarkEvent
    data object CreditCardSaved : CoachMarkEvent
    data object DashboardMonthChanged : CoachMarkEvent
    data object DashboardDayChanged : CoachMarkEvent
    data object HistoryMonthPicked : CoachMarkEvent
    data object HistoryProjectedMonthPicked : CoachMarkEvent
    data object HistoryFilterChanged : CoachMarkEvent
    data object HistoryRangeChanged : CoachMarkEvent
    data object HistorySavingsChanged : CoachMarkEvent
}

sealed interface CoachMarkAdvance {
    data class Event(val event: CoachMarkEvent) : CoachMarkAdvance
    data class TargetVisible(val target: CoachMarkTarget) : CoachMarkAdvance

    /** The route on top. For a screen with no target of its own. */
    data class Screen(val route: String) : CoachMarkAdvance
}

sealed interface CoachMarkStepKind {
    /** Explains something. Moves on with Next; the target stays live so the user can try it. */
    data object Info : CoachMarkStepKind

    /** The user does it. Only [until] moves it on. */
    data class Action(val until: CoachMarkAdvance) : CoachMarkStepKind
}

data class CoachMarkStep(
    val id: String,
    /** null shows a centred card with no hole. */
    val target: CoachMarkTarget?,
    val textKey: String,
    val kind: CoachMarkStepKind,
    /** The state this step would produce already holds, so it is passed without being shown. */
    val skipIfVisible: CoachMarkTarget? = null,
    /** Where to go back to if the target goes away unfinished, such as a sheet closed unsaved. */
    val returnTo: String? = null,
    /** The step is a form, so its keyboard belongs to it and must not hide the mark. */
    val ownsKeyboard: Boolean = false,
    /** Show the text centred if the target is missing, rather than skipping the step. */
    val isTargetOptional: Boolean = false,
    /** On a note: the user doing what it describes moves it on too, without the button. */
    val triedBy: CoachMarkAdvance? = null,
    /** On a note: the target only exists for some data, so a screen without it passes at once. */
    val skipsWhenAbsent: Boolean = false,
) {
    val isAction: Boolean get() = kind is CoachMarkStepKind.Action
}

/** What the ledger says right now. Gating and step lists are pure functions of this. */
data class CoachMarkFacts(
    val hasAnyBudget: Boolean = false,
    val hasBudgetThisMonth: Boolean = false,
    val hasAnyAllocation: Boolean = false,
    val hasAllocationThisMonth: Boolean = false,
    val hasRecurringTransaction: Boolean = false,
    val hasAnyTransaction: Boolean = false,
    val hasCreditCard: Boolean = false,
    val hasIncomeThisMonth: Boolean = false,
) {
    val hasAnyData: Boolean
        get() = hasAnyBudget || hasAnyAllocation || hasAnyTransaction || hasCreditCard
}

enum class CoachMarkRunMode {
    /** Started by the app for a new user. Finishing or skipping is remembered. */
    Automatic,

    /** Started from Settings. Only finishing it is remembered, as the guide's check mark. */
    Replay,
}

/** One run through one guide. Immutable: every move returns the next session. */
data class CoachMarkSession(
    val guide: CoachMarkGuideId,
    val mode: CoachMarkRunMode,
    val steps: List<CoachMarkStep>,
    val index: Int = 0,
    /** Steps passed without being shown. The counter on the card must not include them. */
    val skippedStepCount: Int = 0,
) {
    val step: CoachMarkStep get() = steps[index]
    val isLastStep: Boolean get() = index == steps.lastIndex
    val shownPosition: Int get() = index + 1 - skippedStepCount
    val shownTotal: Int get() = steps.size - skippedStepCount

    /** The next session, or null when there was no next step: the guide is finished. */
    fun advanced(): CoachMarkSession? = if (isLastStep) null else copy(index = index + 1)

    /** Passes a step whose result already holds. Null when it was the last one. */
    fun skipped(): CoachMarkSession? = copy(skippedStepCount = skippedStepCount + 1).advanced()

    fun isSatisfied(by: CoachMarkEvent): Boolean =
        step.kind == CoachMarkStepKind.Action(CoachMarkAdvance.Event(by))

    fun isTried(by: CoachMarkEvent): Boolean = step.triedBy == CoachMarkAdvance.Event(by)

    fun wentBack(to: String): CoachMarkSession {
        val target = steps.indexOfFirst { it.id == to }
        return if (target >= 0) copy(index = target) else this
    }
}
