package com.arthurrios.finova.data.repo

import androidx.room.withTransaction
import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.data.db.ImportBatchEntity
import com.arthurrios.finova.data.db.ImportBatchRowEntity
import com.arthurrios.finova.domain.importer.ImportBatch
import com.arthurrios.finova.domain.importer.ImportBatchStatus
import com.arthurrios.finova.domain.importer.ImportRollback
import com.arthurrios.finova.domain.importer.ImportRollbackReport
import com.arthurrios.finova.domain.importer.ImportableRow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.UUID

/**
 * Statement imports as reversible batches. Port of ImportApplyService, ImportRollbackService and
 * ImportBatchRepository, minus everything sync (Android has none): an undo is a plain local delete.
 */
class ImportRepository(private val db: FinovaDatabase, private val finance: FinanceRepository) {
    private val dao = db.imports()

    class Request(
        val sourceFilename: String,
        val fileHash: String,
        val fileByteCount: Int,
        val columnMapping: String,
        val rowsInFile: Int,
        val rowsSkipped: Int,
        val rowsFailed: Int,
        val rows: List<ImportableRow>,
    )

    class TooManyRows(val count: Int, val limit: Int) : Exception()

    val history: Flow<List<ImportBatch>> = dao.observeHistory().map { rows -> rows.map { it.toModel() } }

    suspend fun appliedFingerprints(): Set<String> = dao.appliedFingerprints().toSet()

    /** The latest import of this exact file still in force, if any. */
    suspend fun priorImport(fileHash: String): ImportBatch? = dao.appliedWithHash(fileHash).firstOrNull()?.toModel()

    suspend fun liveCount(uuid: String): Int = dao.liveCount(uuid)

    /**
     * Writes a reviewed import. The ORDER is the crash safety, as on iOS: the batch is saved on its
     * own first and moved out of `applying` only after the last row, so a batch found in `applying`
     * later was cut short and [reconcileInterrupted] settles it by recounting.
     */
    suspend fun apply(request: Request, progress: (done: Int, total: Int) -> Unit = { _, _ -> }): ImportBatch {
        if (request.rows.size > MAX_ROWS_PER_BATCH) throw TooManyRows(request.rows.size, MAX_ROWS_PER_BATCH)
        val now = System.currentTimeMillis()
        val dates = request.rows.map { it.transaction.date }
        var batch = ImportBatch(
            uuid = UUID.randomUUID().toString().uppercase(),
            createdAt = now,
            appliedAt = now,
            sourceFilename = request.sourceFilename,
            fileHash = request.fileHash,
            fileByteCount = request.fileByteCount,
            columnMapping = request.columnMapping,
            rowsInFile = request.rowsInFile,
            rowsSelected = request.rows.size,
            rowsSkipped = request.rowsSkipped,
            rowsFailed = request.rowsFailed,
            // Stored amounts are magnitudes; the sign comes back from the type.
            amountTotal = request.rows.sumOf { it.transaction.signedAmount },
            dateMin = dates.minOrNull(),
            dateMax = dates.maxOrNull(),
            status = ImportBatchStatus.Applying,
        )
        val batchId = dao.insertBatch(batch.toEntity())

        var inserted = 0
        try {
            // Committed in chunks: a crash keeps whole chunks with their membership, and the bar moves.
            for (chunk in request.rows.chunked(CHUNK)) {
                db.withTransaction {
                    val ids = finance.addAll(chunk.map { it.transaction })
                    dao.insertRows(ids.zip(chunk).map { (id, row) ->
                        ImportBatchRowEntity(
                            batchUuid = batch.uuid,
                            transactionId = id,
                            sourceLine = row.sourceLine,
                            rowFingerprint = row.fingerprint,
                            snapshot = ImportRollback.snapshot(row.transaction),
                        )
                    })
                }
                inserted += chunk.size
                progress(inserted, request.rows.size)
            }
        } catch (e: Exception) {
            batch = batch.copy(status = ImportBatchStatus.Failed, rowsInserted = inserted, finishedAt = System.currentTimeMillis())
                .withNote("Apply failed: ${e.message}")
            dao.updateBatch(batch.toEntity(batchId))
            throw e
        }
        batch = batch.copy(status = ImportBatchStatus.Applied, rowsInserted = inserted, finishedAt = System.currentTimeMillis())
        dao.updateBatch(batch.toEntity(batchId))
        return batch
    }

