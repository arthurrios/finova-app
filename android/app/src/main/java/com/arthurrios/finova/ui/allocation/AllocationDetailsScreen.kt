package com.arthurrios.finova.ui.allocation

import androidx.annotation.StringRes
import androidx.compose.foundation.Canvas
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.AllocationEditScope
import com.arthurrios.finova.domain.allocation.AllocationStatus
import com.arthurrios.finova.ui.budget.AllocationSheet
import com.arthurrios.finova.ui.budget.ChoiceDialog
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.CardHeader
import com.arthurrios.finova.ui.dashboard.DeleteTransactionDialog
import com.arthurrios.finova.ui.dashboard.TransactionEmptyState
import com.arthurrios.finova.ui.dashboard.TransactionListBox
import com.arthurrios.finova.ui.dashboard.TransactionRow
import com.arthurrios.finova.ui.dashboard.TransactionRowUi
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.format.DateTimeFormatter

private val MonthYear: DateTimeFormatter = DateTimeFormatter.ofPattern("MMMM yyyy")
private val TopCorners = RoundedCornerShape(bottomStart = CornerRadius.ExtraLarge, bottomEnd = CornerRadius.ExtraLarge)

/**
 * Port of BudgetAllocationDetailsView: a summary with a usage ring, the month's transactions in
 * the category, and edit/delete (or create, for spending no allocation covers).
 */
@Composable
fun AllocationDetailsScreen(
    viewModel: AllocationDetailsViewModel,
    onBack: () -> Unit,
    onOpenTransaction: (Long) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var pendingDelete by remember { mutableStateOf<TransactionRowUi?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var showSheet by remember { mutableStateOf(false) }

    // iOS returns to the dashboard once the allocation is deleted.
    LaunchedEffect(state.gone) { if (state.gone) onBack() }

    val categoryName = stringResource(state.category.label)
    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = if (state.isUnallocated) categoryName else stringResource(R.string.alloc_details_title, categoryName),
            subtitle = if (state.isUnallocated) stringResource(R.string.alloc_unallocated_subtitle)
            else state.month.format(MonthYear).replaceFirstChar { it.titlecase() },
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
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S4),
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(Spacing.S4),
        ) {
            Column {
                CardHeader(stringResource(R.string.alloc_summary_header))
                Summary(state)
            }
            Column {
                CardHeader(stringResource(R.string.alloc_details_transactions), state.rows.size)
                if (state.rows.isEmpty()) {
                    TransactionEmptyState(stringResource(R.string.alloc_details_empty))
                } else {
                    // As on iOS, at most 300 tall, scrolling inside when longer.
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
        HorizontalDivider(color = FinovaColors.Gray300)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
            modifier = Modifier.background(FinovaColors.Gray100).navigationBarsPadding().padding(Spacing.S4),
        ) {
            if (state.isUnallocated) {
                FinovaButton(text = stringResource(R.string.alloc_details_create), onClick = { showSheet = true })
            } else {
                FinovaButton(text = stringResource(R.string.alloc_details_edit), onClick = { showSheet = true })
                FinovaAccentOutlinedButton(text = stringResource(R.string.alloc_details_delete), onClick = { confirmDelete = true })
            }
        }
    }

    if (showSheet) {
        AllocationSheet(
            month = state.month,
            allocations = state.allocationRows,
            currencyCode = state.currencyCode,
            actions = viewModel,
            onDismiss = { showSheet = false },
            editing = state.allocation,
            preselected = state.category,
        )
    }
    if (confirmDelete) {
        if (state.isRecurring) {
            ChoiceDialog(
                title = stringResource(R.string.alloc_delete_recurring_title),
                message = stringResource(R.string.alloc_delete_recurring_message),
                choices = listOf(
                    stringResource(R.string.alloc_delete_this) to { viewModel.deleteAllocation(AllocationEditScope.ThisOnly) },
                    stringResource(R.string.alloc_delete_future) to { viewModel.deleteAllocation(AllocationEditScope.ThisAndLater) },
                    stringResource(R.string.alloc_delete_all) to { viewModel.deleteAllocation(AllocationEditScope.All) },
                ),
                onDismiss = { confirmDelete = false },
            )
        } else {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text(stringResource(R.string.alloc_delete_title)) },
                text = { Text(stringResource(R.string.alloc_delete_message, categoryName)) },
                confirmButton = {
                    TextButton(onClick = {
                        confirmDelete = false
                        viewModel.deleteAllocation(AllocationEditScope.ThisOnly)
                    }) { Text(stringResource(R.string.alloc_details_delete), color = FinovaColors.MainRed) }
                },
                dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.alert_cancel)) } },
            )
        }
    }
    pendingDelete?.let { row ->
        DeleteTransactionDialog(
            kind = row.seriesKind,
            onDelete = { option ->
                pendingDelete = null
                viewModel.deleteTransaction(row, option)
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun Summary(state: AllocationDetailsUiState) {
    val hidden = state.valuesHidden
    val code = state.currencyCode
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(TopCorners)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, TopCorners)
            .padding(Spacing.S5),
        verticalArrangement = Arrangement.spacedBy(Spacing.S4),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            UsageRing(state)
            Spacer(Modifier.width(Spacing.S6))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
                DetailRow(
                    R.string.alloc_summary_allocated,
                    if (state.isUnallocated) stringResource(R.string.alloc_unallocated_row)
                    else Money.formatMasked(state.allocation!!.allocated, code, hidden),
                )
                DetailRow(R.string.alloc_summary_used, Money.formatMasked(state.used, code, hidden))
                DetailRow(
                    R.string.alloc_summary_remaining,
                    // Money.format puts the sign before the symbol ("-R$ 10,00"), as iOS does.
                    Money.formatMasked(state.remaining, code, hidden),
                    color = if (!hidden && state.status == AllocationStatus.OverBudget) FinovaColors.MainRed else FinovaColors.Gray700,
                )
                if (state.isRecurring) RecurringBadge()
            }
        }
        val warning = when {
            state.isUnallocated -> stringResource(R.string.alloc_unallocated_warning)
            state.status != AllocationStatus.OverBudget -> null
            hidden -> stringResource(R.string.alloc_warning_hidden)
            else -> stringResource(R.string.alloc_summary_over, Money.format(-state.remaining, code))
        }
        warning?.let { WarningBanner(it) }
    }
}

