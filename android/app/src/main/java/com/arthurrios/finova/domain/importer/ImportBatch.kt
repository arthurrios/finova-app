package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.Transaction
import java.time.LocalDate

/**
 * Where an import is in its life. Port of ImportBatchStatus. `Applying` and `RollingBack` are saved
 * BEFORE any row is written and cleared AFTER the last, so a batch found in either at the next visit
 * was cut short and is settled by recounting. (iOS also has the sync-only `rollbackDeferred`.)
 */
enum class ImportBatchStatus(val key: String) {
    Preparing("preparing"),
    Applying("applying"),
    Applied("applied"),
    RollingBack("rollingBack"),
    RolledBack("rolledBack"),
    Failed("failed");

    val isRollbackable: Boolean get() = this == Applied || this == Failed

    companion object {
        fun fromKey(key: String?) = entries.firstOrNull { it.key == key } ?: Failed
    }
}

/** One import, as a reversible unit. Kept on this phone only. Port of ImportBatch.swift. */
data class ImportBatch(
    val uuid: String,
    val createdAt: Long,
    val appliedAt: Long? = null,
    val finishedAt: Long? = null,
    val rolledBackAt: Long? = null,
    val sourceFilename: String,
    /** SHA-256 of the bytes: "you already imported this file" is the cheapest guard against the commonest mistake. */
    val fileHash: String,
    val fileByteCount: Int,
    /** How the file was read, for history. Display data, never queried. */
    val columnMapping: String,
    val rowsInFile: Int,
    val rowsSelected: Int,
    val rowsInserted: Int = 0,
    val rowsSkipped: Int,
    val rowsFailed: Int,
    /** What an undo actually removed: rows edited after the import are kept. */
    val rowsRemoved: Int = 0,
    /** Signed total in cents, so the history list needs no join. */
    val amountTotal: Long,
    val dateMin: LocalDate?,
    val dateMax: LocalDate?,
    val status: ImportBatchStatus,
    val notes: String? = null,
) {
    fun withNote(note: String) = copy(notes = if (notes.isNullOrEmpty()) note else "$notes\n$note")
}

/** What an undo did. */
data class ImportRollbackReport(
    val removed: Int = 0,
    /** Gone before the undo ran: deleted by hand, or a second undo. */
    val alreadyGone: Int = 0,
    /** Edited after the import, so kept: a later edit is newer intent than the import that made the row. */
    val editedKept: Int = 0,
)

object ImportRollback {
    /** The row as it was written, to tell later whether the user changed it. */
    fun snapshot(row: Transaction): String =
        listOf(row.title, row.category.key, row.type.key, row.amount, row.date, row.budgetMonth, row.creditCardId).joinToString("|")

    /**
     * Which of a batch's rows an undo removes. iOS compares the row's `updated_at` against the import
     * time; Android rows carry no edit stamp, so the row is compared with how it was written.
     *
     * @param written transaction id to snapshot, as recorded at import time.
     * @param current the rows still in the ledger, by id.
     */
    fun plan(written: Map<Long, String>, current: Map<Long, Transaction>): Pair<List<Long>, ImportRollbackReport> {
        val doomed = mutableListOf<Long>()
        var gone = 0
        var edited = 0
        for ((id, snapshot) in written) {
            val row = current[id]
            when {
                row == null -> gone++
                snapshot(row) == snapshot -> doomed += id
                else -> edited++
            }
        }
        return doomed to ImportRollbackReport(removed = doomed.size, alreadyGone = gone, editedKept = edited)
    }
}
