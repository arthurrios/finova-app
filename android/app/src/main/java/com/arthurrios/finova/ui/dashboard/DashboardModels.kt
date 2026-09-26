package com.arthurrios.finova.ui.dashboard

import androidx.annotation.DrawableRes
import com.arthurrios.finova.domain.series.SeriesKind
import java.time.LocalDate
import java.time.YearMonth

/** What the dashboard draws. Built by DashboardViewModel from the ledger. */
data class DashboardUiState(
    val userName: String = "",
    val unreadNotifications: Int = 0,
    val currencyCode: String = "BRL",
    val valuesHidden: Boolean = false,
    val months: List<MonthPageUi> = emptyList(),
    val selectedMonth: Int = 0,
    val isLoading: Boolean = true,
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
)
