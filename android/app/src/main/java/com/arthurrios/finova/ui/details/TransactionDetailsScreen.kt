package com.arthurrios.finova.ui.details

import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.EventAvailable
import androidx.compose.ui.graphics.vector.ImageVector
import com.arthurrios.finova.ui.dashboard.CardBody
import com.arthurrios.finova.ui.dashboard.CardHeader
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.SeriesEditOption
import com.arthurrios.finova.domain.series.SeriesKind
import com.arthurrios.finova.ui.addtransaction.AddTransactionRequest
import com.arthurrios.finova.ui.addtransaction.AddTransactionSheet
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.DeleteTransactionDialog
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.format.DateTimeFormatter

private val CardShape = RoundedCornerShape(CornerRadius.ExtraLarge)
private val DateFormat = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/** Port of TransactionDetailsView / ViewController on iOS 1.5.2 (cards and payments come later). */
@Composable
fun TransactionDetailsScreen(
    viewModel: TransactionDetailsViewModel,
    onBack: () -> Unit,
    onCreateCard: () -> Unit = {},
    onPayEarly: () -> Unit = {},
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()
    var confirmCancel by rememberSaveable { mutableStateOf(false) }
    var confirmUndo by rememberSaveable { mutableStateOf(false) }
    var movingStatement by rememberSaveable { mutableStateOf(false) }
    val cards by viewModel.cards.collectAsStateWithLifecycle()
    var showEdit by rememberSaveable { mutableStateOf(false) }
    var showDelete by rememberSaveable { mutableStateOf(false) }
    var pendingEdit by remember { mutableStateOf<AddTransactionRequest?>(null) }

    LaunchedEffect(state.gone) { if (state.gone) onBack() }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.details_header_title),
            subtitle = stringResource(R.string.details_header_subtitle),
            onBack = onBack,
            trailing = {
                RoundIconButton(onClick = viewModel::toggleValues) {
                    Icon(
                        painterResource(if (state.valuesHidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
                        contentDescription = stringResource(if (state.valuesHidden) R.string.month_card_show_values else R.string.month_card_hide_values),
                        modifier = Modifier.size(24.dp),
                    )
                }
            },
        )
        val row = state.row ?: return@Column
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(Spacing.S4),
            verticalArrangement = Arrangement.spacedBy(Spacing.S4),
        ) {
            InfoCard(row, state)
            DetailsCard(row, state)
            if (state.installments.isNotEmpty()) InstallmentsCard(row, state)
            state.statementDue?.let { due ->
                ActionRow(
                    icon = Icons.Outlined.Description,
                    label = stringResource(R.string.move_statement_row),
                    value = due.format(DateTimeFormatter.ofPattern("MMMM yyyy", java.util.Locale.getDefault()))
                        .replaceFirstChar { it.titlecase() },
                    onClick = { movingStatement = true },
                )
            }
            EarlyPaymentAndCancellation(
                state = state,
                onPayEarly = onPayEarly,
                onCancel = { confirmCancel = true },
                onUndo = { confirmUndo = true },
            )
        }
        // Edit and Delete stay at the bottom, like the iOS footer.
        Column(
            Modifier
                .fillMaxWidth()
                .background(FinovaColors.Gray100)
                .navigationBarsPadding()
                .padding(Spacing.S4),
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
        ) {
            FinovaButton(text = stringResource(R.string.details_edit), onClick = { showEdit = true })
            FinovaAccentOutlinedButton(text = stringResource(R.string.details_delete), onClick = { showDelete = true })
        }
    }

    if (showEdit && state.editRequest != null) {
        AddTransactionSheet(
            currencyCode = state.currencyCode,
            defaultRule = viewModel.defaultRule,
            editing = state.editRequest,
            cards = cards,
            onCreateCard = {
                showEdit = false
                onCreateCard()
            },
            onSave = { request ->
                showEdit = false
                when (state.kind) {
                    SeriesKind.Simple -> viewModel.saveOneOff(request)
                    // Series edits ask how far to go first, like the iOS scope alert.
                    else -> pendingEdit = request
                }
            },
            onDismiss = { showEdit = false },
        )
    }
    pendingEdit?.let { request -> EditScopeDialog(state.kind, onPick = { option ->
        pendingEdit = null
        if (state.kind == SeriesKind.Installments) viewModel.saveInstallments(request) else viewModel.saveRecurring(request, option)
    }, onDismiss = { pendingEdit = null }) }
    if (movingStatement) {
        MoveToStatementSheet(
            options = state.moveOptions,
            onPick = { month ->
                movingStatement = false
                viewModel.moveToStatement(month)
            },
            onDismiss = { movingStatement = false },
        )
    }
    if (confirmCancel) {
        val title = stringResource(R.string.cancel_transaction_title, state.row?.title.orEmpty())
        AlertDialog(
            onDismissRequest = { confirmCancel = false },
            title = { Text(stringResource(R.string.cancel_confirm_title)) },
            text = {
                Text(
                    stringResource(
                        if (state.cancelCount == 1) R.string.cancel_confirm_one else R.string.cancel_confirm_other,
                        state.cancelCount,
                        Money.format(state.cancelAmount, state.currencyCode),
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmCancel = false
                    viewModel.cancelPurchase(title, R.string.cancel_error)
                }) { Text(stringResource(R.string.cancel_confirm_action), color = FinovaColors.MainRed) }
            },
            dismissButton = { TextButton(onClick = { confirmCancel = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    if (confirmUndo) {
        val early = state.earlyPaidInstallments != null
        AlertDialog(
            onDismissRequest = { confirmUndo = false },
            title = { Text(stringResource(if (early) R.string.early_undo_title else R.string.cancel_undo_title)) },
            text = { Text(stringResource(if (early) R.string.early_undo_message else R.string.cancel_undo_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmUndo = false
                    viewModel.undo()
                }) { Text(stringResource(if (early) R.string.early_undo_action else R.string.cancel_undo_action), color = FinovaColors.MainRed) }
            },
            dismissButton = { TextButton(onClick = { confirmUndo = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    failure?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::clearFailure,
            title = { Text(stringResource(R.string.alert_error)) },
            text = { Text(stringResource(message)) },
            confirmButton = { TextButton(onClick = viewModel::clearFailure) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
    if (showDelete) {
        DeleteTransactionDialog(
            kind = state.kind,
            onDelete = { option ->
                showDelete = false
                viewModel.delete(option)
            },
            onDismiss = { showDelete = false },
        )
    }
}

/** Port of `showEditScopeAlert`: three choices for recurring, "Edit All" only for installments. */
@Composable
private fun EditScopeDialog(kind: SeriesKind, onPick: (SeriesEditOption) -> Unit, onDismiss: () -> Unit) {
    val recurring = kind == SeriesKind.Recurring
    val choices = if (recurring) listOf(
        SeriesEditOption.ThisOnly to R.string.edit_alert_edit_single,
        SeriesEditOption.ThisAndLater to R.string.edit_alert_edit_future,
        SeriesEditOption.All to R.string.edit_alert_edit_all,
    ) else listOf(SeriesEditOption.All to R.string.edit_alert_edit_all)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(if (recurring) R.string.edit_alert_recurring_title else R.string.edit_alert_installments_title)) },
        text = {
            Column {
                Text(stringResource(if (recurring) R.string.edit_alert_recurring_message else R.string.edit_alert_installments_message))
                choices.forEach { (option, label) ->
                    TextButton(onClick = { onPick(option) }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(label), color = FinovaColors.MainMagenta, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.End)
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}

@Composable
private fun Card(title: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(CardShape).background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, CardShape)) {
        Box(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = Spacing.S5), contentAlignment = Alignment.CenterStart) {
            Text(title.uppercase(), style = FinovaType.Title2XS, color = FinovaColors.Gray500)
        }
        HorizontalDivider(color = FinovaColors.Gray300)
        Column(Modifier.padding(Spacing.S5), verticalArrangement = Arrangement.spacedBy(Spacing.S4)) { content() }
    }
}

@Composable
private fun InfoCard(row: Transaction, state: TransactionDetailsUiState) {
    Card(stringResource(R.string.details_info_header)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(Spacing.S8).clip(RoundedCornerShape(CornerRadius.Medium)).background(FinovaColors.Gray200)
                    .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(CornerRadius.Medium)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(painterResource(row.category.icon(row.type)), null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(Spacing.S5))
            }
            Spacer(Modifier.width(Spacing.S4))
            Text(stringResource(row.category.label), style = FinovaType.TextSMBold, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(Money.annotated(row.amount, state.currencyCode, FinovaType.TextXS, state.valuesHidden), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
                    Spacer(Modifier.width(Spacing.S1))
                    Icon(
                        painterResource(if (row.type == TransactionType.Income) R.drawable.ic_arrow_up else R.drawable.ic_arrow_down),
                        null,
                        tint = if (row.type == TransactionType.Income) FinovaColors.MainGreen else FinovaColors.MainRed,
                        modifier = Modifier.size(14.dp),
                    )
                }
                if (row.installmentNumber != null) {
                    Text("(${row.installmentNumber}/${row.totalInstallments})", style = FinovaType.TextXS, color = FinovaColors.Gray500)
                }
            }
        }
        Text(row.title, style = FinovaType.Input, color = FinovaColors.Gray700)
        Text(
            stringResource(
                when (state.kind) {
                    SeriesKind.Simple -> R.string.transaction_mode_desc_normal
                    SeriesKind.Recurring -> R.string.transaction_mode_desc_recurring
                    SeriesKind.Installments -> R.string.transaction_mode_desc_installments
                }
            ),
            style = FinovaType.TextSM,
            color = FinovaColors.Gray500,
        )
    }
}

@Composable
private fun DetailsCard(row: Transaction, state: TransactionDetailsUiState) {
    Card(stringResource(R.string.details_details_header)) {
        DetailRow(stringResource(R.string.details_label_date), row.date.format(DateFormat))
        DetailRow(
            stringResource(R.string.details_label_type),
            stringResource(if (row.type == TransactionType.Income) R.string.details_type_income else R.string.details_type_expense),
        )
        state.totalValue?.let { DetailRow(stringResource(R.string.details_label_total_value), Money.formatMasked(it, state.currencyCode, state.valuesHidden)) }
        state.lastInstallment?.let { DetailRow(stringResource(R.string.details_label_last_installment), it.format(DateFormat)) }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row {
        Text(label, style = FinovaType.Input, color = FinovaColors.Gray500, modifier = Modifier.weight(1f))
        Text(value, style = FinovaType.Input, color = FinovaColors.Gray700)
    }
}

@Composable
private fun InstallmentsCard(row: Transaction, state: TransactionDetailsUiState) {
    Card(stringResource(R.string.details_installments_header)) {
        state.installments.forEach { item ->
            val current = item.id == row.id
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.details_installment_row, item.installmentNumber ?: 0, item.totalInstallments ?: 0),
                        style = if (current) FinovaType.TextSMBold else FinovaType.TextSM,
                        color = FinovaColors.Gray700,
                    )
                    Text(item.date.format(DateFormat), style = FinovaType.TextXS, color = FinovaColors.Gray500)
                }
                Text(Money.formatMasked(item.amount, state.currencyCode, state.valuesHidden), style = FinovaType.TextSM, color = FinovaColors.Gray700)
            }
        }
    }
}

/**
 * The early-payment and cancellation parts of iOS TransactionDetailsView: the entry rows on an
 * installment with installments still to bill, and on a debit or credit the installments it
 * covers plus the undo row.
 */
@Composable
private fun EarlyPaymentAndCancellation(
    state: TransactionDetailsUiState,
    onPayEarly: () -> Unit,
    onCancel: () -> Unit,
    onUndo: () -> Unit,
) {
    if (state.payableCount > 0) {
        ActionRow(
            icon = Icons.Outlined.EventAvailable,
            label = stringResource(R.string.early_entry),
            value = stringResource(
                if (state.payableCount == 1) R.string.early_entry_count_one else R.string.early_entry_count_other,
                state.payableCount,
            ),
            onClick = onPayEarly,
        )
    }
    state.earlyPaidInstallments?.let { covered ->
        CoveredInstallments(stringResource(R.string.early_included_header), covered, state)
        ActionRow(Icons.AutoMirrored.Outlined.Undo, stringResource(R.string.early_undo_title), null, onUndo, danger = true)
    }
    if (state.cancelCount > 0) {
        ActionRow(
            icon = Icons.Outlined.Cancel,
            label = stringResource(R.string.cancel_entry),
            value = Money.formatMasked(state.cancelAmount, state.currencyCode, state.valuesHidden),
            onClick = onCancel,
        )
    }
    state.refundedInstallments?.let { covered ->
        CoveredInstallments(stringResource(R.string.cancel_refunded_header), covered, state)
        Text(stringResource(R.string.cancel_note), style = FinovaType.TextXS, color = FinovaColors.Gray500)
        ActionRow(Icons.AutoMirrored.Outlined.Undo, stringResource(R.string.cancel_undo_title), null, onUndo, danger = true)
    }
}

/** A settings-style row: icon, label, optional value, chevron (makeActionRow on iOS). */
@Composable
private fun ActionRow(icon: ImageVector, label: String, value: String?, onClick: () -> Unit, danger: Boolean = false) {
    val shape = RoundedCornerShape(CornerRadius.Large)
    val tint = if (danger) FinovaColors.MainRed else FinovaColors.Gray600
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(FinovaColors.Gray100)
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.S4, vertical = Spacing.S4),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.S3))
        Text(label, style = FinovaType.TitleSM, color = if (danger) FinovaColors.MainRed else FinovaColors.Gray700, modifier = Modifier.weight(1f))
        if (value != null) {
            Spacer(Modifier.width(Spacing.S3))
            Text(value, style = FinovaType.TextSM, color = FinovaColors.Gray500)
        }
        Spacer(Modifier.width(Spacing.S2))
        Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = FinovaColors.Gray500, modifier = Modifier.size(14.dp))
    }
}

