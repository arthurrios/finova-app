package com.arthurrios.finova.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.tags.AllocationTagBreakdown
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

private val ChipHeight = 28.dp

/**
 * Port of AllocationTagStripView: each tag's allocated total under the allocations header, doubling
 * as the filter for the list. A clear chip leads while a filter is on; the grey Untagged chip is not
 * a filter; the + chip creates a tag.
 */
@Composable
fun TagStrip(
    breakdown: AllocationTagBreakdown,
    selectedTagId: String?,
    currencyCode: String,
    valuesHidden: Boolean,
    onSelect: (String?) -> Unit,
    onCreate: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().background(FinovaColors.Gray100)) {
        HorizontalDivider(color = FinovaColors.Gray300)
        Row(
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .height(44.dp)
                .horizontalScroll(rememberScrollState())
                .padding(start = Spacing.S5, end = Spacing.S4),
        ) {
            if (selectedTagId != null) {
                RoundChip(FinovaColors.Gray200, FinovaColors.Gray300, onClick = { onSelect(null) }) {
                    Icon(Icons.Filled.Close, stringResource(R.string.tags_strip_clear), tint = FinovaColors.Gray500, modifier = Modifier.size(14.dp))
                }
            }
            breakdown.tagArcs.forEach { arc ->
                val selected = arc.tag.id == selectedTagId
                Chip(
                    title = arc.tag.name,
                    amount = Money.compactMasked(arc.bucket.allocated, currencyCode, valuesHidden),
                    ink = arc.tag.color.inkColor,
                    selected = selected,
                    onClick = { onSelect(if (selected) null else arc.tag.id) },
                )
            }
            breakdown.untagged?.let {
                Chip(stringResource(R.string.tags_strip_untagged), Money.compactMasked(it.allocated, currencyCode, valuesHidden),
                    FinovaColors.Gray400, selected = false, onClick = null)
            }
            RoundChip(FinovaColors.LowMagenta, FinovaColors.MainMagenta, onClick = onCreate) {
                Icon(Icons.Filled.Add, stringResource(R.string.tags_create_title), tint = FinovaColors.MainMagenta, modifier = Modifier.size(14.dp))
            }
        }
    }
}

@Composable
private fun Chip(title: String, amount: String, ink: Color, selected: Boolean, onClick: (() -> Unit)?) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(Spacing.S1),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .height(ChipHeight)
            .clip(CircleShape)
            // Selected chips fill with the dark ink tone, which carries light text.
            .background(if (selected) ink else FinovaColors.Gray200)
            .then(if (selected) Modifier else Modifier.border(1.dp, FinovaColors.Gray300, CircleShape))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = Spacing.S3),
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(if (selected) FinovaColors.Gray100 else ink))
        Text(title, style = FinovaType.TextXS, color = if (selected) FinovaColors.Gray100 else FinovaColors.Gray600, maxLines = 1)
        Text(amount, style = FinovaType.TitleXS, color = if (selected) FinovaColors.Gray100 else FinovaColors.Gray700, maxLines = 1)
    }
}

@Composable
private fun RoundChip(background: Color, border: Color, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier.size(ChipHeight).clip(CircleShape).background(background).border(1.dp, border, CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}
