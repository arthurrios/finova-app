package com.arthurrios.finova.ui.dashboard

import androidx.annotation.DrawableRes
import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.UnallocatedSpending
import com.arthurrios.finova.domain.allocation.UnallocatedSummary
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionMode
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesRules
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.series.SeriesKind
import java.time.LocalDate
import java.time.YearMonth

/** What the dashboard draws. Built by DashboardViewModel from the ledger. */
data class DashboardUiState(
    val userName: String = "",
    val unreadNotifications: Int = 0,
    val currencyCode: String = "BRL",
    val defaultBusinessDayRule: BusinessDayRule = BusinessDayRule.Exact,
    val valuesHidden: Boolean = false,
    val months: List<MonthPageUi> = emptyList(),
    val selectedMonth: Int = 0,
    val isLoading: Boolean = true,
    /** The cards the add sheet offers. */
    val cards: List<CreditCard> = emptyList(),
    /** Every allocation (deleted series months included), for the allocation sheet's checks. */
    val allocationRows: List<AllocationRow> = emptyList(),
)

/** One page of the month carousel: the month card plus that month's transactions. */
data class MonthPageUi(
    val month: YearMonth,
    val isCurrentMonth: Boolean,
    val isPastMonth: Boolean,
    /** Spent (and income-adjusted) value that month, in cents. */
    val usedValue: Long,
    /** Null or zero means no budget set: the card shows "Set budget". */
    val budgetLimit: Long?,
    /** Balance on the last day of the month. */
    val finalBalance: Long?,
    /** Balance today (current month only). */
    val currentBalance: Long?,
    val transactions: List<TransactionRowUi>,
    /** This month's allocations with what was spent against each, biggest first. */
    val allocations: List<BudgetAllocation> = emptyList(),
    val unallocated: UnallocatedSummary = UnallocatedSummary(month, 0, 0, 0),
    /** Categories spent in with no allocation, biggest first. */
    val offPlan: List<UnallocatedSpending> = emptyList(),
    /** Card spending counted this month but charged on a later statement. */
    val deferredCardSpending: Long = 0,
) {
    val hasBudget: Boolean get() = (budgetLimit ?: 0) > 0
}

enum class TransactionModeUi { Normal, Recurring, Installments }

data class TransactionRowUi(
    val id: Long,
    val title: String,
    val date: LocalDate,
    val amount: Long,
    val isIncome: Boolean,
    @DrawableRes val icon: Int,
    val mode: TransactionModeUi = TransactionModeUi.Normal,
    val installmentNumber: Int? = null,
    val totalInstallments: Int? = null,
    /** Paid with a credit card (shows the small card mark next to the date). */
    val isCreditCard: Boolean = false,
    /** A whole credit card statement collapsed into one row. */
    val statementTransactionCount: Int? = null,
    /** An installment paid ahead of time: shown dimmed, not counted in the month. */
    val isSettledEarly: Boolean = false,
    /** Decides which delete question the row gets. */
    val seriesKind: SeriesKind = SeriesKind.Simple,
    /** The statement a statement row stands for (it opens the statement). */
    val statementId: Long? = null,
    /** What the filter's category chips match against. */
    val category: TransactionCategory = TransactionCategory.Miscellaneous,
)

/** How a stored (or statement) row shows in a list. Shared by the dashboard and statement details. */
fun Transaction.toRowUi() = TransactionRowUi(
    id = id,
    title = title,
    date = date,
    amount = amount,
    isIncome = type == TransactionType.Income,
    icon = category.icon(type),
    category = category,
    mode = when (mode) {
        TransactionMode.Recurring -> TransactionModeUi.Recurring
        TransactionMode.Installments -> TransactionModeUi.Installments
        TransactionMode.Normal -> TransactionModeUi.Normal
    },
    installmentNumber = installmentNumber,
    totalInstallments = totalInstallments,
    isCreditCard = creditCardId != null,
    statementTransactionCount = if (isCreditCardStatement) totalInstallments else null,
    statementId = statementId,
    isSettledEarly = isSettledEarly,
    seriesKind = SeriesRules.kindOf(this),
)
