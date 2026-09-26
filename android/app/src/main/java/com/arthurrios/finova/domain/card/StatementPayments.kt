package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth

/**
 * Paying a statement, in part or in full. Port of StatementPaymentService on iOS.
 *
 * A payment is a pair of rows:
 * - a debit on the payment date with no card, so the money leaves the balance that day;
 * - a credit inside the statement for the same amount, so what the statement still charges drops.
 *   It is card-linked (it never counts in the balance itself) and points at the debit.
 * Deleting either half takes the other with it.
 */
object StatementPayments {

    /**
     * What the statement still owes, never negative: its own total less any credit carried in from
     * the card's earlier statements.
     */
    fun remaining(statementId: Long, rows: List<Transaction>, statements: List<CreditCardStatement>): Long {
        val statement = statements.firstOrNull { it.id == statementId }
            ?: return StatementBook.total(statementId, rows).coerceAtLeast(0)
        return StatementBook.charges(statements.filter { it.creditCardId == statement.creditCardId }, rows)[statementId]?.charged ?: 0
    }

    /** The two rows of a payment. The credit's [Transaction.statementPaymentId] is set on insert. */
    fun pair(
        statement: CreditCardStatement,
        amount: Long,
        date: LocalDate,
        debitTitle: String,
        creditTitle: String,
    ): Pair<Transaction, Transaction> {
        require(amount > 0) { "A payment needs a positive amount" }
        val debit = Transaction(
            title = debitTitle,
            category = TransactionCategory.CreditCard,
            type = TransactionType.Expense,
            amount = amount,
            date = date,
            budgetMonth = YearMonth.from(date),
            originalAmount = amount,
            isStatementPayment = true,
        )
        val credit = Transaction(
            title = creditTitle,
            category = TransactionCategory.CreditCard,
            type = TransactionType.Income,
            amount = amount,
            date = date,
            // The statement's own month, so it reduces the invoice where that invoice belongs.
            budgetMonth = YearMonth.from(statement.closingDate),
            originalAmount = amount,
            creditCardId = statement.creditCardId,
            statementId = statement.id,
            // Pinned: a scheduled payment must stay on the invoice it pays.
            isStatementOverridden = true,
        )
        return debit to credit
    }

    /** The other half of a payment row, or none when [row] is not part of a payment. */
    fun partners(row: Transaction, rows: List<Transaction>): List<Long> = when {
        row.isStatementPayment -> rows.filter { it.statementPaymentId == row.id }.map { it.id }
        row.statementPaymentId != null -> listOf(row.statementPaymentId)
        else -> emptyList()
    }

    /** Everything paid against the statement so far, across partial payments. */
    fun totalPaid(statementId: Long, rows: List<Transaction>): Long =
        rows.filter { it.statementId == statementId && it.statementPaymentId != null }.sumOf { it.amount }
}
