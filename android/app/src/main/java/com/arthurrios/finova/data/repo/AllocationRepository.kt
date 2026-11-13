package com.arthurrios.finova.data.repo

import androidx.room.withTransaction
import com.arthurrios.finova.data.db.BudgetAllocationEntity
import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.domain.allocation.AllocationEditScope
import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.model.TransactionCategory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.YearMonth

/** Port of BudgetAllocationRepository and the write side of BudgetAllocationService. */
class AllocationRepository(private val db: FinovaDatabase) {
    private val dao = db.allocations()

    /** Every allocation, deleted series months included (the rules need them). */
    val all: Flow<List<AllocationRow>> = dao.observeAll().map { rows -> rows.map { it.toModel() } }

    /**
     * Adds an allocation. A repeating one also creates its months ahead; with an [endMonth] it
     * stops there and no longer repeats (a bounded series is a parent that stopped repeating but
     * still owns its months, as on iOS). Returns false when the category already has one that month.
     */
    suspend fun create(
        category: TransactionCategory,
        amount: Long,
        month: YearMonth,
        repeating: Boolean,
        endMonth: YearMonth?,
        today: LocalDate = LocalDate.now(),
    ): Boolean = db.withTransaction {
        require(amount > 0)
        val existing = dao.getAll().map { it.toModel() }
        if (Allocations.live(existing).any { it.month == month && it.category == category }) return@withTransaction false
        val id = dao.insert(AllocationRow(month = month, category = category, amount = amount, isRecurring = repeating).toEntity())
        if (repeating) {
            val rows = dao.getAll().map { it.toModel() }
            dao.insertAll(Allocations.missingSeriesMonths(rows, id, endMonth, YearMonth.from(today)).map { it.toEntity() })
            if (endMonth != null) dao.setRecurring(id, false)
        }
        true
    }

    /** Fills in the months repeating series are missing. iOS runs this after every dashboard load. */
    suspend fun materializeAll(today: LocalDate = LocalDate.now()) = db.withTransaction {
        val rows = dao.getAll().map { it.toModel() }
        val missing = Allocations.seriesParents(rows).flatMap { Allocations.missingSeriesMonths(rows, it.id, null, YearMonth.from(today)) }
        if (missing.isNotEmpty()) dao.insertAll(missing.map { it.toEntity() })
    }

    suspend fun edit(id: Long, amount: Long, scope: AllocationEditScope, through: YearMonth? = null) = db.withTransaction {
        require(amount > 0)
        val targets = Allocations.editTargets(dao.getAll().map { it.toModel() }, id, scope, through)
        if (targets.isNotEmpty()) dao.setAmount(targets.toList(), amount)
    }

    /** Removes the given allocations one by one, as "Overwrite Future Allocations" does. */
    suspend fun deleteEach(ids: List<Long>) = db.withTransaction {
        ids.forEach { delete(it, AllocationEditScope.ThisOnly) }
    }

    suspend fun delete(id: Long, scope: AllocationEditScope) = db.withTransaction {
        val plan = Allocations.deletePlan(dao.getAll().map { it.toModel() }, id, scope)
        if (plan.remove.isNotEmpty()) dao.delete(plan.remove.toList())
        if (plan.tombstone.isNotEmpty()) dao.tombstone(plan.tombstone.toList())
        plan.stopRepeating?.let { dao.setRecurring(it, false) }
    }
}

internal fun BudgetAllocationEntity.toModel() = AllocationRow(
    id = id, month = month, category = TransactionCategory.fromKey(category), amount = amount,
    isRecurring = isRecurring, parentId = parentAllocationId, isDeleted = isDeleted,
)

internal fun AllocationRow.toEntity() = BudgetAllocationEntity(
    id = id, month = month, category = category.key, amount = amount,
    isRecurring = isRecurring, parentAllocationId = parentId, isDeleted = isDeleted,
)
