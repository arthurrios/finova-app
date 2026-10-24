package com.arthurrios.finova.domain.history

import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.history.BudgetHistoryMonth.Status
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.Gifts
import com.arthurrios.finova.domain.model.TransactionCategory.Groceries
import com.arthurrios.finova.domain.model.TransactionCategory.Meals
import com.arthurrios.finova.domain.model.TransactionCategory.Travel
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.history.BudgetHistoryUiState
import com.arthurrios.finova.ui.history.SavingsScope
import com.arthurrios.finova.ui.history.previewEnding
import com.arthurrios.finova.domain.history.SavingsContributors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/** Port of BudgetHistoryTests.swift and the pure parts of BudgetHistoryViewModelTests.swift. */
class BudgetHistoryTest {
    private val months = (0 until 6).map { YearMonth.of(2026, 5).plusMonths(it.toLong()) }
    private val current = months.last()

    private fun month(index: Int, planned: Long, spent: Long, isCurrent: Boolean = false) =
        BudgetHistoryMonth(months[index], planned, spent, isCurrent)

    /** A series over [months], the last one open. Each pair is (planned, spent). */
    private fun series(vararg pairs: Pair<Long, Long>) = BudgetHistorySeries(
        BudgetHistoryFilter.WholeMonth,
        pairs.mapIndexed { index, (planned, spent) -> month(index, planned, spent, isCurrent = index == pairs.size - 1) },
    )

    private fun allocation(category: TransactionCategory, index: Int, amount: Long, id: Long = 0) =
        AllocationRow(id = id, month = months[index], category = category, amount = amount)

    private fun history(
        allocations: List<AllocationRow> = emptyList(),
        spent: Map<TransactionCategory, Map<YearMonth, Long>> = emptyMap(),
        totals: Map<YearMonth, BudgetHistory.MonthTotal> = emptyMap(),
    ) = BudgetHistory.of(months, current, allocations, spent, totals)

    // ---- Month status

    @Test fun closedMonthAtOrUnderItsPlanIsWithin() {
        assertEquals(Status.Within, month(0, 100, 100).status)
        assertEquals(Status.Within, month(0, 100, 0).status)
    }

    @Test fun monthPastItsPlanIsOverEvenWhileOpen() {
        assertEquals(Status.Over, month(0, 100, 101).status)
        assertEquals(Status.Over, month(0, 100, 101, isCurrent = true).status)
    }

    @Test fun openMonthUnderItsPlanIsInProgress() = assertEquals(Status.InProgress, month(0, 100, 40, isCurrent = true).status)

    @Test fun spendingWithNoPlanIsNoPlanAndNothingIsEmpty() {
        assertEquals(Status.NoPlan, month(0, 0, 50).status)
        assertEquals(Status.Empty, month(0, 0, 0).status)
    }

    @Test fun splitDrawsTheOverspendAsItsOwnPiece() {
        val over = month(0, 100, 130)
        assertEquals(100L, over.spentWithinPlan)
        assertEquals(30L, over.spentOverPlan)
        assertEquals(-30L, over.difference)
        assertEquals(130, over.percentUsed)
        val unplanned = month(0, 0, 50)
        assertNull(unplanned.percentUsed)
        assertEquals(50L, unplanned.spentWithinPlan)
        assertEquals(0L, unplanned.spentOverPlan)
    }

    // ---- Scores

    @Test fun openMonthIsNeverScored() {
        val s = series(100L to 90L, 100L to 90L, 100L to 90L, 100L to 90L, 100L to 90L, 100L to 200L)
        assertEquals(5, s.scoredMonths.size)
        assertEquals(5, s.monthsOnPlan)
        assertEquals(5, s.streak)
        assertEquals(90 to 90, s.usageRange)
    }

    @Test fun monthsWithoutAPlanAreLeftOutOfTheScore() {
        val s = series(0L to 80L, 100L to 90L, 100L to 120L, 0L to 0L, 100L to 50L, 100L to 10L)
        assertEquals(3, s.scoredMonths.size)
        assertEquals(2, s.monthsOnPlan)
    }

    @Test fun streakStopsAtAMissOrAMonthWithNoPlan() {
        assertEquals(3, series(100L to 90L, 100L to 120L, 100L to 90L, 100L to 80L, 100L to 70L, 100L to 10L).streak)
        assertEquals(0, series(100L to 90L, 100L to 90L, 100L to 90L, 100L to 90L, 100L to 120L, 100L to 10L).streak)
        assertEquals(1, series(100L to 90L, 100L to 90L, 100L to 90L, 0L to 50L, 100L to 90L, 100L to 10L).streak)
    }

