package com.arthurrios.finova.domain.model

import java.time.LocalDate
import java.time.YearMonth

/**
 * A stored transaction. Port of TransactionData on iOS, with the "pointer" columns iOS keeps only
 * in SQLite carried here too. Money is in minor units and always positive; [type] gives the sign.
 *
 * Dates are local calendar dates: iOS stores epoch seconds at local midnight or noon, but only the
 * day ever matters, and a date cannot drift across time zones.
 */
data class Transaction(
    val id: Long = 0,
    val title: String,
    val category: TransactionCategory,
    val type: TransactionType,
    val amount: Long,
    /** The day the money moves, after any weekend shift. Card installments: the due date. */
    val date: LocalDate,
    /** The month this row counts against for budget allocations. */
    val budgetMonth: YearMonth,
    val isRecurring: Boolean = false,
    val hasInstallments: Boolean = false,
    val parentTransactionId: Long? = null,
    val installmentNumber: Int? = null,
    val totalInstallments: Int? = null,
    val originalAmount: Long? = null,
    val creditCardId: Long? = null,
    val statementId: Long? = null,
    val businessDayRule: BusinessDayRule = BusinessDayRule.Exact,
    /** The day before the weekend shift. Null means the same as [date]. */
    val unadjustedDate: LocalDate? = null,
    /** Which occurrence of a series this is. Null means the same as [budgetMonth]. */
    val seriesPeriod: YearMonth? = null,
    val isStatementOverridden: Boolean = false,
    /** Paid ahead of schedule by that payment: no longer counts in totals. */
    val settledByTransactionId: Long? = null,
    val isEarlyPayment: Boolean = false,
    /** Covered by that cancellation credit: still counts. */
    val cancelledByTransactionId: Long? = null,
    val isCancellationRefund: Boolean = false,
    val statementPaymentId: Long? = null,
    val isStatementPayment: Boolean = false,
    /** Only true on the in-memory rows that stand for a whole card statement. */
    val isCreditCardStatement: Boolean = false,
) {
    val signedAmount: Long get() = if (type == TransactionType.Income) amount else -amount
    val slot: YearMonth get() = seriesPeriod ?: budgetMonth
    val unadjusted: LocalDate get() = unadjustedDate ?: date
    val isSettledEarly: Boolean get() = settledByTransactionId != null

    /** Same order of checks as `Transaction.mode` on iOS. */
    val mode: TransactionMode
        get() = when {
            isRecurring -> TransactionMode.Recurring
            hasInstallments -> TransactionMode.Installments
            parentTransactionId != null && installmentNumber != null && totalInstallments != null -> TransactionMode.Installments
            parentTransactionId != null && installmentNumber == null && totalInstallments == null -> TransactionMode.Recurring
            else -> TransactionMode.Normal
        }
}

enum class TransactionMode { Normal, Recurring, Installments }

/** The monthly budget cap. Port of BudgetModel. */
data class Budget(val month: YearMonth, val amount: Long)
