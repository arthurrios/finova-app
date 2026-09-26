package com.arthurrios.finova.ui.early

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.card.Installments
import com.arthurrios.finova.domain.card.OpenInstallment
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

data class EarlyPaymentUiState(
    val seriesTitle: String = "",
    val installments: List<OpenInstallment> = emptyList(),
    val selected: Set<Long> = emptySet(),
    val date: LocalDate = LocalDate.now(),
    /** The card the series is on; null offers no destination choice. */
    val card: CreditCard? = null,
    val chargeToCard: Boolean = false,
    /** The statement the debit would go on, for the confirmation text. */
    val targetStatement: CreditCardStatement? = null,
    val currencyCode: String = "BRL",
    val valuesHidden: Boolean = false,
    val loaded: Boolean = false,
    val saving: Boolean = false,
    val failed: Boolean = false,
    val done: Boolean = false,
) {
    val selectedTotal: Long get() = installments.filter { it.id in selected }.sumOf { it.amount }
    val allSelected: Boolean get() = installments.isNotEmpty() && selected.size == installments.size
    val canContinue: Boolean get() = selected.isNotEmpty() && !saving
}

/** Port of EarlyPaymentViewModel.swift. */
class EarlyPaymentViewModel(
    private val repository: FinanceRepository,
    private val cards: CardRepository,
    private val settings: UserSettingsStore,
    private val transactionId: Long,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel() {
    private val _state = MutableStateFlow(
        EarlyPaymentUiState(currencyCode = settings.currencyCode, valuesHidden = settings.hideValues, date = today())
    )
    val state: StateFlow<EarlyPaymentUiState> = _state.asStateFlow()
    private var statements: List<CreditCardStatement> = emptyList()

    val minimumDate: LocalDate get() = today()

    init {
        viewModelScope.launch {
            val rows = repository.transactions.first()
            statements = repository.statements.first()
            val row = rows.firstOrNull { it.id == transactionId } ?: return@launch
            val card = Installments.cardId(row, rows)?.let { cards.card(it) }
            _state.update {
                it.copy(
                    seriesTitle = row.title,
                    installments = Installments.payable(row, rows, statements, today()),
                    card = card,
                    // A card series charges the open statement unless the user says otherwise.
                    chargeToCard = card != null,
                    loaded = true,
                )
            }
            refreshTarget()
        }
    }

    fun toggle(id: Long) = _state.update { it.copy(selected = if (id in it.selected) it.selected - id else it.selected + id) }

    fun toggleAll() = _state.update { s -> s.copy(selected = if (s.allSelected) emptySet() else s.installments.map { it.id }.toSet()) }

    fun setChargeToCard(toCard: Boolean) = _state.update { it.copy(chargeToCard = toCard) }

    fun setDate(date: LocalDate) {
        _state.update { it.copy(date = maxOf(date, today())) }
        refreshTarget()
    }

    fun dismissError() = _state.update { it.copy(failed = false) }

    private fun refreshTarget() {
        val s = _state.value
        val card = s.card ?: return
        _state.update { it.copy(targetStatement = Installments.nextOpenStatement(statements, card, s.date, settings.defaultBusinessDayRule)) }
    }

    fun confirm(title: String) {
        val s = _state.value
        if (!s.canContinue) return
        _state.update { it.copy(saving = true) }
        viewModelScope.launch {
            val ok = runCatching {
                repository.payInstallmentsEarly(s.selected.toList(), s.date, s.chargeToCard && s.card != null, title)
            }.isSuccess
            _state.update { it.copy(saving = false, done = ok, failed = !ok) }
        }
    }
}
