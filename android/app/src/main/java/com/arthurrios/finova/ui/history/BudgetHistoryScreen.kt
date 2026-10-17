package com.arthurrios.finova.ui.history

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.history.BudgetHistoryFilter
import com.arthurrios.finova.domain.history.BudgetHistoryMonth
import com.arthurrios.finova.domain.history.BudgetHistorySeries
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.HiddenValue
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.YearMonth

private val CardShape = RoundedCornerShape(CornerRadius.ExtraLarge)

/**
 * Past months of the budget and of each allocation, against their plans. Port of
 * BudgetHistoryViewController + BudgetHistoryContentView: what is shown and over how long, the
 * selected month with the chart, what the selection saved, and three insight tiles.
 *
 * Every control that changes the readout sits in or above the card it changes.
 */
@Composable
fun BudgetHistoryScreen(viewModel: BudgetHistoryViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    fun tick() = haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.history_title),
            subtitle = stringResource(R.string.history_subtitle_personal),
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
        if (!state.isLoaded) return@Column
        if (state.isEmpty) {
            EmptyState()
            return@Column
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S4),
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(Spacing.S4),
        ) {
            Controls(state, onPick = { picking = true }, onSpan = { tick(); viewModel.selectSpan(it) })
            ChartCard(state) { month ->
                if (month != state.selectedMonth?.month) {
                    tick()
                    viewModel.selectMonth(month)
                }
            }
            SavingsCard(state, onStart = { tick(); viewModel.selectSavingsStart(it) })
            Insights(state.series)
        }
    }

    if (picking) {
        FilterPickerSheet(
            state = state,
            onDismiss = { picking = false },
            onPick = {
                tick()
                picking = false
                viewModel.selectFilter(it)
            },
        )
    }
}

@Composable
fun BudgetHistoryFilter.title(): String = when (this) {
    BudgetHistoryFilter.WholeMonth -> stringResource(R.string.history_filter_whole_month)
    is BudgetHistoryFilter.Category -> stringResource(category.label)
}

/** "October 2026". */
@Composable
fun longMonth(month: YearMonth): String = stringArrayResource(R.array.month_long)[month.monthValue - 1] + " ${month.year}"

@Composable
private fun FilterIcon(filter: BudgetHistoryFilter, tint: Color, size: androidx.compose.ui.unit.Dp) = when (filter) {
    BudgetHistoryFilter.WholeMonth -> Icon(Icons.Outlined.CalendarMonth, null, tint = tint, modifier = Modifier.size(size))
    is BudgetHistoryFilter.Category ->
        Icon(painterResource(filter.category.icon(TransactionType.Expense)), null, tint = tint, modifier = Modifier.size(size))
}

// ---- Controls ------------------------------------------------------------------------------------

/** What is shown, and over how long. One button opens the full list of filters. */
@Composable
private fun Controls(state: BudgetHistoryUiState, onPick: () -> Unit, onSpan: (HistorySpan) -> Unit) {
    val chooseLabel = stringResource(R.string.history_a11y_choose_filter)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2),
            modifier = Modifier
                .weight(1f, fill = false)
                .height(36.dp)
                .clip(CircleShape)
                .background(FinovaColors.Gray100)
                .border(1.dp, FinovaColors.Gray300, CircleShape)
                .clickable(onClickLabel = chooseLabel, onClick = onPick)
                .padding(horizontal = Spacing.S4),
        ) {
            FilterIcon(state.filter, FinovaColors.Gray700, 16.dp)
            Text(state.filter.title(), style = FinovaType.TextSMBold, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Filled.KeyboardArrowDown, null, tint = FinovaColors.Gray700, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.weight(0.01f).width(Spacing.S3))
        if (state.offersLongerSpan) SpanPicker(state.span, onSpan)
    }
}

