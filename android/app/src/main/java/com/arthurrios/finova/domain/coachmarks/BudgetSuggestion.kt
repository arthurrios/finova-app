package com.arthurrios.finova.domain.coachmarks

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import java.time.YearMonth

object BudgetSuggestion {
    /**
     * What comes in during a month: the amount a budget is suggested to match. Card rows are left out
     * because a card refund is not money received, and installments paid early because the ledger
     * leaves them out too, so this cannot disagree with the month the user sees.
     */
    fun monthlyIncome(rows: List<Transaction>, month: YearMonth): Long =
        rows.filter {
            it.budgetMonth == month && it.type == TransactionType.Income && it.creditCardId == null && !it.isSettledEarly
        }.sumOf { it.amount }
}
