package com.arthurrios.finova.data.db

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate

/** One statement import. Port of the iOS `ImportBatches` table; local only, like iOS. */
@Entity(tableName = "import_batches", indices = [Index(value = ["uuid"], unique = true), Index("created_at")])
data class ImportBatchEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val uuid: String,
    @ColumnInfo(name = "created_at") val createdAt: Long,
    @ColumnInfo(name = "applied_at") val appliedAt: Long? = null,
    @ColumnInfo(name = "finished_at") val finishedAt: Long? = null,
    @ColumnInfo(name = "rolled_back_at") val rolledBackAt: Long? = null,
    @ColumnInfo(name = "source_filename") val sourceFilename: String,
    @ColumnInfo(name = "file_hash") val fileHash: String,
    @ColumnInfo(name = "file_byte_count") val fileByteCount: Int,
    @ColumnInfo(name = "column_mapping") val columnMapping: String,
    @ColumnInfo(name = "rows_in_file") val rowsInFile: Int,
    @ColumnInfo(name = "rows_selected") val rowsSelected: Int,
    @ColumnInfo(name = "rows_inserted") val rowsInserted: Int,
    @ColumnInfo(name = "rows_skipped") val rowsSkipped: Int,
    @ColumnInfo(name = "rows_failed") val rowsFailed: Int,
    @ColumnInfo(name = "rows_removed") val rowsRemoved: Int,
    @ColumnInfo(name = "amount_total") val amountTotal: Long,
    @ColumnInfo(name = "date_min") val dateMin: LocalDate?,
    @ColumnInfo(name = "date_max") val dateMax: LocalDate?,
    val status: String,
    val notes: String? = null,
)

/**
 * A transaction a batch created. Its own table, as on iOS (`ImportBatchRows`): it outlives the
 * transaction, and [snapshot] is how an undo tells an untouched row from one the user edited since.
 */
@Entity(
    tableName = "import_batch_rows",
    indices = [Index("batch_uuid"), Index("transaction_id"), Index("row_fingerprint")],
)
data class ImportBatchRowEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "batch_uuid") val batchUuid: String,
    @ColumnInfo(name = "transaction_id") val transactionId: Long,
    @ColumnInfo(name = "source_line") val sourceLine: Int?,
    @ColumnInfo(name = "row_fingerprint") val rowFingerprint: String,
    val snapshot: String,
)

@Dao
interface ImportDao {
    @Insert
    suspend fun insertBatch(entity: ImportBatchEntity): Long

    @Update
    suspend fun updateBatch(entity: ImportBatchEntity)

    @Query("SELECT * FROM import_batches WHERE uuid = :uuid")
    suspend fun batch(uuid: String): ImportBatchEntity?

    @Query("SELECT * FROM import_batches ORDER BY created_at DESC LIMIT 100")
    fun observeHistory(): Flow<List<ImportBatchEntity>>

    @Query("SELECT * FROM import_batches WHERE status IN (:statuses)")
    suspend fun batchesWithStatus(statuses: List<String>): List<ImportBatchEntity>

    @Query("SELECT * FROM import_batches WHERE file_hash = :hash AND status = 'applied' ORDER BY created_at DESC")
    suspend fun appliedWithHash(hash: String): List<ImportBatchEntity>

    @Insert
    suspend fun insertRows(rows: List<ImportBatchRowEntity>)

    @Query("SELECT * FROM import_batch_rows WHERE batch_uuid = :uuid")
    suspend fun rows(uuid: String): List<ImportBatchRowEntity>

    /** Rows of imports still in force: an undone import may be imported again. */
    @Query("SELECT r.row_fingerprint FROM import_batch_rows r JOIN import_batches b ON b.uuid = r.batch_uuid WHERE b.status = 'applied'")
    suspend fun appliedFingerprints(): List<String>

    @Query("SELECT COUNT(*) FROM import_batch_rows r JOIN transactions t ON t.id = r.transaction_id WHERE r.batch_uuid = :uuid")
    suspend fun liveCount(uuid: String): Int
}