/** 6M / 12M. Hand-built, as on iOS: a capsule with the chosen option filled in magenta. */
@Composable
private fun SpanPicker(selected: HistorySpan, onSpan: (HistorySpan) -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, CircleShape)
            .padding(3.dp),
    ) {
        HistorySpan.entries.forEach { span ->
            val isSelected = span == selected
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(width = 40.dp, height = 28.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) FinovaColors.MainMagenta else Color.Transparent)
                    .clickable { onSpan(span) },
            ) {
                Text(
                    stringResource(if (span == HistorySpan.SixMonths) R.string.history_range_6m else R.string.history_range_12m),
                    fontSize = 11.sp, fontWeight = FontWeight.Bold,
                    color = if (isSelected) Color.White else FinovaColors.Gray500,
                )
            }
        }
    }
}

// ---- Chart card ----------------------------------------------------------------------------------

@Composable
private fun ChartCard(state: BudgetHistoryUiState, onSelect: (YearMonth) -> Unit) {
    val hidden = state.valuesHidden
    val selected = state.selectedMonth
    Column(
        verticalArrangement = Arrangement.spacedBy(Spacing.S4),
        modifier = Modifier.card().padding(Spacing.S5),
    ) {
        if (selected != null) Readout(state, selected, onSelect)
        BudgetHistoryChart(
            months = state.series.months,
            selected = selected?.month,
            valuesHidden = hidden,
            currencyCode = state.currencyCode,
            onSelect = onSelect,
            modifier = Modifier.fillMaxWidth().height(210.dp),
        )
        Legend()
    }
}

/** The selected month in words and figures. Follows a finger scrubbing the chart. */
@Composable
private fun Readout(state: BudgetHistoryUiState, month: BudgetHistoryMonth, onSelect: (YearMonth) -> Unit) {
    val hidden = state.valuesHidden
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepButton(state.neighbour(-1), back = true, onSelect)
            Text(longMonth(month.month), style = FinovaType.TextSMBold, color = FinovaColors.Gray600)
            StepButton(state.neighbour(1), back = false, onSelect)
            Spacer(Modifier.weight(1f))
            // Right-aligned, in the same column as the status pill under it.
            if (month.isCurrent) {
                Text(
                    stringResource(R.string.history_status_in_progress),
                    fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.MainMagenta,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(FinovaColors.MainMagenta.copy(alpha = 0.1f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                Money.formatMasked(month.spent, state.currencyCode, hidden),
                style = FinovaType.TitleLG.copy(fontSize = 24.sp), color = FinovaColors.Gray700,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
            )
            Spacer(Modifier.weight(0.01f).width(Spacing.S2))
            StatusPill(month, hidden, state.currencyCode)
        }
        Text(planLine(month, hidden, state.currencyCode), style = FinovaType.TextXS, color = FinovaColors.Gray500)
    }
}

/** One month back or forward, within the bars on screen. Next to the month name it changes. */
@Composable
private fun StepButton(target: YearMonth?, back: Boolean, onSelect: (YearMonth) -> Unit) {
    Box(
        contentAlignment = if (back) Alignment.CenterStart else Alignment.Center,
        modifier = Modifier
            .size(width = if (back) 20.dp else 28.dp, height = 28.dp)
            .clickable(enabled = target != null) { target?.let(onSelect) },
    ) {
        Icon(
            if (back) Icons.AutoMirrored.Filled.KeyboardArrowLeft else Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = stringResource(if (back) R.string.history_a11y_previous_month else R.string.history_a11y_next_month),
            tint = if (target == null) FinovaColors.Gray300 else FinovaColors.MainMagenta,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun planLine(month: BudgetHistoryMonth, hidden: Boolean, code: String): String {
    if (!month.hasPlan) return stringResource(R.string.history_hero_no_plan)
    var line = stringResource(R.string.history_hero_of_format, Money.formatMasked(month.planned, code, hidden))
    month.percentUsed?.let { line += " · " + stringResource(R.string.history_percent_format, it) }
    return line
}

/** The short status a month carries: an amount when values are visible, a word when not. */
@Composable
fun statusText(month: BudgetHistoryMonth, hidden: Boolean, code: String): String = when (month.status) {
    // Hidden, an open month still reads "On plan": the readout already has an "In progress" badge.
    BudgetHistoryMonth.Status.Within, BudgetHistoryMonth.Status.InProgress ->
        if (hidden) stringResource(R.string.history_status_within)
        else stringResource(R.string.history_status_left_format, Money.format(month.difference, code))
    BudgetHistoryMonth.Status.Over ->
        if (hidden) stringResource(R.string.history_status_over_plain)
        else stringResource(R.string.history_status_over_format, Money.format(-month.difference, code))
    BudgetHistoryMonth.Status.NoPlan -> stringResource(R.string.history_status_no_plan)
    BudgetHistoryMonth.Status.Empty -> stringResource(R.string.history_status_empty)
}

/** The amount left or over, coloured by outcome. */
@Composable
private fun StatusPill(month: BudgetHistoryMonth, hidden: Boolean, code: String) {
    val (tint, icon) = when (month.status) {
        BudgetHistoryMonth.Status.Within -> FinovaColors.MainGreen to Icons.Filled.Check
        BudgetHistoryMonth.Status.InProgress -> FinovaColors.MainGreen to Icons.Outlined.Schedule
        BudgetHistoryMonth.Status.Over -> FinovaColors.MainRed to Icons.Filled.NorthEast
        else -> FinovaColors.Gray500 to Icons.Filled.Remove
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .height(22.dp)
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.1f))
            .padding(horizontal = Spacing.S2),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(11.dp))
        Text(statusText(month, hidden, code), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = tint, maxLines = 1)
    }
}

@Composable
private fun Legend() {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S4), verticalAlignment = Alignment.CenterVertically) {
        LegendItem(FinovaColors.MainMagenta, stringResource(R.string.history_legend_spent))
        LegendItem(FinovaColors.MainRed, stringResource(R.string.history_legend_over))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(width = 12.dp, height = 10.dp).drawBehind {
                drawRoundRect(FinovaColors.Gray300, topLeft = androidx.compose.ui.geometry.Offset(1.dp.toPx(), 0f),
                    size = androidx.compose.ui.geometry.Size(10.dp.toPx(), 10.dp.toPx()),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
                drawRect(FinovaColors.Gray600, size = androidx.compose.ui.geometry.Size(12.dp.toPx(), 2.dp.toPx()))
            })
            Text(stringResource(R.string.history_legend_plan), fontSize = 10.sp, color = FinovaColors.Gray500)
        }
    }
}

