package com.arthurrios.finova.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow
import java.time.YearMonth

@Dao
interface TransactionDao {
    @Query("SELECT * FROM transactions ORDER BY date DESC, id DESC")
    fun observeAll(): Flow<List<TransactionEntity>>

    @Query("SELECT * FROM transactions")
    suspend fun getAll(): List<TransactionEntity>

    @Query("SELECT * FROM transactions WHERE id = :id")
    suspend fun getById(id: Long): TransactionEntity?

    @Insert
    suspend fun insert(entity: TransactionEntity): Long

    @Insert
    suspend fun insertAll(entities: List<TransactionEntity>): List<Long>

    @Update
    suspend fun update(entity: TransactionEntity)

    @Update
    suspend fun updateAll(entities: List<TransactionEntity>)

    @Query("DELETE FROM transactions WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<Long>)

    @Query("UPDATE transactions SET parent_transaction_id = :parentId WHERE id = :id")
    suspend fun setParent(id: Long, parentId: Long)

    @Query("UPDATE transactions SET is_recurring = :recurring WHERE id IN (:ids)")
    suspend fun setRecurring(ids: List<Long>, recurring: Boolean)

    @Query("SELECT COUNT(*) FROM transactions")
    suspend fun count(): Int
}

@Dao
interface BudgetDao {
    @Query("SELECT * FROM budgets")
    fun observeAll(): Flow<List<BudgetEntity>>

    @Upsert
    suspend fun upsert(entity: BudgetEntity)

    @Query("DELETE FROM budgets WHERE month = :month")
    suspend fun delete(month: YearMonth)
}

@Dao
interface RecurringExclusionDao {
    @Query("SELECT * FROM recurring_exclusions")
    suspend fun getAll(): List<RecurringExclusionEntity>

    @Query("SELECT * FROM recurring_exclusions")
    fun observeAll(): Flow<List<RecurringExclusionEntity>>

    @Upsert
    suspend fun add(entity: RecurringExclusionEntity)

    @Query("UPDATE recurring_exclusions SET parent_id = :toParent WHERE parent_id = :fromParent AND series_period >= :fromSlot")
    suspend fun move(fromParent: Long, toParent: Long, fromSlot: YearMonth)

    @Query("DELETE FROM recurring_exclusions WHERE parent_id IN (:parentIds)")
    suspend fun deleteForParents(parentIds: List<Long>)
}

@Dao
interface UserSettingsDao {
    @Query("SELECT * FROM user_settings WHERE id = 0")
    fun observe(): Flow<UserSettingsEntity?>

    @Upsert
    suspend fun save(entity: UserSettingsEntity)
}

@Dao
interface CreditCardDao {
    /** Live cards, newest first, as iOS `getCreditCards` orders them. */
    @Query("SELECT * FROM credit_cards WHERE is_deleted = 0 ORDER BY created_at DESC, id DESC")
    fun observeActive(): Flow<List<CreditCardEntity>>

    /** Every card, deleted ones too: their statements still charge the balance. */
    @Query("SELECT * FROM credit_cards")
    suspend fun getAll(): List<CreditCardEntity>

    @Query("SELECT * FROM credit_cards")
    fun observeAll(): Flow<List<CreditCardEntity>>

    @Query("SELECT * FROM credit_cards WHERE id = :id")
    suspend fun getById(id: Long): CreditCardEntity?

    @Insert
    suspend fun insert(card: CreditCardEntity): Long

    @Update
    suspend fun update(card: CreditCardEntity)

    @Query("UPDATE credit_cards SET is_default = 0, updated_at = :now WHERE is_default = 1")
    suspend fun clearDefault(now: Long = System.currentTimeMillis())

    @Query("UPDATE credit_cards SET is_deleted = 1, is_default = 0, updated_at = :now WHERE id = :id")
    suspend fun softDelete(id: Long, now: Long = System.currentTimeMillis())
}

@Dao
interface StatementDao {
    @Query("SELECT * FROM credit_card_statements")
    fun observeAll(): Flow<List<StatementEntity>>

    @Query("SELECT * FROM credit_card_statements")
    suspend fun getAll(): List<StatementEntity>

    @Query("SELECT * FROM credit_card_statements WHERE credit_card_id = :cardId ORDER BY closing_date")
    suspend fun forCard(cardId: Long): List<StatementEntity>

    @Query("SELECT * FROM credit_card_statements WHERE id = :id")
    suspend fun getById(id: Long): StatementEntity?

    @Insert
    suspend fun insert(statement: StatementEntity): Long

    @Update
    suspend fun update(statement: StatementEntity)

    @Query("DELETE FROM credit_card_statements WHERE id = :id")
    suspend fun delete(id: Long)
}

@Dao
interface AllocationDao {
    @Query("SELECT * FROM budget_allocations")
    fun observeAll(): Flow<List<BudgetAllocationEntity>>

    @Query("SELECT * FROM budget_allocations")
    suspend fun getAll(): List<BudgetAllocationEntity>

    @Insert
    suspend fun insert(allocation: BudgetAllocationEntity): Long

    @Insert
    suspend fun insertAll(allocations: List<BudgetAllocationEntity>)

    @Query("UPDATE budget_allocations SET amount = :amount WHERE id IN (:ids)")
    suspend fun setAmount(ids: List<Long>, amount: Long)

    @Query("UPDATE budget_allocations SET is_deleted = 1 WHERE id IN (:ids)")
    suspend fun tombstone(ids: List<Long>)

    @Query("UPDATE budget_allocations SET is_recurring = :recurring WHERE id = :id")
    suspend fun setRecurring(id: Long, recurring: Boolean)

    @Query("DELETE FROM budget_allocations WHERE id IN (:ids)")
    suspend fun delete(ids: List<Long>)
}
