package com.arthurrios.finova.ui.importer

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.importer.ColumnRole
import com.arthurrios.finova.domain.importer.CsvImportEngine
import com.arthurrios.finova.domain.importer.DateFormatSpec
import com.arthurrios.finova.domain.importer.DetectedFileFormat
import com.arthurrios.finova.domain.importer.Disposition
import com.arthurrios.finova.domain.importer.ImportBatch
import com.arthurrios.finova.domain.importer.ImportBatchStatus
import com.arthurrios.finova.domain.importer.ImportError
import com.arthurrios.finova.domain.importer.ImportRow
import com.arthurrios.finova.domain.importer.RowDecision
import com.arthurrios.finova.domain.importer.RowError
import com.arthurrios.finova.domain.importer.RowWarning
import com.arthurrios.finova.domain.importer.SignConvention
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Date

private val CardShape = RoundedCornerShape(CornerRadius.ExtraLarge)
private val DayMonthYear: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/**
 * What the picker offers. Banks label CSV exports loosely, so anything can be picked (iOS accepts
 * `public.data` for the same reason) and the file is judged by its CONTENT, never its declared type.
 */
private val PickerTypes = arrayOf(
    "text/*", "text/csv", "text/comma-separated-values", "application/csv",
    "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/octet-stream", "*/*",
)

// ---- History ---------------------------------------------------------------------------------------

/**
 * The way into the feature: pick a file, or undo a past import. Port of ImportHistoryViewController.
 */