@Composable
private fun LegendItem(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(color))
        Text(label, fontSize = 10.sp, color = FinovaColors.Gray500)
    }
}

// ---- Savings -------------------------------------------------------------------------------------

/** What the chosen filter saved in closed months, from a start month the user picks. */
@Composable
private fun SavingsCard(state: BudgetHistoryUiState, onStart: (YearMonth?) -> Unit) {
    val savings = state.savings
    val hidden = state.valuesHidden
    Column(
        verticalArrangement = Arrangement.spacedBy(Spacing.S2),
        modifier = Modifier.card().padding(Spacing.S5),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.history_savings_title).uppercase(), style = FinovaType.Title2XS, color = FinovaColors.Gray500)
            Spacer(Modifier.weight(1f))
            SavingsStartMenu(state, onStart)
        }
        if (savings.months == 0) {
            Text(stringResource(R.string.history_savings_none), style = FinovaType.TextSM, color = FinovaColors.Gray500)
        } else {
            Text(
                Money.formatMasked(savings.net, state.currencyCode, hidden),
                style = FinovaType.TitleLG.copy(fontSize = 24.sp),
                color = when {
                    hidden -> FinovaColors.Gray700
                    savings.net >= 0 -> FinovaColors.MainGreen
                    else -> FinovaColors.MainRed
                },
                maxLines = 1,
            )
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // Both sides only when both have something; the net above already says one side.
                if (!hidden && savings.saved > 0 && savings.overspent > 0) {
                    Text(
                        stringResource(
                            R.string.history_savings_detail_format,
                            Money.format(savings.saved, state.currencyCode), Money.format(savings.overspent, state.currencyCode),
                        ),
                        style = FinovaType.TextXS, color = FinovaColors.Gray500,
                    )
                }
                Text(monthsCount(savings.months), style = FinovaType.TextXS, color = FinovaColors.Gray500)
            }
        }
    }
}

@Composable
private fun monthsCount(months: Int) =
    if (months == 1) stringResource(R.string.history_savings_months_one) else stringResource(R.string.history_savings_months_format, months)

