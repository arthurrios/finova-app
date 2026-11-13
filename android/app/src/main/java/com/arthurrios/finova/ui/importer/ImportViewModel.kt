package com.arthurrios.finova.ui.importer

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.data.repo.ImportRepository
import com.arthurrios.finova.domain.importer.ColumnRole
import com.arthurrios.finova.domain.importer.CsvImportEngine
import com.arthurrios.finova.domain.importer.DateFormatSpec
import com.arthurrios.finova.domain.importer.ImportBatch
import com.arthurrios.finova.domain.importer.ImportError
import com.arthurrios.finova.domain.importer.ImportOverrides
import com.arthurrios.finova.domain.importer.ImportPlan
import com.arthurrios.finova.domain.importer.ImportRollbackReport
import com.arthurrios.finova.domain.importer.ImportRow
import com.arthurrios.finova.domain.importer.InferenceConfidence
import com.arthurrios.finova.domain.importer.ResolvedSchema
import com.arthurrios.finova.domain.importer.SignConvention
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A picked file's bytes. Everything downstream works on these; no Uri escapes the picker. */
class LoadedFile(val displayName: String, val data: ByteArray)

/** Something to tell the user. Resolved to text by the screen, which has the resources. */
sealed interface ImportMessage {
    data class Failure(val error: ImportError) : ImportMessage
    data class BatchTooLarge(val count: Int, val limit: Int) : ImportMessage
    data object ApplyFailed : ImportMessage
    data object MappingIncomplete : ImportMessage
    data class KeptEdited(val count: Int) : ImportMessage
}

/** Where the flow goes next, sent once. */
enum class ImportStep { Mapping, Review, Finished }

/** The review section a row sits in. Port of ImportReviewSection. */
enum class ReviewSection { WillBeAdded, NeedsDecision, Duplicates, CouldNotBeRead }

data class ImportUiState(
    val parsing: Boolean = false,
    val file: LoadedFile? = null,
    val plan: ImportPlan? = null,
    /** The schema being corrected on the mapping screen. */
    val schema: ResolvedSchema? = null,
    val overrides: ImportOverrides = ImportOverrides(),
    val priorImport: ImportBatch? = null,
    /** Rows written so far and the total, while an apply runs. */
    val applying: Pair<Int, Int>? = null,
    val applyError: ImportMessage? = null,
    val finished: ImportBatch? = null,
    val currencyCode: String = "BRL",
) {
    fun isIncluded(row: ImportRow) = overrides.isIncluded(row)

    fun category(row: ImportRow): TransactionCategory =
        overrides.byFingerprint[row.fingerprint]?.category ?: row.categorySuggestion?.category ?: TransactionCategory.Miscellaneous

    fun title(row: ImportRow): String =
        overrides.byFingerprint[row.fingerprint]?.title ?: row.parsed?.title?.title ?: row.rawCells.firstOrNull().orEmpty()

    /** Included rows first, then those waiting on a decision, duplicates, and the unreadable. */
    val sections: List<Pair<ReviewSection, List<ImportRow>>>
        get() {
            val plan = plan ?: return emptyList()
            return listOf(
                ReviewSection.WillBeAdded to plan.rows.filter { isIncluded(it) },
                ReviewSection.NeedsDecision to plan.undecidedRows.filterNot { isIncluded(it) },
                ReviewSection.Duplicates to plan.duplicateRows.filterNot { isIncluded(it) },
                ReviewSection.CouldNotBeRead to plan.failedRows,
            ).filter { it.second.isNotEmpty() }
        }

    val resolved get() = plan?.resolve(overrides)

    /** The signed total of what will actually be written. */
    val netTotal: Long get() = resolved?.rows?.sumOf { it.transaction.signedAmount } ?: 0

    val canApply: Boolean get() = applying == null && (resolved?.rows?.isNotEmpty() == true)

    val needsSignDecision: Boolean get() = plan?.undecidedRows?.isNotEmpty() == true
}

/**
 * The whole import flow, shared by its three screens: history (pick a file, undo a past import),
 * mapping (correct how the file was read) and review (the diff the user signs off). Port of
 * ImportHistoryViewModel, ImportMappingViewModel and ImportReviewViewModel.
 */