/** The read-only list of installments an early payment paid or a cancellation refunds. */
@Composable
private fun CoveredInstallments(title: String, installments: List<Transaction>, state: TransactionDetailsUiState) {
    val monthYear = DateTimeFormatter.ofPattern("MMM/yy", java.util.Locale.getDefault())
    Column {
        CardHeader(title, installments.size)
        if (installments.isNotEmpty()) {
            CardBody {
                installments.forEachIndexed { index, item ->
                    if (index > 0) HorizontalDivider(color = FinovaColors.Gray300)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (item.installmentNumber != null && item.totalInstallments != null)
                                stringResource(R.string.early_row, item.installmentNumber, item.totalInstallments, item.date.format(monthYear))
                            else item.title,
                            style = FinovaType.TextSMBold,
                            color = FinovaColors.Gray700,
                            modifier = Modifier.weight(1f),
                        )
                        Text(Money.formatMasked(item.amount, state.currencyCode, state.valuesHidden), style = FinovaType.TextSM, color = FinovaColors.Gray500)
                    }
                }
            }
        }
    }
}

/**
 * "Move to Statement": iOS asks with an action sheet of months; this is the Android sheet. Each
 * month is named by the due date of the statement it means.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun MoveToStatementSheet(
    options: List<Pair<java.time.YearMonth, java.time.LocalDate>>,
    onPick: (java.time.YearMonth) -> Unit,
    onDismiss: () -> Unit,
) {
    val format = DateTimeFormatter.ofPattern("MMMM yyyy", java.util.Locale.getDefault())
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = FinovaColors.Gray100) {
        Column(Modifier.navigationBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = Spacing.S4)) {
            Text(stringResource(R.string.move_statement_title), style = FinovaType.TitleSM, color = FinovaColors.Gray700,
                modifier = Modifier.padding(horizontal = Spacing.S6))
            Text(stringResource(R.string.move_statement_message), style = FinovaType.TextSM, color = FinovaColors.Gray500,
                modifier = Modifier.padding(start = Spacing.S6, end = Spacing.S6, top = Spacing.S1, bottom = Spacing.S3))
            options.forEach { (month, due) ->
                Text(
                    due.format(format).replaceFirstChar { it.titlecase() },
                    style = FinovaType.TextSM,
                    color = FinovaColors.Gray700,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onPick(month) }
                        .padding(horizontal = Spacing.S6, vertical = Spacing.S4),
                )
            }
        }
    }
}
