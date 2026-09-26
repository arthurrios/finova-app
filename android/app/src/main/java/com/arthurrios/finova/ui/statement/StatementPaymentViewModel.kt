package com.arthurrios.finova.ui.statement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.card.StatementPayments
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

data class StatementPaymentUiState(
    val card: CreditCard? = null,
    val statement: CreditCardStatement? = null,
    /** What the statement owes now. */
    val remaining: Long = 0,
    val amount: Long = 0,
    val payToday: Boolean = true,
    /** The scheduled date (never before today). */
    val scheduledDate: LocalDate = LocalDate.now(),
    val currencyCode: String = "BRL",
    val valuesHidden: Boolean = false,
    val saving: Boolean = false,
    val failed: Boolean = false,
    val done: Boolean = false,
) {
    val balanceAfter: Long get() = (remaining - amount).coerceAtLeast(0)
    val paysInFull: Boolean get() = amount > 0 && amount >= remaining
    val exceedsBalance: Boolean get() = amount > remaining
    val canContinue: Boolean get() = amount in 1..remaining && !saving
    fun paymentDate(today: LocalDate): LocalDate = if (payToday) today else maxOf(scheduledDate, today)
    /** "Oct/26": which invoice, by its due date (iOS `monthYearShortFormatter`). */
    val statementLabel: String
        get() = statement?.dueDate?.format(DateTimeFormatter.ofPattern("MMM/yy", Locale.getDefault())).orEmpty()
}

/** Port of StatementPaymentViewModel.swift. */
class StatementPaymentViewModel(
    private val repository: FinanceRepository,
    private val cards: CardRepository,
    private val settings: UserSettingsStore,
    private val statementId: Long,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel() {
    private val _state = MutableStateFlow(
        StatementPaymentUiState(currencyCode = settings.currencyCode, valuesHidden = settings.hideValues, scheduledDate = today())
    )
    val state: StateFlow<StatementPaymentUiState> = _state.asStateFlow()

    val minimumDate: LocalDate get() = today()

    init {
        viewModelScope.launch {
            val statement = repository.statements.first().firstOrNull { it.id == statementId } ?: return@launch
            val remaining = StatementPayments.remaining(statementId, repository.transactions.first())
            // The full balance is pre-filled, as on iOS.
            _state.update {
                it.copy(card = cards.card(statement.creditCardId), statement = statement, remaining = remaining, amount = remaining)
            }
        }
    }

    fun setAmount(cents: Long) = _state.update { it.copy(amount = cents) }
    fun setPayToday(today: Boolean) = _state.update { it.copy(payToday = today) }
    fun setScheduledDate(date: LocalDate) = _state.update { it.copy(scheduledDate = maxOf(date, today())) }
    fun dismissError() = _state.update { it.copy(failed = false) }

    fun toggleValues() {
        val hidden = !_state.value.valuesHidden
        settings.hideValues = hidden
        _state.update { it.copy(valuesHidden = hidden) }
    }

    fun confirm(debitTitle: String, creditTitle: String) {
        val s = _state.value
        if (!s.canContinue) return
        _state.update { it.copy(saving = true) }
        viewModelScope.launch {
            val ok = runCatching {
                repository.payStatement(statementId, s.amount, s.paymentDate(today()), debitTitle, creditTitle)
            }.isSuccess
            _state.update { it.copy(saving = false, done = ok, failed = !ok) }
        }
    }
}
