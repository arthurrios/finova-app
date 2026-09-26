package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth

/** An installment that can still be paid early or refunded, and when it is billed. */
data class OpenInstallment(val row: Transaction, val dueDate: LocalDate) {
    val id: Long get() = row.id
    val amount: Long get() = row.amount
    val number: Int get() = row.installmentNumber ?: 0
    val total: Int get() = row.totalInstallments ?: 0
}

/**
 * Early payment ("antecipação") and cancelling an installment purchase. Ports of
 * InstallmentSeriesLocator, EarlyPaymentService and InstallmentCancellationService on iOS.
 *
 * Early payment: one debit for the chosen installments, each marked settled by it. Settled
 * installments stop counting; the debit counts instead, on its date or on the card's next open
 * statement. Cancellation: one credit for everything still to be billed, each installment marked
 * cancelled by it. Cancelled installments keep counting, so the two cancel out over time.
 */
object Installments {

    fun seriesParentId(row: Transaction): Long? = when {
        row.parentTransactionId != null && row.parentTransactionId != row.id -> row.parentTransactionId
        row.hasInstallments -> row.id
        else -> null
    }

    /**
     * The series' installments in order. When fewer than expected hang off the parent (a split
     * link), siblings with the same title, count and card join in; duplicates by number keep the
     * lowest id.
     */
    fun children(row: Transaction, rows: List<Transaction>): List<Transaction> {
        val parentId = seriesParentId(row)
        val linked = if (parentId == null) emptyList()
        else rows.filter { it.parentTransactionId == parentId && it.installmentNumber != null && it.totalInstallments != null }
        val expected = linked.firstOrNull()?.totalInstallments ?: row.totalInstallments
        val all = if (expected == null || linked.size >= expected) linked else {
            val title = linked.firstOrNull()?.title ?: row.title
            val cardId = linked.firstOrNull()?.creditCardId ?: row.creditCardId
            linked + rows.filter {
                it.installmentNumber != null && it.totalInstallments == expected && it.title == title && it.creditCardId == cardId
            }
        }
        return all.groupBy { it.installmentNumber!! }.map { (_, same) -> same.minBy { it.id } }.sortedBy { it.installmentNumber }
    }

    /**
     * Installments not yet billed: not paid early, and on a statement that has not closed (or, with
     * no card or a missing statement, dated after today). Newest first, as iOS lists them.
     */
    fun outstanding(row: Transaction, rows: List<Transaction>, statements: List<CreditCardStatement>, today: LocalDate): List<OpenInstallment> {
        val byId = statements.associateBy { it.id }
        return children(row, rows).mapNotNull { child ->
            if (child.isSettledEarly) return@mapNotNull null
            val statement = child.statementId?.let { byId[it] }
            when {
                child.creditCardId != null && statement != null ->
                    if (statement.closingDate > today && !statement.isPaid) OpenInstallment(child, statement.dueDate) else null
                child.date > today -> OpenInstallment(child, child.date)
                else -> null
            }
        }.sortedByDescending { it.number }
    }

    /** The credit that cancelled the purchase, if it was cancelled. */
    fun cancellationRefundId(row: Transaction, rows: List<Transaction>): Long? =
        children(row, rows).firstNotNullOfOrNull { it.cancelledByTransactionId }

    /** A cancelled purchase cannot also be paid early: its installments are already offset. */
    fun payable(row: Transaction, rows: List<Transaction>, statements: List<CreditCardStatement>, today: LocalDate): List<OpenInstallment> =
        if (cancellationRefundId(row, rows) != null) emptyList() else outstanding(row, rows, statements, today)

    /** Same list: what a cancellation refunds. */
    fun refundable(row: Transaction, rows: List<Transaction>, statements: List<CreditCardStatement>, today: LocalDate) =
        payable(row, rows, statements, today)

    /** The card the series is charged to, if any. */
    fun cardId(row: Transaction, rows: List<Transaction>): Long? =
        row.creditCardId ?: seriesParentId(row)?.let { parent ->
            rows.firstOrNull { (it.id == parent || it.parentTransactionId == parent) && it.creditCardId != null }?.creditCardId
        }

    /**
     * The statement money the user chooses to move (an early payment, a cancellation credit) lands
     * on: the first cycle after [date] that has not closed and is not paid. Routing by date alone
     * would pick a statement closing that very day, one already issued, where the user would never
     * see the amount.
     */
    fun nextOpenStatement(statements: List<CreditCardStatement>, card: CreditCard, date: LocalDate, rule: BusinessDayRule): CreditCardStatement {
        var candidate = StatementBook.route(statements, card, date, rule)
        while (candidate.closingDate <= date || candidate.isPaid) candidate = StatementBook.next(statements, card, candidate, rule)
        return candidate
    }

    fun earlyPaymentDebit(total: Long, date: LocalDate, title: String) = Transaction(
        title = title,
        // What leaves the account is a card payment, so it sits under Credit Card.
        category = TransactionCategory.CreditCard,
        type = TransactionType.Expense,
        amount = total,
        date = date,
        budgetMonth = YearMonth.from(date),
        originalAmount = total,
        isEarlyPayment = true,
    )

    fun cancellationCredit(total: Long, date: LocalDate, title: String) = Transaction(
        title = title,
        category = TransactionCategory.CreditCard,
        type = TransactionType.Income,
        amount = total,
        date = date,
        budgetMonth = YearMonth.from(date),
        originalAmount = total,
        isCancellationRefund = true,
    )
}
