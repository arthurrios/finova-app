package com.arthurrios.finova.domain.history

import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.AllocationBalanceProjection
import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.UnallocatedSpending
import com.arthurrios.finova.domain.allocation.UnallocatedSummary
import com.arthurrios.finova.domain.history.BudgetForecastFigures.Status
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.Groceries
import com.arthurrios.finova.domain.model.TransactionCategory.Market
import com.arthurrios.finova.domain.model.TransactionCategory.Meals
import com.arthurrios.finova.domain.model.TransactionCategory.Salary
import com.arthurrios.finova.domain.model.TransactionCategory.Taxes
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.budget.projection
import com.arthurrios.finova.ui.dashboard.MonthPageUi
import com.arthurrios.finova.ui.history.BudgetForecastText
import com.arthurrios.finova.ui.history.BudgetHistoryUiState
import com.arthurrios.finova.ui.history.HistorySpan
import com.arthurrios.finova.ui.history.legendRows
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/**
 * Port of BudgetHistoryForecastTests.swift: what each filter reads from one projected month, that a
 * month with no budget never reads as a plan of zero, that a projected month reaches no score, that
 * the screen moves through past and projected months as one run, and that a month carries the
 * dashboard's own projection.
 */
class BudgetHistoryForecastTest {
    private val today = LocalDate.of(2026, 10, 15)
    private val current = YearMonth.from(today)

    private fun anchor(offset: Int): YearMonth = current.plusMonths(offset.toLong())

    private fun allocation(category: TransactionCategory, planned: Long, used: Long, month: YearMonth) =
        BudgetAllocation(0, month, category, planned, isRecurring = false, parentId = null, used = used)

    /**
     * Budget 10.000: groceries planned 3.000 with 1.000 dated, meals planned 2.000 and already 2.500,
     * and 1.200 of taxes in a category with no allocation.
     */
    private fun month(offset: Int = 1, budget: Long = 10_000, balance: Long? = 50_000, deferred: Long = 0): BudgetForecastMonth {
        val anchor = anchor(offset)
        return BudgetForecastMonth.of(
            month = anchor,
            allocations = listOf(allocation(Groceries, 3_000, 1_000, anchor), allocation(Meals, 2_000, 2_500, anchor)),
            summary = UnallocatedSummary(anchor, budget, 5_000, 1_200),
            unallocatedSpending = listOf(UnallocatedSpending(Taxes, 1_200)),
            closingBalance = balance,
            deferredCardSpending = deferred,
            statementsDue = 700,
        )
    }

    private fun emptyMonth(offset: Int): BudgetForecastMonth {
        val anchor = anchor(offset)
        return BudgetForecastMonth.of(anchor, emptyList(), UnallocatedSummary(anchor, 0, 0, 0), emptyList(), null, 0, 0)
    }

    private fun figures(month: BudgetForecastMonth, filter: BudgetHistoryFilter) = BudgetForecast(listOf(month)).figures(filter)[0]

    private val whole = BudgetHistoryFilter.WholeMonth
    private val outside = BudgetHistoryFilter.OutsideAllocations
    private fun category(category: TransactionCategory) = BudgetHistoryFilter.Category(category)

    // ---- Filters

    @Test fun wholeMonthExpectsTheFullPlanPlusWhatIsDatedOutsideIt() {
        val f = figures(month(), whole)
        assertEquals(10_000L, f.planned)
        // Groceries at their plan, meals at the 2.500 already past theirs.
        assertEquals(5_500L, f.inside)
        assertEquals(1_200L, f.outside)
        assertEquals(6_700L, f.expected)
        assertEquals(3_300L, f.difference)
        assertEquals(Status.Fits, f.status)
    }

    @Test fun categoryReadsItsPlanAgainstItsDatedRows() {
        val f = figures(month(), category(Groceries))
        assertEquals(3_000L, f.planned)
        assertEquals(1_000L, f.expected)
        assertEquals(2_000L, f.difference)
        assertEquals(Status.Fits, f.status)
    }

    @Test fun categoryPastItsPlanIsShort() {
        val f = figures(month(), category(Meals))
        assertEquals(Status.Short, f.status)
        assertEquals(-500L, f.difference)
    }

    @Test fun categoryWithNoAllocationThatMonthHasRowsButNoPlan() {
        val f = figures(month(), category(Taxes))
        assertFalse(f.hasPlan)
        assertEquals(1_200L, f.expected)
        assertEquals(Status.NoPlan, f.status)
    }

