package com.arthurrios.finova.ui.budgets

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

    fun delete(month: YearMonth) {
        viewModelScope.launch { repository.deleteBudget(month) }
    }

    fun toggleValues() {
        val hidden = !_valuesHidden.value
        settings.hideValues = hidden
        _valuesHidden.value = hidden
    }
}
