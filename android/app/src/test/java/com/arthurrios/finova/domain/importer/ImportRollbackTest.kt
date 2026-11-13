package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/** The undo rules: untouched rows go, edited rows stay, rows already gone are counted. Port of ImportRollbackTests' classes A-D. */
class ImportRollbackTest {
    private fun row(id: Long, title: String = "Padaria", amount: Long = 2_350, category: TransactionCategory = TransactionCategory.Meals) = Transaction(
        id = id, title = title, category = category, type = TransactionType.Expense, amount = amount,
        date = LocalDate.of(2026, 10, 3), budgetMonth = YearMonth.of(2026, 10),
    )

    @Test fun untouchedRowsAreRemoved() {
        val written = mapOf(1L to ImportRollback.snapshot(row(1)), 2L to ImportRollback.snapshot(row(2)))
        val (doomed, report) = ImportRollback.plan(written, mapOf(1L to row(1), 2L to row(2)))
        assertEquals(listOf(1L, 2L), doomed.sorted())
        assertEquals(ImportRollbackReport(removed = 2), report)
    }

    @Test fun aRowEditedAfterImportingIsKept() {
        val written = mapOf(1L to ImportRollback.snapshot(row(1)), 2L to ImportRollback.snapshot(row(2)))
        val current = mapOf(1L to row(1, title = "Padaria Central"), 2L to row(2, category = TransactionCategory.Groceries))
        val (doomed, report) = ImportRollback.plan(written, current)
        assertTrue(doomed.isEmpty())
        assertEquals(2, report.editedKept)
    }

    @Test fun aRowAlreadyDeletedIsCountedNotRemovedTwice() {
        val written = mapOf(1L to ImportRollback.snapshot(row(1)), 2L to ImportRollback.snapshot(row(2)))
        val (doomed, report) = ImportRollback.plan(written, mapOf(2L to row(2)))
        assertEquals(listOf(2L), doomed)
        assertEquals(1, report.alreadyGone)
    }

    @Test fun onlyAppliedAndFailedBatchesCanBeUndone() {
        assertTrue(ImportBatchStatus.Applied.isRollbackable)
        assertTrue(ImportBatchStatus.Failed.isRollbackable)
        assertFalse(ImportBatchStatus.RolledBack.isRollbackable)
        assertFalse(ImportBatchStatus.Applying.isRollbackable)
        assertEquals(ImportBatchStatus.RollingBack, ImportBatchStatus.fromKey("rollingBack"))
    }
}
