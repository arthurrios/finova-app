package com.arthurrios.finova.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionMode
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.domain.series.SeriesRules
import com.arthurrios.finova.domain.time.SeriesMonths
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

/**
 * Port of DashboardViewModel.swift. The database streams are combined into month pages every time
 * something changes, so there is no cache to invalidate (iOS keeps a 60-second one).
 */
class DashboardViewModel(
    private val repository: FinanceRepository,
    private val settings: UserSettingsStore,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel(), DashboardActions {

    private val selectedMonth = MutableStateFlow(SeriesMonths.todayIndex())
    private val valuesHidden = MutableStateFlow(settings.hideValues)

    // Kept for the day slider, which asks for balances as the user drags.
    private var latestRows: List<Transaction> = emptyList()
    private var latestOffset: Long = 0

    val state: StateFlow<DashboardUiState> = combine(
        repository.transactions,
        repository.budgets,
        repository.balanceOffset,
        selectedMonth,
        valuesHidden,
    ) { rows, budgets, offset, selected, hidden ->
        latestRows = rows
        latestOffset = offset
        val day = today()
        val thisMonth = YearMonth.from(day)
        val months = SeriesMonths.carouselMonths(thisMonth)
        val summaries = LedgerCalculator.monthlySummaries(rows, budgets, offset, months, day)
        val listed = rows.filter(FinanceRepository::isListed).groupBy { YearMonth.from(it.date) }
        DashboardUiState(
            // iOS falls back to "User" when it has no name.
            userName = settings.currentUserName()?.takeIf { it.isNotBlank() } ?: "User",
            currencyCode = settings.currencyCode,
            valuesHidden = hidden,
            months = summaries.map { summary ->
                MonthPageUi(
                    month = summary.month,
                    isCurrentMonth = summary.month == thisMonth,
                    isPastMonth = summary.month < thisMonth,
                    usedValue = summary.usedValue,
                    budgetLimit = summary.budgetLimit,
                    finalBalance = summary.finalBalance,
                    currentBalance = summary.currentBalance,
                    transactions = listed[summary.month].orEmpty()
                        .sortedWith(compareByDescending<Transaction> { it.date }.thenByDescending { it.id })
                        .map { it.toRow() },
                )
            },
            selectedMonth = selected,
            isLoading = false,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DashboardUiState(selectedMonth = SeriesMonths.todayIndex()))

    init {
        // iOS fills in recurring months after every dashboard load; once per open is enough here,
        // since new series generate their months when they are created.
        viewModelScope.launch { repository.materializeRecurring(today()) }
    }

    override fun onSelectMonth(index: Int) {
        selectedMonth.value = index
    }

    override fun balanceForDay(page: MonthPageUi, day: Int): Long =
        LedgerCalculator.balanceOn(latestRows, latestOffset, page.month.atDay(day.coerceIn(1, page.month.lengthOfMonth())))

    override fun onToggleValues() {
        val hidden = !valuesHidden.value
        settings.hideValues = hidden
        valuesHidden.value = hidden
    }

    override fun onDeleteTransaction(row: TransactionRowUi, option: SeriesDeleteOption) {
        viewModelScope.launch { repository.delete(row.id, option) }
    }

    private fun Transaction.toRow() = TransactionRowUi(
        id = id,
        title = title,
        date = date,
        amount = amount,
        isIncome = type == TransactionType.Income,
        icon = category.icon(type),
        mode = when (mode) {
            TransactionMode.Recurring -> TransactionModeUi.Recurring
            TransactionMode.Installments -> TransactionModeUi.Installments
            TransactionMode.Normal -> TransactionModeUi.Normal
        },
        installmentNumber = installmentNumber,
        totalInstallments = totalInstallments,
        isCreditCard = creditCardId != null,
        isSettledEarly = isSettledEarly,
        seriesKind = SeriesRules.kindOf(this),
    )
}