@Composable
fun savingsStartTitle(start: YearMonth?): String =
    if (start == null) stringResource(R.string.history_savings_since_start)
    else stringResource(R.string.history_savings_since_format, longMonth(start))

/** iOS uses a system pull-down menu here; Android's is the Material dropdown menu. */
@Composable
private fun SavingsStartMenu(state: BudgetHistoryUiState, onStart: (YearMonth?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.clip(RoundedCornerShape(CornerRadius.Small)).clickable { open = true }.padding(vertical = 2.dp),
        ) {
            Text(savingsStartTitle(state.savingsStart), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.MainMagenta)
            Icon(Icons.Filled.UnfoldMore, null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(14.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = FinovaColors.Gray100) {
            StartOption(null, state.savingsStart) { open = false; onStart(it) }
            HorizontalDivider(color = FinovaColors.Gray300)
            state.savingsStartOptions.asReversed().forEach { month ->
                StartOption(month, state.savingsStart) { open = false; onStart(it) }
            }
        }
    }
}

@Composable
private fun StartOption(month: YearMonth?, current: YearMonth?, onPick: (YearMonth?) -> Unit) {
    DropdownMenuItem(
        text = { Text(month?.let { longMonth(it) } ?: stringResource(R.string.history_savings_since_start), style = FinovaType.TextSM) },
        trailingIcon = if (month == current) ({ Icon(Icons.Filled.Check, null, tint = FinovaColors.MainMagenta) }) else null,
        onClick = { onPick(month) },
    )
}

// ---- Insights ------------------------------------------------------------------------------------

@Composable
private fun Insights(series: BudgetHistorySeries) {
    val scored = series.scoredMonths.size
    val none = stringResource(R.string.history_insight_none)
    val onPlan = if (scored > 0) stringResource(R.string.history_insight_on_plan_value_format, series.monthsOnPlan, scored) else none
    val range = series.usageRange?.let { (low, high) -> if (low == high) "$low%" else "$low–$high%" } ?: none
    val streak = series.streak
    val streakValue = when {
        scored == 0 -> none
        streak == 1 -> stringResource(R.string.history_insight_streak_value_one)
        else -> stringResource(R.string.history_insight_streak_value_format, streak)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2)) {
        InsightTile(Icons.Filled.Verified, FinovaColors.MainGreen, stringResource(R.string.history_insight_on_plan_title), onPlan,
            stringResource(R.string.history_insight_on_plan_caption), Modifier.weight(1f))
        InsightTile(Icons.Filled.SwapHoriz, FinovaColors.MainMagenta, stringResource(R.string.history_insight_range_title), range,
            stringResource(R.string.history_insight_range_caption), Modifier.weight(1f))
        InsightTile(Icons.Filled.LocalFireDepartment, if (streak > 0) FinovaColors.WarningAmber else FinovaColors.Gray400,
            stringResource(R.string.history_insight_streak_title), streakValue, stringResource(R.string.history_insight_streak_caption), Modifier.weight(1f))
    }
}

