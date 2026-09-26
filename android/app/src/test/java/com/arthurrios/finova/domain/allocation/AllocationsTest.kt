package com.arthurrios.finova.domain.allocation

import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.*
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class AllocationsTest {
    private val sep = YearMonth.of(2026, 9)
    private fun spend(id: Long, category: TransactionCategory, amount: Long, month: YearMonth = sep, card: Long? = null, statement: Long? = null, settled: Boolean = false) =
        Transaction(
            id = id, title = "T$id", category = category, type = TransactionType.Expense, amount = amount,
            date = month.atDay(10), budgetMonth = month, creditCardId = card, statementId = statement,
            settledByTransactionId = if (settled) 99 else null,
        )

    @Test fun usageCountsExpensesInTheBudgetMonthButNotEarlyPaidOnes() {
        val rows = listOf(spend(1, Meals, 1_000), spend(2, Meals, 500), spend(3, Meals, 700, settled = true), spend(4, Market, 300, month = sep.plusMonths(1)))
        assertEquals(mapOf(Meals to 1_500L), Allocations.usage(rows, sep))
    }

    @Test fun summaryAndUnallocatedSpending() {
        val allocations = listOf(AllocationRow(1, sep, Meals, 2_000))
        val rows = listOf(spend(1, Meals, 1_500), spend(2, Travel, 900), spend(3, Gifts, 100))
        val summary = Allocations.unallocatedSummary(allocations, rows, listOf(Budget(sep, 5_000)), sep)
        assertEquals(3_000L, summary.unallocated); assertEquals(1_000L, summary.usedInUnallocatedCategories); assertEquals(2_000L, summary.unallocatedRemaining)
        assertEquals(listOf(Travel, Gifts), Allocations.unallocatedSpending(allocations, rows, sep).map { it.category })
    }

    @Test fun deferredCardSpendingIsWhatIsDueInALaterMonth() {
        val statements = listOf(
            CreditCardStatement(id = 1, creditCardId = 7, closingDate = LocalDate.of(2026, 9, 5), dueDate = LocalDate.of(2026, 9, 12)),
            CreditCardStatement(id = 2, creditCardId = 7, closingDate = LocalDate.of(2026, 10, 5), dueDate = LocalDate.of(2026, 10, 12)),
        )
        val rows = listOf(spend(1, Meals, 100, card = 7, statement = 1), spend(2, Meals, 200, card = 7, statement = 2), spend(3, Meals, 400, card = 7))
        assertEquals(600L, Allocations.deferredCardSpending(rows, statements, sep))
    }

    @Test fun aSeriesFillsLaterMonthsWithTheLatestAmountAndSkipsDeletedOrHeldMonths() {
        val allocations = listOf(
            AllocationRow(1, sep, Meals, 1_000, isRecurring = true),
            AllocationRow(2, sep.plusMonths(2), Meals, 1_500, isRecurring = true, parentId = 1),
            AllocationRow(3, sep.plusMonths(3), Meals, 1_500, isRecurring = true, parentId = 1, isDeleted = true),
            AllocationRow(4, sep.plusMonths(4), Meals, 800),
        )
        val missing = Allocations.missingSeriesMonths(allocations, 1, endMonth = sep.plusMonths(5), thisMonth = sep)
        assertEquals(listOf(sep.plusMonths(1), sep.plusMonths(5)), missing.map { it.month })
        assertEquals(listOf(1_000L, 1_500L), missing.map { it.amount })
        assertTrue(missing.all { it.parentId == 1L && it.isRecurring })
    }

    @Test fun aStoppedSeriesIsFilledButNotExtended() {
        val allocations = listOf(
            AllocationRow(1, sep, Meals, 1_000, isRecurring = false),
            AllocationRow(2, sep.plusMonths(2), Meals, 1_000, isRecurring = true, parentId = 1),
        )
        assertEquals(listOf(sep.plusMonths(1)), Allocations.missingSeriesMonths(allocations, 1, null, sep).map { it.month })
    }

    @Test fun editScopes() {
        val allocations = listOf(
            AllocationRow(1, sep, Meals, 1_000, isRecurring = true),
            AllocationRow(2, sep.plusMonths(1), Meals, 1_000, isRecurring = true, parentId = 1),
            AllocationRow(3, sep.plusMonths(2), Meals, 1_000, isRecurring = true, parentId = 1),
        )
        assertEquals(setOf(2L), Allocations.editTargets(allocations, 2, AllocationEditScope.ThisOnly))
        // The root follows "this and later" so months made later copy the new amount.
        assertEquals(setOf(1L, 2L, 3L), Allocations.editTargets(allocations, 2, AllocationEditScope.ThisAndLater))
        assertEquals(setOf(1L, 2L, 3L), Allocations.editTargets(allocations, 3, AllocationEditScope.All))
    }

    @Test fun deletingTombstonesSeriesMonthsAndRemovesOneOffs() {
        val allocations = listOf(
            AllocationRow(1, sep, Meals, 1_000, isRecurring = true),
            AllocationRow(2, sep.plusMonths(1), Meals, 1_000, isRecurring = true, parentId = 1),
            AllocationRow(3, sep.plusMonths(2), Meals, 1_000, isRecurring = true, parentId = 1),
            AllocationRow(4, sep, Travel, 500),
        )
        assertEquals(Allocations.DeletePlan(setOf(4), emptySet(), null), Allocations.deletePlan(allocations, 4, AllocationEditScope.ThisOnly))
        assertEquals(Allocations.DeletePlan(emptySet(), setOf(2), null), Allocations.deletePlan(allocations, 2, AllocationEditScope.ThisOnly))
        assertEquals(Allocations.DeletePlan(emptySet(), setOf(2, 3), 1), Allocations.deletePlan(allocations, 2, AllocationEditScope.ThisAndLater))
        assertEquals(setOf(1L, 2L, 3L), Allocations.deletePlan(allocations, 1, AllocationEditScope.All).tombstone)
    }
}
