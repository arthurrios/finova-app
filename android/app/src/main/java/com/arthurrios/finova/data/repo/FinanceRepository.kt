package com.arthurrios.finova.data.repo

import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.data.db.UserSettingsEntity
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.Transaction
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * The signed-in user's money data. Port of the parts of TransactionRepository, BudgetRepository
 * and the balance offset in UIDUserDefaultsManager that the dashboard uses.
 */
class FinanceRepository(private val db: FinovaDatabase) {

    /** Every stored row, series parents included (iOS `fetchAllTransactions`). */
    val transactions: Flow<List<Transaction>> = db.transactions().observeAll().map { rows -> rows.map { it.toDomain() } }

    val budgets: Flow<List<Budget>> = db.budgets().observeAll().map { rows -> rows.map { it.toDomain() } }

    val balanceOffset: Flow<Long> = db.userSettings().observe().map { it?.balanceOffset ?: 0 }

    suspend fun add(transaction: Transaction): Long = db.transactions().insert(transaction.toEntity())

    suspend fun addAll(transactions: List<Transaction>): List<Long> = db.transactions().insertAll(transactions.map { it.toEntity() })

    suspend fun delete(ids: List<Long>) = db.transactions().deleteByIds(ids)

    suspend fun setBudget(budget: Budget) = db.budgets().upsert(budget.toEntity())

    suspend fun setBalanceOffset(value: Long) = db.userSettings().save(UserSettingsEntity(balanceOffset = value))

    suspend fun isEmpty(): Boolean = db.transactions().count() == 0

    companion object {
        /**
         * What the lists show: iOS `fetchTransactions` hides a recurring parent that is not
         * self-linked and the zero-amount installment parent.
         */
        fun isListed(t: Transaction): Boolean =
            !(t.isRecurring && t.parentTransactionId == null) && !(t.hasInstallments && t.parentTransactionId == null)
    }
}
