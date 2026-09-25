package com.arthurrios.finova.debug

import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth

/**
 * Debug builds only (MainActivity checks): fills an empty database with a few months of plain
 * transactions, a budget and a starting balance, so screens can be checked on the emulator. The
 * iOS counterpart is DemoSeedGenerator.
 */
object DebugSeeder {
    suspend fun seedIfEmpty(repository: FinanceRepository, today: LocalDate = LocalDate.now()) {
        if (!repository.isEmpty()) return
        val thisMonth = YearMonth.from(today)
        val rows = (-2..1).flatMap { offset ->
            val month = thisMonth.plusMonths(offset.toLong())
            listOf(
                row("Salary", TransactionCategory.Salary, TransactionType.Income, 8_500_00, month, 5),
                row("Rent", TransactionCategory.HomeMaintenance, TransactionType.Expense, 2_400_00, month, 10),
                row("Supermarket", TransactionCategory.Groceries, TransactionType.Expense, 612_35, month, 12),
                row("Electricity", TransactionCategory.Utilities, TransactionType.Expense, 238_90, month, 15),
                row("Streaming", TransactionCategory.Subscriptions, TransactionType.Expense, 55_90, month, 18),
                row("Dinner out", TransactionCategory.Meals, TransactionType.Expense, 184_00, month, 21),
                row("Gym", TransactionCategory.Fitness, TransactionType.Expense, 129_00, month, 25),
            )
        }
        repository.addAll(rows)
        (-2..1).forEach { repository.setBudget(Budget(thisMonth.plusMonths(it.toLong()), 5_000_00)) }
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