@Composable
fun ImportHistoryScreen(viewModel: ImportViewModel, onBack: () -> Unit, onStep: (ImportStep) -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val history by viewModel.history.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf<ImportMessage?>(null) }
    var selected by remember { mutableStateOf<ImportBatch?>(null) }
    var confirmUndo by remember { mutableStateOf<Pair<ImportBatch, Int>?>(null) }

    LaunchedEffect(viewModel) { viewModel.steps.collect(onStep) }
    LaunchedEffect(viewModel) { viewModel.messages.collect { message = it } }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult // backed out of the picker: not an error
        scope.launch {
            when (val loaded = withContext(Dispatchers.IO) { readFile(context, uri) }) {
                is Result.Success -> viewModel.parse(loaded.file)
                is Result.Failure -> viewModel.reportPickerFailure(loaded.error)
            }
        }
    }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.import_history_title), subtitle = null, onBack = onBack)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (history.isEmpty()) {
                Text(
                    stringResource(R.string.import_history_empty), style = FinovaType.TextSM, color = FinovaColors.Gray500,
                    textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center).padding(horizontal = Spacing.S6),
                )
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(Spacing.S2),
                    modifier = Modifier.fillMaxSize().padding(horizontal = Spacing.S4),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = Spacing.S4),
                ) {
                    items(history, key = { it.uuid }) { batch -> BatchRow(batch, state.currencyCode) { selected = batch } }
                }
            }
            if (state.parsing) {
                androidx.compose.material3.CircularProgressIndicator(color = FinovaColors.MainMagenta, modifier = Modifier.align(Alignment.Center))
            }
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S2),
            modifier = Modifier.navigationBarsPadding().padding(start = Spacing.S4, end = Spacing.S4, bottom = Spacing.S3),
        ) {
            FinovaButton(
                text = stringResource(R.string.import_history_pick_file),
                onClick = { picker.launch(PickerTypes) },
                loading = state.parsing,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                stringResource(R.string.import_history_footnote), style = FinovaType.TextXS, color = FinovaColors.Gray500,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    selected?.let { batch -> BatchDetailsSheet(batch, viewModel, onDismiss = { selected = null }) { live -> selected = null; confirmUndo = batch to live } }
    confirmUndo?.let { (batch, live) ->
        AlertDialog(
            onDismissRequest = { confirmUndo = null },
            title = { Text(stringResource(R.string.import_history_undo_confirm_title)) },
            text = { Text(stringResource(R.string.import_history_undo_confirm_message, live, batch.sourceFilename)) },
            confirmButton = {
                TextButton(onClick = { confirmUndo = null; viewModel.rollback(batch) }) {
                    Text(stringResource(R.string.import_history_undo), color = FinovaColors.MainRed)
                }
            },
            dismissButton = { TextButton(onClick = { confirmUndo = null }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    message?.let { MessageDialog(it) { message = null } }
}

@Composable
private fun BatchRow(batch: ImportBatch, currencyCode: String, onClick: () -> Unit) {
    val spent = batch.status == ImportBatchStatus.RolledBack
    Column(
        verticalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(CardShape)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, CardShape)
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.S4, vertical = Spacing.S3)
            .alpha(if (spent) 0.55f else 1f),
    ) {
        Text(batch.sourceFilename, style = FinovaType.TitleSM, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
        Text(summary(batch, currencyCode), style = FinovaType.TextXS, color = FinovaColors.Gray500, maxLines = 2)
        Text(
            listOfNotNull(dateTime(batch.createdAt), range(batch)).joinToString(" · "),
            style = FinovaType.TextXS, color = FinovaColors.Gray400,
        )
    }
}

@Composable
private fun summary(batch: ImportBatch, currencyCode: String): String = when (batch.status) {
    ImportBatchStatus.RolledBack -> stringResource(R.string.import_history_status_rolled_back, batch.rolledBackAt?.let(::dateTime).orEmpty())
    ImportBatchStatus.Applied -> stringResource(R.string.import_history_status_applied, batch.rowsInserted, Money.format(kotlin.math.abs(batch.amountTotal), currencyCode))
    ImportBatchStatus.Failed -> stringResource(R.string.import_history_status_failed)
    else -> stringResource(R.string.import_history_status_interrupted)
}

private fun dateTime(millis: Long): String =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

private fun range(batch: ImportBatch): String? {
    val min = batch.dateMin ?: return null
    val max = batch.dateMax ?: return null
    return "${min.format(DayMonthYear)} – ${max.format(DayMonthYear)}"
}

/** What iOS shows in an action sheet: the counts, the notes, and Undo. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BatchDetailsSheet(batch: ImportBatch, viewModel: ImportViewModel, onDismiss: () -> Unit, onUndo: (live: Int) -> Unit) {
    var live by remember(batch.uuid) { mutableStateOf<Int?>(null) }
    LaunchedEffect(batch.uuid) { live = viewModel.liveCount(batch) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = FinovaColors.Gray100) {
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
            modifier = Modifier.navigationBarsPadding().padding(start = Spacing.S5, end = Spacing.S5, bottom = Spacing.S5),
        ) {
            Text(batch.sourceFilename, style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            Text(stringResource(R.string.import_history_detail_rows, batch.rowsInserted, live ?: 0), style = FinovaType.TextSM, color = FinovaColors.Gray600)
            Text(stringResource(R.string.import_history_detail_skipped, batch.rowsSkipped, batch.rowsFailed), style = FinovaType.TextSM, color = FinovaColors.Gray600)
            batch.notes?.let { Text(it, style = FinovaType.TextXS, color = FinovaColors.Gray500) }
            if (batch.status.isRollbackable) {
                Spacer(Modifier.height(Spacing.S2))
                FinovaAccentOutlinedButton(
                    text = stringResource(R.string.import_history_undo),
                    onClick = { onUndo(live ?: 0) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private sealed interface Result {
    class Success(val file: LoadedFile) : Result
    class Failure(val error: ImportError) : Result
}

/** Reads the picked file whole, refusing an empty or oversized one before it is loaded. */
private fun readFile(context: Context, uri: Uri): Result = try {
    var name = uri.lastPathSegment ?: "statement"
    var size = -1L
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            cursor.getString(0)?.let { name = it }
            if (!cursor.isNull(1)) size = cursor.getLong(1)
        }
    }
    when {
        size > CsvImportEngine.MAX_FILE_BYTES -> Result.Failure(ImportError.FileTooLarge(size.toInt(), CsvImportEngine.MAX_FILE_BYTES))
        else -> {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
            when {
                bytes.isEmpty() -> Result.Failure(ImportError.EmptyFile)
                bytes.size > CsvImportEngine.MAX_FILE_BYTES -> Result.Failure(ImportError.FileTooLarge(bytes.size, CsvImportEngine.MAX_FILE_BYTES))
                else -> Result.Success(LoadedFile(name, bytes))
            }
        }
    }
} catch (e: Exception) {
    Result.Failure(ImportError.CannotReadFile)
}

@Composable
private fun MessageDialog(message: ImportMessage, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.import_error_title)) },
        text = { Text(messageText(message)) },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_ok)) } },
    )
}

