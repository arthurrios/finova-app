package com.arthurrios.finova.ui.filter

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.dashboard.TransactionModeUi
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * Port of TransactionFilterModalView: day range, type, mode and category, with Clear and Apply
 * pinned under the scrolling sections. iOS slides up a hand-made panel; Android uses the native
 * bottom sheet. Picks stay local until Apply, so closing the sheet changes nothing.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TransactionFilterSheet(
    current: TransactionFilters,
    daysInMonth: Int,
    onApply: (TransactionFilters) -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    // An unset range opens on the whole month, as iOS does.
    var draft by remember {
        mutableStateOf(current.copy(startDay = current.startDay ?: 1, endDay = current.endDay ?: daysInMonth))
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = FinovaColors.Gray100,
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.7f).navigationBarsPadding()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(start = Spacing.S8, end = Spacing.S6, bottom = Spacing.S3),
            ) {
                Text(
                    stringResource(R.string.filter_title),
                    style = FinovaType.TitleXS,
                    color = FinovaColors.Gray700,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        painterResource(R.drawable.ic_x),
                        contentDescription = stringResource(R.string.add_transaction_close),
                        tint = FinovaColors.Gray500,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.S5),
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Spacing.S8, vertical = Spacing.S3),
            ) {
                Section(stringResource(R.string.filter_day_range_title)) {
                    ScopeSelector(
                        useGlobal = draft.useGlobalFilter,
                        onSelect = { draft = draft.copy(useGlobalFilter = it) },
                    )
                    DayRangeSlider(
                        startDay = draft.startDay ?: 1,
                        endDay = draft.endDay ?: daysInMonth,
                        daysInMonth = daysInMonth,
                        enabled = !draft.useGlobalFilter,
                        onChange = { start, end -> draft = draft.copy(startDay = start, endDay = end) },
                    )
                }
                Section(stringResource(R.string.filter_type_title)) {
                    ChipRow {
                        // Income first, as TransactionType.allCases lists it on iOS.
                        listOf(true to R.string.add_transaction_income, false to R.string.add_transaction_expense)
                            .forEach { (isIncome, label) ->
                                Chip(stringResource(label), isIncome in draft.types) {
                                    draft = draft.copy(types = draft.types.toggle(isIncome))
                                }
                            }
                    }
                }
                Section(stringResource(R.string.filter_mode_title)) {
                    ChipRow {
                        TransactionModeUi.entries.forEach { mode ->
                            Chip(stringResource(mode.label), mode in draft.modes) {
                                draft = draft.copy(modes = draft.modes.toggle(mode))
                            }
                        }
                    }
                }
                Section(stringResource(R.string.filter_category_title)) {
                    ChipRow {
                        TransactionCategory.entries.forEach { category ->
                            Chip(stringResource(category.label), category in draft.categories) {
                                draft = draft.copy(categories = draft.categories.toggle(category))
                            }
                        }
                    }
                }
            }

            HorizontalDivider(color = FinovaColors.Gray300)
            Row(
                horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
                modifier = Modifier.padding(start = Spacing.S8, end = Spacing.S8, top = Spacing.S4, bottom = Spacing.S6),
            ) {
                FinovaAccentOutlinedButton(
                    text = stringResource(R.string.filter_clear),
                    onClick = onClear,
                    modifier = Modifier.weight(1f),
                )
                FinovaButton(
                    text = stringResource(R.string.filter_apply),
                    onClick = {
                        // Global mode drops the range, exactly like iOS applyButtonTapped.
                        onApply(if (draft.useGlobalFilter) draft.withoutDayFilter() else draft)
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
        Text(title, style = FinovaType.Title2XS, color = FinovaColors.Gray600)
        content()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipRow(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2)) { content() }
}

/** iOS draws these chips by hand; the Material filter chip is the native match. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Chip(text: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(text, style = FinovaType.TextXS) },
        shape = RoundedCornerShape(16.dp),
        colors = FilterChipDefaults.filterChipColors(
            containerColor = FinovaColors.Gray200,
            labelColor = FinovaColors.Gray600,
            selectedContainerColor = FinovaColors.MainMagenta,
            selectedLabelColor = FinovaColors.Gray100,
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = FinovaColors.Gray300,
            selectedBorderWidth = 0.dp,
        ),
    )
}

/** Global keeps the filter on every month; Custom adds a day range for this month only. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScopeSelector(useGlobal: Boolean, onSelect: (Boolean) -> Unit) {
    val options = listOf(true to R.string.filter_mode_global, false to R.string.filter_mode_custom)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (global, label) ->
            SegmentedButton(
                selected = useGlobal == global,
                onClick = { onSelect(global) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = FinovaColors.MainMagenta,
                    activeContentColor = FinovaColors.Gray100,
                    activeBorderColor = FinovaColors.Gray300,
                    inactiveContainerColor = FinovaColors.Gray200,
                    inactiveContentColor = FinovaColors.Gray600,
                    inactiveBorderColor = FinovaColors.Gray300,
                ),
                icon = {},
            ) {
                Text(
                    stringResource(label),
                    style = if (useGlobal == global) FinovaType.TextSMBold else FinovaType.TextSM,
                )
            }
        }
    }
}

private val TransactionModeUi.label: Int
    get() = when (this) {
        TransactionModeUi.Normal -> R.string.transaction_mode_normal
        TransactionModeUi.Recurring -> R.string.transaction_mode_recurring
        TransactionModeUi.Installments -> R.string.transaction_mode_installments
    }

private fun <T> Set<T>.toggle(item: T): Set<T> = if (item in this) this - item else this + item
