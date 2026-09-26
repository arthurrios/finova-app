package com.arthurrios.finova.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.LocalDate
import java.time.YearMonth

/**
 * The iOS `Transactions` table (docs/data-layer-spec.md 1.1), in one table instead of iOS's SQLite
 * plus JSON copy. No foreign keys, like iOS in practice; every index iOS meant to create is here.
 */
@Entity(
    tableName = "transactions",
    indices = [
        Index("date"),
        Index("category"),
        Index("budget_month"),
        Index("parent_transaction_id"),
        Index("is_recurring"),
        Index("credit_card_id"),
        Index("statement_id"),
        Index("settled_by_transaction_id"),
        Index("cancelled_by_transaction_id"),
        Index("statement_payment_id"),
    ],
)
data class TransactionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    /** TransactionCategory.key, e.g. "market". */
    val category: String,
    /** "income" or "expense". */
    val type: String,
    val amount: Long,
    val date: LocalDate,
    @ColumnInfo(name = "budget_month") val budgetMonth: YearMonth,
    @ColumnInfo(name = "is_recurring") val isRecurring: Boolean = false,
    @ColumnInfo(name = "has_installments") val hasInstallments: Boolean = false,
    @ColumnInfo(name = "parent_transaction_id") val parentTransactionId: Long? = null,
    @ColumnInfo(name = "installment_number") val installmentNumber: Int? = null,
    @ColumnInfo(name = "total_installments") val totalInstallments: Int? = null,
    @ColumnInfo(name = "original_amount") val originalAmount: Long? = null,
    @ColumnInfo(name = "credit_card_id") val creditCardId: Long? = null,
    @ColumnInfo(name = "statement_id") val statementId: Long? = null,
    @ColumnInfo(name = "is_statement_overridden") val isStatementOverridden: Boolean = false,
    @ColumnInfo(name = "settled_by_transaction_id") val settledByTransactionId: Long? = null,
    @ColumnInfo(name = "is_early_payment") val isEarlyPayment: Boolean = false,
    @ColumnInfo(name = "cancelled_by_transaction_id") val cancelledByTransactionId: Long? = null,
    @ColumnInfo(name = "is_cancellation_refund") val isCancellationRefund: Boolean = false,
    @ColumnInfo(name = "statement_payment_id") val statementPaymentId: Long? = null,
    @ColumnInfo(name = "is_statement_payment") val isStatementPayment: Boolean = false,
    /** exact / nextBusinessDay / previousBusinessDay. */
    @ColumnInfo(name = "business_day_rule") val businessDayRule: String = "exact",
    @ColumnInfo(name = "unadjusted_date") val unadjustedDate: LocalDate? = null,
    @ColumnInfo(name = "series_period") val seriesPeriod: YearMonth? = null,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis(),
)

/** The iOS `Budgets` table: one cap per month. */
@Entity(tableName = "budgets")
data class BudgetEntity(
    @PrimaryKey val month: YearMonth,
    val amount: Long,
)

/**
 * A recurring occurrence the user deleted on its own. iOS keeps this only in memory, so the
 * month comes back after a relaunch; here it is stored.
 */
@Entity(tableName = "recurring_exclusions", primaryKeys = ["parent_id", "series_period"])
data class RecurringExclusionEntity(
    @ColumnInfo(name = "parent_id") val parentId: Long,
    @ColumnInfo(name = "series_period") val seriesPeriod: YearMonth,
)

/** Per-user values iOS keeps in UserDefaults under `<key>_<uid>`. A single row. */
@Entity(tableName = "user_settings")
data class UserSettingsEntity(
    @PrimaryKey val id: Int = 0,
    /** Starting balance that every running balance begins from (balanceOffset_<uid>). */
    @ColumnInfo(name = "balance_offset") val balanceOffset: Long = 0,
)

/**
 * The iOS `CreditCards` table (docs/data-layer-spec.md 1.3). Deleting is soft, as on iOS: the
 * row stays so its purchases and statements keep a card to point at.
 */
@Entity(tableName = "credit_cards")
data class CreditCardEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    @ColumnInfo(name = "last_four_digits") val lastFourDigits: String,
    /** CardBrand.key, e.g. "visa". */
    @ColumnInfo(name = "card_brand") val cardBrand: String,
    /** 1…28, like the iOS CHECK constraint. */
    @ColumnInfo(name = "closing_day") val closingDay: Int,
    @ColumnInfo(name = "due_day") val dueDay: Int,
    @ColumnInfo(name = "credit_limit") val creditLimit: Long? = null,
    /** CardColor.key, e.g. "blue". */
    @ColumnInfo(name = "card_color") val cardColor: String = "blue",
    @ColumnInfo(name = "is_deleted") val isDeleted: Boolean = false,
    @ColumnInfo(name = "is_default") val isDefault: Boolean = false,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "updated_at") val updatedAt: Long = System.currentTimeMillis(),
)

/**
 * The iOS `CreditCardStatements` table (docs/data-layer-spec.md 1.4): one billing cycle of a card.
 * `total_amount` is a cached signed sum; the rows pointing at the statement are the truth.
 */
@Entity(
    tableName = "credit_card_statements",
    indices = [Index("credit_card_id"), Index("due_date"), Index(value = ["credit_card_id", "closing_date"])],
)
data class StatementEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "credit_card_id") val creditCardId: Long,
    @ColumnInfo(name = "closing_date") val closingDate: LocalDate,
    @ColumnInfo(name = "due_date") val dueDate: LocalDate,
    @ColumnInfo(name = "total_amount") val totalAmount: Long = 0,
    @ColumnInfo(name = "is_paid") val isPaid: Boolean = false,
    @ColumnInfo(name = "paid_date") val paidDate: LocalDate? = null,
    @ColumnInfo(name = "paid_amount") val paidAmount: Long? = null,
    /** The user edited the dates by hand; card-cycle repairs leave them alone. */
    @ColumnInfo(name = "is_dates_overridden") val isDatesOverridden: Boolean = false,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "updated_at") val updatedAt: Long = System.currentTimeMillis(),
)

/**
 * A budget allocation (docs/data-layer-spec.md 1.5). iOS keeps these in one UserDefaults blob
 * shared by every account on the phone; here they live in the account's own database.
 */
@Entity(tableName = "budget_allocations", indices = [Index("month"), Index("parent_allocation_id")])
data class BudgetAllocationEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val month: YearMonth,
    /** TransactionCategory.key. */
    val category: String,
    val amount: Long,
    @ColumnInfo(name = "is_recurring") val isRecurring: Boolean = false,
    @ColumnInfo(name = "parent_allocation_id") val parentAllocationId: Long? = null,
    /** A deleted month of a series, kept so the series does not recreate it. */
    @ColumnInfo(name = "is_deleted") val isDeleted: Boolean = false,
)