    @Test fun outsideReadsTheUnallocatedBudgetAgainstOutsideRows() {
        val f = figures(month(), outside)
        assertEquals(5_000L, f.planned)
        assertEquals(1_200L, f.expected)
        assertEquals(3_800L, f.difference)
    }

    @Test fun outsideHasNoPlanWhenTheCategoriesTookTheBudget() {
        val f = figures(month(budget = 4_000), outside)
        assertFalse(f.hasPlan)
        assertEquals(Status.NoPlan, f.status)
    }

    @Test fun sameCategoryAllocationsAreSummed() {
        val anchor = anchor(1)
        val month = BudgetForecastMonth.of(
            anchor, listOf(allocation(Groceries, 1_000, 400, anchor), allocation(Groceries, 500, 400, anchor)),
            UnallocatedSummary(anchor, 0, 1_500, 0), emptyList(), null, 0, 0,
        )
        assertEquals(listOf(BudgetForecastMonth.Allocation(Groceries, 1_500, 400)), month.allocations)
    }

    private fun row(amount: Long, category: TransactionCategory, month: YearMonth = anchor(1), summary: Boolean = false) = Transaction(
        title = "t", category = category, type = TransactionType.Expense, amount = amount,
        date = month.atDay(10), budgetMonth = month, hasInstallments = summary,
    )

    @Test fun rowsFollowTheFilterAndHideTheInstallmentSummaryRow() {
        val forecast = BudgetForecast(listOf(month()))
        val rows = listOf(row(100, Groceries), row(900, Taxes), row(50, Groceries, anchor(2)), row(0, Taxes, summary = true))
        assertEquals(listOf(900L, 100L), forecast.transactions(whole, anchor(1), rows).map { it.amount })
        assertEquals(listOf(100L), forecast.transactions(category(Groceries), anchor(1), rows).map { it.amount })
        assertEquals(listOf(900L), forecast.transactions(outside, anchor(1), rows).map { it.amount })
    }

    // ---- No budget

    @Test fun aMonthWithNoBudgetHasNoPlanRatherThanAPlanOfZero() {
        val f = figures(month(budget = 0), whole)
        assertFalse(f.hasPlan)
        assertNull(f.percentExpected)
        assertEquals(Status.NoPlan, f.status)
        assertEquals(6_700L, f.expected)
        assertEquals(0L, f.overPlan)
        assertEquals(R.string.history_forecast_no_budget, BudgetForecastText.status(f, hidden = false).text)
    }

    @Test fun aMonthWithNothingAtAllIsEmpty() {
        assertEquals(Status.Empty, figures(emptyMonth(1), whole).status)
        assertTrue(BudgetForecast(listOf(emptyMonth(1))).isEmpty)
    }

    // ---- Chart pieces

    @Test fun barPiecesAddUpToWhatIsExpected() {
        val short = figures(month(budget = 6_000), whole)
        assertEquals(5_500L, short.insideWithinPlan)
        assertEquals(500L, short.outsideWithinPlan)
        assertEquals(700L, short.overPlan)
        assertEquals(short.expected, short.insideWithinPlan + short.outsideWithinPlan + short.overPlan)
    }

    // ---- Dashboard

    /** The same values through the card's projection and through a projected month. */
    @Test fun aFutureMonthCarriesTheDashboardProjection() {
        val anchor = anchor(1)
        val allocations = listOf(allocation(Groceries, 3_000, 1_000, anchor), allocation(Meals, 2_000, 2_500, anchor))
        val summary = UnallocatedSummary(anchor, 10_000, 5_000, 1_200)
        val spending = listOf(UnallocatedSpending(Taxes, 1_200))
        val page = MonthPageUi(
            month = anchor, isCurrentMonth = false, isPastMonth = false, usedValue = 4_700, budgetLimit = 10_000,
            finalBalance = 50_000, currentBalance = 50_000, transactions = emptyList(),
            allocations = allocations, unallocated = summary, offPlan = spending, deferredCardSpending = 300,
        )
        val month = BudgetForecastMonth.of(anchor, allocations, summary, spending, 50_000, 300, 0)

        val dashboard = page.projection()!!
        assertEquals(dashboard, month.projection)
        // 50.000 - 300 deferred - 2.000 groceries unspent.
        assertEquals(47_700L, month.projection?.projected)
        // The month's own figures are the card's terms, added up.
        assertEquals(dashboard.usedWithinAllocations + dashboard.unspentAllocations + dashboard.overspent, month.inside + month.outside)
    }

