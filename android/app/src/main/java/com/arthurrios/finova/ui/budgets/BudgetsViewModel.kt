package com.arthurrios.finova.ui.budgets

import com.arthurrios.finova.domain.budget.BudgetRange
import com.arthurrios.finova.domain.budget.BudgetFollowsIncome
import com.arthurrios.finova.domain.coachmarks.BudgetSuggestion
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.model.Budget
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.YearMonth

/** Port of BudgetsViewModel.swift plus the confirmations BudgetsViewController asks for. */
class BudgetsViewModel(
    private val repository: FinanceRepository,
    private val settings: UserSettingsStore,
    initialMonth: YearMonth?,
    /** "Budget follows income"; null in previews and tests. */
    private val followIncome: com.arthurrios.finova.data.BudgetFollowsIncomeService? = null,
) : ViewModel() {

    val followSettings: StateFlow<BudgetFollowsIncome.Settings> =
        followIncome?.settings ?: MutableStateFlow(BudgetFollowsIncome.Settings())

    /** Counted income per month, for each row's "80% of income" note. */
    val incomeByMonth: StateFlow<Map<YearMonth, Long>> = repository.transactions
        .map(BudgetFollowsIncome::incomeByMonth)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    init {
        followIncome?.reload()
        viewModelScope.launch { followIncome?.recompute(repository) }
    }

    /** Whether [month]'s budget is set from income right now. */
    fun follows(month: YearMonth): Boolean =
        BudgetFollowsIncome.follows(month, followSettings.value, incomeByMonth.value, YearMonth.now())

    fun enableFollow(includePastMonths: Boolean) {
        val service = followIncome ?: return
        viewModelScope.launch { service.enable(repository, followSettings.value.percent, includePastMonths) }
    }

    fun disableFollow() {
        followIncome?.disable()
    }

    fun setFollowPercent(percent: Int) {
        val service = followIncome ?: return
        viewModelScope.launch { service.setPercent(repository, percent) }
    }

    /** A fixed month inside the range follows income again. */
    fun rejoin(month: YearMonth) {
        val service = followIncome ?: return
        viewModelScope.launch { service.optIn(repository, month) }
    }

    /** A month opted out while the switch is on, inside its range: it can rejoin instead of being deleted. */
    fun isFixedInRange(month: YearMonth): Boolean {
        val s = followSettings.value
        return s.isEnabled && month >= (s.startMonth ?: YearMonth.now()) && month in s.optedOutMonths
    }

    /** A budget typed by hand while the switch is on keeps that month fixed. */
    private fun keepFixed(months: Collection<YearMonth>) = followIncome?.optOut(months)

    /** Newest month first, as the iOS table lists them. */
    val budgets: StateFlow<List<Budget>> = repository.budgets
        .map { list -> list.sortedByDescending { it.month } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val currencyCode: String get() = settings.currencyCode

    private val _valuesHidden = MutableStateFlow(settings.hideValues)
    val valuesHidden: StateFlow<Boolean> = _valuesHidden.asStateFlow()

    /** Opening from a month's "Set budget" pre-fills that month. */
    val initialMonth: YearMonth? = initialMonth

    /** A save that would overwrite a month's budget, waiting for "Update". */
    private val _pendingOverwrite = MutableStateFlow<Budget?>(null)
    val pendingOverwrite: StateFlow<Budget?> = _pendingOverwrite.asStateFlow()

    /** Returns true when saved straight away (the form can clear). */
    fun save(month: YearMonth, amount: Long): Boolean {
        val budget = Budget(month, amount)
        if (budgets.value.any { it.month == month }) {
            _pendingOverwrite.value = budget
            return false
        }
        keepFixed(listOf(month))
        viewModelScope.launch { repository.setBudget(budget) }
        return true
    }

    fun confirmOverwrite() {
        val budget = _pendingOverwrite.value ?: return
        _pendingOverwrite.value = null
        keepFixed(listOf(budget.month))
        viewModelScope.launch { repository.setBudget(budget) }
    }

    fun cancelOverwrite() {
        _pendingOverwrite.value = null
    }

    /** A many-month save that meets months with a budget, waiting for "Replace" or "Keep". */
    data class PendingRange(val start: YearMonth, val end: YearMonth, val amount: Long, val existing: List<YearMonth>)

    private val _pendingRange = MutableStateFlow<PendingRange?>(null)
    val pendingRange: StateFlow<PendingRange?> = _pendingRange.asStateFlow()

    /**
     * Saves [amount] for every month from [start] through [end]. Returns true when saved straight
     * away (the form can clear); false when some months already have a budget and the user must
     * pick "Replace them" or "Keep existing" first.
     */
    fun saveRange(start: YearMonth, end: YearMonth, amount: Long): Boolean {
        val existing = BudgetRange.existingIn(budgets.value.map { it.month }, start, end)
        if (existing.isNotEmpty()) {
            _pendingRange.value = PendingRange(start, end, amount, existing)
            return false
        }
        writeRange(start, end, amount, replaceExisting = true)
        return true
    }

    /**
     * Answers the conflict question: true replaces those months, false fills only the empty ones.
     * Takes the question itself: the dialog dismisses (clearing [pendingRange]) before it answers.
     */
    fun resolveRange(pending: PendingRange, replaceExisting: Boolean) {
        _pendingRange.value = null
        writeRange(pending.start, pending.end, pending.amount, replaceExisting)
    }

    fun cancelRange() {
        _pendingRange.value = null
    }

    private fun writeRange(start: YearMonth, end: YearMonth, amount: Long, replaceExisting: Boolean) {
        val months = BudgetRange.monthsToWrite(budgets.value.map { it.month }, start, end, replaceExisting)
        keepFixed(months)
        viewModelScope.launch { repository.setBudgets(months, amount) }
    }

    /** What comes in during a month, which the guide offers as its budget. Zero with no month. */
    fun incomeOf(month: YearMonth?): kotlinx.coroutines.flow.Flow<Long> =
        repository.transactions.map { rows -> month?.let { BudgetSuggestion.monthlyIncome(rows, it) } ?: 0L }

    fun delete(month: YearMonth) {
        // Deleting a month that follows income keeps it empty: without the opt-out the next
        // recompute would write it straight back.
        if (follows(month)) keepFixed(listOf(month))
        viewModelScope.launch { repository.deleteBudget(month) }
    }

    fun toggleValues() {
        val hidden = !_valuesHidden.value
        settings.hideValues = hidden
        _valuesHidden.value = hidden
    }
}