    @Test fun usageRangeIsUnclamped() {
        assertEquals(60 to 140, series(100L to 60L, 100L to 140L, 100L to 95L, 100L to 10L).usageRange)
        assertNull(series(0L to 50L, 100L to 10L).usageRange)
    }

    // ---- Savings

    @Test fun savingsNetWhatMonthsLeftAgainstOverspend() {
        val savings = series(200L to 100L, 100L to 130L, 100L to 50L, 100L to 10L).savings()
        assertEquals(BudgetHistorySeries.Savings(saved = 150, overspent = 30, months = 3), savings)
        assertEquals(120L, savings.net)
    }

    @Test fun savingsSkipMonthsWithoutAPlanAndCountFromTheStart() {
        assertEquals(60L, series(0L to 500L, 100L to 40L, 100L to 10L).savings().net)
        val s = series(100L to 0L, 100L to 0L, 100L to 150L, 100L to 80L, 100L to 10L)
        assertEquals(-30L, s.savings(months[2]).net)
        assertEquals(2, s.savings(months[2]).months)
        assertEquals(170L, s.savings(null).net)
        assertEquals(-80L, series(100L to 180L, 100L to 10L).savings().net)
        assertEquals(BudgetHistorySeries.Savings.None, series(0L to 0L, 100L to 10L).savings())
    }