    @Test fun noBalanceMeansNoProjectionLikeTheCard() {
        assertNull(month(balance = null).projection)
    }

    // ---- Stats

    /** Five closed months on plan, then the open one. */
    private val pastHistory: BudgetHistory
        get() {
            val anchors = (-5..0).map(::anchor)
            return BudgetHistory.of(anchors, anchors.last(), emptyList(), emptyMap(), anchors.associateWith { BudgetHistory.MonthTotal(1_000, 900) })
        }

    private fun state(forecast: BudgetForecast, filter: BudgetHistoryFilter = whole, month: YearMonth? = null) =
        BudgetHistoryUiState(filter = filter, selected = month ?: current).withHistory(pastHistory, firstLoad = true, newForecast = forecast)

    private val sixMonths: BudgetForecast
        get() = BudgetForecast((1..BudgetForecast.MONTHS_AHEAD).map { month(it, budget = 100) })

    @Test fun projectedMonthsReachNoScoreAndNoSavings() {
        val without = state(BudgetForecast.Empty)
        val with = state(sixMonths)

        assertEquals(without.series, with.series)
        assertEquals(5, with.series.monthsOnPlan)
        assertEquals(5, with.series.streak)
        assertEquals(without.series.usageRange, with.series.usageRange)
        assertEquals(without.savings, with.savings)
        assertEquals(without.savingsStartOptions, with.savingsStartOptions)
        assertFalse(with.series.months.any { it.month > anchor(0) })

        // Selecting a month ahead moves none of them either.
        val selected = with.selecting(anchor(3))
        assertEquals(anchor(3), selected.selectedForecast?.month)
        assertEquals(without.savings, selected.savings)
        assertEquals(anchor(0), selected.savingsEnd)
        assertEquals(5, selected.series.streak)
    }

    @Test fun seriesNeverTakesMonthsPastTheOpenOne() {
        assertEquals(anchor(0), pastHistory.months.last())
        assertEquals(anchor(-1), pastHistory.closedMonths.last())
    }

    // ---- Screen state

    @Test fun arrowsWalkFromThePastIntoTheForecastAndStopAtItsEnd() {
        var s = state(sixMonths)
        assertEquals(anchor(1), s.neighbour(1))
        assertEquals(anchor(-1), s.neighbour(-1))

        s = s.selecting(anchor(1))
        assertEquals(anchor(1), s.displayedMonth)
        assertEquals(anchor(0), s.neighbour(-1))

        s = s.selecting(anchor(BudgetForecast.MONTHS_AHEAD))
        assertNull(s.neighbour(1))
    }

    @Test fun aMonthPastTheForecastCannotBeSelected() {
        val s = state(sixMonths).selecting(anchor(BudgetForecast.MONTHS_AHEAD + 1))
        assertEquals(anchor(0), s.selected)
    }

    @Test fun openingOnAMonthAheadSelectsIt() {
        assertEquals(anchor(2), state(sixMonths, month = anchor(2)).selectedForecast?.month)
    }

    @Test fun openingPastTheForecastFallsBackToTheOpenMonth() {
        val s = state(sixMonths, month = anchor(9))
        assertEquals(anchor(0), s.selected)
        assertNull(s.selectedForecast)
    }

    @Test fun changingFilterKeepsTheProjectedMonthSelected() {
        val s = state(sixMonths, month = anchor(2)).chosen(category(Groceries))
        assertEquals(anchor(2), s.selectedForecast?.month)
        assertEquals(3_000L, s.selectedForecast?.planned)
    }

    @Test fun changingRangeKeepsTheProjectedMonthSelected() {
        val s = state(sixMonths, month = anchor(2))
            .copy(span = HistorySpan.TwelveMonths).keepingSelectionVisible()
            .copy(span = HistorySpan.SixMonths).keepingSelectionVisible()
        assertEquals(anchor(2), s.selected)
    }

    @Test fun aCategoryPlannedOnlyAheadIsOfferedWithNoPastBars() {
        var s = state(sixMonths)
        assertTrue(category(Groceries) in s.filters)

        s = s.chosen(category(Groceries))
        assertTrue(s.series.months.isEmpty())
        assertEquals(anchor(1), s.selectedForecast?.month)
        assertEquals(BudgetHistorySeries.Savings.None, s.savings)
    }

