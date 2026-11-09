package com.arthurrios.finova.ui.history

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.R
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.AllocationRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.history.BudgetForecast
import com.arthurrios.finova.domain.history.BudgetForecastFigures
import com.arthurrios.finova.domain.history.BudgetForecastMonth
import com.arthurrios.finova.domain.history.BudgetHistory
import com.arthurrios.finova.domain.history.BudgetHistoryFilter
import com.arthurrios.finova.domain.history.BudgetHistoryMonth
import com.arthurrios.finova.domain.history.BudgetHistoryReader
import com.arthurrios.finova.domain.history.BudgetHistorySeries
import com.arthurrios.finova.domain.history.SavingsContributors
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

/** How many months the chart shows, ending at the open month. */
enum class HistorySpan(val months: Int) { SixMonths(6), TwelveMonths(12) }

/** Which months the Saved and "Why" cards count, both ending at the selected month. */
enum class SavingsScope {
    /** From the chosen start up to the selected month: the running total. */
    UpTo,

    /** The selected month alone, so its own savers and overspenders can be read. */
    Only,
}

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
    /** Not remembered: "only" is a closer look at one month, and the screen opens on the running total. */
    val savingsScope: SavingsScope = SavingsScope.UpTo,
    val valuesHidden: Boolean = false,
    val currencyCode: String = "BRL",
    val isLoaded: Boolean = false,
    /** Every expense behind the bars, early-paid installments removed. Filtered per month and filter. */
    val expenses: List<Transaction> = emptyList(),
    /** The last day the open month's "so far" figures count. */
    val today: LocalDate = LocalDate.now(),
    /** Filters left by drilling into the "Why" card, most recent last; the picker starts over. */
    val filterTrail: List<BudgetHistoryFilter> = emptyList(),
    /** The months ahead of the open one, read with the history. */
    val forecast: BudgetForecast = BudgetForecast.Empty,
) {
    /** A category first planned in a month ahead: it has no past to read, only a forecast. */
    private fun isForecastOnly(filter: BudgetHistoryFilter): Boolean =
        filter is BudgetHistoryFilter.Category && history.series(filter) == null && filter.category in forecast.plannedCategories

    private fun fullSeries(filter: BudgetHistoryFilter) = history.series(filter)
        ?: if (isForecastOnly(filter)) BudgetHistorySeries(filter, emptyList()) else history.wholeMonth

    /** The bars on screen: the chosen span, minus leading months with nothing in them. */
    val series: BudgetHistorySeries get() = fullSeries(filter).suffix(span.months).trimmingLeadingEmptyMonths()

    val selectedMonth: BudgetHistoryMonth? get() = series.month(selected) ?: series.months.lastOrNull()

    /**
     * The projected bars after the past ones, for the chosen filter. Never part of [series], so they
     * reach no score, streak or savings figure. Empty when no month ahead has anything for this filter:
     * six blank columns would only squeeze the past bars.
     */
    val forecastMonths: List<BudgetForecastFigures>
        get() = forecast.figures(filter).takeUnless { months -> months.all { it.status == BudgetForecastFigures.Status.Empty } }.orEmpty()

    /**
     * The selected month when it lies ahead. While it does, [selectedMonth] stays on the open month
     * and the Saved figures are not on screen.
     */
    val selectedForecast: BudgetForecastFigures? get() = forecastMonths.firstOrNull { it.month == selected }

    /** The month highlighted on the chart, past or projected. */
    val displayedMonth: YearMonth? get() = selectedForecast?.month ?: selectedMonth?.month

    val filters: List<BudgetHistoryFilter>
        get() = history.filters + forecast.plannedCategories.map { BudgetHistoryFilter.Category(it) }.filter(::isForecastOnly)

    val isEmpty: Boolean get() = history.isEmpty && forecast.isEmpty

    /**
     * The 12-month option only when it would show more than the 6-month one. A ledger with five
     * months of history draws the same bars under both, and a switch that changes nothing reads as broken.
     */
    val offersLongerSpan: Boolean
        get() = fullSeries(filter).suffix(HistorySpan.TwelveMonths.months).trimmingLeadingEmptyMonths().months.size > HistorySpan.SixMonths.months

    /**
     * Saved counts up to the month being read, so moving through the chart shows the running total.
     * The open month never counts, so selecting it counts up to the month before.
     */
    val savingsEnd: YearMonth? get() = selectedMonth?.month

    /** The last month Saved includes: the selected month, or the closed month before an open one. */
    val savingsEndMonth: YearMonth? get() = savingsEnd?.let { end -> history.closedMonths.lastOrNull { it <= end } }

    /** The first month Saved counts: the chosen start, or the selected month itself under [SavingsScope.Only]. */
    val countedStart: YearMonth? get() = if (savingsScope == SavingsScope.Only) savingsEnd else savingsStart

    /**
     * "Only" is on and the selected month is still open. Its figures are what it has left, or is over,
     * up to today - not saved yet - so the screen labels them "so far" and keeps what is left grey.
     */
    val isSoFar: Boolean get() = savingsScope == SavingsScope.Only && selectedMonth?.isCurrent == true

    /** The history the Saved and "Why" figures read: the open month counted so far under [isSoFar]. */
    private val countedHistory: BudgetHistory get() = if (isSoFar) history.countingOpenMonthSoFar(expenses, today) else history

    val savings: BudgetHistorySeries.Savings get() = savings(filter)

    /**
     * Outside allocations counts its named differences too, so its Saved figure is the same number
     * as its row in the list and in the whole month's "Why" card.
     */
    fun savings(filter: BudgetHistoryFilter): BudgetHistorySeries.Savings =
        if (filter == BudgetHistoryFilter.OutsideAllocations) countedHistory.outsideSavings(countedStart, savingsEnd) ?: BudgetHistorySeries.Savings.None
        else countedHistory.series(filter)?.savings(countedStart, savingsEnd) ?: BudgetHistorySeries.Savings.None

    /** What made the Saved figure, over the same months it counts. */
    val contributors: SavingsContributors? get() = countedHistory.contributors(filter, countedStart, savingsEnd)

    /** One month of the chosen filter as the detail under its row: the sum, the expense count, the three biggest. */
    data class MonthDetail(
        val month: BudgetHistoryMonth,
        val expenseCount: Int,
        val biggest: List<Transaction>,
        /** Outside allocations only: the month budget and what the categories got. */
        val budgetSplit: Pair<Long, Long>?,
    )

    fun monthDetail(month: YearMonth): MonthDetail? {
        val bar = history.series(filter)?.month(month) ?: return null
        // Zero-amount rows never count.
        val listed = history.transactions(filter, month, expenses).filter { it.amount > 0 }
        // For Outside allocations the plan is itself a subtraction, and showing it is what explains a
        // large number with no expense behind it.
        val split = if (filter == BudgetHistoryFilter.OutsideAllocations) budgetSplit(month).takeIf { it.first > 0 } else null
        return MonthDetail(bar, listed.size, listed.take(3), split)
    }

    /** One projected month as its card shows it: the figures, the rows already dated, the three biggest. */
    data class ForecastDetail(
        val figures: BudgetForecastFigures,
        val month: BudgetForecastMonth,
        val scheduledCount: Int,
        val biggest: List<Transaction>,
    )

    fun forecastDetail(figures: BudgetForecastFigures): ForecastDetail? {
        val month = forecast.month(figures.month) ?: return null
        val listed = forecast.transactions(filter, figures.month, expenses).filter { it.amount > 0 }
        return ForecastDetail(figures, month, listed.size, listed.take(3))
    }

    /**
     * The balance a projected month's readout leads with: the whole month's only, because a balance
     * does not apply to a category. Null when the month has no balance either.
     */
    fun forecastBalance(figures: BudgetForecastFigures): Long? =
        if (figures.filter == BudgetHistoryFilter.WholeMonth) forecast.month(figures.month)?.projection?.projected else null

    /** A month's budget and what its categories got: the subtraction behind outside figures. */
    fun budgetSplit(month: YearMonth): Pair<Long, Long> =
        (history.wholeMonth.month(month)?.planned ?: 0L) to history.categories.sumOf { it.month(month)?.planned ?: 0L }

    /** The expenses outside every category in [months], biggest first. */
    fun outsideExpenses(months: List<YearMonth>): List<Transaction> =
        months.flatMap { history.transactions(BudgetHistoryFilter.OutsideAllocations, it, expenses) }
            .filter { it.amount > 0 }
            .sortedByDescending { it.amount }

    /** The named parts of the outside remainder, while that filter is chosen. */
    val outsideDifferences: List<BudgetHistory.OutsideDifference>
        get() = if (outsideTiming == null) emptyList() else countedHistory.outsideDifferences(countedStart, savingsEnd)

    /** Opens a part of the "Why" card, remembering where it came from. */
    fun drilled(into: BudgetHistoryFilter): BudgetHistoryUiState =
        if (into == filter) this else copy(filterTrail = filterTrail + filter, filter = into).keepingSelectionVisible()

    fun back(): BudgetHistoryUiState {
        val previous = filterTrail.lastOrNull() ?: return this
        return copy(filterTrail = filterTrail.dropLast(1), filter = previous).keepingSelectionVisible()
    }

    /** A choice from the picker starts over. */
    fun chosen(filter: BudgetHistoryFilter): BudgetHistoryUiState =
        copy(filterTrail = emptyList(), filter = filter).keepingSelectionVisible()

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
        get() = if (history.categories.isEmpty()) null else countedHistory.outsideAllocations(countedStart, savingsEnd)

    /**
     * What the outside series does not explain, since [savingsStart]. Shown under the Saved card
     * while the outside filter is chosen, so that card plus this line equal its row in the list.
     */
    val outsideTiming: Long?
        get() = if (filter == BudgetHistoryFilter.OutsideAllocations) countedHistory.outsideTiming(countedStart, savingsEnd) else null

    /** The month the arrows step to, or null at either end of the bars on screen. */
    fun neighbour(offset: Int): YearMonth? {
        val months = series.months.map { it.month } + forecastMonths.map { it.month }
        val index = months.indexOf(displayedMonth)
        if (index < 0) return null
        return months.getOrNull(index + offset)
    }

    /** Selects a past or projected month on the chart. Any other month changes nothing. */
    fun selecting(month: YearMonth): BudgetHistoryUiState =
        if (series.month(month) != null || forecastMonths.any { it.month == month }) copy(selected = month) else this

    /** A shorter span or a trimmed series can drop the selected month off the chart: select the open month. */
    fun keepingSelectionVisible(): BudgetHistoryUiState {
        if (series.month(selected) != null || selectedForecast != null) return this
        val month = series.months.lastOrNull()?.month ?: forecastMonths.firstOrNull()?.month ?: return this
        return copy(selected = month)
    }

    /**
     * A new read of the ledger. A filter no longer in the window falls back to the whole month, and an
     * entry month older than six months opens the longer span so it is on screen.
     */
    fun withHistory(newHistory: BudgetHistory, firstLoad: Boolean, newForecast: BudgetForecast = forecast): BudgetHistoryUiState {
        var next = copy(history = newHistory, forecast = newForecast, isLoaded = true)
        if (newHistory.series(next.filter) == null && !next.isForecastOnly(next.filter)) next = next.copy(filter = BudgetHistoryFilter.WholeMonth)
        if (firstLoad) {
            val index = newHistory.months.indexOf(next.selected)
            if (index >= 0 && newHistory.months.size - index > HistorySpan.SixMonths.months) next = next.copy(span = HistorySpan.TwelveMonths)
        }
        if (next.selected !in newHistory.months && next.selectedForecast == null) next = next.copy(selected = newHistory.current)
        return next.keepingSelectionVisible()
    }
}

