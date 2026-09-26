package com.arthurrios.finova.ui.budget

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.allocation.UnallocatedSpending
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Port of AllocationCell for an allocation: used / allocated, and what is left (or over). */
@Composable
fun AllocationRowView(allocation: BudgetAllocation, currencyCode: String, valuesHidden: Boolean, onClick: () -> Unit) {
    val remaining = allocation.remaining
    CategoryRow(
        category = allocation.category,
        iconTint = FinovaColors.MainMagenta,
        subtitle = if (valuesHidden) Money.formatMasked(0, currencyCode, true)
        else "${Money.compact(allocation.used, currencyCode)} / ${Money.compact(allocation.allocated, currencyCode)}",
        subtitleColor = FinovaColors.Gray500,
        value = Money.compactMasked(kotlin.math.abs(remaining), currencyCode, valuesHidden),
        up = remaining >= 0,
        onClick = onClick,
    )
}

/** AllocationCell for spending no allocation covers. */
@Composable
fun OffPlanRowView(spending: UnallocatedSpending, currencyCode: String, valuesHidden: Boolean, onClick: () -> Unit) {
    CategoryRow(
        category = spending.category,
        iconTint = FinovaColors.Gray500,
        subtitle = stringResource(R.string.alloc_unallocated_row),
        subtitleColor = FinovaColors.Gray400,
        value = Money.compactMasked(spending.spent, currencyCode, valuesHidden),
        up = false,
        onClick = onClick,
    )
}

@Composable
private fun CategoryRow(
    category: TransactionCategory,
    iconTint: Color,
    subtitle: String,
    subtitleColor: Color,
    value: String,
    up: Boolean,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.S5, vertical = Spacing.S4),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(Spacing.S8)
                .clip(RoundedCornerShape(CornerRadius.Medium))
                .background(FinovaColors.Gray200)
                .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(CornerRadius.Medium)),
        ) {
            Icon(painterResource(category.icon(TransactionType.Expense)), contentDescription = null, tint = iconTint, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(Spacing.S5))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(category.label), style = FinovaType.TextSMBold, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = FinovaType.TextXS, color = subtitleColor)
        }
        Spacer(Modifier.width(Spacing.S2))
        Icon(
            painterResource(if (up) R.drawable.ic_arrow_up else R.drawable.ic_arrow_down),
            contentDescription = null,
            tint = if (up) FinovaColors.MainGreen else FinovaColors.MainRed,
            modifier = Modifier.size(12.dp),
        )
        Spacer(Modifier.width(Spacing.S1))
        Text(value, style = FinovaType.TextSMBold, color = FinovaColors.Gray700)
    }
}

/** The empty state under the allocations header. */
@Composable
fun AllocationsEmpty() {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .clip(RoundedCornerShape(bottomStart = CornerRadius.ExtraLarge, bottomEnd = CornerRadius.ExtraLarge))
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(bottomStart = CornerRadius.ExtraLarge, bottomEnd = CornerRadius.ExtraLarge))
            .padding(horizontal = Spacing.S5),
    ) {
        Text(stringResource(R.string.budget_allocations_empty), style = FinovaType.TextXS, color = FinovaColors.Gray500)
    }
}