    @Test fun aForecastOnlyCategorySurvivesAReloadOfTheLedger() {
        val s = state(sixMonths, filter = category(Groceries))
        assertEquals(category(Groceries), s.filter)
    }

    @Test fun onlyAForecastIsNotAnEmptyScreen() {
        val s = BudgetHistoryUiState().withHistory(BudgetHistory.Empty, firstLoad = true, newForecast = sixMonths)
        assertFalse(s.isEmpty)
    }

    @Test fun withNothingAheadThePastBarsKeepTheChart() {
        val s = state(BudgetForecast((1..6).map(::emptyMonth)))
        assertTrue(s.forecastMonths.isEmpty())
        assertNull(s.neighbour(1))
        assertEquals(anchor(0), s.selecting(anchor(1)).selected)
    }

    @Test fun aFilterWithNothingAheadShowsNoColumnsWhileTheOthersDo() {
        val s = state(sixMonths)
        assertEquals(BudgetForecast.MONTHS_AHEAD, s.forecastMonths.size)
        assertTrue(s.chosen(category(Market)).forecastMonths.isEmpty())
    }

    @Test fun detailListsRowsOfTheChosenFilter() {
        val s = state(sixMonths, month = anchor(1))
        val detail = s.forecastDetail(s.selectedForecast!!)!!
        assertEquals(700L, detail.month.statementsDue)
        assertEquals(0, detail.scheduledCount)
    }

    @Test fun detailTakesTheThreeBiggestRowsAndCountsThemAll() {
        val rows = listOf(row(10, Taxes), row(40, Taxes), row(20, Taxes), row(30, Taxes), row(0, Taxes))
        val s = state(sixMonths, month = anchor(1)).copy(expenses = rows)
        val detail = s.forecastDetail(s.selectedForecast!!)!!
        assertEquals(4, detail.scheduledCount)
        assertEquals(listOf(40L, 30L, 20L), detail.biggest.map { it.amount })
    }

    // ---- Text

    @Test fun hiddenValuesLeaveNoAmountInStatusOrTalkBack() {
        listOf(figures(month(), whole), figures(month(budget = 6_000), whole)).forEach { f ->
            assertTrue(BudgetForecastText.status(f, hidden = true).amounts.isEmpty())
            assertTrue(BudgetForecastText.accessibility(f, hidden = true).all { it.amounts.isEmpty() })
        }
    }

    @Test fun talkBackSaysTheValueIsProjected() {
        listOf(false, true).forEach { hidden ->
            assertEquals(R.string.history_forecast_badge, BudgetForecastText.accessibility(figures(month(), whole), hidden).first().text)
        }
    }

    // ---- Legend

    @Test fun legendStaysOnOneRowWhenItFits() {
        assertEquals(listOf(listOf(0, 1, 2, 3, 4)), legendRows(listOf(20, 20, 20, 20, 20), breakAt = 3, gap = 5, maxWidth = 120))
    }

    @Test fun legendDropsTheForecastItemsToASecondRowWhenItDoesNot() {
        assertEquals(listOf(listOf(0, 1, 2), listOf(3, 4)), legendRows(listOf(20, 20, 20, 20, 20), breakAt = 3, gap = 5, maxWidth = 119))
    }

    @Test fun aLegendRowStillTooWideWrapsBetweenLabels() {
        assertEquals(listOf(listOf(0), listOf(1, 2), listOf(3)), legendRows(listOf(40, 20, 20, 20), breakAt = 3, gap = 5, maxWidth = 45))
    }

    // ---- BudgetHistoryReader.forecast against the dashboard's read of one ledger

    private val thisMonth = current
    private val nextMonth = current.plusMonths(1)
    private val monthAfter = current.plusMonths(2)

    private val cardId = 7L
    private val statementId = 3L
    private val statements = listOf(CreditCardStatement(id = statementId, creditCardId = cardId, closingDate = nextMonth.atDay(28), dueDate = monthAfter.atDay(8)))