@Composable
private fun messageText(message: ImportMessage): String = when (message) {
    is ImportMessage.Failure -> errorText(message.error)
    is ImportMessage.BatchTooLarge -> stringResource(R.string.import_error_batch_too_large, message.count, message.limit)
    ImportMessage.ApplyFailed -> stringResource(R.string.import_error_apply_failed)
    ImportMessage.MappingIncomplete -> stringResource(R.string.import_mapping_error_incomplete)
    is ImportMessage.KeptEdited -> stringResource(R.string.import_history_undo_kept_edited, message.count)
}

/** Concrete about numbers and formats: "too large" without the figure leaves nothing to act on. */
@Composable
private fun errorText(error: ImportError): String = when (error) {
    ImportError.CannotReadFile -> stringResource(R.string.import_error_cannot_read)
    is ImportError.FileTooLarge -> stringResource(R.string.import_error_too_large, error.bytes / 1_048_576, error.limit / 1_048_576)
    is ImportError.TooManyRows -> stringResource(R.string.import_error_too_many_rows, error.count, error.limit)
    ImportError.EmptyFile -> stringResource(R.string.import_error_empty)
    ImportError.NotTextual -> stringResource(R.string.import_error_not_textual)
    is ImportError.UnterminatedQuote -> stringResource(R.string.import_error_unterminated_quote, error.line)
    ImportError.NoUsableColumns -> stringResource(R.string.import_error_no_usable_columns)
    is ImportError.WrongFileFormat -> stringResource(R.string.import_error_wrong_format, formatName(error))
    is ImportError.NotTabular -> stringResource(R.string.import_error_not_tabular, error.details)
    ImportError.InconsistentDateFormat -> stringResource(R.string.import_error_inconsistent_dates)
    ImportError.Cancelled -> stringResource(R.string.import_error_cannot_read)
}

@Composable
private fun formatName(error: ImportError.WrongFileFormat): String = stringResource(
    when {
        error.encrypted -> R.string.import_format_encrypted
        error.detected == DetectedFileFormat.ZipContainer -> R.string.import_format_spreadsheet
        error.detected == DetectedFileFormat.Ole2Document -> R.string.import_format_excel_legacy
        error.detected == DetectedFileFormat.Pdf -> R.string.import_format_pdf
        error.detected == DetectedFileFormat.Rtf -> R.string.import_format_rtf
        else -> R.string.import_format_binary
    },
)

// ---- Mapping ---------------------------------------------------------------------------------------

private enum class MappingField(val title: Int) {
    DateFormat(R.string.import_mapping_field_date_format),
    Sign(R.string.import_mapping_field_sign),
    DateColumn(R.string.import_mapping_field_date_column),
    DescriptionColumn(R.string.import_mapping_field_description_column),
    AmountColumn(R.string.import_mapping_field_amount_column),
}

