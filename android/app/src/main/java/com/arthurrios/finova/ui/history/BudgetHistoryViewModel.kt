package com.arthurrios.finova.ui.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.AllocationRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.history.BudgetHistory
import com.arthurrios.finova.domain.history.BudgetHistoryFilter
import com.arthurrios.finova.domain.history.BudgetHistoryMonth
import com.arthurrios.finova.domain.history.BudgetHistoryReader
import com.arthurrios.finova.domain.history.BudgetHistorySeries
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

/** How many months the chart shows, ending at the open month. */
enum class HistorySpan(val months: Int) { SixMonths(6), TwelveMonths(12) }

/**
 * What the budget history screen draws. Pure: every derived figure is read from [history] and the
 * user's choices, so the selection rules are testable without a database.
 */
data class BudgetHistoryUiState(
    val history: BudgetHistory = BudgetHistory.Empty,
    val filter: BudgetHistoryFilter = BudgetHistoryFilter.WholeMonth,
    val span: HistorySpan = HistorySpan.SixMonths,
    val selected: YearMonth = YearMonth.now(),
    /** First closed month counted in "saved". Null counts from the first month that had a plan. */
    val savingsStart: YearMonth? = null,
    val valuesHidden: Boolean = false,
    val currencyCode: String = "BRL",
    val isLoaded: Boolean = false,
) {
    private fun fullSeries(filter: BudgetHistoryFilter) = history.series(filter) ?: history.wholeMonth

    /** The bars on screen: the chosen span, minus leading months with nothing in them. */
    val series: BudgetHistorySeries get() = fullSeries(filter).suffix(span.months).trimmingLeadingEmptyMonths()

    val selectedMonth: BudgetHistoryMonth? get() = series.month(selected) ?: series.months.lastOrNull()

    val filters: List<BudgetHistoryFilter> get() = history.filters

    val isEmpty: Boolean get() = history.isEmpty

    /**
     * The 12-month option only when it would show more than the 6-month one. A ledger with five
     * months of history draws the same bars under both, and a switch that changes nothing reads as broken.
     */
    val offersLongerSpan: Boolean
        get() = fullSeries(filter).suffix(HistorySpan.TwelveMonths.months).trimmingLeadingEmptyMonths().months.size > HistorySpan.SixMonths.months

    val savings: BudgetHistorySeries.Savings get() = savings(filter)

    fun savings(filter: BudgetHistoryFilter): BudgetHistorySeries.Savings =
        history.series(filter)?.savings(savingsStart) ?: BudgetHistorySeries.Savings.None

    /**
     * Closed months a savings start can be set to: from the first month any filter had a plan. A start
     * before that counts nothing more than "since the start" does.
     */
    val savingsStartOptions: List<YearMonth>
        get() {
            val first = (listOf(history.wholeMonth) + history.categories).mapNotNull { it.scoredMonths.firstOrNull()?.month }.minOrNull()
                ?: return emptyList()
            return history.closedMonths.filter { it >= first }
        }

    /** The remainder row under the categories. Null with no categories: nothing to reconcile. */
    val outsideAllocations: Long?
        get() = if (history.categories.isEmpty()) null else history.outsideAllocations(savingsStart)

    /**
     * What the outside series does not explain, since [savingsStart]. Shown under the Saved card
     * while the outside filter is chosen, so that card plus this line equal its row in the list.
     */
    val outsideTiming: Long?
        get() = if (filter == BudgetHistoryFilter.OutsideAllocations) history.outsideTiming(savingsStart) else null

    /** The month the arrows step to, or null at either end of the bars on screen. */
    fun neighbour(offset: Int): YearMonth? {
        val months = series.months
        val index = months.indexOfFirst { it.month == selectedMonth?.month }
        if (index < 0) return null
        return months.getOrNull(index + offset)?.month
    }

    /** A shorter span or a trimmed series can drop the selected month off the chart: select the open month. */
    fun keepingSelectionVisible(): BudgetHistoryUiState {
        if (series.month(selected) != null) return this
        val last = series.months.lastOrNull() ?: return this
        return copy(selected = last.month)
    }

    /**
     * A new read of the ledger. A filter no longer in the window falls back to the whole month, and an
     * entry month older than six months opens the longer span so it is on screen.
     */
    fun withHistory(newHistory: BudgetHistory, firstLoad: Boolean): BudgetHistoryUiState {
        var next = copy(history = newHistory, isLoaded = true)
        if (newHistory.series(next.filter) == null) next = next.copy(filter = BudgetHistoryFilter.WholeMonth)
        if (firstLoad) {
            val index = newHistory.months.indexOf(next.selected)
            if (index >= 0 && newHistory.months.size - index > HistorySpan.SixMonths.months) next = next.copy(span = HistorySpan.TwelveMonths)
        }
        if (next.selected !in newHistory.months) next = next.copy(selected = newHistory.current)
        return next.keepingSelectionVisible()
    }
}

/**
 * Port of BudgetHistoryViewModel. Reads the ledger as a stream, so an edit made on a screen opened
 * from here shows on return, as iOS reloads on appear.
 */
class BudgetHistoryViewModel(
    repository: FinanceRepository,
    allocations: AllocationRepository,
    private val settings: UserSettingsStore,
    private val uid: String,
    filter: BudgetHistoryFilter = BudgetHistoryFilter.WholeMonth,
    month: YearMonth? = null,
    today: () -> LocalDate = LocalDate::now,
) : ViewModel() {

    private val _state = MutableStateFlow(
        BudgetHistoryUiState(
            filter = filter,
            selected = month ?: YearMonth.from(today()),
            savingsStart = settings.budgetHistorySavingsStart(uid),
            valuesHidden = settings.hideValues,
            currencyCode = settings.currencyCode,
        )
    )
    val state: StateFlow<BudgetHistoryUiState> = _state

    init {
        viewModelScope.launch {
            combine(repository.ledgerRows, repository.budgets, repository.balanceOffset, allocations.all) { rows, budgets, offset, allocationRows ->
                BudgetHistoryReader.read(rows, budgets, offset, allocationRows, today())
            }.collect { history ->
                _state.update { it.withHistory(history, firstLoad = !it.isLoaded) }
            }
        }
    }

    fun selectFilter(filter: BudgetHistoryFilter) = _state.update {
        if (it.filter == filter) it else it.copy(filter = filter).keepingSelectionVisible()
    }

    fun selectSpan(span: HistorySpan) = _state.update {
        if (it.span == span) it else it.copy(span = span).keepingSelectionVisible()
    }

    fun selectMonth(month: YearMonth) = _state.update {
        if (it.series.month(month) == null) it else it.copy(selected = month)
    }

    fun selectSavingsStart(start: YearMonth?) {
        settings.setBudgetHistorySavingsStart(uid, start)
        _state.update { it.copy(savingsStart = start) }
    }

    fun toggleValues() {
        val hidden = !_state.value.valuesHidden
        settings.hideValues = hidden
        _state.update { it.copy(valuesHidden = hidden) }
    }
}