    private val stored = listOf(
        row(500_000, Salary, thisMonth).copy(type = TransactionType.Income),
        row(12_000, Market, nextMonth),
        row(8_000, Meals, nextMonth),
        // Charged to next month's plan, on a statement that settles the month after: the deferred term.
        row(5_000, Market, nextMonth).copy(creditCardId = cardId, statementId = statementId),
        // After the month: must not reach its closing balance.
        row(30_000, Market, monthAfter),
    )
    private val statementRow = Transaction(
        id = -3007, title = "Visa", category = TransactionCategory.CreditCard, type = TransactionType.Expense, amount = 5_000,
        date = monthAfter.atDay(8), budgetMonth = nextMonth, creditCardId = cardId, isCreditCardStatement = true,
    )
    private val ledger = stored + statementRow
    private val budgets = listOf(Budget(nextMonth, 100_000))
    private val allocationRows = listOf(AllocationRow(id = 1, month = nextMonth, category = Market, amount = 40_000))

    private fun read() = BudgetHistoryReader.forecast(ledger, budgets, 0, allocationRows, statements, today)

    /** What DashboardViewModel hands the card, on its wider range of months. */
    private fun dashboardPage(month: YearMonth): MonthPageUi {
        val summary = LedgerCalculator.monthlySummaries(ledger, budgets, 0, (-2..7).map(::anchor), today).first { it.month == month }
        return MonthPageUi(
            month = month, isCurrentMonth = false, isPastMonth = false, usedValue = summary.usedValue, budgetLimit = summary.budgetLimit,
            finalBalance = summary.finalBalance, currentBalance = summary.currentBalance, transactions = emptyList(),
            allocations = Allocations.withUsage(allocationRows, stored, month).sortedByDescending { it.allocated },
            unallocated = Allocations.unallocatedSummary(allocationRows, stored, budgets, month),
            offPlan = Allocations.unallocatedSpending(allocationRows, stored, month),
            deferredCardSpending = Allocations.deferredCardSpending(stored, statements, month),
        )
    }

    @Test fun theReaderReadsTheMonthTheDashboardCardBuilds() {
        val forecast = read()
        assertEquals((1..BudgetForecast.MONTHS_AHEAD).map(::anchor), forecast.months.map { it.month })

        val month = forecast.month(nextMonth)!!
        val dashboard = dashboardPage(nextMonth).projection()!!
        assertEquals(dashboard, month.projection)
        assertEquals(AllocationBalanceProjection.Tense.Projected, month.projection?.tense)
        assertEquals(dashboardPage(nextMonth).finalBalance, dashboard.base)

        // 500.000 in, 20.000 out in cash, 5.000 deferred, 23.000 of the plan unspent.
        assertEquals(480_000L, month.projection?.base)
        assertEquals(5_000L, month.projection?.deferredCardSpending)
        assertEquals(452_000L, month.projection?.projected)
        assertEquals(100_000L, month.budget)
        assertEquals(40_000L, month.inside)
        assertEquals(8_000L, month.outside)
    }

    @Test fun everyMonthAheadMatchesTheDashboard() {
        read().months.forEach { assertEquals(dashboardPage(it.month).projection(), it.projection) }
    }

    @Test fun aStatementMovesTheBalanceButNotTheExpectedCosts() {
        val due = read().month(monthAfter)!!
        assertEquals(5_000L, due.statementsDue)
        // The month's only row in a category: the statement's own category never shows up.
        assertEquals(30_000L, due.outside)
        assertNull(due.outsideByCategory[TransactionCategory.CreditCard])
        // 480.000 - 30.000 - the 5.000 statement.
        assertEquals(445_000L, due.projection?.base)
        assertEquals(0L, read().month(nextMonth)?.statementsDue)
    }

    @Test fun aCardPurchaseCountsOnceInTheMonthItWasMade() {
        val forecast = read()
        assertEquals(17_000L, forecast.month(nextMonth)?.allocations?.single()?.scheduled)
        assertNotNull(forecast.month(monthAfter))
        val wholeFigures = forecast.figures(whole)
        assertEquals(listOf(48_000L, 30_000L), wholeFigures.take(2).map { it.expected })
    }

    @Test fun nothingAheadReadsAsEmpty() {
        assertTrue(BudgetHistoryReader.forecast(emptyList(), emptyList(), 0, emptyList(), emptyList(), today).isEmpty)
    }

    @Test fun deletedAllocationsAreNotPlanned() {
        val rows = listOf(AllocationRow(id = 1, month = nextMonth, category = Market, amount = 40_000, isDeleted = true))
        val forecast = BudgetHistoryReader.forecast(emptyList(), emptyList(), 0, rows, emptyList(), today)
        assertTrue(forecast.plannedCategories.isEmpty())
    }
}
