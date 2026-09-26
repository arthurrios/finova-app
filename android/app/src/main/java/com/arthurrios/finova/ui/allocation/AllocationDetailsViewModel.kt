package com.arthurrios.finova.ui.allocation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.AllocationRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.allocation.AllocationEditScope
import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.AllocationStatus
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.ui.budget.AllocationSheetActions
import com.arthurrios.finova.ui.dashboard.TransactionRowUi
import com.arthurrios.finova.ui.dashboard.toRowUi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

data class AllocationDetailsUiState(
    val category: TransactionCategory,
    val month: YearMonth,
    /** Null in unallocated mode: spending in a category no allocation covers. */
    val allocation: BudgetAllocation? = null,
    /** What was spent: against the allocation, or in the category when there is none. */
    val used: Long = 0,
    val rows: List<TransactionRowUi> = emptyList(),
    val allocationRows: List<AllocationRow> = emptyList(),
    val currencyCode: String = "BRL",
    val valuesHidden: Boolean = false,
    /** True once the allocation this screen showed was deleted. */
    val gone: Boolean = false,
) {
    val isUnallocated: Boolean get() = allocation == null
    val remaining: Long get() = allocation?.remaining ?: -used
    /** iOS shows a full ring at 100% for unallocated spending. */
    val percentage: Int get() = allocation?.usagePercentage?.toInt() ?: 100
    val status: AllocationStatus get() = allocation?.status ?: AllocationStatus.OverBudget
    val isRecurring: Boolean get() = allocation?.isPartOfSeries == true
}

/**
 * Port of BudgetAllocationDetailsViewModel. Opened by category and month, so it follows the data:
 * an allocation created here switches the screen from unallocated to allocated mode, as iOS does
 * after its create flow.
 */
class AllocationDetailsViewModel(
    private val repository: FinanceRepository,
    private val allocations: AllocationRepository,
    private val settings: UserSettingsStore,
    private val category: TransactionCategory,
    private val month: YearMonth,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel(), AllocationSheetActions {
    private val valuesHidden = MutableStateFlow(settings.hideValues)
    private var hadAllocation = false

    val state: StateFlow<AllocationDetailsUiState> =
        combine(repository.transactions, allocations.all, valuesHidden) { rows, allocationRows, hidden ->
            val allocation = Allocations.withUsage(allocationRows, rows, month).firstOrNull { it.category == category }
            val gone = hadAllocation && allocation == null
            if (allocation != null) hadAllocation = true
            // The rows usage counts: this category's expenses in the budget month. Installments paid
            // early are left out, since their early payment is what counts.
            val members = rows.filter {
                FinanceRepository.isListed(it) && it.category == category && it.type == TransactionType.Expense &&
                    it.budgetMonth == month && !it.isSettledEarly && !it.isCreditCardStatement
            }
            AllocationDetailsUiState(
                category = category,
                month = month,
                allocation = allocation,
                used = allocation?.used ?: members.sumOf { it.amount },
                rows = members.sortedWith(compareByDescending<Transaction> { it.date }.thenByDescending { it.id }).map { it.toRowUi() },
                allocationRows = allocationRows,
                currencyCode = settings.currencyCode,
                valuesHidden = hidden,
                gone = gone,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AllocationDetailsUiState(category, month))

    fun deleteAllocation(scope: AllocationEditScope) {
        val id = state.value.allocation?.id ?: return
        viewModelScope.launch { allocations.delete(id, scope) }
    }

    fun deleteTransaction(row: TransactionRowUi, option: SeriesDeleteOption) {
        viewModelScope.launch { repository.delete(row.id, option) }
    }

    override fun createAllocation(
        category: TransactionCategory, amount: Long, month: YearMonth,
        repeating: Boolean, endMonth: YearMonth?, overwrite: List<Long>,
    ) {
        viewModelScope.launch {
            if (overwrite.isNotEmpty()) allocations.deleteEach(overwrite)
            allocations.create(category, amount, month, repeating, endMonth, today())
        }
    }

    override fun editAllocation(id: Long, amount: Long, scope: AllocationEditScope, through: YearMonth?) {
        viewModelScope.launch { allocations.edit(id, amount, scope, through) }
    }

    fun toggleValues() {
        val hidden = !valuesHidden.value
        settings.hideValues = hidden
        valuesHidden.value = hidden
    }
}
