package com.arthurrios.finova.data

import android.content.Context
import androidx.core.content.edit
import com.arthurrios.finova.data.repo.AllocationRepository
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.coachmarks.BudgetSuggestion
import com.arthurrios.finova.domain.coachmarks.CoachMarkFacts
import com.arthurrios.finova.domain.coachmarks.CoachMarkPreferences
import java.time.YearMonth
import kotlinx.coroutines.flow.first

/** Where [com.arthurrios.finova.domain.coachmarks.CoachMarkStateStore] keeps its lines. */
class SharedCoachMarkPreferences(context: Context) : CoachMarkPreferences {
    private val prefs = context.getSharedPreferences("finova_coach_marks", Context.MODE_PRIVATE)

    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String) = prefs.edit { putString(key, value) }
    override fun remove(key: String) = prefs.edit { remove(key) }
}

/** Reads through the repositories, so it sees the current user's rows and nothing else. */
object CoachMarkLedger {
    suspend fun facts(
        finance: FinanceRepository,
        cards: CardRepository,
        allocations: AllocationRepository,
        thisMonth: YearMonth = YearMonth.now(),
    ): CoachMarkFacts {
        val budgets = finance.budgets.first()
        val allocationRows = allocations.all.first()
        val transactions = finance.transactions.first()
        return CoachMarkFacts(
            hasAnyBudget = budgets.isNotEmpty(),
            hasBudgetThisMonth = budgets.any { it.month == thisMonth },
            hasAnyAllocation = allocationRows.isNotEmpty(),
            hasAllocationThisMonth = allocationRows.any { it.month == thisMonth },
            hasRecurringTransaction = transactions.any { it.isRecurring },
            hasAnyTransaction = transactions.isNotEmpty(),
            hasCreditCard = cards.activeCards.first().isNotEmpty(),
            hasIncomeThisMonth = BudgetSuggestion.monthlyIncome(transactions, thisMonth) > 0,
        )
    }
}
