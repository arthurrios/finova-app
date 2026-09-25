package com.arthurrios.finova.domain.ledger

import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth

/** The numbers on one month card. Port of MonthlyData in TransactionLedgerService.swift. */
data class MonthSummary(
    val month: YearMonth,
    val income: Long,
    val expense: Long,
    /** Every expense dated in the month, card purchases included, statement rows excluded. */
    val usedValue: Long,
    val budgetLimit: Long?,
    val previousBalance: Long,
    val finalBalance: Long,
    val currentBalance: Long,
)

/**
 * Pure port of TransactionLedgerService.calculateMonthlyData on iOS.
 *
 * Rows are bucketed by [Transaction.date] (not by budget month). "Cash" rows move the balance:
 * rows without a card, plus the rows that stand for a whole card statement (which land on the
 * statement's due date). Card purchases count in "used" in their own month instead.
 *
 * One deliberate difference: iOS starts the running balance at the first month of the carousel,
 * so transactions older than a year drop out as months pass. Here everything before the first
 * month is added to the starting balance, so the balance never drifts.
 */
object LedgerCalculator {

    /**
     * [rows] are all stored transactions (series parents included) plus any statement rows.
     * Early-paid installments are skipped here, as iOS removes them before calculating.
     */
    fun monthlySummaries(
        rows: List<Transaction>,
        budgets: List<Budget>,
        balanceOffset: Long,
        months: List<YearMonth>,
        today: LocalDate,
    ): List<MonthSummary> {
        if (months.isEmpty()) return emptyList()
        val counted = rows.filterNot { it.isSettledEarly }
        val cash = counted.filter { it.isCash }
        val budgetByMonth = budgets.associate { it.month to it.amount }
        val byMonth = counted.groupBy { YearMonth.from(it.date) }
        val thisMonth = YearMonth.from(today)

        var previous = balanceOffset + cash.filter { it.date < months.first().atDay(1) }.sumOf { it.signedAmount }
        return months.map { month ->
            val inMonth = byMonth[month].orEmpty()
            val cashInMonth = inMonth.filter { it.isCash }
            val income = cashInMonth.filter { it.type == TransactionType.Income }.sumOf { it.amount }
            val expense = cashInMonth.filter { it.type == TransactionType.Expense }.sumOf { it.amount }
            val used = inMonth.filter { it.type == TransactionType.Expense && !it.isCreditCardStatement }.sumOf { it.amount }
            val final = previous + income - expense
            val current = when {
                month < thisMonth -> final
                month > thisMonth -> previous
                else -> previous + cashInMonth.filter { it.date <= today }.sumOf { it.signedAmount }
            }
            MonthSummary(
                month = month,
                income = income,
                expense = expense,
                usedValue = used,
                budgetLimit = budgetByMonth[month],
                previousBalance = previous,
                finalBalance = final,
                currentBalance = current,
            ).also { previous = final }
        }
    }

    /** The balance at the end of [day]. Port of `calculateBalanceForDay` / `balanceAsOf`. */
    fun balanceOn(rows: List<Transaction>, balanceOffset: Long, day: LocalDate): Long =
        balanceOffset + rows.filter { !it.isSettledEarly && it.isCash && it.date <= day }.sumOf { it.signedAmount }

    private val Transaction.isCash: Boolean get() = creditCardId == null || isCreditCardStatement
}
