package com.arthurrios.finova.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionMode
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.domain.series.SeriesRules
import com.arthurrios.finova.domain.time.BusinessDayAdjuster
import com.arthurrios.finova.domain.time.SeriesMonths
import com.arthurrios.finova.ui.addtransaction.AddMode
import com.arthurrios.finova.ui.addtransaction.AddTransactionRequest
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
    private val cardRepository: CardRepository,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel(), DashboardActions {

    private val selectedMonth = MutableStateFlow(SeriesMonths.todayIndex())
    private val valuesHidden = MutableStateFlow(settings.hideValues)

    // Kept for the day slider, which asks for balances as the user drags.
    private var latestRows: List<Transaction> = emptyList()
    private var latestOffset: Long = 0

    val state: StateFlow<DashboardUiState> = combine(
        repository.ledgerRows,
        combine(repository.budgets, repository.balanceOffset, cardRepository.activeCards, ::Triple),
        selectedMonth,
        valuesHidden,
    ) { rows, (budgets, offset, cards), selected, hidden ->
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
            defaultBusinessDayRule = settings.defaultBusinessDayRule,
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
                        .map { it.toRowUi() },
                )
            },
            selectedMonth = selected,
            isLoading = false,
            cards = cards,
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

    override fun currentBalanceToday(): Long = LedgerCalculator.balanceOn(latestRows, latestOffset, today())

    /** Port of AdjustBalanceModalViewController.didTapConfirm: the gap goes into the offset. */
    override fun onConfirmAdjustBalance(realBalance: Long, appBalance: Long) {
        val newOffset = realBalance - appBalance + latestOffset
        viewModelScope.launch { repository.setBalanceOffset(newOffset) }
    }

    override fun onToggleValues() {
        val hidden = !valuesHidden.value
        settings.hideValues = hidden
        valuesHidden.value = hidden
    }

    /** Port of AddTransactionModalViewModel's add paths (no card yet). */
    override fun onSaveTransaction(request: AddTransactionRequest) {
        val draft = request.draft
        viewModelScope.launch {
            when (request.mode) {
                AddMode.Normal -> {
                    val date = BusinessDayAdjuster.adjust(draft.date, draft.rule)
                    repository.add(
                        Transaction(
                            title = draft.title,
                            category = draft.category,
                            type = draft.type,
                            amount = draft.amount,
                            date = date,
                            // A one-off counts in the month it actually lands in.
                            budgetMonth = YearMonth.from(date),
                            businessDayRule = draft.rule,
                            unadjustedDate = draft.date,
                            creditCardId = draft.creditCardId,
                        )
                    )
                }
                AddMode.Recurring -> repository.addRecurring(draft, today())
                AddMode.Installments -> repository.addInstallments(draft, request.installments)
            }
            // Open the month the new transaction lands in, as iOS scrolls the carousel there.
            val index = SeriesMonths.carouselMonths(YearMonth.from(today())).indexOf(YearMonth.from(draft.date))
            if (index >= 0) selectedMonth.value = index
        }
    }

    override fun onDeleteTransaction(row: TransactionRowUi, option: SeriesDeleteOption) {
        viewModelScope.launch { repository.delete(row.id, option) }
    }
}
