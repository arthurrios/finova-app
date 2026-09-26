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
