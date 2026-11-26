package com.arthurrios.finova.ui.budgets

import com.arthurrios.finova.domain.budget.BudgetRange
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
) : ViewModel() {

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
        viewModelScope.launch { repository.setBudget(budget) }
        return true
    }

    fun confirmOverwrite() {
        val budget = _pendingOverwrite.value ?: return
        _pendingOverwrite.value = null
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

    /** Answers the conflict question: true replaces those months, false fills only the empty ones. */
    fun resolveRange(replaceExisting: Boolean) {
        val pending = _pendingRange.value ?: return
        _pendingRange.value = null
        writeRange(pending.start, pending.end, pending.amount, replaceExisting)
    }

    fun cancelRange() {
        _pendingRange.value = null
    }

    private fun writeRange(start: YearMonth, end: YearMonth, amount: Long, replaceExisting: Boolean) {
        val months = BudgetRange.monthsToWrite(budgets.value.map { it.month }, start, end, replaceExisting)
        viewModelScope.launch { repository.setBudgets(months, amount) }
    }

    /** What comes in during a month, which the guide offers as its budget. Zero with no month. */
    fun incomeOf(month: YearMonth?): kotlinx.coroutines.flow.Flow<Long> =
        repository.transactions.map { rows -> month?.let { BudgetSuggestion.monthlyIncome(rows, it) } ?: 0L }

    fun delete(month: YearMonth) {
        viewModelScope.launch { repository.deleteBudget(month) }
    }

    fun toggleValues() {
        val hidden = !_valuesHidden.value
        settings.hideValues = hidden
        _valuesHidden.value = hidden
    }
}
