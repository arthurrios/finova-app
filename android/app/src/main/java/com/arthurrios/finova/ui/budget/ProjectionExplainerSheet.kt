package com.arthurrios.finova.ui.budget

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.AllocationBalanceProjection
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.CategorySpendHistory
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.format.localizedDayOfMonth
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import com.arthurrios.finova.domain.model.TransactionCategory

/**
 * Port of ProjectionExplainerView/ViewModel: the "if fully used" figure, itemised, and what the
 * user's closed months say about the assumption behind it. It reads the card's own projection, so
 * the two can never disagree.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectionExplainerSheet(
    projection: AllocationBalanceProjection,
    balanceDay: Int,
    allocations: List<BudgetAllocation>,
    histories: Map<TransactionCategory, CategorySpendHistory>,
    currencyCode: String,
    valuesHidden: Boolean,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(),
        containerColor = FinovaColors.Gray100,
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(start = Spacing.S5, end = Spacing.S5, bottom = Spacing.S8),
        ) {
            Text(stringResource(R.string.projection_title), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            Spacer(Modifier.height(Spacing.S5))
            SectionHeader(stringResource(R.string.projection_formula_header))
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
                FormulaRow(
                    stringResource(R.string.projection_formula_balance, localizedDayOfMonth(balanceDay)),
                    Money.formatMasked(projection.base, currencyCode, valuesHidden),
                )
                // A term worth zero is noise in an explanation, so it is left out.
                if (projection.deferredCardSpending > 0) {
                    FormulaRow(stringResource(R.string.projection_formula_card),
                        "-" + Money.formatMasked(projection.deferredCardSpending, currencyCode, valuesHidden), subtraction = true)
                }
                if (projection.unspentAllocations > 0) {
                    FormulaRow(stringResource(R.string.projection_formula_unspent),
                        "-" + Money.formatMasked(projection.unspentAllocations, currencyCode, valuesHidden), subtraction = true)
                }
                HorizontalDivider(color = FinovaColors.Gray300)
                FormulaRow(
                    stringResource(R.string.projection_formula_result),
                    Money.formatMasked(projection.projected, currencyCode, valuesHidden),
                    result = true,
                    // No red while masked: a red row of dots still tells of an overdraft.
                    negative = !valuesHidden && projection.projected < 0,
                )
            }
            Spacer(Modifier.height(Spacing.S2))
            Text(stringResource(R.string.projection_formula_note), style = FinovaType.TextXS, color = FinovaColors.Gray500)
            Spacer(Modifier.height(Spacing.S5))
            SectionHeader(stringResource(R.string.projection_history_header))
            val rows = allocations.map { it.category to (histories[it.category] ?: CategorySpendHistory.None) }
            if (rows.none { it.second.verdict != CategorySpendHistory.Verdict.NotEnoughHistory }) {
                Text(stringResource(R.string.projection_history_empty), style = FinovaType.TextSM, color = FinovaColors.Gray500)
            } else {
                // Percentages and month counts, not amounts, so never masked.
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
                    rows.forEach { (category, history) -> HistoryRow(category, history) }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text, style = FinovaType.TitleXS, color = FinovaColors.Gray500)
    Spacer(Modifier.height(Spacing.S2))
}

@Composable
private fun FormulaRow(label: String, value: String, subtraction: Boolean = false, result: Boolean = false, negative: Boolean = false) {
    val style = if (result) FinovaType.TextSMBold else FinovaType.TextSM
    Row(verticalAlignment = Alignment.Top) {
        Text(label, style = style, color = if (result) FinovaColors.Gray700 else FinovaColors.Gray500, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(Spacing.S3))
        Text(
            value, style = style, textAlign = TextAlign.End,
            color = when {
                negative -> FinovaColors.MainRed
                subtraction -> FinovaColors.Gray500
                else -> FinovaColors.Gray700
            },
        )
    }
}

@Composable
private fun HistoryRow(category: TransactionCategory, history: CategorySpendHistory) {
    val (low, high) = history.percentRange
    val range = if (low == high) stringResource(R.string.projection_history_single, low)
    else stringResource(R.string.projection_history_range, low, high)
    val (shown, detail) = when (val verdict = history.verdict) {
        CategorySpendHistory.Verdict.NotEnoughHistory -> null to stringResource(R.string.projection_history_none)
        is CategorySpendHistory.Verdict.Consistent ->
            range to pluralStringResource(R.plurals.projection_history_months, verdict.months, verdict.months)
        // A spread this wide has no usable typical figure; the range still shows how wide it is.
        is CategorySpendHistory.Verdict.Varied -> range to stringResource(R.string.projection_history_varied)
    }
    Row(verticalAlignment = Alignment.Top) {
        Text(stringResource(category.label), style = FinovaType.TextSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(Spacing.S3))
        Column(horizontalAlignment = Alignment.End) {
            shown?.let { Text(it, style = FinovaType.TextSMBold, color = FinovaColors.Gray700) }
            Text(detail, style = FinovaType.TextXS, color = FinovaColors.Gray500)
        }
    }
}
