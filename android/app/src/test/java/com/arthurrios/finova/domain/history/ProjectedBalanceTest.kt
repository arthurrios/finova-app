package com.arthurrios.finova.domain.history

import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.AllocationBalanceProjection
import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.card.StatementBook
import com.arthurrios.finova.domain.card.StatementPayments
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.CreditCard as CreditCardCategory
import com.arthurrios.finova.domain.model.TransactionCategory.Market
import com.arthurrios.finova.domain.model.TransactionCategory.Meals
import com.arthurrios.finova.domain.model.TransactionCategory.Salary
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.budget.projection
import com.arthurrios.finova.ui.dashboard.MonthPageUi
import com.arthurrios.finova.ui.history.BudgetForecastText
import com.arthurrios.finova.ui.history.BudgetHistoryUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/**
 * The projected balance of the current month and the months ahead, through the rows, the statements
 * and the ledger the app really reads:
 * `projected(M) = base(M) - outstandingCard(M) - plan(current..M)`.
 *
 * Every read asserts the budget history and the dashboard agree on every month ahead.
 */
class ProjectedBalanceTest {
    private val today = LocalDate.of(2026, 10, 15)
    private val oct = YearMonth.from(today)
    private val nov = oct.plusMonths(1)
    private val dec = oct.plusMonths(2)
    private val jan = oct.plusMonths(3)

    private val card = CreditCard(id = 7, name = "Visa", lastFourDigits = "4242", closingDay = 28, dueDay = 8)

    /** The statement closing the 28th of [closing], due the 8th of the month after. */
    private fun statement(id: Long, closing: YearMonth) =
        CreditCardStatement(id = id, creditCardId = card.id, closingDate = closing.atDay(28), dueDate = closing.plusMonths(1).atDay(8))

    private val octStatement = statement(1, oct)
    private val novStatement = statement(2, nov)
    private val statements = listOf(octStatement, novStatement)

    private fun cash(amount: Long, category: TransactionCategory, month: YearMonth, type: TransactionType = TransactionType.Expense) = Transaction(
        title = "t", category = category, type = type, amount = amount, date = month.atDay(10), budgetMonth = month,
    )

    private fun onCard(amount: Long, category: TransactionCategory, month: YearMonth, on: CreditCardStatement, type: TransactionType = TransactionType.Expense) =
        cash(amount, category, month, type).copy(creditCardId = card.id, statementId = on.id)

    private fun monthly(category: TransactionCategory, amount: Long) =
        (0..7).map { AllocationRow(id = it + 1L, month = oct.plusMonths(it.toLong()), category = category, amount = amount) }

    private inner class Read(val rows: List<Transaction>, val allocations: List<AllocationRow>, val offset: Long, statements: List<CreditCardStatement>) {
        private val ledger = rows + StatementBook.statementRows(listOf(card), statements, rows)
        private val budgets = emptyList<Budget>()
        val forecast = BudgetHistoryReader.forecast(ledger, budgets, offset, allocations, statements, today)

        // What DashboardViewModel builds for its months.
        private val months = (-2..7).map { oct.plusMonths(it.toLong()) }
        private val commitments = Allocations.balanceCommitments(allocations, rows, statements, Allocations.statementsDue(ledger), oct, months.last())
        private val summaries = LedgerCalculator.monthlySummaries(ledger, budgets, offset, months, today).associateBy { it.month }

        fun page(month: YearMonth): MonthPageUi {
            val summary = summaries.getValue(month)
            return MonthPageUi(
                month = month, isCurrentMonth = month == oct, isPastMonth = month < oct, usedValue = summary.usedValue,
                budgetLimit = summary.budgetLimit, finalBalance = summary.finalBalance, currentBalance = summary.currentBalance,
                transactions = emptyList(),
                allocations = Allocations.withUsage(allocations, rows, month),
                unallocated = Allocations.unallocatedSummary(allocations, rows, budgets, month),
                offPlan = Allocations.unallocatedSpending(allocations, rows, month),
                deferredCardSpending = commitments[month]?.outstandingCard ?: Allocations.deferredCardSpending(rows, statements, month),
                reservedPlan = commitments[month]?.reservedPlan,
            )
        }

        fun projected(month: YearMonth): Long = page(month).projection()!!.projected

        /** The month's figure, once the budget history's matches. */
        fun checked(month: YearMonth): Long {
            if (month > oct) assertEquals(page(month).projection(), forecast.month(month)!!.projection)
            return projected(month)
        }
    }

    private fun read(rows: List<Transaction>, allocations: List<AllocationRow> = emptyList(), offset: Long = 0, statements: List<CreditCardStatement> = this.statements) =
        Read(rows, allocations, offset, statements)

    private val marketInOctober = listOf(AllocationRow(id = 1, month = oct, category = Market, amount = 1_000))

