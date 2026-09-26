package com.arthurrios.finova.ui.statement

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.StatementStatus
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.DeleteTransactionDialog
import com.arthurrios.finova.ui.dashboard.TransactionListBox
import com.arthurrios.finova.ui.dashboard.TransactionListHeader
import com.arthurrios.finova.ui.dashboard.TransactionRow
import com.arthurrios.finova.ui.dashboard.TransactionRowUi
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.format.DateTimeFormatter

private val DateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/**
 * Port of StatementDetailsView: the statement's summary card, its transactions (tap opens one,
 * swipe or trash deletes), and the footer actions until it is paid.
 */
@Composable
fun StatementDetailsScreen(
    viewModel: StatementDetailsViewModel,
    onBack: () -> Unit,
    onOpenTransaction: (Long) -> Unit,
    onPay: () -> Unit = {},
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var pendingDelete by remember { mutableStateOf<TransactionRowUi?>(null) }
    var confirmPaid by rememberSaveable { mutableStateOf(false) }

    // iOS closes the screen once its last transaction is deleted (the statement goes with it).
    LaunchedEffect(state.gone) { if (state.gone) onBack() }

    val card = state.card
    val statement = state.statement
    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = card?.let { stringResource(R.string.statement_details_title, it.name) }.orEmpty(),
            subtitle = null,
            onBack = onBack,
            trailing = {
                RoundIconButton(onClick = viewModel::toggleValues) {
                    Icon(
                        painterResource(if (state.valuesHidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
                        contentDescription = stringResource(
                            if (state.valuesHidden) R.string.month_card_show_values else R.string.month_card_hide_values
                        ),
                        modifier = Modifier.size(24.dp),
                    )
                }
            },
        )
        if (statement == null) return@Column
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S4),
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(Spacing.S4),
        ) {
            val status = statement.status(viewModel.statusToday)
            Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.S4),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(CornerRadius.ExtraLarge))
                    .background(FinovaColors.Gray100)
                    .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(CornerRadius.ExtraLarge))
                    .padding(Spacing.S5),
            ) {
                InfoRow(R.string.statement_details_card, card?.let { "${it.name} ****${it.lastFourDigits}" }.orEmpty())
                InfoRow(
                    R.string.statement_details_period,
                    "${state.periodStart?.format(DateFormat)} — ${statement.closingDate.format(DateFormat)}",
                )
                InfoRow(R.string.statement_details_closing, statement.closingDate.format(DateFormat))
                InfoRow(R.string.statement_details_due, statement.dueDate.format(DateFormat))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.statement_details_total), style = FinovaType.TextSM, color = FinovaColors.Gray500,
                        modifier = Modifier.weight(1f))
                    Text(
                        Money.annotated(state.total, state.currencyCode, FinovaType.TextXS, state.valuesHidden),
                        style = FinovaType.TitleMD,
                        color = FinovaColors.Gray700,
                    )
                }
                // A credit larger than a statement carries on to the next ones (see StatementBook.charges).
                if (state.carriedIn < 0) {
                    InfoRow(R.string.statement_details_carried_in, Money.formatMasked(state.carriedIn, state.currencyCode, state.valuesHidden),
                        valueColor = FinovaColors.MainGreen)
                }
                if (state.carriedOut < 0) {
                    InfoRow(R.string.statement_details_carried_out, Money.formatMasked(-state.carriedOut, state.currencyCode, state.valuesHidden),
                        valueColor = FinovaColors.MainGreen)
                }
                InfoRow(R.string.statement_details_status, stringResource(status.label), valueColor = status.color)
            }
            statement.paidDate?.takeIf { statement.isPaid }?.let { paid ->
                Text(
                    stringResource(R.string.statement_details_paid_on, paid.format(DateFormat)),
                    style = FinovaType.TextSM,
                    color = FinovaColors.Gray500,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Column {
                TransactionListHeader(count = state.rows.size)
                if (state.rows.isNotEmpty()) {
                    // As on iOS, the list is at most 300 tall and scrolls inside when longer.
                    TransactionListBox(Modifier.heightIn(max = 300.dp)) {
                        LazyColumn {
                            itemsIndexed(state.rows, key = { _, row -> row.id }) { index, row ->
                                if (index > 0) HorizontalDivider(color = FinovaColors.Gray300)
                                TransactionRow(
                                    row = row,
                                    currencyCode = state.currencyCode,
                                    valuesHidden = state.valuesHidden,
                                    onClick = { onOpenTransaction(row.id) },
                                    onDelete = { pendingDelete = row },
                                )
                            }
                        }
                    }
                }
            }
        }
        // Hidden once the statement is paid, like the iOS footer.
        if (!statement.isPaid) {
            HorizontalDivider(color = FinovaColors.Gray300)
            Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.S3),
                modifier = Modifier.background(FinovaColors.Gray100).navigationBarsPadding().padding(Spacing.S4),
            ) {
                // Nothing to pay on a statement that owes nothing (a credit balance).
                if (state.total > 0) {
                    FinovaButton(text = stringResource(R.string.statement_details_pay), onClick = onPay)
                }
                FinovaAccentOutlinedButton(
                    text = stringResource(R.string.statement_details_mark_paid),
                    onClick = { confirmPaid = true },
                )
            }
        }
    }

    if (confirmPaid) {
        AlertDialog(
            onDismissRequest = { confirmPaid = false },
            title = { Text(stringResource(R.string.statement_details_mark_paid)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmPaid = false
                    // iOS returns to the previous screen once the statement is marked paid.
                    viewModel.markAsPaid(onDone = onBack)
                }) { Text(stringResource(R.string.alert_ok)) }
            },
            dismissButton = { TextButton(onClick = { confirmPaid = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    pendingDelete?.let { row ->
        DeleteTransactionDialog(
            kind = row.seriesKind,
            onDelete = { option ->
                pendingDelete = null
                viewModel.delete(row, option)
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun InfoRow(@StringRes title: Int, value: String, valueColor: Color = FinovaColors.Gray700) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(title), style = FinovaType.TextSM, color = FinovaColors.Gray500)
        Spacer(Modifier.width(Spacing.S3))
        Text(
            value,
            style = FinovaType.TextSMBold,
            color = valueColor,
            textAlign = TextAlign.End,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

@get:StringRes
private val StatementStatus.label: Int
    get() = when (this) {
        StatementStatus.Open -> R.string.statement_status_open
        StatementStatus.Closed -> R.string.statement_status_closed
        StatementStatus.Paid -> R.string.statement_status_paid
        StatementStatus.Overdue -> R.string.statement_status_overdue
        StatementStatus.Scheduled -> R.string.statement_status_scheduled
    }

/** StatementStatus.color on iOS. */
private val StatementStatus.color: Color
    get() = when (this) {
        StatementStatus.Open, StatementStatus.Scheduled -> FinovaColors.MainGreen
        StatementStatus.Closed -> FinovaColors.WarningAmber
        StatementStatus.Paid -> FinovaColors.Gray500
        StatementStatus.Overdue -> FinovaColors.MainRed
    }