    @Test fun outsideAllocationsMakesTheCategoriesAddUpToTheWholeMonth() {
        val h = history(
            allocations = listOf(allocation(Groceries, 3, 500), allocation(Groceries, 4, 500), allocation(Meals, 3, 300), allocation(Meals, 4, 300)),
            spent = mapOf(Groceries to mapOf(months[3] to 450L, months[4] to 450L), Meals to mapOf(months[3] to 330L, months[4] to 330L)),
            totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 800), months[4] to BudgetHistory.MonthTotal(1_000, 800)),
        )
        val categories = h.categories.sumOf { it.savings(null).net }
        assertEquals(40L, categories)
        assertEquals(360L, h.outsideAllocations(null))
        assertEquals(h.wholeMonth.savings(null).net, categories + h.outsideAllocations(null)!!)
        assertEquals(180L, h.outsideAllocations(months[4]))
        assertNull(history(listOf(allocation(Groceries, 3, 500)), mapOf(Groceries to mapOf(months[3] to 450L))).outsideAllocations(null))
    }

    @Test fun outsideSeriesIsUnallocatedBudgetAgainstUnplannedSpending() {
        // Month 3: budget 1_000, groceries planned 500. Travel had no allocation and spent 120.
        val h = history(
            allocations = listOf(allocation(Groceries, 3, 500)),
            spent = mapOf(Groceries to mapOf(months[3] to 450L), Travel to mapOf(months[3] to 120L)),
            totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 600)),
        )
        val month = h.series(BudgetHistoryFilter.OutsideAllocations)?.month(months[3])
        assertEquals(500L, month?.planned)
        assertEquals(120L, month?.spent)
        // Whole 400 - groceries 50 = 350 outside; the series explains 380, the card's date clock 30 less.
        assertEquals(350L, h.outsideAllocations(null))
        assertEquals(380L, h.series(BudgetHistoryFilter.OutsideAllocations)?.savings(null)?.net)
        assertEquals(-30L, h.outsideTiming(null))
    }

    @Test fun overAllocatedMonthHasNoOutsidePlan() {
        val h = history(
            allocations = listOf(allocation(Groceries, 3, 1_200)),
            spent = mapOf(Groceries to mapOf(months[3] to 900L)),
            totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 900)),
        )
        assertEquals(false, h.series(BudgetHistoryFilter.OutsideAllocations)?.month(months[3])?.hasPlan)
    }

    @Test fun noCategoriesMeansNoOutsideSeries() {
        val h = history(totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 900)))
        assertNull(h.series(BudgetHistoryFilter.OutsideAllocations))
    }

    @Test fun theTimingLineShowsOnlyWhileTheOutsideFilterIsChosen() {
        val h = history(
            allocations = listOf(allocation(Groceries, 3, 500)),
            spent = mapOf(Groceries to mapOf(months[3] to 450L), Travel to mapOf(months[3] to 120L)),
            totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 600)),
        )
        assertNull(BudgetHistoryUiState().withHistory(h, firstLoad = true).outsideTiming)
        val outside = BudgetHistoryUiState(filter = BudgetHistoryFilter.OutsideAllocations).withHistory(h, firstLoad = true)
        assertEquals(BudgetHistoryFilter.OutsideAllocations, outside.filter)
        assertEquals(-30L, outside.outsideTiming)
    }

    // ---- Up to a month (iOS 7c07005 and later)

    @Test fun savingsThroughAMonthStopAtThatMonth() {
        // Saved per closed month: +100, -30, +50; the open month never counts.
        val s = series(200L to 100L, 100L to 130L, 100L to 50L, 100L to 10L)
        assertEquals(100L, s.savings(end = months[0]).net)
        assertEquals(70L, s.savings(end = months[1]).net)
        assertEquals(120L, s.savings(end = months[3]).net)
        assertEquals(20L, s.savings(months[1], months[2]).net)
        assertEquals(BudgetHistorySeries.Savings.None, s.savings(months[2], months[1]))
    }

    @Test fun outsideAllocationsFollowTheSameMonths() {
        val h = history(
            allocations = listOf(allocation(Groceries, 3, 500), allocation(Groceries, 4, 500)),
            spent = mapOf(Groceries to mapOf(months[3] to 450L, months[4] to 450L)),
            totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 800), months[4] to BudgetHistory.MonthTotal(1_000, 800)),
        )
        // Through month 3 only: whole 200 - groceries 50.
        assertEquals(150L, h.outsideAllocations(null, months[3]))
        assertEquals(300L, h.outsideAllocations(null, null))
    }

    // ---- Transactions behind a bar

    private fun spend(
        title: String, category: TransactionCategory, amount: Long, dated: Int, budgetMonth: Int,
        statement: Boolean = false, installmentParent: Boolean = false,
    ) = Transaction(
        title = title, category = category, type = TransactionType.Expense, amount = amount,
        date = months[dated].atDay(15), budgetMonth = months[budgetMonth],
        isCreditCardStatement = statement, hasInstallments = installmentParent,
    )

    @Test fun categoryBarListsItsBudgetMonthExpensesBiggestFirst() {
        val h = history(listOf(allocation(Groceries, 3, 500)))
        val expenses = listOf(
            spend("Small", Groceries, 100, 3, 3),
            spend("Big", Groceries, 300, 3, 3),
            // Dated in month 3 but billed to month 4, so it belongs to month 4's bar.
            spend("Card", Groceries, 999, 3, 4),
            spend("Other", Meals, 50, 3, 3),
        )
        assertEquals(listOf("Big", "Small"), h.transactions(BudgetHistoryFilter.Category(Groceries), months[3], expenses).map { it.title })
    }

    @Test fun wholeMonthListsExpensesByDateWithoutStatementPayments() {
        val h = history()
        val expenses = listOf(
            spend("Card", Groceries, 999, 3, 4),
            spend("Statement", TransactionCategory.CreditCard, 5_000, 3, 3, statement = true),
            spend("Next month", Meals, 10, 4, 3),
        )
        assertEquals(listOf("Card"), h.transactions(BudgetHistoryFilter.WholeMonth, months[3], expenses).map { it.title })
    }

    @Test fun outsideListsOnlyCategoriesWithNoAllocationThatMonth() {
        // Groceries planned in month 3 only; travel never.
        val h = history(listOf(allocation(Groceries, 3, 500)))
        val expenses = listOf(
            spend("Groceries 3", Groceries, 100, 3, 3),
            spend("Groceries 4", Groceries, 200, 4, 4),
            spend("Travel 3", Travel, 300, 3, 3),
        )
        assertEquals(listOf("Travel 3"), h.transactions(BudgetHistoryFilter.OutsideAllocations, months[3], expenses).map { it.title })
        assertEquals(listOf("Groceries 4"), h.transactions(BudgetHistoryFilter.OutsideAllocations, months[4], expenses).map { it.title })
    }

    @Test fun parentInstallmentsNeverShow() {
        val h = history(listOf(allocation(TransactionCategory.Education, 3, 500)))
        val expenses = listOf(
            spend("Student card", TransactionCategory.Education, 0, 3, 3, installmentParent = true),
            spend("Course", TransactionCategory.Education, 120, 3, 3),
        )
        assertEquals(listOf("Course"), h.transactions(BudgetHistoryFilter.Category(TransactionCategory.Education), months[3], expenses).map { it.title })
        assertEquals(listOf("Course"), h.transactions(BudgetHistoryFilter.WholeMonth, months[3], expenses).map { it.title })
    }

    // ---- What made Saved

    private fun part(category: TransactionCategory) = SavingsContributors.Part.Category(category)

    @Test fun wholeMonthIsExplainedByCategoriesAndTheRemainder() {
        // Months 1 and 2: budget 1_000, used 900, so the whole month saves 200.
        val h = history(
            allocations = listOf(allocation(Groceries, 1, 500), allocation(Groceries, 2, 500), allocation(Meals, 1, 200), allocation(Meals, 2, 200)),
            spent = mapOf(Groceries to mapOf(months[1] to 400L, months[2] to 450L), Meals to mapOf(months[1] to 260L, months[2] to 240L)),
            totals = mapOf(months[1] to BudgetHistory.MonthTotal(1_000, 900), months[2] to BudgetHistory.MonthTotal(1_000, 900)),
        )
        val result = h.contributors(BudgetHistoryFilter.WholeMonth, null, null)!!
        assertEquals(200L, result.total)
        // Groceries +150, meals -100, the remainder 200 - 50 = +150.
        assertEquals(listOf(part(Groceries), SavingsContributors.Part.OutsideAllocations), result.savers.map { it.part })
        assertEquals(listOf<SavingsContributors.Part>(part(Meals)), result.overspenders.map { it.part })
        assertEquals(0L, result.others)
        assertEquals(months[1], result.firstMonth)
        assertEquals(months[2], result.lastMonth)
    }

    private val fiveClosed = BudgetHistory(
        months, current,
        series(100L to 50L, 100L to 60L, 100L to 70L, 100L to 80L, 100L to 110L, 100L to 1L),
        emptyList(),
    )

    @Test fun onlyThreeNamedPerSideAndTheRestAddUp() {
        // Five closed months: +50, +40, +30, +20, -10; the sixth is open.
        val result = fiveClosed.contributors(BudgetHistoryFilter.WholeMonth, null, null)!!
        assertEquals(listOf(50L, 40L, 30L), result.savers.map { it.net })
        assertEquals(listOf(-10L), result.overspenders.map { it.net })
        assertEquals(20L, result.others)
        assertEquals(1, result.othersCount)
        assertEquals(130L, result.total)
    }

    @Test fun othersKeepsItsPartsBiggestFirst() {
        val result = fiveClosed.contributors(BudgetHistoryFilter.WholeMonth, null, null)!!
        assertEquals(listOf(20L), result.rest.map { it.net })
        assertEquals(20L, result.others)
    }

    @Test fun categoryIsExplainedByItsMonthsWithinThePeriod() {
        val h = history(
            allocations = listOf(allocation(Groceries, 1, 500), allocation(Groceries, 2, 500), allocation(Groceries, 3, 500)),
            spent = mapOf(Groceries to mapOf(months[1] to 450L, months[2] to 520L, months[3] to 100L)),
        )
        val result = h.contributors(BudgetHistoryFilter.Category(Groceries), months[2], months[3])!!
        assertEquals(listOf(SavingsContributors.Item(SavingsContributors.Part.Month(months[3]), 400)), result.savers)
        assertEquals(listOf(SavingsContributors.Item(SavingsContributors.Part.Month(months[2]), -20)), result.overspenders)
        assertEquals(380L, result.total)
        assertNull(h.contributors(BudgetHistoryFilter.Category(Groceries), months[4], null))
    }

    /** Month 1 has unallocated budget; month 2's categories took more than the budget. */
    private val outsideLedger get() = history(
        allocations = listOf(allocation(Groceries, 1, 500), allocation(Groceries, 2, 1_100)),
        spent = mapOf(Groceries to mapOf(months[1] to 450L, months[2] to 1_000L), Travel to mapOf(months[1] to 100L, months[2] to 200L)),
        totals = mapOf(months[1] to BudgetHistory.MonthTotal(1_000, 700), months[2] to BudgetHistory.MonthTotal(1_000, 1_200)),
    )

    @Test fun outsideDifferencesNameTheirReasonAndAddUp() {
        val h = outsideLedger
        val differences = h.outsideDifferences(null, null)
        assertEquals(
            listOf(BudgetHistory.OutsideDifference.Reason.CategoriesAboveBudget, BudgetHistory.OutsideDifference.Reason.SpentOutsideWithNoRoom, BudgetHistory.OutsideDifference.Reason.OtherMonth),
            differences.map { it.reason },
        )
        // Month 2's -300 is two true parts: categories 100 above the budget, and 200 on travel with no budget left.
        assertEquals(listOf(months[2]), differences[0].months)
        assertEquals(-100L, differences[0].amount)
        assertEquals(-200L, differences[1].amount)
        assertEquals(-150L, differences[2].amount)
        assertEquals(h.outsideTiming(null, null), differences.sumOf { it.amount })
    }

    @Test fun outsideViewTotalsToItsRowAndListsTheDifferences() {
        val h = outsideLedger
        val row = h.outsideAllocations(null, null)
        assertEquals(row, h.outsideSavings(null, null)?.net)
        val why = h.contributors(BudgetHistoryFilter.OutsideAllocations, null, null)!!
        assertEquals(row, why.total)
        val parts = (why.savers + why.overspenders + why.rest).map { it.part }
        assertTrue(SavingsContributors.Part.Month(months[1]) in parts)
        assertTrue(SavingsContributors.Part.Difference(BudgetHistory.OutsideDifference.Reason.CategoriesAboveBudget) in parts)
        assertTrue(SavingsContributors.Part.Difference(BudgetHistory.OutsideDifference.Reason.SpentOutsideWithNoRoom) in parts)
    }

    @Test fun categoriesUsingExactlyTheBudgetLeaveOnlyTheOutsideSpending() {
        // Budget 1_000, groceries 1_000: no gap line, only the 120 spent on travel with no room.
        val h = history(
            allocations = listOf(allocation(Groceries, 2, 1_000)),
            spent = mapOf(Groceries to mapOf(months[2] to 900L), Travel to mapOf(months[2] to 120L)),
            totals = mapOf(months[2] to BudgetHistory.MonthTotal(1_000, 1_020)),
        )
        val differences = h.outsideDifferences(null, null)
        assertEquals(listOf(BudgetHistory.OutsideDifference.Reason.SpentOutsideWithNoRoom), differences.map { it.reason })
        assertEquals(-120L, differences.first().amount)
        assertEquals(h.outsideTiming(null, null), differences.sumOf { it.amount })
    }

    @Test fun backReturnsToWhereTheDrillStartedAndThePickerStartsOver() {
        val h = history(listOf(allocation(Groceries, 3, 500)), totals = months.associateWith { BudgetHistory.MonthTotal(100, 90) })
        var s = BudgetHistoryUiState().withHistory(h, firstLoad = true)
        assertTrue(s.filterTrail.isEmpty())
        s = s.drilled(BudgetHistoryFilter.Category(Groceries))
        assertEquals(listOf<BudgetHistoryFilter>(BudgetHistoryFilter.WholeMonth), s.filterTrail)
        s = s.back()
        assertEquals(BudgetHistoryFilter.WholeMonth, s.filter)
        assertTrue(s.filterTrail.isEmpty())
        s = s.drilled(BudgetHistoryFilter.Category(Groceries)).chosen(BudgetHistoryFilter.WholeMonth)
        assertTrue(s.filterTrail.isEmpty())
    }

    @Test fun savedFollowsTheSelectedMonth() {
        val h = history(totals = months.associateWith { BudgetHistory.MonthTotal(100, 90) })
        var s = BudgetHistoryUiState().withHistory(h, firstLoad = true)
        // The open month counts up to the month before it: all five closed months.
        assertEquals(5, s.savings.months)
        assertEquals(months[4], s.savingsEndMonth)
        s = s.copy(selected = months[2])
        assertEquals(3, s.savings.months)
        assertEquals(months[2], s.savingsEndMonth)
    }

    @Test fun onlyCountsTheSelectedMonthAndTheWhyCardFollows() {
        val h = history(totals = months.associateWith { BudgetHistory.MonthTotal(100, 90) })
        var s = BudgetHistoryUiState().withHistory(h, firstLoad = true).copy(selected = months[2], savingsScope = SavingsScope.Only)
        assertEquals(1, s.savings.months)
        assertEquals(10L, s.savings.net)
        assertEquals(10L, s.contributors?.total)
        assertEquals(months[2], s.contributors?.firstMonth)
        assertFalse(s.isSoFar)
        // Scrubbing the chart moves the one month counted.
        s = s.copy(selected = months[4])
        assertEquals(months[4], s.contributors?.firstMonth)
    }

    @Test fun onlyIgnoresTheChosenStartWithoutChangingIt() {
        val h = history(totals = months.associateWith { BudgetHistory.MonthTotal(100, 90) })
        val upTo = BudgetHistoryUiState().withHistory(h, firstLoad = true).copy(selected = months[2], savingsStart = months[3])
        assertEquals(0, upTo.savings.months)
        val only = upTo.copy(savingsScope = SavingsScope.Only)
        assertEquals(1, only.savings.months)
        assertEquals(months[3], only.savingsStart)
    }

    @Test fun onlyOnTheOpenMonthCountsItSoFar() {
        val h = history(totals = months.associateWith { BudgetHistory.MonthTotal(100, 90) })
        val s = BudgetHistoryUiState().withHistory(h, firstLoad = true).copy(savingsScope = SavingsScope.Only)
        // What the open month has left up to today, and the Why card adds up to the same.
        assertTrue(s.isSoFar)
        assertEquals(1, s.savings.months)
        assertEquals(s.savings.net, s.contributors?.total)
        assertEquals(current, s.contributors?.firstMonth)
        // The running total still leaves the open month out.
        val upTo = s.copy(savingsScope = SavingsScope.UpTo)
        assertFalse(upTo.isSoFar)
        assertEquals(5, upTo.savings.months)
    }

    // ---- Trimming

    @Test fun leadingEmptyMonthsAreTrimmedButTheOpenMonthStays() {
        val trimmed = series(0L to 0L, 0L to 0L, 100L to 50L, 0L to 0L, 100L to 60L, 100L to 10L).trimmingLeadingEmptyMonths()
        assertEquals(months.drop(2), trimmed.months.map { it.month })
        assertEquals(listOf(months[2]), series(0L to 0L, 0L to 0L, 0L to 0L).trimmingLeadingEmptyMonths().months.map { it.month })
        assertEquals(months.drop(3), series(1L to 1L, 2L to 2L, 3L to 3L, 4L to 4L, 5L to 5L, 6L to 6L).suffix(3).months.map { it.month })
    }

    // ---- Building

    @Test fun categoryMonthsPairAllocationWithSpending() {
        val h = history(listOf(allocation(Groceries, 4, 500), allocation(Groceries, 5, 500)), mapOf(Groceries to mapOf(months[4] to 650L, months[5] to 120L)))
        val groceries = h.series(BudgetHistoryFilter.Category(Groceries))!!
        assertEquals(Status.Over, groceries.month(months[4])?.status)
        assertEquals(Status.InProgress, groceries.month(months[5])?.status)
        assertEquals(Status.Empty, groceries.month(months[3])?.status)
    }

    @Test fun twoRowsForOneCategoryAndMonthAreSummed() {
        val h = history(listOf(allocation(Meals, 2, 100, id = 1), allocation(Meals, 2, 50, id = 2)))
        assertEquals(150L, h.series(BudgetHistoryFilter.Category(Meals))?.month(months[2])?.planned)
    }

    @Test fun categoriesWithNoPlanInTheWindowAreLeftOutAndDeletedMonthsDoNotCount() {
        val before = AllocationRow(month = months[0].minusMonths(1), category = Travel, amount = 900)
        val deleted = allocation(Meals, 1, 300).copy(isDeleted = true)
        val h = history(listOf(before, allocation(Gifts, 1, 0), deleted))
        assertEquals(listOf<BudgetHistoryFilter>(BudgetHistoryFilter.WholeMonth), h.filters)
    }

    @Test fun categoriesAreOrderedByThisMonthsPlanThenByTheWindowsTotal() {
        val h = history(listOf(allocation(Meals, 5, 200), allocation(Groceries, 5, 800), allocation(Travel, 1, 5_000), allocation(Gifts, 1, 10)))
        assertEquals(
            listOf(BudgetHistoryFilter.WholeMonth) + listOf(Groceries, Meals, Travel, Gifts).map { BudgetHistoryFilter.Category(it) },
            h.filters,
        )
    }

    @Test fun wholeMonthComesFromTheMonthTotals() {
        val h = history(totals = mapOf(months[3] to BudgetHistory.MonthTotal(1_000, 1_200), months[4] to BudgetHistory.MonthTotal(null, 300)))
        assertEquals(Status.Over, h.wholeMonth.month(months[3])?.status)
        assertEquals(Status.NoPlan, h.wholeMonth.month(months[4])?.status)
        assertEquals(Status.Empty, h.wholeMonth.month(months[0])?.status)
        assertFalse(h.isEmpty)
        assertTrue(history().isEmpty)
        assertEquals(months.dropLast(1), history().closedMonths)
    }

    // ---- Reading the ledger

    private fun expense(category: TransactionCategory, month: YearMonth, amount: Long, card: Long? = null) = Transaction(
        title = "x", category = category, type = TransactionType.Expense, amount = amount,
        date = month.atDay(10), budgetMonth = month, creditCardId = card,
    )

    @Test fun readerReachesBackToTheFirstPlanAndMatchesTheCards() {
        val today = LocalDate.of(2026, 10, 17)
        val now = YearMonth.from(today)
        val first = now.minusMonths(20)
        val h = BudgetHistoryReader.read(
            ledgerRows = listOf(expense(Groceries, now.minusMonths(1), 700), expense(Groceries, now.minusMonths(1), 50, card = 1)),
            budgets = listOf(Budget(first, 1_000)),
            balanceOffset = 0,
            allocations = listOf(AllocationRow(month = now.minusMonths(1), category = Groceries, amount = 600)),
            today = today,
        )
        assertEquals(21, h.months.size)
        assertEquals(first, h.months.first())
        val groceries = h.series(BudgetHistoryFilter.Category(Groceries))!!.month(now.minusMonths(1))!!
        // Card purchases count against the allocation in their budget month, as on the card.
        assertEquals(750L, groceries.spent)
        assertEquals(Status.Over, groceries.status)
        // A ledger with no plan still gets the thirteen-month window.
        assertEquals(13, BudgetHistoryReader.read(emptyList(), emptyList(), 0, emptyList(), today).months.size)
    }

    // ---- Screen state (BudgetHistoryViewModelTests)

    private fun state(selected: YearMonth = current) =
        BudgetHistoryUiState(selected = selected).withHistory(
            history(totals = months.associateWith { BudgetHistory.MonthTotal(100, 90) }),
            firstLoad = true,
        )

    @Test fun arrowsFromTheOpenMonthGoBackButNotForward() {
        val s = state()
        assertEquals(months[4], s.neighbour(-1))
        assertNull(s.neighbour(1))
    }

    @Test fun arrowsStepBothWaysFromAMiddleMonthAndStopAtTheFirstBar() {
        assertEquals(months[1], state(months[2]).neighbour(-1))
        assertEquals(months[3], state(months[2]).neighbour(1))
        assertNull(state(months[0]).neighbour(-1))
    }

    @Test fun startOptionsBeginAtTheFirstPlannedMonthAndLeaveOutTheOpenOne() {
        val h = history(totals = mapOf(months[2] to BudgetHistory.MonthTotal(100, 50), months[3] to BudgetHistory.MonthTotal(100, 50)))
        val s = BudgetHistoryUiState().withHistory(h, firstLoad = true)
        assertEquals(months.subList(2, 5), s.savingsStartOptions)
        assertEquals(emptyList<YearMonth>(), BudgetHistoryUiState().withHistory(history(), firstLoad = true).savingsStartOptions)
    }

    @Test fun aFilterThatIsGoneFallsBackToTheWholeMonth() {
        val s = BudgetHistoryUiState(filter = BudgetHistoryFilter.Category(Travel)).withHistory(history(), firstLoad = true)
        assertEquals(BudgetHistoryFilter.WholeMonth, s.filter)
    }

    @Test fun previewEndsAtTheMonthOnScreenAndHidesWithNoPlan() {
        val h = history(months.indices.map { allocation(Groceries, it, 100, id = it + 1L) })
        val groceries = h.series(BudgetHistoryFilter.Category(Groceries))
        assertEquals(months.take(4), groceries.previewEnding(months[3])!!.months.map { it.month })
        assertNull(history().series(BudgetHistoryFilter.Category(Groceries)).previewEnding(months[3]))
    }
}