class ImportViewModel(
    private val imports: ImportRepository,
    private val finance: FinanceRepository,
    settings: UserSettingsStore,
    private val categoryNames: Map<TransactionCategory, String>,
    private val untitled: String,
) : ViewModel() {

    private val _state = MutableStateFlow(ImportUiState(currencyCode = settings.currencyCode))
    val state: StateFlow<ImportUiState> = _state

    val history: StateFlow<List<ImportBatch>> = imports.history.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _messages = Channel<ImportMessage>(Channel.BUFFERED)
    val messages = _messages.receiveAsFlow()

    private val _steps = Channel<ImportStep>(Channel.BUFFERED)
    val steps = _steps.receiveAsFlow()

    init {
        // Settles anything a crash left mid-write, the first moment the user asks about imports.
        viewModelScope.launch { imports.reconcileInterrupted() }
    }

    suspend fun liveCount(batch: ImportBatch) = imports.liveCount(batch.uuid)

    // ---- Reading a file ------------------------------------------------------------------------

    fun parse(file: LoadedFile) {
        _state.update { it.copy(parsing = true) }
        viewModelScope.launch {
            val result = withContext(Dispatchers.Default) {
                runCatching { CsvImportEngine.makePlan(input(file)) }
            }
            _state.update { it.copy(parsing = false) }
            result.onSuccess { plan ->
                val prior = imports.priorImport(plan.source.sha256)
                _state.update {
                    ImportUiState(file = file, plan = plan, schema = plan.schema, priorImport = prior, currencyCode = it.currencyCode)
                }
                // A file read with low confidence, or with no date or amount found, is checked first;
                // the diff after it is the one step never skipped.
                _steps.send(if (plan.confidence.band == InferenceConfidence.Band.Low || !plan.schema.isUsable) ImportStep.Mapping else ImportStep.Review)
            }.onFailure { error ->
                _messages.send(ImportMessage.Failure(error as? ImportError ?: ImportError.CannotReadFile))
            }
        }
    }

    fun reportPickerFailure(error: ImportError) {
        viewModelScope.launch { _messages.send(ImportMessage.Failure(error)) }
    }

    private suspend fun input(file: LoadedFile) = CsvImportEngine.Input(
        filename = file.displayName,
        data = file.data,
        alreadyImported = imports.appliedFingerprints(),
        existing = finance.storedRows(),
        categoryNames = categoryNames,
        untitled = untitled,
    )

    // ---- Mapping -------------------------------------------------------------------------------

    fun setDateFormat(spec: DateFormatSpec) = _state.update { it.copy(schema = it.schema?.copy(dateFormat = spec)) }

    fun setSignConvention(convention: SignConvention) = _state.update { it.copy(schema = it.schema?.copy(signConvention = convention)) }

    fun setColumn(index: Int, role: ColumnRole) = _state.update { it.copy(schema = it.schema?.withColumn(index, role)) }

    fun confirmMapping() {
        val current = _state.value
        val schema = current.schema ?: return
        val file = current.file ?: return
        val plan = current.plan ?: return
        if (!schema.isUsable) {
            viewModelScope.launch { _messages.send(ImportMessage.MappingIncomplete) }
            return
        }
        _state.update { it.copy(parsing = true) }
        viewModelScope.launch {
            val result = withContext(Dispatchers.Default) { runCatching { CsvImportEngine.replan(input(file), schema, plan) } }
            _state.update { it.copy(parsing = false) }
            result.onSuccess { replanned ->
                _state.update { it.copy(plan = replanned, schema = replanned.schema) }
                _steps.send(ImportStep.Review)
            }.onFailure { error ->
                _messages.send(ImportMessage.Failure(error as? ImportError ?: ImportError.CannotReadFile))
            }
        }
    }

    // ---- Review edits --------------------------------------------------------------------------

    private fun edit(row: ImportRow, change: (com.arthurrios.finova.domain.importer.RowOverride) -> com.arthurrios.finova.domain.importer.RowOverride) =
        _state.update { it.copy(overrides = it.overrides.update(row.fingerprint, change)) }

    fun toggle(row: ImportRow) {
        val included = _state.value.isIncluded(row)
        edit(row) { it.copy(isIncluded = !included) }
    }

    fun setCategory(row: ImportRow, category: TransactionCategory) = edit(row) { it.copy(category = category) }

    fun setTitle(row: ImportRow, title: String) = edit(row) { it.copy(title = title.trim().ifEmpty { null }) }

    /** Settles an ambiguous-sign row by stating its direction. */
    fun setType(row: ImportRow, type: TransactionType) = edit(row) { it.copy(type = type, isIncluded = true) }

    /** One direction for every row still waiting on the sign question. */
    fun resolveAllSigns(asWritten: Boolean) {
        val rows = _state.value.plan?.undecidedRows.orEmpty()
        _state.update { state ->
            var overrides = state.overrides
            for (row in rows) {
                val parsed = row.parsed ?: continue
                val asRead = if (parsed.signedCents > 0) TransactionType.Income else TransactionType.Expense
                val chosen = if (asWritten) asRead else if (asRead == TransactionType.Income) TransactionType.Expense else TransactionType.Income
                overrides = overrides.update(row.fingerprint) { it.copy(type = chosen, isIncluded = true) }
            }
            state.copy(overrides = overrides)
        }
    }

    // ---- Apply ---------------------------------------------------------------------------------

    fun apply() {
        val current = _state.value
        val plan = current.plan ?: return
        val file = current.file ?: return
        if (!current.canApply) return
        val resolved = plan.resolve(current.overrides)
        _state.update { it.copy(applying = 0 to resolved.rows.size, applyError = null) }
        viewModelScope.launch {
            try {
                val batch = imports.apply(
                    ImportRepository.Request(
                        sourceFilename = file.displayName,
                        fileHash = plan.source.sha256,
                        fileByteCount = plan.source.byteCount,
                        columnMapping = plan.schema.describe(),
                        rowsInFile = plan.rows.size,
                        rowsSkipped = resolved.skippedCount,
                        rowsFailed = resolved.failedCount,
                        rows = resolved.rows,
                    ),
                ) { done, total -> _state.update { it.copy(applying = done to total) } }
                _state.update { it.copy(applying = null, finished = batch) }
            } catch (e: ImportRepository.TooManyRows) {
                _state.update { it.copy(applying = null, applyError = ImportMessage.BatchTooLarge(e.count, e.limit)) }
            } catch (e: Exception) {
                _state.update { it.copy(applying = null, applyError = ImportMessage.ApplyFailed) }
            }
        }
    }

    /** Back to the history screen, with the finished or discarded import forgotten. */
    fun reset() = _state.update { ImportUiState(currencyCode = it.currencyCode) }

    // ---- Undo ----------------------------------------------------------------------------------

    fun rollback(batch: ImportBatch) {
        viewModelScope.launch {
            val report: ImportRollbackReport? = imports.rollback(batch.uuid)
            if (report != null && report.editedKept > 0) _messages.send(ImportMessage.KeptEdited(report.editedKept))
        }
    }
}
