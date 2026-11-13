package com.arthurrios.finova.ui.filter

import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.ui.dashboard.TransactionModeUi
import com.arthurrios.finova.ui.dashboard.TransactionRowUi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class TransactionFiltersTest {
    private fun row(
        id: Long,
        title: String = "Row $id",
        day: Int = 10,
        amount: Long = 1_000,
        isIncome: Boolean = false,
        category: TransactionCategory = TransactionCategory.Market,
        mode: TransactionModeUi = TransactionModeUi.Normal,
    ) = TransactionRowUi(
        id = id, title = title, date = LocalDate.of(2026, 9, day), amount = amount,
        isIncome = isIncome, icon = 0, mode = mode, category = category,
    )

    @Test fun emptyFiltersKeepEveryRow() {
        val rows = listOf(row(1), row(2, isIncome = true))
        assertEquals(rows, rows.filtered("", TransactionFilters()))
        assertTrue(TransactionFilters().isEmpty(30))
    }

    @Test fun eachSectionIsAnAnyOfAndSectionsCombine() {
        val rows = listOf(
            row(1, category = TransactionCategory.Market),
            row(2, category = TransactionCategory.Meals, mode = TransactionModeUi.Recurring),
            row(3, category = TransactionCategory.Meals, isIncome = true),
        )
        val meals = TransactionFilters(categories = setOf(TransactionCategory.Meals, TransactionCategory.Travel))
        assertEquals(listOf(2L, 3L), rows.filtered("", meals).map { it.id })
        val mealsExpenses = meals.copy(types = setOf(false))
        assertEquals(listOf(2L), rows.filtered("", mealsExpenses).map { it.id })
        val recurring = TransactionFilters(modes = setOf(TransactionModeUi.Recurring))
        assertEquals(listOf(2L), rows.filtered("", recurring).map { it.id })
    }

    @Test fun searchIgnoresCaseAndAccents() {
        val rows = listOf(row(1, title = "Café da Manhã"), row(2, title = "Mercado"))
        assertEquals(listOf(1L), rows.filtered("  cafe da manha ", TransactionFilters()).map { it.id })
        assertEquals(listOf(1L), rows.filtered("CAFÉ", TransactionFilters()).map { it.id })
    }

    @Test fun dayRangeOnlyCountsInCustomMode() {
        val rows = listOf(row(1, day = 5), row(2, day = 15))
        val global = TransactionFilters(startDay = 10, endDay = 20, useGlobalFilter = true)
        assertEquals(2, rows.filtered("", global).size)
        assertFalse(global.hasDayFilter(30))
        val custom = global.copy(useGlobalFilter = false)
        assertEquals(listOf(2L), rows.filtered("", custom).map { it.id })
        assertTrue(custom.hasDayFilter(30))
    }

    @Test fun crossedThumbsWrapRoundTheMonth() {
        val rows = listOf(row(1, day = 5), row(2, day = 15), row(3, day = 25), row(4, day = 13), row(5, day = 20))
        val wrap = TransactionFilters(startDay = 20, endDay = 13, useGlobalFilter = false)
        assertEquals(listOf(1L, 3L, 4L, 5L), rows.filtered("", wrap).map { it.id })
    }

    @Test fun aWholeMonthRangeIsNotAFilter() {
        val all = TransactionFilters(startDay = 1, endDay = 30, useGlobalFilter = false)
        assertTrue(all.isEmpty(30))
        // The same range in a 31-day month leaves out day 31, so there it is a filter.
        assertFalse(all.isEmpty(31))
    }

    @Test fun otherMonthsGetTheFilterWithoutItsDays() {
        val custom = TransactionFilters(types = setOf(true), startDay = 3, endDay = 9, useGlobalFilter = false)
        val carried = custom.withoutDayFilter()
        assertEquals(setOf(true), carried.types)
        assertFalse(carried.hasDayFilter(30))
    }

    @Test fun theTotalAddsIncomeAndSubtractsExpenses() {
        val rows = listOf(row(1, amount = 5_000, isIncome = true), row(2, amount = 1_250), row(3, amount = 250))
        assertEquals(3_500L, rows.filteredTotal())
    }
}