    @Test fun eachMonthCarriesThePlansBeforeIt() {
        val salaries = (0..7).map { cash(8_000, Salary, oct.plusMonths(it.toLong()), TransactionType.Income) }
        val read = read(salaries, monthly(Market, 1_000))
        assertEquals(7_000L, read.checked(oct))
        assertEquals(14_000L, read.checked(nov))
        assertEquals(21_000L, read.checked(dec))
    }

    @Test fun aPartlySpentCurrentMonthAddsOnlyWhatIsLeft() {
        val read = read(listOf(cash(400, Market, oct)), monthly(Market, 1_000), offset = 10_000)
        // 9.600 - 600 left of October.
        assertEquals(9_000L, read.checked(oct))
        // 9.600 - 600 - 1.000.
        assertEquals(8_000L, read.checked(nov))
        assertEquals(600L, read.page(oct).projection()!!.reservedPlan)
    }

    @Test fun pastPlansAddNothing() {
        val september = AllocationRow(id = 9, month = oct.minusMonths(1), category = Market, amount = 5_000)
        val read = read(emptyList(), monthly(Market, 1_000) + september, offset = 10_000)
        assertEquals(9_000L, read.checked(oct))
    }

    @Test fun headroomIsNotReserved() {
        // No allocation at all: nothing is held back, however large the budget.
        val read = read(emptyList(), offset = 10_000)
        assertEquals(10_000L, read.checked(nov))
    }

    // ---- A card purchase counts once

    private fun assertCountedOnce(read: Read) {
        assertEquals(listOf(9_000L, 9_000L, 9_000L), listOf(oct, nov, dec).map(read::checked))
    }

    private val purchase = onCard(300, Market, oct, octStatement)

    @Test fun aCardPurchaseCountsOnceInTheMonthItWasMadeAndAcrossItsSettling() {
        val read = read(listOf(purchase), marketInOctober, offset = 10_000)
        assertCountedOnce(read)
        assertEquals(300L, read.page(oct).projection()!!.deferredCardSpending)
        assertEquals(0L, read.page(nov).projection()!!.deferredCardSpending)
        assertEquals(9_700L, read.page(nov).projection()!!.base)
    }

    private fun payment(on: CreditCardStatement, date: LocalDate, amount: Long = 300): List<Transaction> {
        val (debit, credit) = StatementPayments.pair(on, amount, date, "paid", "credit")
        return listOf(debit.copy(id = 100), credit.copy(id = 101, statementPaymentId = 100))
    }

    @Test fun aStatementPaidBeforeItsDueDateCountsOnce() {
        assertCountedOnce(read(listOf(purchase) + payment(octStatement, today), marketInOctober, offset = 10_000))
    }

    @Test fun aStatementPaidBeforeItClosesCountsOnce() {
        // The credit's budget month is November, its closing month. The debit is already in October.
        val rows = listOf(onCard(300, Market, oct, novStatement)) + payment(novStatement, today)
        assertCountedOnce(read(rows, marketInOctober, offset = 10_000))
    }

    @Test fun aPaymentScheduledForTheDueDateDropsNothing() {
        // The credit's budget month is October, but the debit only reaches the balance in November.
        assertCountedOnce(read(listOf(purchase) + payment(octStatement, nov.atDay(8)), marketInOctober, offset = 10_000))
    }

    @Test fun aPartlyPaidStatementCountsOnce() {
        assertCountedOnce(read(listOf(purchase) + payment(octStatement, today, amount = 100), marketInOctober, offset = 10_000))
    }

    @Test fun aPurchaseSettlingLaterStaysOutstandingUntilThen() {
        val read = read(listOf(onCard(300, Market, oct, novStatement)), marketInOctober, offset = 10_000)
        assertEquals(300L, read.page(nov).projection()!!.deferredCardSpending)
        assertEquals(listOf(9_000L, 9_000L, 9_000L, 9_000L), listOf(oct, nov, dec, jan).map(read::checked))
        assertEquals(0L, read.page(dec).projection()!!.deferredCardSpending)
    }

    @Test fun aStoredRowCountsFromItsOwnBudgetMonth() {
        val janStatement = statement(3, dec)
        val rows = listOf(onCard(300, Market, nov, janStatement))
        val read = read(rows, offset = 10_000, statements = statements + janStatement)
        assertEquals(0L, read.page(oct).projection()!!.deferredCardSpending)
        assertEquals(300L, read.page(nov).projection()!!.deferredCardSpending)
        assertEquals(300L, read.page(dec).projection()!!.deferredCardSpending)
        assertEquals(0L, read.page(jan).projection()!!.deferredCardSpending)
    }

    @Test fun aRowWithNoLiveStatementStaysOutstanding() {
        val rows = listOf(purchase.copy(statementId = null))
        val read = read(rows, offset = 10_000)
        assertEquals(listOf(9_700L, 9_700L, 9_700L), listOf(oct, nov, dec).map(read::checked))
    }

