package com.arthurrios.finova.domain.budget

import com.arthurrios.finova.domain.model.Budget
import java.time.YearMonth

/**
 * "Create budgets for many months at once" (iOS `BudgetsViewModel.addBudgets` and
 * `BudgetRepository.upsertBudgets`): one save writes the same amount to every month from the
 * start month through the end month. Months that already have a budget are replaced or kept, as
 * the user picks.
 */
object BudgetRange {

    /** Every month from [start] through [end], both included. Empty when [end] is before [start]. */
    fun months(start: YearMonth, end: YearMonth): List<YearMonth> =
        if (end < start) emptyList()
        else generateSequence(start) { it.plusMonths(1) }.takeWhile { it <= end }.toList()

    /** The months in the range that already hold a budget, in calendar order. */
    fun existingIn(existing: Collection<YearMonth>, start: YearMonth, end: YearMonth): List<YearMonth> {
        val taken = existing.toSet()
        return months(start, end).filter { it in taken }
    }

    /** The months one save writes: all of them, or only the empty ones when keeping existing. */
    fun monthsToWrite(
        existing: Collection<YearMonth>,
        start: YearMonth,
        end: YearMonth,
        replaceExisting: Boolean,
    ): List<YearMonth> {
        val taken = existing.toSet()
        return months(start, end).filter { replaceExisting || it !in taken }
    }

    /**
     * Writes every month inside ONE [transaction], so a failure on any month writes none of them.
     * The repository passes Room's `withTransaction` and the DAO upsert.
     */
    suspend fun write(
        months: List<YearMonth>,
        amount: Long,
        transaction: suspend (suspend () -> Unit) -> Unit,
        upsert: suspend (Budget) -> Unit,
    ) {
        if (months.isEmpty()) return
        transaction { months.forEach { upsert(Budget(it, amount)) } }
    }
}
