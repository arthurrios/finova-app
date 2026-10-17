package com.arthurrios.finova.debug

import com.arthurrios.finova.data.repo.AllocationRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.TransactionDraft
import java.time.LocalDate
import java.time.YearMonth

/**
 * Debug builds only (MainActivity checks): fills an empty database with seven months of plain
 * transactions, budgets, repeating allocations and a starting balance, so screens (the budget
 * history most of all) can be checked on the emulator. Some months deliberately go over plan. The
 * iOS counterpart is DemoSeedGenerator.
 */
object DebugSeeder {
    suspend fun seedIfEmpty(
        repository: FinanceRepository,
        allocations: AllocationRepository? = null,
        today: LocalDate = LocalDate.now(),
    ) {
        if (!repository.isEmpty()) return
        val thisMonth = YearMonth.from(today)
        // Spending that moves from month to month, so the history has hits and misses.
        val groceries = listOf(598_40, 702_15, 655_80, 612_35, 731_90, 580_10, 640_00)
        val meals = listOf(162_00, 184_00, 251_50, 140_00, 199_90, 236_00, 120_00)
        val rows = (-6..1).flatMap { offset ->
            val month = thisMonth.plusMonths(offset.toLong())
            val index = (offset + 6).coerceAtMost(groceries.lastIndex)
            listOf(
                row("Salary", TransactionCategory.Salary, TransactionType.Income, 8_500_00, month, 5),
                row("Rent", TransactionCategory.HomeMaintenance, TransactionType.Expense, 2_400_00, month, 10),
                row("Supermarket", TransactionCategory.Groceries, TransactionType.Expense, groceries[index].toLong(), month, 12),
                row("Electricity", TransactionCategory.Utilities, TransactionType.Expense, 238_90, month, 15),
                row("Dinner out", TransactionCategory.Meals, TransactionType.Expense, meals[index].toLong(), month, 21),
                row("Gym", TransactionCategory.Fitness, TransactionType.Expense, 129_00, month, 25),
            )
        }
        repository.addAll(rows)
        repository.addRecurring(
            TransactionDraft("Netflix", TransactionCategory.Subscriptions, TransactionType.Expense, 55_90, thisMonth.minusMonths(3).atDay(8)),
            today,
        )
        repository.addInstallments(
            TransactionDraft("Smart TV", TransactionCategory.Entertainment, TransactionType.Expense, 3_600_00, thisMonth.minusMonths(1).atDay(20)),
            count = 10,
        )
        (-6..1).forEach { repository.setBudget(Budget(thisMonth.plusMonths(it.toLong()), 5_000_00)) }
        allocations?.let { repo ->
            val start = thisMonth.minusMonths(6)
            repo.create(TransactionCategory.Groceries, 650_00, start, repeating = true, endMonth = null, today = today)
            repo.create(TransactionCategory.Meals, 200_00, start, repeating = true, endMonth = null, today = today)
            repo.create(TransactionCategory.Utilities, 250_00, start, repeating = true, endMonth = null, today = today)
        }
        repository.setBalanceOffset(1_250_00)
    }

    private fun row(title: String, category: TransactionCategory, type: TransactionType, amount: Long, month: YearMonth, day: Int) =
        Transaction(
            title = title,
            category = category,
            type = type,
            amount = amount,
            date = month.atDay(day.coerceAtMost(month.lengthOfMonth())),
            budgetMonth = month,
        )
}