/**
 * A confirmation screen, not a form: every field arrives with the engine's best guess, and the ones it
 * was least sure of are in red. Port of ImportMappingViewController.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportMappingScreen(viewModel: ImportViewModel, onBack: () -> Unit, onStep: (ImportStep) -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var message by remember { mutableStateOf<ImportMessage?>(null) }
    var picking by remember { mutableStateOf<MappingField?>(null) }
    LaunchedEffect(viewModel) { viewModel.steps.collect(onStep) }
    LaunchedEffect(viewModel) { viewModel.messages.collect { message = it } }

    val plan = state.plan
    val schema = state.schema
    if (plan == null || schema == null) return
    val confidence = plan.confidence
    val weak = buildSet {
        if (confidence.dateFormat.score < 0.6) add(MappingField.DateFormat)
        if (confidence.signConvention.score < 0.6) add(MappingField.Sign)
        if (confidence.columnRoles.score < 0.6) addAll(listOf(MappingField.DateColumn, MappingField.DescriptionColumn, MappingField.AmountColumn))
    }
    val columnCount = plan.rows.firstOrNull()?.rawCells?.size ?: schema.roles.size
    fun sample(index: Int, limit: Int = 3) = plan.rows.take(limit).mapNotNull { it.rawCells.getOrNull(index) }.filter { it.isNotEmpty() }.joinToString(" · ")
    @Composable
    fun columnLabel(index: Int?): String = when {
        index == null -> stringResource(R.string.import_mapping_column_none)
        sample(index, 1).isEmpty() -> stringResource(R.string.import_mapping_column_number, index + 1)
        else -> "${index + 1}: ${sample(index, 1)}"
    }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.import_mapping_title), subtitle = state.file?.displayName, onBack = onBack)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S2),
            modifier = Modifier.weight(1f).padding(Spacing.S4),
        ) {
            Text(stringResource(R.string.import_mapping_header).uppercase(), style = FinovaType.TextXS, color = FinovaColors.Gray500, modifier = Modifier.padding(start = Spacing.S2))
            Column(Modifier.clip(CardShape).background(FinovaColors.Gray100)) {
                MappingField.entries.forEachIndexed { index, field ->
                    if (index > 0) HorizontalDivider(color = FinovaColors.Gray300, modifier = Modifier.padding(start = Spacing.S4))
                    val value = when (field) {
                        MappingField.DateFormat -> schema.dateFormat.pattern
                        MappingField.Sign -> stringResource(signLabel(schema.signConvention))
                        MappingField.DateColumn -> columnLabel(schema.column(ColumnRole.Date))
                        MappingField.DescriptionColumn -> columnLabel(schema.column(ColumnRole.Description))
                        MappingField.AmountColumn -> columnLabel(schema.column(ColumnRole.Amount) ?: schema.column(ColumnRole.Debit))
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { picking = field }.padding(horizontal = Spacing.S4, vertical = Spacing.S2),
                    ) {
                        Text(
                            stringResource(field.title), style = FinovaType.TextSM,
                            color = if (field in weak) FinovaColors.MainRed else FinovaColors.Gray700,
                        )
                        Spacer(Modifier.width(Spacing.S3))
                        Text(
                            value, style = FinovaType.TextSM, color = FinovaColors.Gray500, textAlign = TextAlign.End,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                        )
                        Spacer(Modifier.width(Spacing.S2))
                        Icon(painterResource(R.drawable.ic_chevron_right), null, tint = FinovaColors.Gray400, modifier = Modifier.size(12.dp))
                    }
                }
            }
            Text(stringResource(R.string.import_mapping_footer), style = FinovaType.TextXS, color = FinovaColors.Gray500, modifier = Modifier.padding(horizontal = Spacing.S2))
        }
        FinovaButton(
            text = stringResource(R.string.import_mapping_confirm),
            onClick = viewModel::confirmMapping,
            loading = state.parsing,
            modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(Spacing.S4),
        )
    }

    picking?.let { field ->
        val options: List<Pair<String, () -> Unit>> = when (field) {
            MappingField.DateFormat -> DateFormatSpec.Candidates.map { spec -> spec.pattern to { viewModel.setDateFormat(spec) } }
            MappingField.Sign -> SignConvention.entries.map { convention -> stringResource(signLabel(convention)) to { viewModel.setSignConvention(convention) } }
            else -> {
                val role = when (field) {
                    MappingField.DateColumn -> ColumnRole.Date
                    MappingField.DescriptionColumn -> ColumnRole.Description
                    else -> ColumnRole.Amount
                }
                (0 until columnCount).map { index ->
                    val sample = sample(index)
                    (if (sample.isEmpty()) stringResource(R.string.import_mapping_column_number, index + 1) else "${index + 1}: $sample") to { viewModel.setColumn(index, role) }
                }
            }
        }
        val title = if (field == MappingField.DateFormat || field == MappingField.Sign) stringResource(field.title) else stringResource(R.string.import_mapping_column_pick)
        OptionSheet(title, options) { picking = null }
    }
    message?.let { MessageDialog(it) { message = null } }
}

private fun signLabel(convention: SignConvention) = when (convention) {
    SignConvention.NegativeIsExpense -> R.string.import_mapping_sign_negative_is_expense
    SignConvention.PositiveIsExpense -> R.string.import_mapping_sign_positive_is_expense
    SignConvention.SeparateDebitCredit -> R.string.import_mapping_sign_separate_columns
    SignConvention.IndicatorColumn -> R.string.import_mapping_sign_indicator_column
}

/** iOS picks from an action sheet; Android from a bottom sheet list. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OptionSheet(title: String, options: List<Pair<String, () -> Unit>>, selected: String? = null, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = FinovaColors.Gray100) {
        Text(title, style = FinovaType.TitleMD, color = FinovaColors.Gray700, modifier = Modifier.padding(start = Spacing.S5, end = Spacing.S5, bottom = Spacing.S2))
        LazyColumn(Modifier.heightIn(max = 520.dp).navigationBarsPadding()) {
            items(options) { (label, action) ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { action(); onDismiss() }.padding(horizontal = Spacing.S5, vertical = Spacing.S4),
                ) {
                    Text(label, style = FinovaType.TextSM, color = FinovaColors.Gray700, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    if (label == selected) Icon(Icons.Filled.CheckCircle, null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

// ---- Review ----------------------------------------------------------------------------------------

/**
 * The diff the user signs off on, then the apply. Port of ImportReviewViewController: every row in
 * file order by section, failures included, and nothing written until Add.
 */
