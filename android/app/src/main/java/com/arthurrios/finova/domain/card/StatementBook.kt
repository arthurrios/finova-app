package com.arthurrios.finova.domain.card

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth

/**
 * Which statement a card row belongs to, and what a statement charges. Pure ports of
 * CreditCardService.getOrCreateStatement, nextStatement and generateStatementTransactions.
 *
 * The lookups return a statement with id 0 when none exists yet; the repository inserts it.
 */
object StatementBook {

    /**
     * The statement for a purchase on [purchase] (the picked date, before any weekend shift). The
     * card's current closing day decides the cycle. Lookup order, as on iOS:
     * 1. a statement closing exactly on that date;
     * 2. any statement of the card closing in the same month (lowest id), which is still that
     *    month's invoice after the closing day changed;
     * 3. a new one.
     */
    fun route(
        statements: List<CreditCardStatement>,
        card: CreditCard,
        purchase: LocalDate,
        rule: BusinessDayRule,
    ): CreditCardStatement = forClosing(statements, card, CardCycle.closingDate(card.closingDay, purchase), rule)

    /**
     * The cycle after [current]. Installments 2…N chain this way instead of routing by their own
     * date: on a card closing the 28th, a purchase on the 30th and its second installment (clamped
     * to Feb 28) would otherwise land on the same invoice, leaving March with none.
     */
    fun next(
        statements: List<CreditCardStatement>,
        card: CreditCard,
        current: CreditCardStatement,
        rule: BusinessDayRule,
    ): CreditCardStatement {
        val month = YearMonth.from(current.closingDate).plusMonths(1)
        return forClosing(statements, card, CardCycle.closingDateIn(month, card.closingDay), rule)
    }

    private fun forClosing(
        statements: List<CreditCardStatement>,
        card: CreditCard,
        closing: LocalDate,
        rule: BusinessDayRule,
    ): CreditCardStatement {
        val mine = statements.filter { it.creditCardId == card.id }
        mine.firstOrNull { it.closingDate == closing }?.let { return it }
        mine.filter { YearMonth.from(it.closingDate) == YearMonth.from(closing) }.minByOrNull { it.id }?.let { return it }
        return CreditCardStatement(
            creditCardId = card.id,
            closingDate = closing,
            dueDate = CardCycle.dueDate(closing, card.dueDay, rule),
        )
    }

    /** The rows a statement holds: every card row pointing at it, not the synthetic statement row. */
    fun members(statementId: Long, rows: List<Transaction>): List<Transaction> =
        rows.filter { it.statementId == statementId && !it.isCreditCardStatement }

    /**
     * What the statement charges: purchases add, credits (refunds, payments) subtract. Installments
     * already paid early are left out, since their own debit paid them. It can go negative.
     */
    fun total(statementId: Long, rows: List<Transaction>): Long =
        members(statementId, rows).filterNot { it.isSettledEarly }.sumOf { -it.signedAmount }

    /**
     * One synthetic row per statement that charges something, dated on its due date: this is how
     * card spending reaches the balance. A statement of a deleted card still charges, since its
     * purchases really happened. Empty statements and credit balances make no row.
     */
    fun statementRows(
        cards: List<CreditCard>,
        statements: List<CreditCardStatement>,
        rows: List<Transaction>,
    ): List<Transaction> {
        val cardById = cards.associateBy { it.id }
        return statements.mapNotNull { statement ->
            val card = cardById[statement.creditCardId] ?: return@mapNotNull null
            val members = members(statement.id, rows)
            val total = total(statement.id, rows)
            if (members.isEmpty() || total <= 0) return@mapNotNull null
            Transaction(
                id = -(statement.id * 1000 + card.id),
                // The screen formats "<card> Statement"; the row carries the card name.
                title = card.name,
                category = TransactionCategory.CreditCard,
                type = TransactionType.Expense,
                amount = total,
                date = statement.dueDate,
                budgetMonth = YearMonth.from(statement.closingDate),
                totalInstallments = members.size,
                originalAmount = total,
                creditCardId = card.id,
                statementId = statement.id,
                isCreditCardStatement = true,
            )
        }
    }
}