@Composable
private fun InsightTile(icon: ImageVector, tint: Color, title: String, value: String, caption: String, modifier: Modifier) {
    Column(
        verticalArrangement = Arrangement.spacedBy(Spacing.S1),
        modifier = modifier.card().padding(Spacing.S3),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(12.dp))
            Text(title, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.Gray500, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(value, style = FinovaType.TitleMD, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(caption, fontSize = 10.sp, lineHeight = 13.sp, color = FinovaColors.Gray400, maxLines = 2)
    }
}

// ---- Filter picker -------------------------------------------------------------------------------

/**
 * Every filter in one list, each with what it saved since the chosen start month, so the list that
 * picks a category also compares them. A system sheet on iOS, a Material bottom sheet here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterPickerSheet(state: BudgetHistoryUiState, onDismiss: () -> Unit, onPick: (BudgetHistoryFilter) -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(),
        containerColor = FinovaColors.Gray100,
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S1),
            modifier = Modifier.padding(start = Spacing.S5, end = Spacing.S5, bottom = Spacing.S3),
        ) {
            Text(stringResource(R.string.history_picker_title), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            Text(
                stringResource(R.string.history_savings_title) + " · " + savingsStartTitle(state.savingsStart),
                style = FinovaType.TextXS, color = FinovaColors.Gray500,
            )
        }
        LazyColumn(Modifier.heightIn(max = 560.dp).navigationBarsPadding()) {
            items(state.filters, key = { it.toString() }) { filter ->
                FilterRow(state, filter, onPick)
                HorizontalDivider(color = FinovaColors.Gray300, modifier = Modifier.padding(start = 64.dp))
            }
            state.outsideAllocations?.let { amount -> item { OutsideRow(amount, state) } }
        }
    }
}

@Composable
private fun FilterRow(state: BudgetHistoryUiState, filter: BudgetHistoryFilter, onPick: (BudgetHistoryFilter) -> Unit) {
    val isSelected = filter == state.filter
    val savings = state.savings(filter)
    val hidden = state.valuesHidden
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onPick(filter) }
            .padding(horizontal = Spacing.S5, vertical = Spacing.S3),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(CornerRadius.Medium))
                .background(if (isSelected) FinovaColors.MainMagenta.copy(alpha = 0.1f) else FinovaColors.Gray200),
        ) {
            FilterIcon(filter, if (isSelected) FinovaColors.MainMagenta else FinovaColors.Gray600, 18.dp)
        }
        Text(
            filter.title(), style = if (isSelected) FinovaType.TextSMBold else FinovaType.TextSM, color = FinovaColors.Gray700,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        Text(
            if (savings.months == 0) stringResource(R.string.history_insight_none) else Money.formatMasked(savings.net, state.currencyCode, hidden),
            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
            color = when {
                savings.months == 0 || hidden -> FinovaColors.Gray500
                savings.net >= 0 -> FinovaColors.MainGreen
                else -> FinovaColors.MainRed
            },
        )
        Icon(
            Icons.Filled.Check, null, tint = if (isSelected) FinovaColors.MainMagenta else Color.Transparent,
            modifier = Modifier.size(16.dp),
        )
    }
}

/**
 * The remainder, so the category rows plus this one add up to the whole month. Not a filter: there
 * is no chart for it, so it is a plain row with no tap and no checkmark.
 */
@Composable
private fun OutsideRow(amount: Long, state: BudgetHistoryUiState) {
    val hidden = state.valuesHidden
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
        modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.S5, vertical = Spacing.S3),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(36.dp).drawBehind {
                drawRoundRect(
                    FinovaColors.Gray300, cornerRadius = androidx.compose.ui.geometry.CornerRadius(CornerRadius.Medium.toPx()),
                    style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))),
                )
            },
        ) {
            Box(Modifier.size(14.dp).drawBehind {
                drawRect(FinovaColors.Gray500, style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 2.dp.toPx()))))
            })
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.history_outside_title), style = FinovaType.TextSM, color = FinovaColors.Gray700)
            Text(stringResource(R.string.history_outside_caption), fontSize = 11.sp, lineHeight = 14.sp, color = FinovaColors.Gray500)
        }
        Text(
            if (hidden) HiddenValue else Money.format(amount, state.currencyCode),
            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
            color = when {
                hidden -> FinovaColors.Gray500
                amount >= 0 -> FinovaColors.MainGreen
                else -> FinovaColors.MainRed
            },
        )
        // Keeps the amount in the same column as the rows above, which keep a checkmark slot.
        Spacer(Modifier.width(16.dp))
    }
}

// ---- Empty ---------------------------------------------------------------------------------------

@Composable
private fun EmptyState() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S3, Alignment.CenterVertically),
        modifier = Modifier.fillMaxSize().padding(Spacing.S8),
    ) {
        Icon(Icons.Outlined.BarChart, null, tint = FinovaColors.Gray400, modifier = Modifier.size(40.dp))
        Text(stringResource(R.string.history_empty_title), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
        Text(
            stringResource(R.string.history_empty_message), style = FinovaType.TextSM, color = FinovaColors.Gray500,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

/** The white, bordered card every section on the light screens uses. */
private fun Modifier.card() = fillMaxWidth()
    .clip(CardShape)
    .background(FinovaColors.Gray100)
    .border(1.dp, FinovaColors.Gray300, CardShape)