/** A string and the amounts it takes. Kept apart from formatting so the words can be tested. */
data class ForecastText(@param:StringRes val text: Int, val amounts: List<Long> = emptyList())

/** The words a projected month carries. They never say "saved" or "on plan": nothing has happened yet. */
object BudgetForecastText {

    /** The status a projected month carries: an amount when values are visible, a word when not. */
    fun status(month: BudgetForecastFigures, hidden: Boolean): ForecastText = when (month.status) {
        BudgetForecastFigures.Status.Fits ->
            if (hidden) ForecastText(R.string.history_forecast_status_fits)
            else ForecastText(R.string.history_status_left_format, listOf(month.difference))
        BudgetForecastFigures.Status.Short ->
            if (hidden) ForecastText(R.string.history_forecast_status_short)
            else ForecastText(R.string.history_forecast_status_short_format, listOf(-month.difference))
        BudgetForecastFigures.Status.NoPlan, BudgetForecastFigures.Status.Empty -> ForecastText(noPlan(month.filter))
    }

    /** A month with no plan says so in words, so it never reads as a plan of zero. */
    @StringRes
    fun noPlan(filter: BudgetHistoryFilter): Int = when (filter) {
        is BudgetHistoryFilter.Category -> R.string.history_forecast_no_allocation
        BudgetHistoryFilter.WholeMonth, BudgetHistoryFilter.OutsideAllocations -> R.string.history_forecast_no_budget
    }

