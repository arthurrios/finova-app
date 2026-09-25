package com.arthurrios.finova.ui.dashboard

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.YearMonth

/**
 * The month strip above the carousel. iOS builds it by hand (MonthSelectorView); on Android it is
 * the Material 3 scrollable tab row, styled the same: bold dark selected month with a magenta
 * underline, small gray neighbours, and chevrons on both ends.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonthTabs(
    months: List<YearMonth>,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val names = stringArrayResource(R.array.month_short)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.S1)
            .height(Spacing.S12),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = { onSelect((selected - 1).coerceAtLeast(0)) }, enabled = selected > 0) {
            Icon(
                painter = painterResource(R.drawable.ic_chevron_left),
                contentDescription = stringResource(R.string.month_previous),
                tint = FinovaColors.Gray500,
                modifier = Modifier.size(Spacing.S4),
            )
        }
        PrimaryScrollableTabRow(
            selectedTabIndex = selected,
            modifier = Modifier.weight(1f),
            containerColor = Color.Transparent,
            edgePadding = 0.dp,
            // Material's default 90dp fits three months; iOS shows five.
            minTabWidth = 56.dp,
            divider = {},
            indicator = {
                TabRowDefaults.PrimaryIndicator(
                    modifier = Modifier.tabIndicatorOffset(selected, matchContentSize = true),
                    width = androidx.compose.ui.unit.Dp.Unspecified,
                    height = 2.dp,
                    color = FinovaColors.MainMagenta,
                    shape = androidx.compose.ui.graphics.RectangleShape,
                )
            },
        ) {
            months.forEachIndexed { index, month ->
                val isSelected = index == selected
                Tab(
                    selected = isSelected,
                    onClick = { onSelect(index) },
                    selectedContentColor = FinovaColors.Gray700,
                    unselectedContentColor = FinovaColors.Gray400,
                    text = {
                        Text(
                            text = names[month.monthValue - 1].uppercase(),
                            style = if (isSelected) FinovaType.TitleXS else FinovaType.Title2XS,
                        )
                    },
                )
            }
        }
        IconButton(
            onClick = { onSelect((selected + 1).coerceAtMost(months.lastIndex)) },
            enabled = selected < months.lastIndex,
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_chevron_right),
                contentDescription = stringResource(R.string.month_next),
                tint = FinovaColors.Gray500,
                modifier = Modifier.size(Spacing.S4),
            )
        }
    }
}
