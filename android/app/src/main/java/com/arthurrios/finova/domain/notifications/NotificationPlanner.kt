package com.arthurrios.finova.domain.notifications

import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.card.StatementBook
import com.arthurrios.finova.domain.ledger.LedgerCalculator
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesKind
import com.arthurrios.finova.domain.series.SeriesRules
import java.time.LocalDate
import java.time.YearMonth

/** Which reminders the user wants. Port of NotificationPreferencesManager (all on by default). */
data class NotificationPreferences(
    val allDisabled: Boolean = false,
    val transactions: Boolean = true,
    val appUpdates: Boolean = true,
    val negativeBalance: Boolean = true,
    val cardStatements: Boolean = true,
)

/** One reminder to send today, with what its text needs. */
sealed interface PlannedNotification {
    /** Stable per event, so a second run on the same day never sends it twice. */
    val id: String

    data class TransactionDue(override val id: String, val title: String, val amount: Long, val type: TransactionType) : PlannedNotification
    data class SeriesMonth(override val id: String, val kind: SeriesKind, val count: Int, val total: Long) : PlannedNotification
    data class StatementClosed(override val id: String, val cardName: String, val amount: Long) : PlannedNotification
    data class StatementDue(override val id: String, val cardName: String, val amount: Long) : PlannedNotification
    data class NegativeBalanceTomorrow(override val id: String, val day: LocalDate) : PlannedNotification
}

/**
 * What to tell the user today. Pure port of the iOS schedulers (MonthlyNotificationManager,
 * SeriesNotificationScheduler, StatementNotificationPlan, BalanceMonitorManager). iOS schedules up to
 * 64 notifications ahead; Android instead runs this once each morning and sends what is due, so
 * nothing needs rescheduling when data changes.
 */
object NotificationPlanner {

    fun plan(
        today: LocalDate,
        rows: List<Transaction>,
        statements: List<CreditCardStatement>,
        cards: List<CreditCard>,
        balanceOffset: Long,
        prefs: NotificationPreferences,
    ): List<PlannedNotification> {
        if (prefs.allDisabled) return emptyList()
        val stored = rows.filter { !it.isCreditCardStatement && FinanceRepository.isListed(it) }
        val planned = mutableListOf<PlannedNotification>()

        if (prefs.transactions) {
            // One per transaction on its day (iOS "Upcoming debit/credit" at 8 AM).
            stored.filter { it.date == today && !it.isSettledEarly }.sortedBy { it.id }.forEach {
                planned += PlannedNotification.TransactionDue("transaction_${it.id}_$today", it.title, it.amount, it.type)
            }
        }

        // One reminder per month per series kind, on the day of that month's first row, with the
        // month's count and total. iOS sends these whatever the transaction switch says.
        for (kind in listOf(SeriesKind.Installments, SeriesKind.Recurring)) {
            val month = YearMonth.from(today)
            val inMonth = stored.filter { SeriesRules.kindOf(it) == kind && YearMonth.from(it.date) == month && !it.isSettledEarly }
            if (inMonth.isNotEmpty() && inMonth.minOf { it.date } == today) {
                val prefix = if (kind == SeriesKind.Installments) "installment_month_" else "recurring_month_"
                planned += PlannedNotification.SeriesMonth("$prefix$month", kind, inMonth.size, inMonth.sumOf { it.amount })
            }
        }

        if (prefs.cardStatements) {
            val charges = statements.groupBy { it.creditCardId }.values
                .flatMap { StatementBook.charges(it, stored).entries }.associate { it.key to it.value.charged }
            statements.filter { !it.isPaid }.forEach { statement ->
                // Nothing owed: "your statement of R$ 0,00 is due" is the wrong message.
                val amount = charges[statement.id] ?: 0
                if (amount <= 0) return@forEach
                val card = cards.firstOrNull { it.id == statement.creditCardId }?.name ?: return@forEach
                if (statement.closingDate == today) planned += PlannedNotification.StatementClosed("statement_closed_${statement.id}", card, amount)
                if (statement.dueDate == today) planned += PlannedNotification.StatementDue("statement_pay_${statement.id}", card, amount)
            }
        }

        if (prefs.negativeBalance) {
            // Warn the morning before the first day in the next 30 that ends negative, as iOS does.
            val firstNegative = (1..30).map { today.plusDays(it.toLong()) }
                .firstOrNull { LedgerCalculator.balanceOn(rows, balanceOffset, it) < 0 }
            if (firstNegative == today.plusDays(1)) {
                planned += PlannedNotification.NegativeBalanceTomorrow("negative_balance_$firstNegative", firstNegative)
            }
        }
        return planned
    }
}
