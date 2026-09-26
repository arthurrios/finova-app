package com.arthurrios.finova.ui.details

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
fun TransactionDetailsScreen(viewModel: TransactionDetailsViewModel, onBack: () -> Unit, onCreateCard: () -> Unit = {}) {
    val state by viewModel.state.collectAsStateWithLifecycle()
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
