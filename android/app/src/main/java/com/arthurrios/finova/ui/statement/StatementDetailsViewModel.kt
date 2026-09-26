package com.arthurrios.finova.ui.statement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.card.StatementBook
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.ui.dashboard.TransactionRowUi
import com.arthurrios.finova.ui.dashboard.toRowUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate

data class StatementDetailsUiState(
    val card: CreditCard? = null,
    val statement: CreditCardStatement? = null,
    /** The purchases and credits on the statement, newest first. */
    val rows: List<TransactionRowUi> = emptyList(),
    /** What the statement charges: its purchases minus credits, less credit carried in. */
    val total: Long = 0,
    /** Credit from the card's earlier statements that lowers this one (zero or negative). */
    val carriedIn: Long = 0,
    /** Credit this statement passes on to the next one (zero or negative). */
    val carriedOut: Long = 0,
    val currencyCode: String = "BRL",
    val valuesHidden: Boolean = false,
    /** True once the statement is gone (its last row was deleted). */
    val gone: Boolean = false,
) {
    /** The day after the previous cycle closed, through this closing date. */
    val periodStart: LocalDate? get() = statement?.closingDate?.minusMonths(1)?.plusDays(1)
}

/** Port of StatementDetailsViewModel.swift. */
class StatementDetailsViewModel(
    private val repository: FinanceRepository,
    private val cards: CardRepository,
    private val settings: UserSettingsStore,
    private val statementId: Long,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel() {
    private val valuesHidden = MutableStateFlow(settings.hideValues)
    private val card = MutableStateFlow<CreditCard?>(null)
    private var loaded = false

    val state: StateFlow<StatementDetailsUiState> =
        combine(repository.statements, repository.transactions, card, valuesHidden) { statements, rows, card, hidden ->
            val statement = statements.firstOrNull { it.id == statementId }
                ?: return@combine StatementDetailsUiState(gone = loaded, valuesHidden = hidden)
            loaded = true
            if (card?.id != statement.creditCardId) loadCard(statement.creditCardId)
            val charge = StatementBook.charges(statements.filter { it.creditCardId == statement.creditCardId }, rows)[statementId]
            StatementDetailsUiState(
                card = card,
                statement = statement,
                rows = StatementBook.members(statementId, rows)
                    .sortedWith(compareByDescending<com.arthurrios.finova.domain.model.Transaction> { it.date }.thenByDescending { it.id })
                    .map { it.toRowUi() },
                total = charge?.charged ?: 0,
                carriedIn = charge?.carriedIn ?: 0,
                carriedOut = charge?.carriedOut ?: 0,
                currencyCode = settings.currencyCode,
                valuesHidden = hidden,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), StatementDetailsUiState())

    val statusToday: LocalDate get() = today()

    private fun loadCard(id: Long) {
        viewModelScope.launch { card.value = cards.card(id) }
    }

    fun markAsPaid() {
        val total = state.value.total
        viewModelScope.launch { repository.markStatementPaid(statementId, total, today()) }
    }

    fun delete(row: TransactionRowUi, option: SeriesDeleteOption) {
        viewModelScope.launch { repository.delete(row.id, option) }
    }

    fun toggleValues() {
        val hidden = !valuesHidden.value
        settings.hideValues = hidden
        valuesHidden.value = hidden
    }
}
