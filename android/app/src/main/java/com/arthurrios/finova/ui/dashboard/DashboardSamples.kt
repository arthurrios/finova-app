package com.arthurrios.finova.ui.dashboard

import com.arthurrios.finova.R
import java.time.LocalDate
import java.time.YearMonth

/** Made-up data for previews and for the screen until the ledger is ported. */
object DashboardSamples {
    fun state(): DashboardUiState {
        val now = YearMonth.now()
        val months = (-2..2).map { offset ->
            val month = now.plusMonths(offset.toLong())
            MonthPageUi(
                month = month,
                isCurrentMonth = offset == 0,
                isPastMonth = offset < 0,
                usedValue = 770_978,
                budgetLimit = if (offset > 1) null else 780_000,
                finalBalance = 354_155,
                currentBalance = 354_155,
                transactions = if (offset == 1) emptyList() else rows(month),
            )
        }
        return DashboardUiState(
            userName = "Jack",
            unreadNotifications = 3,
            currencyCode = "USD",
            months = months,
            selectedMonth = 2,
            isLoading = false,
        )
    }

    private fun rows(month: YearMonth): List<TransactionRowUi> {
        val day = { d: Int -> LocalDate.of(month.year, month.month, d.coerceAtMost(month.lengthOfMonth())) }
        return listOf(
            TransactionRowUi(1, "Bose QuietComfort – Amazon", day(27), 6_980, false, R.drawable.ic_lucide_icon_entertainment,
                TransactionModeUi.Installments, 2, 5, isCreditCard = true),
            TransactionRowUi(2, "iPhone 17 Pro – Apple", day(27), 9_991, false, R.drawable.ic_lucide_icon_dollar,
                TransactionModeUi.Installments, 5, 12, isCreditCard = true),
            TransactionRowUi(3, "Amex Gold Statement", day(10), 37_248, false, R.drawable.ic_lucide_icon_credit_card,
                statementTransactionCount = 6),
            TransactionRowUi(4, "American Red Cross", day(5), 2_500, false, R.drawable.ic_lucide_icon_donations,
                TransactionModeUi.Recurring),
            TransactionRowUi(5, "Salary", day(5), 850_000, true, R.drawable.ic_lucide_icon_salary, TransactionModeUi.Recurring),
            TransactionRowUi(6, "Groceries", day(3), 18_340, false, R.drawable.ic_lucide_icon_groceries),
        )
    }
}