/** Port of CircularProgressView: a 120pt ring with the usage percentage and status inside. */
@Composable
private fun UsageRing(state: AllocationDetailsUiState) {
    val color = if (state.isUnallocated) FinovaColors.Gray400 else state.status.color
    val progress = if (state.isUnallocated) 1f else (state.percentage / 100f).coerceIn(0f, 1f)
    Box(Modifier.size(120.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 12.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            drawArc(FinovaColors.Gray300, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
            drawArc(color, -90f, 360f * progress, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (state.isUnallocated) {
                Text(Money.compactMasked(state.used, state.currencyCode, state.valuesHidden), style = FinovaType.TitleSM, color = FinovaColors.Gray700)
                Text(stringResource(R.string.alloc_unallocated_spent), style = FinovaType.TextSM, color = FinovaColors.Gray500)
            } else {
                Text("${state.percentage}%", style = FinovaType.TitleLG, color = FinovaColors.Gray700)
                Text(stringResource(state.status.label), style = FinovaType.TextSM, color = state.status.color)
            }
        }
    }
}

@Composable
private fun DetailRow(@StringRes title: Int, value: String, color: Color = FinovaColors.Gray700) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(title), style = FinovaType.TextSM, color = FinovaColors.Gray500)
        Spacer(Modifier.width(Spacing.S2))
        Text(
            value, style = FinovaType.TextSMBold, color = color, textAlign = TextAlign.End,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun RecurringBadge() {
    val shape = RoundedCornerShape(CornerRadius.Small)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(shape)
            .background(FinovaColors.LowMagenta)
            .border(1.dp, FinovaColors.MainMagenta, shape)
            .padding(horizontal = Spacing.S2, vertical = Spacing.S1),
    ) {
        Icon(painterResource(R.drawable.ic_reload), contentDescription = null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(12.dp))
        Spacer(Modifier.width(Spacing.S1))
        Text(stringResource(R.string.alloc_summary_recurring), style = FinovaType.TextXS, color = FinovaColors.MainMagenta)
    }
}

@Composable
private fun WarningBanner(message: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(CornerRadius.Medium))
            .background(FinovaColors.LowAmber)
            .padding(horizontal = Spacing.S4, vertical = Spacing.S3),
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = FinovaColors.WarningAmber, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(Spacing.S2))
        Text(message, style = FinovaType.TextSM, color = FinovaColors.WarningAmber)
    }
}

/** AllocationStatus.color on iOS. */
val AllocationStatus.color: Color
    get() = when (this) {
        AllocationStatus.UnderBudget -> FinovaColors.MainMagenta
        AllocationStatus.NearLimit -> FinovaColors.WarningAmber
        AllocationStatus.OverBudget -> FinovaColors.MainRed
    }

@get:StringRes
val AllocationStatus.label: Int
    get() = when (this) {
        AllocationStatus.UnderBudget -> R.string.alloc_status_under
        AllocationStatus.NearLimit -> R.string.alloc_status_near
        AllocationStatus.OverBudget -> R.string.alloc_status_over
    }