    /** What TalkBack reads. Opens by saying it is projected, so the amounts are never taken for a result. */
    fun accessibility(month: BudgetForecastFigures, hidden: Boolean, balance: Long? = null): List<ForecastText> = buildList {
        add(ForecastText(R.string.history_forecast_badge))
        if (balance != null) {
            add(if (hidden) ForecastText(R.string.history_forecast_readout_balance) else ForecastText(R.string.history_forecast_a11y_balance_format, listOf(balance)))
        }
        if (!hidden) {
            add(
                if (month.hasPlan) ForecastText(R.string.history_forecast_a11y_expected_of_format, listOf(month.expected, month.planned))
                else ForecastText(R.string.history_forecast_a11y_expected_format, listOf(month.expected))
            )
        }
        add(status(month, hidden))
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
            today = today(),
            savingsStart = settings.budgetHistorySavingsStart(uid),
            valuesHidden = settings.hideValues,
            currencyCode = settings.currencyCode,
        )
    )
    val state: StateFlow<BudgetHistoryUiState> = _state

    init {
        viewModelScope.launch {
            combine(repository.ledgerRows, repository.budgets, repository.balanceOffset, allocations.all, repository.statements) { rows, budgets, offset, allocationRows, statements ->
                Triple(
                    BudgetHistoryReader.read(rows, budgets, offset, allocationRows, today()),
                    BudgetHistoryReader.forecast(rows, budgets, offset, allocationRows, statements, today()),
                    rows.filter { it.type == TransactionType.Expense && !it.isCreditCardStatement && !it.isSettledEarly && !it.isStatementPayment },
                )
            }.collect { (history, forecast, expenses) ->
                _state.update { it.withHistory(history, firstLoad = !it.isLoaded, newForecast = forecast).copy(expenses = expenses, today = today()) }
            }
        }
    }

    fun selectFilter(filter: BudgetHistoryFilter) = _state.update { it.chosen(filter) }

    fun drill(into: BudgetHistoryFilter) = _state.update { it.drilled(into) }

    fun goBack() = _state.update { it.back() }

    fun selectSpan(span: HistorySpan) = _state.update {
        if (it.span == span) it else it.copy(span = span).keepingSelectionVisible()
    }

    fun selectMonth(month: YearMonth) = _state.update { it.selecting(month) }

    fun selectSavingsStart(start: YearMonth?) {
        settings.setBudgetHistorySavingsStart(uid, start)
        _state.update { it.copy(savingsStart = start) }
    }

    fun selectSavingsScope(scope: SavingsScope) = _state.update { it.copy(savingsScope = scope) }

    fun toggleValues() {
        val hidden = !_state.value.valuesHidden
        settings.hideValues = hidden
        _state.update { it.copy(valuesHidden = hidden) }
    }
}
