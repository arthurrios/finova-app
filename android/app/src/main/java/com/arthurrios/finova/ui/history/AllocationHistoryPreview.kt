package com.arthurrios.finova.ui.history

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.history.BudgetHistorySeries
import com.arthurrios.finova.ui.dashboard.CardHeader
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.YearMonth

private val BottomCorners = RoundedCornerShape(bottomStart = CornerRadius.ExtraLarge, bottomEnd = CornerRadius.ExtraLarge)

/**
 * The history section on the allocation details screen: six months of this category in miniature,
 * one line saying how often it stayed on plan, and the way into the full history. Port of
 * AllocationHistoryPreviewView. The whole card is one button.
 */
@Composable
fun AllocationHistoryPreview(
    series: BudgetHistorySeries,
    selected: YearMonth,
    valuesHidden: Boolean,
    currencyCode: String,
    onOpen: () -> Unit,
) {
    val scored = series.scoredMonths.size
    val summary = if (scored == 0) stringResource(R.string.history_preview_not_enough)
        else stringResource(R.string.history_preview_summary_format, series.monthsOnPlan, scored)
    val cta = stringResource(R.string.history_preview_cta)
    Column {
        CardHeader(stringResource(R.string.history_preview_header))
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
            modifier = Modifier
                .fillMaxWidth()
                .clip(BottomCorners)
                .background(FinovaColors.Gray100)
                .border(1.dp, FinovaColors.Gray300, BottomCorners)
                .clickable(onClickLabel = cta, role = Role.Button, onClick = onOpen)
                .padding(Spacing.S5),
        ) {
            BudgetHistoryChart(
                months = series.months,
                selected = selected,
                valuesHidden = valuesHidden,
                currencyCode = currencyCode,
                compact = true,
                contentDescription = summary,
                modifier = Modifier.fillMaxWidth().height(76.dp),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(summary, style = FinovaType.TextXS, color = FinovaColors.Gray500, maxLines = 2, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(Spacing.S2))
                Text(cta, style = FinovaType.TextSMBold, color = FinovaColors.MainMagenta)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(16.dp))
            }
        }
    }
}

/**
 * This category's last six months for the preview, ending at the month on screen when it is in the
 * window, so a past month's details show the six months up to it. Null when the category had no
 * plan anywhere in the window: a category never planned has no history worth a card.
 */
fun BudgetHistorySeries?.previewEnding(month: YearMonth): BudgetHistorySeries? {
    if (this == null) return null
    val end = months.indexOfFirst { it.month == month }.takeIf { it >= 0 } ?: (months.size - 1)
    val preview = copy(months = months.take(end + 1).takeLast(6)).trimmingLeadingEmptyMonths()
    return preview.takeIf { it.months.isNotEmpty() && !it.isEmpty }
}
