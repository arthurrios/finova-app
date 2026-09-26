package com.arthurrios.finova.ui.details

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.card.Installments
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.domain.series.SeriesEditOption
import com.arthurrios.finova.domain.series.SeriesKind
import com.arthurrios.finova.domain.series.SeriesRules
import com.arthurrios.finova.domain.series.TransactionDraft
import com.arthurrios.finova.ui.addtransaction.AddMode
import com.arthurrios.finova.ui.addtransaction.AddTransactionRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate

data class TransactionDetailsUiState(
    val row: Transaction? = null,
    val kind: SeriesKind = SeriesKind.Simple,
    val currencyCode: String = "BRL",
    val valuesHidden: Boolean = false,
    /** The series' installments, in order (installment rows only). */
    val installments: List<Transaction> = emptyList(),
    val totalValue: Long? = null,
    val lastInstallment: LocalDate? = null,
    /** What the edit sheet opens with. */
    val editRequest: AddTransactionRequest? = null,
    /** True once the row is gone (deleted, or rebuilt by an installment edit). */
    val gone: Boolean = false,
    /** Installments of this series that can still be paid early. */
    val payableCount: Int = 0,
    /** What cancelling the purchase would credit (0: nothing left to cancel, or already cancelled). */
    val cancelAmount: Long = 0,
    val cancelCount: Int = 0,
    /** This row is an early-payment debit; these are the installments it paid. */
    val earlyPaidInstallments: List<Transaction>? = null,
    /** This row is a cancellation credit; these are the installments it refunds. */
    val refundedInstallments: List<Transaction>? = null,
)

/** Port of TransactionDetailsViewModel.swift (cards, early payment and cancellation come later). */
class TransactionDetailsViewModel(
    private val repository: FinanceRepository,
    private val settings: UserSettingsStore,
    private val transactionId: Long,
    cardRepository: CardRepository,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel() {

    /** The cards the edit sheet offers. */
    val cards: StateFlow<List<CreditCard>> = cardRepository.activeCards
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val defaultRule get() = settings.defaultBusinessDayRule

    private val valuesHidden = MutableStateFlow(settings.hideValues)
    private var allRows: List<Transaction> = emptyList()
    private var loaded = false

    val state: StateFlow<TransactionDetailsUiState> = combine(repository.transactions, repository.statements, valuesHidden) { rows, statements, hidden ->
        allRows = rows
        val row = rows.firstOrNull { it.id == transactionId }
        if (row == null) return@combine TransactionDetailsUiState(gone = loaded, valuesHidden = hidden)
        loaded = true
        val kind = SeriesRules.kindOf(row)
        val seriesId = SeriesRules.seriesId(row)
        val installments = if (kind == SeriesKind.Installments) {
            rows.filter { it.parentTransactionId == seriesId && it.installmentNumber != null }.sortedBy { it.installmentNumber }
        } else emptyList()
        val parent = rows.firstOrNull { it.id == seriesId }
        val refundable = if (kind == SeriesKind.Installments) Installments.refundable(row, rows, statements, today()) else emptyList()
        TransactionDetailsUiState(
            row = row,
            kind = kind,
            currencyCode = settings.currencyCode,
            valuesHidden = hidden,
            installments = installments,
            totalValue = if (kind == SeriesKind.Installments) row.originalAmount else null,
            lastInstallment = installments.lastOrNull()?.date,
            editRequest = editRequestFor(row, kind, parent, installments),
            payableCount = if (kind == SeriesKind.Installments) Installments.payable(row, rows, statements, today()).size else 0,
            cancelAmount = refundable.sumOf { it.amount },
            cancelCount = refundable.size,
            earlyPaidInstallments = if (row.isEarlyPayment) rows.filter { it.settledByTransactionId == row.id }.sortedBy { it.installmentNumber } else null,
            refundedInstallments = if (row.isCancellationRefund) rows.filter { it.cancelledByTransactionId == row.id }.sortedBy { it.installmentNumber } else null,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TransactionDetailsUiState())

    /**
     * An installment is edited as its whole series, from the series' start (iOS pre-fills the start
     * date, not this installment's, or the rebuild would restart the series at this installment).
     */
    private fun editRequestFor(row: Transaction, kind: SeriesKind, parent: Transaction?, installments: List<Transaction>) =
        when (kind) {
            SeriesKind.Installments -> AddTransactionRequest(
                draft = TransactionDraft(
                    title = row.title,
                    category = row.category,
                    type = row.type,
                    amount = row.originalAmount ?: installments.sumOf { it.amount },
                    date = installments.firstOrNull()?.unadjusted ?: parent?.date ?: row.unadjusted,
                    rule = row.businessDayRule,
                    creditCardId = row.creditCardId,
                ),
                mode = AddMode.Installments,
                installments = row.totalInstallments ?: installments.size,
            )
            else -> AddTransactionRequest(
                draft = TransactionDraft(
                    row.title, row.category, row.type, row.amount, row.unadjusted, row.businessDayRule,
                    creditCardId = row.creditCardId,
                ),
                mode = if (kind == SeriesKind.Recurring) AddMode.Recurring else AddMode.Normal,
                installments = 0,
            )
        }

    fun toggleValues() {
        val hidden = !valuesHidden.value
        settings.hideValues = hidden
        valuesHidden.value = hidden
    }

    fun delete(option: SeriesDeleteOption) {
        viewModelScope.launch { repository.delete(transactionId, option) }
    }

    /** Set when an action failed; the screen shows the matching error. */
    private val _failure = MutableStateFlow<Int?>(null)
    val failure: StateFlow<Int?> = _failure

    fun clearFailure() {
        _failure.value = null
    }

    /** Port of TransactionDetailsViewModel.cancelPurchase. */
    fun cancelPurchase(title: String, @androidx.annotation.StringRes errorRes: Int) {
        viewModelScope.launch {
            runCatching { repository.cancelInstallmentPurchase(transactionId, title, today()) }
                .onFailure { _failure.value = errorRes }
        }
    }

    /**
     * Undoes an early payment or a cancellation by deleting this row: the delete puts its
     * installments back, as on iOS.
     */
    fun undo() = delete(SeriesDeleteOption.ThisOnly)

    /** A one-off saves straight away; series edits come through [saveRecurring] / [saveInstallments]. */
    fun saveOneOff(request: AddTransactionRequest) {
        val row = state.value.row ?: return
        viewModelScope.launch { repository.update(SeriesRules.editOneOff(row, request.draft)) }
    }

    fun saveRecurring(request: AddTransactionRequest, option: SeriesEditOption) {
        val row = state.value.row ?: return
        viewModelScope.launch { repository.applyEdit(SeriesRules.editRecurring(row, request.draft, option, allRows)) }
    }

    fun saveInstallments(request: AddTransactionRequest) {
        val row = state.value.row ?: return
        viewModelScope.launch { repository.replaceInstallments(SeriesRules.seriesId(row), request.draft, request.installments) }
    }
}