@Composable
fun ImportReviewScreen(viewModel: ImportViewModel, onDiscard: () -> Unit, onFinished: () -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var confirmApply by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<ImportRow?>(null) }
    var signFor by remember { mutableStateOf<ImportRow?>(null) }
    var categoryFor by remember { mutableStateOf<ImportRow?>(null) }

    // Nothing is written yet, but laying out the diff is work: leaving asks first.
    BackHandler(enabled = state.applying == null) { confirmDiscard = true }
    val plan = state.plan ?: return
    val resolved = state.resolved
    val code = state.currencyCode

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.import_review_title), subtitle = state.file?.displayName, onBack = { confirmDiscard = true })
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(Spacing.S4),
            verticalArrangement = Arrangement.spacedBy(Spacing.S2),
        ) {
            for ((section, rows) in state.sections) {
                item(key = "header-$section") {
                    Text(
                        "${stringResource(section.title)} (${rows.size})".uppercase(),
                        style = FinovaType.TextXS, color = FinovaColors.Gray500,
                        modifier = Modifier.padding(start = Spacing.S2, top = Spacing.S2),
                    )
                }
                item(key = "rows-$section") {
                    Column(Modifier.clip(CardShape).background(FinovaColors.Gray100)) {
                        rows.forEachIndexed { index, row ->
                            if (index > 0) HorizontalDivider(color = FinovaColors.Gray300, modifier = Modifier.padding(start = 52.dp))
                            ReviewRow(
                                row = row,
                                title = state.title(row),
                                category = state.category(row),
                                included = state.isIncluded(row),
                                currencyCode = code,
                                onToggle = { viewModel.toggle(row) },
                                onCategory = { categoryFor = row },
                                onTap = {
                                    when {
                                        row.disposition.isFailure -> Unit
                                        row.disposition == Disposition.NeedsDecision(RowDecision.AmbiguousSign) -> signFor = row
                                        else -> editing = row
                                    }
                                },
                            )
                        }
                    }
                }
                section.footer?.let { footer ->
                    item(key = "footer-$section") {
                        Text(stringResource(footer), style = FinovaType.TextXS, color = FinovaColors.Gray500, modifier = Modifier.padding(horizontal = Spacing.S2))
                    }
                }
            }
        }
        HorizontalDivider(color = FinovaColors.Gray300)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S2),
            modifier = Modifier.background(FinovaColors.Gray200).navigationBarsPadding().padding(Spacing.S4),
        ) {
            val warning = state.applyError?.let { messageText(it) } ?: when {
                plan.source.wasLossy -> stringResource(R.string.import_review_warning_damaged_file)
                state.priorImport != null -> stringResource(
                    R.string.import_review_warning_already_imported,
                    DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(state.priorImport!!.createdAt)),
                    state.priorImport!!.rowsInserted,
                )
                else -> null
            }
            warning?.let { Text(it, style = FinovaType.TextXS, color = FinovaColors.MainRed) }
            if (state.needsSignDecision && state.applying == null) SignPrompt(viewModel::resolveAllSigns)
            Row(verticalAlignment = Alignment.CenterVertically) {
                val applying = state.applying
                Text(
                    if (applying != null) stringResource(R.string.import_review_applying, applying.first, applying.second)
                    else stringResource(R.string.import_review_summary, resolved?.rows?.size ?: 0, resolved?.skippedCount ?: 0, resolved?.failedCount ?: 0),
                    style = FinovaType.TextSM, color = FinovaColors.Gray600, modifier = Modifier.weight(1f),
                )
                if (applying == null) {
                    val net = state.netTotal
                    Text(
                        (if (net >= 0) "+" else "-") + Money.format(kotlin.math.abs(net), code),
                        style = FinovaType.TextSMBold, color = if (net >= 0) FinovaColors.MainGreen else FinovaColors.Gray700,
                    )
                }
            }
            state.applying?.let { (done, total) ->
                LinearProgressIndicator(
                    progress = { if (total == 0) 0f else done.toFloat() / total },
                    color = FinovaColors.MainMagenta, trackColor = FinovaColors.Gray300,
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                )
            }
            FinovaButton(
                text = stringResource(R.string.import_review_apply),
                onClick = { confirmApply = true },
                enabled = state.canApply,
                loading = state.applying != null,
                modifier = Modifier.fillMaxWidth(),
            )
            FinovaAccentOutlinedButton(
                text = stringResource(R.string.import_review_cancel),
                onClick = { confirmDiscard = true },
                enabled = state.applying == null,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    if (confirmApply) {
        AlertDialog(
            onDismissRequest = { confirmApply = false },
            title = { Text(stringResource(R.string.import_confirm_title)) },
            text = { Text(stringResource(R.string.import_confirm_message, resolved?.rows?.size ?: 0)) },
            confirmButton = { TextButton(onClick = { confirmApply = false; viewModel.apply() }) { Text(stringResource(R.string.import_confirm_ok)) } },
            dismissButton = { TextButton(onClick = { confirmApply = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(R.string.import_discard_title)) },
            text = { Text(stringResource(R.string.import_discard_message)) },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onDiscard() }) { Text(stringResource(R.string.import_discard_ok), color = FinovaColors.MainRed) }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    // Once rows are written there is nothing to cancel, so a single OK.
    state.finished?.let { batch ->
        AlertDialog(
            onDismissRequest = onFinished,
            title = { Text(stringResource(R.string.import_done_title)) },
            text = { Text(stringResource(R.string.import_done_message, batch.rowsInserted)) },
            confirmButton = { TextButton(onClick = onFinished) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
    signFor?.let { row ->
        AlertDialog(
            onDismissRequest = { signFor = null },
            title = { Text(state.title(row)) },
            text = { Text(stringResource(R.string.import_review_sign_prompt)) },
            confirmButton = { TextButton(onClick = { signFor = null; viewModel.setType(row, TransactionType.Income) }) { Text(stringResource(R.string.add_transaction_income)) } },
            dismissButton = { TextButton(onClick = { signFor = null; viewModel.setType(row, TransactionType.Expense) }) { Text(stringResource(R.string.add_transaction_expense)) } },
        )
    }
    editing?.let { row ->
        var text by remember(row.fingerprint) { mutableStateOf(state.title(row)) }
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(stringResource(R.string.import_review_edit_title)) },
            text = { OutlinedTextField(value = text, onValueChange = { text = it }, singleLine = true) },
            confirmButton = { TextButton(onClick = { editing = null; viewModel.setTitle(row, text) }) { Text(stringResource(R.string.alert_ok)) } },
            dismissButton = { TextButton(onClick = { editing = null }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    categoryFor?.let { row ->
        val current = state.category(row)
        val names = TransactionCategory.entries.map { it to stringResource(it.label) }.sortedBy { it.second }
        OptionSheet(
            title = stringResource(R.string.import_review_category_title),
            options = names.map { (category, name) -> name to { viewModel.setCategory(row, category) } },
            selected = names.first { it.first == current }.second,
        ) { categoryFor = null }
    }
}

private val ReviewSection.title
    get() = when (this) {
        ReviewSection.WillBeAdded -> R.string.import_review_section_will_add
        ReviewSection.NeedsDecision -> R.string.import_review_section_needs_decision
        ReviewSection.Duplicates -> R.string.import_review_section_duplicates
        ReviewSection.CouldNotBeRead -> R.string.import_review_section_failed
    }

private val ReviewSection.footer
    get() = when (this) {
        ReviewSection.WillBeAdded -> null
        ReviewSection.NeedsDecision -> R.string.import_review_section_needs_decision_footer
        ReviewSection.Duplicates -> R.string.import_review_section_duplicates_footer
        ReviewSection.CouldNotBeRead -> R.string.import_review_section_failed_footer
    }

@Composable
private fun SignPrompt(onResolve: (asWritten: Boolean) -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(Spacing.S1),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(CornerRadius.Large)).background(FinovaColors.Gray100).padding(Spacing.S3),
    ) {
        Text(stringResource(R.string.import_review_sign_prompt), style = FinovaType.TextXS, color = FinovaColors.Gray700)
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S5)) {
            Text(stringResource(R.string.import_review_sign_prompt_as_written), style = FinovaType.TextSMBold, color = FinovaColors.MainMagenta,
                modifier = Modifier.clickable { onResolve(true) }.padding(vertical = Spacing.S1))
            Text(stringResource(R.string.import_review_sign_prompt_inverted), style = FinovaType.TextSMBold, color = FinovaColors.MainMagenta,
                modifier = Modifier.clickable { onResolve(false) }.padding(vertical = Spacing.S1))
        }
    }
}

/** One proposed transaction. A skipped row is dimmed, never hidden: it must stay visible and reversible. */
@Composable
private fun ReviewRow(
    row: ImportRow,
    title: String,
    category: TransactionCategory,
    included: Boolean,
    currencyCode: String,
    onToggle: () -> Unit,
    onCategory: () -> Unit,
    onTap: () -> Unit,
) {
    val failed = row.disposition.isFailure
    val parsed = row.parsed
    val isIncome = (parsed?.signedCents ?: 0) > 0
    val type = if (isIncome) TransactionType.Income else TransactionType.Expense
    Row(
        verticalAlignment = Alignment.Top,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onTap).padding(horizontal = Spacing.S4, vertical = Spacing.S3)
            .alpha(if (included || failed) 1f else 0.55f),
    ) {
        if (!failed) {
            Icon(
                if (included) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                contentDescription = stringResource(if (included) R.string.import_review_a11y_included else R.string.import_review_a11y_excluded),
                tint = if (included) FinovaColors.MainMagenta else FinovaColors.Gray400,
                modifier = Modifier.size(24.dp).clip(RoundedCornerShape(12.dp)).clickable(onClick = onToggle),
            )
        } else {
            Icon(Icons.Outlined.ErrorOutline, null, tint = FinovaColors.MainRed, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.width(Spacing.S3))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    painterResource(category.icon(type)), contentDescription = stringResource(category.label),
                    tint = if (included) FinovaColors.MainMagenta else FinovaColors.Gray400,
                    modifier = Modifier.size(20.dp).clickable(enabled = !failed, onClick = onCategory),
                )
                Spacer(Modifier.width(Spacing.S2))
                Text(title.uppercase(), style = FinovaType.TitleSM, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (parsed != null) {
                    Spacer(Modifier.width(Spacing.S2))
                    Text(
                        (if (isIncome) "+" else "-") + Money.format(kotlin.math.abs(parsed.signedCents), currencyCode),
                        style = FinovaType.TextSMBold,
                        color = when {
                            !included -> FinovaColors.Gray400
                            isIncome -> FinovaColors.MainGreen
                            else -> FinovaColors.Gray700
                        },
                    )
                }
            }
            Text(
                if (parsed != null) "${parsed.date.format(DayMonthYear)} · ${stringResource(category.label)}" else row.rawCells.joinToString(" · "),
                style = FinovaType.TextXS, color = FinovaColors.Gray500, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            badge(row)?.let { Text(it, style = FinovaType.TextXS, color = if (failed) FinovaColors.MainRed else FinovaColors.Gray500, maxLines = 2) }
        }
    }
}

@Composable
private fun badge(row: ImportRow): String? {
    val parts = mutableListOf<String>()
    when (val disposition = row.disposition) {
        is Disposition.DuplicateExact -> parts += stringResource(R.string.import_review_badge_duplicate_exact)
        is Disposition.DuplicateLikely -> parts += stringResource(R.string.import_review_badge_duplicate_likely, (disposition.similarity * 100).toInt())
        is Disposition.DuplicateInFile -> parts += stringResource(R.string.import_review_badge_duplicate_in_file)
        Disposition.AlreadyImported -> parts += stringResource(R.string.import_review_badge_already_imported)
        is Disposition.NeedsDecision -> parts += stringResource(
            when (disposition.decision) {
                RowDecision.AmbiguousSign -> R.string.import_review_badge_ambiguous_sign
                RowDecision.AmbiguousDate -> R.string.import_review_badge_ambiguous_date
                RowDecision.DebitAndCreditBothSet -> R.string.import_review_badge_both_columns
            },
        )
        is Disposition.Failed -> parts += when (val error = disposition.error) {
            is RowError.UnparseableDate -> stringResource(R.string.import_review_error_bad_date, error.value)
            is RowError.UnparseableAmount -> stringResource(R.string.import_review_error_bad_amount, error.value)
            RowError.ZeroAmount -> stringResource(R.string.import_review_error_zero_amount)
            is RowError.MissingField -> stringResource(R.string.import_review_error_missing_field)
            RowError.AmountOutOfRange -> stringResource(R.string.import_review_error_amount_out_of_range)
        }
        Disposition.Insert -> Unit
    }
    for (warning in row.warnings) parts += stringResource(
        when (warning) {
            RowWarning.AmountRounded -> R.string.import_review_badge_rounded
            RowWarning.AmbiguousNumberFormat -> R.string.import_review_badge_ambiguous_number
            RowWarning.InstallmentHintIgnored -> R.string.import_review_badge_installment_ignored
            RowWarning.TitleWasEmpty -> R.string.import_review_badge_no_description
            RowWarning.DateFarFromOthers -> R.string.import_review_badge_odd_date
        },
    )
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}