    @Test fun anEarlyPaidInstallmentIsNotOutstanding() {
        val rows = listOf(purchase.copy(settledByTransactionId = 50))
        assertEquals(10_000L, read(rows, offset = 10_000).checked(oct))
    }

    @Test fun aRefundNetsLikeTheStatementDoes() {
        val rows = listOf(purchase, onCard(100, Market, oct, octStatement, TransactionType.Income))
        val read = read(rows, offset = 10_000)
        assertEquals(200L, read.page(oct).projection()!!.deferredCardSpending)
        assertEquals(listOf(9_800L, 9_800L, 9_800L), listOf(oct, nov, dec).map(read::checked))
    }

    // ---- The Credit Card category

    @Test fun aCreditCardAllocationDoesNotDoubleTheBill() {
        val allocation = listOf(AllocationRow(id = 1, month = nov, category = CreditCardCategory, amount = 1_000))
        val read = read(listOf(onCard(800, Meals, oct, octStatement)), allocation, offset = 10_000)
        // November: 800 of the 1.000 is the bill itself, so only 200 is still to leave.
        assertEquals(200L, read.page(nov).projection()!!.reservedPlan)
        assertEquals(9_000L, read.checked(nov))
    }

    @Test fun aPaidBillStillDrawsDownItsCreditCardAllocation() {
        val allocation = listOf(AllocationRow(id = 1, month = nov, category = CreditCardCategory, amount = 1_000))
        val paid = listOf(onCard(800, Meals, oct, octStatement)) + payment(octStatement, nov.atDay(5), amount = 800)
        assertEquals(9_000L, read(paid, allocation, offset = 10_000).checked(nov))
    }

    // ---- Closed months

    @Test fun aClosedMonthKeepsItsOwnFigures() {
        val september = oct.minusMonths(1)
        val allocations = listOf(AllocationRow(id = 1, month = september, category = Market, amount = 1_000))
        val projection = read(emptyList(), allocations, offset = 10_000).page(september).projection()!!
        assertEquals(AllocationBalanceProjection.Tense.Actual, projection.tense)
        assertEquals(1_000L, projection.unspentAllocations)
        assertEquals(1_000L, projection.reservedPlan)
        assertEquals(9_000L, projection.projected)
    }

    // ---- The readout

    private fun state(forecast: BudgetForecast, filter: BudgetHistoryFilter = BudgetHistoryFilter.WholeMonth) =
        BudgetHistoryUiState(filter = filter, selected = nov).withHistory(BudgetHistory.Empty, firstLoad = true, newForecast = forecast)

    private val salaries = (0..7).map { cash(8_000, Salary, oct.plusMonths(it.toLong()), TransactionType.Income) }

    @Test fun aWholeMonthLeadsWithItsBalance() {
        val s = state(read(salaries, monthly(Market, 1_000)).forecast)
        assertEquals(14_000L, s.forecastBalance(s.selectedForecast!!))
    }

    @Test fun aCategoryKeepsItsOwnReadout() {
        val s = state(read(salaries, monthly(Market, 1_000)).forecast, BudgetHistoryFilter.Category(Market))
        assertNull(s.forecastBalance(s.selectedForecast!!))
    }

    @Test fun theOutsideFilterKeepsItsOwnReadout() {
        val forecast = read(salaries + cash(50, Meals, nov), monthly(Market, 1_000)).forecast
        val figures = forecast.figures(BudgetHistoryFilter.OutsideAllocations).first { it.month == nov }
        assertNull(state(forecast).forecastBalance(figures))
    }

    @Test fun aMonthWithNoBalanceKeepsItsOwnReadout() {
        val month = BudgetForecastMonth.of(nov, emptyList(), com.arthurrios.finova.domain.allocation.UnallocatedSummary(nov, 100, 0, 0), emptyList(), null, 0, 0)
        val s = state(BudgetForecast(listOf(month)))
        assertNull(s.forecastBalance(s.selectedForecast!!))
    }

    @Test fun talkBackReadsTheBalanceAndHiddenValuesMaskIt() {
        val s = state(read(salaries, monthly(Market, 1_000)).forecast)
        val figures = s.selectedForecast!!
        val spoken = BudgetForecastText.accessibility(figures, hidden = false, balance = 14_000)
        assertEquals(R.string.history_forecast_a11y_balance_format, spoken[1].text)
        assertEquals(listOf(14_000L), spoken[1].amounts)

        val masked = BudgetForecastText.accessibility(figures, hidden = true, balance = 14_000)
        assertEquals(R.string.history_forecast_readout_balance, masked[1].text)
        assertTrue(masked.all { it.amounts.isEmpty() })
    }
}