    /**
     * Removes the rows a batch created. A row the user edited since is KEPT: a later edit is newer
     * intent than the import that made it. Safe to run twice.
     */
    suspend fun rollback(uuid: String): ImportRollbackReport? {
        val entity = dao.batch(uuid) ?: return null
        val batch = entity.toModel()
        if (batch.status == ImportBatchStatus.RolledBack) return ImportRollbackReport(alreadyGone = batch.rowsRemoved)
        dao.updateBatch(batch.copy(status = ImportBatchStatus.RollingBack).toEntity(entity.id))

        val written = dao.rows(uuid).associate { it.transactionId to it.snapshot }
        val current = db.transactions().getAll().filter { it.id in written }.associate { it.id to it.toDomain() }
        val (doomed, report) = ImportRollback.plan(written, current)
        finance.deleteImported(doomed)

        var done = batch.copy(status = ImportBatchStatus.RolledBack, rowsRemoved = report.removed, rolledBackAt = System.currentTimeMillis())
        if (report.editedKept > 0) done = done.withNote("${report.editedKept} row(s) kept because they were edited after importing.")
        dao.updateBatch(done.toEntity(entity.id))
        return report
    }

    /**
     * Settles batches a crash left mid-write: `applying` becomes applied with the rows actually there
     * (a partial import is a smaller import, not a corrupt one), `rollingBack` runs its undo again.
     * Called when the import screen opens, never at launch, as on iOS.
     */
    suspend fun reconcileInterrupted() {
        for (entity in dao.batchesWithStatus(listOf(ImportBatchStatus.Applying.key, ImportBatchStatus.RollingBack.key))) {
            val batch = entity.toModel()
            if (batch.status == ImportBatchStatus.Applying) {
                val live = dao.liveCount(batch.uuid)
                dao.updateBatch(
                    batch.copy(status = ImportBatchStatus.Applied, rowsInserted = live, finishedAt = System.currentTimeMillis())
                        .withNote("Interrupted during apply; recovered $live row(s).").toEntity(entity.id),
                )
            } else {
                rollback(batch.uuid)
            }
        }
    }

    companion object {
        /** iOS caps one batch at 1000 rows for its sync engine; kept, so a file behaves the same on both. */
        const val MAX_ROWS_PER_BATCH = 1000
        private const val CHUNK = 100
    }
}

private fun ImportBatchEntity.toModel() = ImportBatch(
    uuid = uuid, createdAt = createdAt, appliedAt = appliedAt, finishedAt = finishedAt, rolledBackAt = rolledBackAt,
    sourceFilename = sourceFilename, fileHash = fileHash, fileByteCount = fileByteCount, columnMapping = columnMapping,
    rowsInFile = rowsInFile, rowsSelected = rowsSelected, rowsInserted = rowsInserted, rowsSkipped = rowsSkipped,
    rowsFailed = rowsFailed, rowsRemoved = rowsRemoved, amountTotal = amountTotal, dateMin = dateMin, dateMax = dateMax,
    status = ImportBatchStatus.fromKey(status), notes = notes,
)

private fun ImportBatch.toEntity(id: Long = 0) = ImportBatchEntity(
    id = id, uuid = uuid, createdAt = createdAt, appliedAt = appliedAt, finishedAt = finishedAt, rolledBackAt = rolledBackAt,
    sourceFilename = sourceFilename, fileHash = fileHash, fileByteCount = fileByteCount, columnMapping = columnMapping,
    rowsInFile = rowsInFile, rowsSelected = rowsSelected, rowsInserted = rowsInserted, rowsSkipped = rowsSkipped,
    rowsFailed = rowsFailed, rowsRemoved = rowsRemoved, amountTotal = amountTotal, dateMin = dateMin, dateMax = dateMax,
    status = status.key, notes = notes,
)
