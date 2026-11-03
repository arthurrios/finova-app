package com.arthurrios.finova.ui.history

import com.arthurrios.finova.domain.coachmarks.CoachMarkEvent
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget
import com.arthurrios.finova.ui.coachmarks.LocalCoachMarks
import com.arthurrios.finova.ui.coachmarks.CoachMarkLoading
import com.arthurrios.finova.ui.coachmarks.CoachMarkSheet
import com.arthurrios.finova.ui.coachmarks.coachMarkTarget
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.history.BudgetForecastFigures
import com.arthurrios.finova.domain.history.BudgetHistory
import com.arthurrios.finova.domain.history.BudgetHistoryFilter
import com.arthurrios.finova.domain.history.BudgetHistoryMonth
import com.arthurrios.finova.domain.history.BudgetHistorySeries
import com.arthurrios.finova.domain.history.SavingsContributors
import com.arthurrios.finova.domain.model.Transaction
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
import java.time.format.DateTimeFormatter

private val CardShape = RoundedCornerShape(CornerRadius.ExtraLarge)
private val DayMonthYear: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/** The transaction list's row height, so the rows here read as the same kind of table. */
private val RowHeight = 60.dp

/** Where the screen scrolls after a drill (to the top) or a back (to the "Why" card). */
private enum class ScrollTarget { Top, Why }

/**
 * Past months of the budget and of each allocation, against their plans. Port of
 * BudgetHistoryViewController + BudgetHistoryContentView: what is shown and over how long, the
 * selected month with the chart, what it saved up to that month, why, and the months at a glance.
 *
 * Every control that changes the readout sits in or above the card it changes.
 */
@Composable
fun BudgetHistoryScreen(viewModel: BudgetHistoryViewModel, onBack: () -> Unit, onOpenTransaction: (Long) -> Unit = {}) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    fun tick() = haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
    val scroll = rememberScrollState()
    var whyOffset by remember { mutableIntStateOf(0) }
    var scrollTarget by remember { mutableStateOf<ScrollTarget?>(null) }
    var scrollRequest by remember { mutableIntStateOf(0) }
    val coachMarks = LocalCoachMarks.current
    CoachMarkLoading(!state.isLoaded)

    // Drilling in shows the chart of what was opened; going back returns to the card it came from.
    LaunchedEffect(scrollRequest) {
        val target = scrollTarget ?: return@LaunchedEffect
        withFrameNanos { }
        scroll.animateScrollTo(if (target == ScrollTarget.Top) 0 else whyOffset)
        scrollTarget = null
    }
    fun scrollTo(target: ScrollTarget) {
        scrollTarget = target
        scrollRequest++
    }

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
                .verticalScroll(scroll)
                .navigationBarsPadding()
                .padding(Spacing.S4),
        ) {
            // Grouped, so a hidden back button leaves no gap above the controls.
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
                state.filterTrail.lastOrNull()?.let { previous ->
                    BackToButton(previous.title()) {
                        tick()
                        viewModel.goBack()
                        scrollTo(ScrollTarget.Why)
                    }
                }
                Controls(state, onPick = { picking = true }, onSpan = {
                    tick()
                    if (it != state.span) coachMarks?.post(CoachMarkEvent.HistoryRangeChanged)
                    viewModel.selectSpan(it)
                })
            }
            ChartCard(state) { month ->
                if (month != state.displayedMonth) {
                    tick()
                    viewModel.selectMonth(month)
                    coachMarks?.post(CoachMarkEvent.HistoryMonthPicked)
                    if (viewModel.state.value.selectedForecast != null) coachMarks?.post(CoachMarkEvent.HistoryProjectedMonthPicked)
                }
            }
            // A month ahead has saved nothing, so its card replaces the two that read results.
            val forecast = state.selectedForecast
            if (forecast != null) {
                ForecastCard(state, forecast, onOpenTransaction)
            } else {
                SavingsCard(
                    state,
                    onStart = { tick(); viewModel.selectSavingsStart(it) },
                    onScope = {
                        tick()
                        viewModel.selectSavingsScope(it)
                        coachMarks?.post(CoachMarkEvent.HistorySavingsChanged)
                    },
                )
                state.contributors?.let { contributors ->
                    Box(Modifier.onGloballyPositioned { whyOffset = it.positionInParent().y.toInt() }) {
                        ContributorsCard(
                            state = state,
                            contributors = contributors,
                            onDrill = {
                                tick()
                                viewModel.drill(it)
                                scrollTo(ScrollTarget.Top)
                            },
                            onOpenTransaction = onOpenTransaction,
                        )
                    }
                }
            }
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
                val changed = it != state.filter
                viewModel.selectFilter(it)
                if (changed) coachMarks?.post(CoachMarkEvent.HistoryFilterChanged)
            },
        )
    }
}

@Composable
fun BudgetHistoryFilter.title(): String = when (this) {
    BudgetHistoryFilter.WholeMonth -> stringResource(R.string.history_filter_whole_month)
    is BudgetHistoryFilter.Category -> stringResource(category.label)
    BudgetHistoryFilter.OutsideAllocations -> stringResource(R.string.history_outside_title)
}

/** "October 2026". */
@Composable
fun longMonth(month: YearMonth): String = stringArrayResource(R.array.month_long)[month.monthValue - 1] + " ${month.year}"

/** "Aug, Sep". */
@Composable
private fun monthList(months: List<YearMonth>): String {
    val names = stringArrayResource(R.array.month_short)
    return months.joinToString(", ") { names[it.monthValue - 1] }
}

/** "May to Sep 2026", or one month's name: the months a Saved figure covers. */
@Composable
private fun periodTitle(first: YearMonth, last: YearMonth): String =
    if (first == last) longMonth(first)
    else stringResource(R.string.history_explain_earlier_format, stringArrayResource(R.array.month_short)[first.monthValue - 1], longMonth(last))

@Composable
private fun FilterIcon(filter: BudgetHistoryFilter, tint: Color, size: Dp) = when (filter) {
    BudgetHistoryFilter.WholeMonth -> Icon(Icons.Outlined.CalendarMonth, null, tint = tint, modifier = Modifier.size(size))
    is BudgetHistoryFilter.Category ->
        Icon(painterResource(filter.category.icon(TransactionType.Expense)), null, tint = tint, modifier = Modifier.size(size))
    BudgetHistoryFilter.OutsideAllocations -> DashedSquare(tint, size)
}

/** The outside filter's mark: a dashed square, for the part of the budget no category holds. */
@Composable
private fun DashedSquare(tint: Color, size: Dp) {
    Box(Modifier.size(size).padding(size / 8).drawBehind {
        drawRect(tint, style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 2.dp.toPx()))))
    })
}

/** "‹ Back to Whole month": shown only after drilling in, so the summary is one tap away. */
@Composable
private fun BackToButton(previous: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .height(32.dp)
            .clip(CircleShape)
            .background(FinovaColors.MainMagenta.copy(alpha = 0.1f))
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.S3),
    ) {
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(18.dp))
        Text(stringResource(R.string.history_back_format, previous), style = FinovaType.TextSMBold, color = FinovaColors.MainMagenta)
    }
}

// ---- Shared pieces (the app's table style) -----------------------------------------------------------

/**
 * A card in the app's table style: the CardHeader band (44dp, small uppercase grey title, optional
 * accessory) over a body, in one bordered card with a separator under the header.
 */
@Composable
private fun SectionCard(title: String, modifier: Modifier = Modifier, accessory: (@Composable () -> Unit)? = null, content: @Composable () -> Unit) {
    Column(modifier.card()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().height(44.dp).padding(start = Spacing.S5, end = Spacing.S4),
        ) {
            Text(
                title.uppercase(), style = FinovaType.Title2XS, color = FinovaColors.Gray500,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            accessory?.invoke()
        }
        Separator()
        content()
    }
}

/** The app's table separator: full width, 1dp, gray300. */
@Composable
private fun Separator() = Box(Modifier.fillMaxWidth().height(1.dp).background(FinovaColors.Gray300))

/** The transaction cell's icon box: 32dp, gray200, gray300 border, magenta glyph. */
@Composable
private fun IconBox(content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(CornerRadius.Medium)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.size(Spacing.S8).clip(shape).background(FinovaColors.Gray200).border(1.dp, FinovaColors.Gray300, shape),
    ) { content() }
}

/** A small band naming a group of rows, like a table section header. */
@Composable
private fun GroupLabel(text: String, tint: Color) {
    Text(
        text.uppercase(), style = FinovaType.Title2XS, color = tint,
        modifier = Modifier.fillMaxWidth().heightIn(min = 32.dp).background(FinovaColors.Gray200.copy(alpha = 0.5f))
            .padding(horizontal = Spacing.S5, vertical = 10.dp),
    )
}

/** One named contributor: an icon, a name, and how much it saved (green) or overspent (red). */
@Composable
private fun ContributorRow(
    icon: @Composable () -> Unit,
    title: String,
    amount: String,
    tint: Color,
    accessory: ImageVector,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
        modifier = Modifier.fillMaxWidth().heightIn(min = RowHeight).clickable(onClick = onClick).padding(horizontal = Spacing.S5, vertical = Spacing.S2),
    ) {
        IconBox(icon)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
            Text(title, style = FinovaType.TextSMBold, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis)
            subtitle?.let { Text(it, style = FinovaType.TextXS, color = FinovaColors.Gray500, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        Text(amount, style = FinovaType.TextSMBold, color = tint, maxLines = 1)
        Icon(accessory, null, tint = FinovaColors.Gray400, modifier = Modifier.size(16.dp))
    }
}

/** One expense in the transaction cell's style. A tap opens its details. */
@Composable
private fun ExpenseRow(transaction: Transaction, hidden: Boolean, currencyCode: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
        modifier = Modifier.fillMaxWidth().heightIn(min = RowHeight).clickable(onClick = onClick).padding(horizontal = Spacing.S5, vertical = Spacing.S2),
    ) {
        IconBox {
            Icon(painterResource(transaction.category.icon(transaction.type)), null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(16.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
            Text(transaction.title, style = FinovaType.TextSMBold, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                transaction.date.format(DayMonthYear) + " · " + stringResource(transaction.category.label),
                style = FinovaType.TextXS, color = FinovaColors.Gray500, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Text(Money.formatMasked(-transaction.amount, currencyCode, hidden), style = FinovaType.TextSMBold, color = FinovaColors.Gray700, maxLines = 1)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = FinovaColors.Gray400, modifier = Modifier.size(16.dp))
    }
}

/** The card's closing total, set off from the rows above like the details screens' footer. */
@Composable
private fun CardFooter(label: String, caption: String?, value: String, tint: Color) {
    Separator()
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = RowHeight).background(FinovaColors.Gray200.copy(alpha = 0.5f)).padding(horizontal = Spacing.S5, vertical = Spacing.S2),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = FinovaType.TextSMBold, color = FinovaColors.Gray700)
            caption?.let { Text(it, style = FinovaType.TextXS, color = FinovaColors.Gray500) }
        }
        Text(value, style = FinovaType.TextSMBold, color = tint, maxLines = 1)
    }
}

/** The tinted band an opened row shows its arithmetic in, indented to the row title. */
@Composable
private fun DetailBand(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(FinovaColors.Gray200.copy(alpha = 0.5f))
            .padding(start = Spacing.S5 + Spacing.S8 + Spacing.S3, end = Spacing.S5, top = Spacing.S3, bottom = Spacing.S3),
    ) { content() }
}

@Composable
private fun DetailLine(label: String, value: String, tint: Color = FinovaColors.Gray600, bold: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.S1)) {
        Text(label, style = if (bold) FinovaType.TextSMBold else FinovaType.TextSM, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(Spacing.S2))
        Text(value, style = if (bold) FinovaType.TextSMBold else FinovaType.TextSM, color = tint, maxLines = 1)
    }
}

@Composable
private fun Note(text: String) = Text(text, style = FinovaType.TextXS, color = FinovaColors.Gray500, modifier = Modifier.padding(top = Spacing.S1))

/**
 * Green for saved and red for over. What the open month has left so far ([soFar]) is grey: it is not
 * saved yet, and the days left can still use it. An overspend stays red - it cannot be undone.
 */
private fun outcomeTint(value: Long, hidden: Boolean, soFar: Boolean = false) = when {
    hidden -> FinovaColors.Gray700
    value < 0 -> FinovaColors.MainRed
    soFar -> FinovaColors.Gray700
    else -> FinovaColors.MainGreen
}

// ---- Controls --------------------------------------------------------------------------------------

/** What is shown, and over how long. One button opens the full list of filters. */
@Composable
private fun Controls(state: BudgetHistoryUiState, onPick: () -> Unit, onSpan: (HistorySpan) -> Unit) {
    val chooseLabel = stringResource(R.string.history_a11y_choose_filter)
    Row(verticalAlignment = Alignment.CenterVertically) {
        // The button keeps its own width; the box around it takes the room the switch leaves, so the
        // switch sits on the right edge and a long category name truncates instead of pushing it off.
        Box(Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.S2),
                modifier = Modifier
                    .coachMarkTarget(CoachMarkTarget.BudgetHistoryFilter)
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
        }
        if (state.offersLongerSpan) {
            Spacer(Modifier.width(Spacing.S3))
            SpanPicker(state.span, onSpan)
        }
    }
}

/** 6M / 12M. Hand-built, as on iOS: a capsule with the chosen option filled in magenta. */
@Composable
private fun SpanPicker(selected: HistorySpan, onSpan: (HistorySpan) -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier
            .coachMarkTarget(CoachMarkTarget.BudgetHistoryRange)
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

// ---- Chart card ------------------------------------------------------------------------------------

@Composable
private fun ChartCard(state: BudgetHistoryUiState, onSelect: (YearMonth) -> Unit) {
    val selected = state.selectedMonth
    val forecast = state.selectedForecast
    SectionCard(
        stringResource(R.string.history_section_chart),
        modifier = Modifier
            .coachMarkTarget(CoachMarkTarget.BudgetHistoryChart)
            .coachMarkTarget(CoachMarkTarget.BudgetHistoryProjected, enabled = state.forecastMonths.isNotEmpty()),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.S4), modifier = Modifier.padding(Spacing.S5)) {
            if (forecast != null) ForecastReadout(state, forecast, onSelect)
            else if (selected != null) Readout(state, selected, onSelect)
            BudgetHistoryChart(
                months = state.series.months,
                forecast = state.forecastMonths,
                selected = state.displayedMonth,
                valuesHidden = state.valuesHidden,
                currencyCode = state.currencyCode,
                onSelect = onSelect,
                modifier = Modifier.fillMaxWidth().height(210.dp),
            )
            Legend(state.forecastMonths)
        }
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
            if (month.isCurrent) {
                Text(
                    stringResource(R.string.history_status_in_progress),
                    fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.MainMagenta,
                    modifier = Modifier.clip(CircleShape).background(FinovaColors.MainMagenta.copy(alpha = 0.1f)).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        // Names the big number, which otherwise reads as a total of something unknown.
        Text(
            when (val filter = state.filter) {
                BudgetHistoryFilter.WholeMonth -> stringResource(R.string.history_readout_spent_whole)
                is BudgetHistoryFilter.Category -> stringResource(R.string.history_readout_spent_category_format, stringResource(filter.category.label))
                BudgetHistoryFilter.OutsideAllocations -> stringResource(R.string.history_readout_spent_outside)
            },
            fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.Gray500, modifier = Modifier.padding(top = Spacing.S1),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                Money.formatMasked(month.spent, state.currencyCode, hidden),
                style = FinovaType.TitleLG.copy(fontSize = 24.sp), color = FinovaColors.Gray700,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(Spacing.S2))
            StatusPill(month, hidden, state.currencyCode)
        }
        Text(planLine(state, month), style = FinovaType.TextXS, color = FinovaColors.Gray500)
    }
}

/**
 * A projected month, in the shape of [Readout] with its own words: a "Projected" badge where the open
 * month says "In progress", and expected costs where a past month says spent.
 */
@Composable
private fun ForecastReadout(state: BudgetHistoryUiState, month: BudgetForecastFigures, onSelect: (YearMonth) -> Unit) {
    val hidden = state.valuesHidden
    val code = state.currencyCode
    // A whole month with a balance leads with it. Its costs stay in the projected month card below.
    val balance = state.forecastBalance(month)
    val spoken = BudgetForecastText.accessibility(month, hidden, balance).map { it.text(code) }.joinToString(", ")
    Column(
        verticalArrangement = Arrangement.spacedBy(Spacing.S1),
        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = spoken },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StepButton(state.neighbour(-1), back = true, onSelect)
            Text(longMonth(month.month), style = FinovaType.TextSMBold, color = FinovaColors.Gray600)
            StepButton(state.neighbour(1), back = false, onSelect)
            Spacer(Modifier.weight(1f))
            Text(
                stringResource(R.string.history_forecast_badge),
                fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.Gray600,
                modifier = Modifier.clip(CircleShape).background(FinovaColors.Gray200).padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
        Text(
            if (balance != null) stringResource(R.string.history_forecast_readout_balance)
            else when (val filter = state.filter) {
                BudgetHistoryFilter.WholeMonth -> stringResource(R.string.history_forecast_expected_whole)
                is BudgetHistoryFilter.Category -> stringResource(R.string.history_forecast_expected_category_format, stringResource(filter.category.label))
                BudgetHistoryFilter.OutsideAllocations -> stringResource(R.string.history_forecast_line_outside)
            },
            fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.Gray500, modifier = Modifier.padding(top = Spacing.S1),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                Money.formatMasked(balance ?: month.expected, code, hidden),
                style = FinovaType.TitleLG.copy(fontSize = 24.sp), color = FinovaColors.Gray500,
                // Shrinks like iOS's minimum scale factor: a cut-off amount reads as a different amount.
                autoSize = TextAutoSize.StepBased(minFontSize = 14.sp, maxFontSize = 24.sp),
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(Spacing.S2))
            ForecastStatusPill(month, hidden, code)
        }
        Text(
            if (balance != null && month.hasPlan) stringResource(R.string.history_forecast_a11y_expected_of_format, Money.formatMasked(month.expected, code, hidden), Money.formatMasked(month.planned, code, hidden))
            else forecastPlanLine(month, hidden, code),
            style = FinovaType.TextXS, color = FinovaColors.Gray500,
        )
    }
}

@Composable
private fun forecastPlanLine(month: BudgetForecastFigures, hidden: Boolean, code: String): String {
    if (!month.hasPlan) return stringResource(BudgetForecastText.noPlan(month.filter))
    var line = stringResource(R.string.history_hero_of_format, Money.formatMasked(month.planned, code, hidden))
    if (!hidden) month.percentExpected?.let { line += " · " + stringResource(R.string.history_percent_format, it) }
    return line
}

/** Full amounts in the phone's format, in the string they belong to. */
@Composable
private fun ForecastText.text(code: String): String =
    if (amounts.isEmpty()) stringResource(text)
    else stringResource(text, *amounts.map { Money.format(it, code) }.toTypedArray())

/**
 * What a projected month has left or is short. Grey and amber, never the green and red of a result,
 * and no check mark: nothing here has happened yet.
 */
@Composable
private fun ForecastStatusPill(month: BudgetForecastFigures, hidden: Boolean, code: String) {
    val (tint, icon) = when (month.status) {
        BudgetForecastFigures.Status.Fits -> FinovaColors.Gray500 to Icons.Outlined.CalendarMonth
        BudgetForecastFigures.Status.Short -> FinovaColors.WarningAmber to Icons.Outlined.WarningAmber
        else -> FinovaColors.Gray500 to Icons.Filled.Remove
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.height(22.dp).clip(CircleShape).background(tint.copy(alpha = 0.1f)).padding(horizontal = Spacing.S2),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(11.dp))
        Text(BudgetForecastText.status(month, hidden).text(code), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = tint, maxLines = 1)
    }
}

/** One month back or forward, within the bars on screen. Next to the month name it changes. */
@Composable
private fun StepButton(target: YearMonth?, back: Boolean, onSelect: (YearMonth) -> Unit) {
    Box(
        contentAlignment = if (back) Alignment.CenterStart else Alignment.Center,
        modifier = Modifier.size(width = if (back) 20.dp else 28.dp, height = 28.dp).clickable(enabled = target != null) { target?.let(onSelect) },
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
private fun planLine(state: BudgetHistoryUiState, month: BudgetHistoryMonth): String {
    val hidden = state.valuesHidden
    if (!month.hasPlan) {
        // Outside allocations has no plan when the categories took the whole budget: say so, with by
        // how much, instead of a bare "nothing planned".
        if (state.filter == BudgetHistoryFilter.OutsideAllocations) {
            val (budget, inCategories) = state.budgetSplit(month.month)
            if (budget == 0L) return stringResource(R.string.history_readout_no_budget)
            val over = inCategories - budget
            return if (over > 0 && !hidden) stringResource(R.string.history_readout_categories_over_format, Money.format(over, state.currencyCode))
            else stringResource(R.string.history_readout_categories_full)
        }
        return stringResource(R.string.history_hero_no_plan)
    }
    var line = stringResource(R.string.history_hero_of_format, Money.formatMasked(month.planned, state.currencyCode, hidden))
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
        modifier = Modifier.height(22.dp).clip(CircleShape).background(tint.copy(alpha = 0.1f)).padding(horizontal = Spacing.S2),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(11.dp))
        Text(statusText(month, hidden, code), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = tint, maxLines = 1)
    }
}

/**
 * One row when it fits. With the forecast items a pt-BR row may not, and a squeezed label breaks
 * mid-word, so they drop to a second row, as on iOS. Labels never wrap.
 */
@Composable
private fun Legend(forecast: List<BudgetForecastFigures>) {
    Layout(
        content = {
            LegendItem(FinovaColors.MainMagenta, stringResource(R.string.history_legend_spent))
            LegendItem(FinovaColors.MainRed, stringResource(R.string.history_legend_over))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(width = 12.dp, height = 10.dp).drawBehind {
                    drawRoundRect(FinovaColors.Gray300, topLeft = androidx.compose.ui.geometry.Offset(1.dp.toPx(), 0f),
                        size = androidx.compose.ui.geometry.Size(10.dp.toPx(), 10.dp.toPx()),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
                    drawRect(FinovaColors.Gray600, size = androidx.compose.ui.geometry.Size(12.dp.toPx(), 2.dp.toPx()))
                })
                LegendLabel(stringResource(R.string.history_legend_plan))
            }
            if (forecast.isNotEmpty()) DashedLegendItem(FinovaColors.MainMagenta, stringResource(R.string.history_forecast_badge))
            if (forecast.any { it.hasPlan && it.inside > 0 && it.outsideWithinPlan > 0 }) {
                DashedLegendItem(FinovaColors.WarningAmber, stringResource(R.string.history_forecast_legend_outside))
            }
        },
        modifier = Modifier.fillMaxWidth(),
    ) { measurables, constraints ->
        val gap = Spacing.S4.roundToPx()
        val rowGap = Spacing.S2.roundToPx()
        val items = measurables.map { it.measure(constraints.copy(minWidth = 0, minHeight = 0)) }
        val rows = legendRows(items.map { it.width }, RecordedLegendItems, gap, constraints.maxWidth)
        val heights = rows.map { row -> row.maxOf { items[it].height } }
        val height = heights.sum() + rowGap * (rows.size - 1)
        layout(constraints.maxWidth, height) {
            var y = 0
            rows.forEachIndexed { index, row ->
                var x = 0
                row.forEach { item ->
                    items[item].placeRelative(x, y + (heights[index] - items[item].height) / 2)
                    x += items[item].width + gap
                }
                y += heights[index] + rowGap
            }
        }
    }
}

/** Spent, Over plan and Plan: what the forecast items drop below. */
private const val RecordedLegendItems = 3

/**
 * The legend's rows, as indices into [widths]. Everything on one row when it fits. If not, the items
 * from [breakAt] start their own row, and a row still too wide for [maxWidth] wraps between labels.
 */
internal fun legendRows(widths: List<Int>, breakAt: Int, gap: Int, maxWidth: Int): List<List<Int>> {
    if (widths.sum() + gap * (widths.size - 1) <= maxWidth) return listOf(widths.indices.toList())
    val rows = mutableListOf<MutableList<Int>>()
    var used = 0
    widths.forEachIndexed { index, width ->
        val current = rows.lastOrNull()
        if (current == null || index == breakAt || used + gap + width > maxWidth) {
            rows += mutableListOf(index)
            used = width
        } else {
            current += index
            used += gap + width
        }
    }
    return rows
}

@Composable
private fun LegendLabel(text: String) = Text(text, fontSize = 10.sp, color = FinovaColors.Gray500, maxLines = 1, softWrap = false)

@Composable
private fun LegendItem(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(color))
        LegendLabel(label)
    }
}

/** An outlined swatch: what a hatched bar is made of, too thin to hatch at this size. */
@Composable
private fun DashedLegendItem(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(10.dp).drawBehind {
            drawRoundRect(
                color,
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 1.5.dp.toPx()))),
            )
        })
        LegendLabel(label)
    }
}

// ---- Projected month -------------------------------------------------------------------------------

/**
 * The month's sum, then its place in the balance, then the rows already dated in it. Every line is a
 * forecast, and the note under the sum says so in words.
 */
@Composable
private fun ForecastCard(state: BudgetHistoryUiState, figures: BudgetForecastFigures, onOpenTransaction: (Long) -> Unit) {
    val detail = state.forecastDetail(figures) ?: return
    val hidden = state.valuesHidden
    val code = state.currencyCode
    val projection = detail.month.projection
    SectionCard(stringResource(R.string.history_forecast_card_title), Modifier.coachMarkTarget(CoachMarkTarget.BudgetHistoryForecastCard)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S5, vertical = Spacing.S3)) {
            ForecastSum(state, detail)
        }
        if (figures.filter == BudgetHistoryFilter.WholeMonth && projection != null) {
            Separator()
            Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S5, vertical = Spacing.S3)) {
                // A statement moves the balance, never the costs above: each purchase counts once.
                if (detail.month.statementsDue > 0) {
                    DetailLine(stringResource(R.string.history_forecast_statements), Money.formatMasked(-detail.month.statementsDue, code, hidden))
                }
                DetailLine(stringResource(R.string.history_forecast_balance), Money.formatMasked(projection.projected, code, hidden), bold = true)
                Note(stringResource(R.string.history_forecast_balance_note))
                if (detail.month.statementsDue > 0) Note(stringResource(R.string.history_forecast_statements_note))
            }
        }
        if (detail.biggest.isNotEmpty()) {
            Separator()
            GroupLabel(stringResource(R.string.history_forecast_line_scheduled), FinovaColors.Gray500)
            detail.biggest.forEach { transaction ->
                Separator()
                ExpenseRow(transaction, hidden, code) { onOpenTransaction(transaction.id) }
            }
        }
    }
}

@Composable
private fun ForecastSum(state: BudgetHistoryUiState, detail: BudgetHistoryUiState.ForecastDetail) {
    val figures = detail.figures
    val hidden = state.valuesHidden
    val code = state.currencyCode
    val outsideLabel = stringResource(R.string.history_forecast_line_outside)
    when (figures.filter) {
        BudgetHistoryFilter.WholeMonth -> {
            ForecastPlanLine(state, figures)
            DetailLine(stringResource(R.string.history_forecast_line_inside), Money.formatMasked(-figures.inside, code, hidden))
            DetailLine(outsideLabel, Money.formatMasked(-figures.outside, code, hidden))
        }
        is BudgetHistoryFilter.Category -> {
            ForecastPlanLine(state, figures)
            DetailLine(stringResource(R.string.history_forecast_line_scheduled), Money.formatMasked(-figures.expected, code, hidden))
        }
        BudgetHistoryFilter.OutsideAllocations -> {
            if (detail.month.budget > 0) {
                DetailLine(stringResource(R.string.history_explain_plan_whole_month), Money.formatMasked(detail.month.budget, code, hidden))
                DetailLine(stringResource(R.string.history_explain_in_categories), Money.formatMasked(-detail.month.allocated, code, hidden))
            }
            ForecastPlanLine(state, figures)
            DetailLine(outsideLabel, Money.formatMasked(-figures.outside, code, hidden))
        }
    }
    if (figures.hasPlan) {
        DetailLine(
            stringResource(if (figures.difference < 0) R.string.history_forecast_short else R.string.history_forecast_left),
            Money.formatMasked(kotlin.math.abs(figures.difference), code, hidden),
            tint = if (!hidden && figures.difference < 0) FinovaColors.WarningAmber else FinovaColors.Gray600,
            bold = true,
        )
    }
    Note(stringResource(if (figures.filter == BudgetHistoryFilter.WholeMonth) R.string.history_forecast_note_whole else R.string.history_forecast_note_rows))
}

/** The plan line, or the words for having none: a month with no plan never shows a zero. */
@Composable
private fun ForecastPlanLine(state: BudgetHistoryUiState, figures: BudgetForecastFigures) {
    DetailLine(
        planLabel(state),
        if (figures.hasPlan) Money.formatMasked(figures.planned, state.currencyCode, state.valuesHidden)
        else stringResource(BudgetForecastText.noPlan(figures.filter)),
    )
}

// ---- Savings ---------------------------------------------------------------------------------------

/**
 * What the chosen filter saved in closed months: from a start month the user picks up to the selected
 * one, or the selected month alone. The start menu only applies to the first.
 */
@Composable
private fun SavingsCard(state: BudgetHistoryUiState, onStart: (YearMonth?) -> Unit, onScope: (SavingsScope) -> Unit) {
    val savings = state.savings
    val hidden = state.valuesHidden
    val accessory: (@Composable () -> Unit)? =
        if (state.savingsScope == SavingsScope.UpTo) ({ SavingsStartMenu(state, onStart) }) else null
    SectionCard(stringResource(R.string.history_savings_title), Modifier.coachMarkTarget(CoachMarkTarget.BudgetHistorySavings), accessory = accessory) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2), modifier = Modifier.fillMaxWidth().padding(Spacing.S5)) {
            val selected = state.selectedMonth
            if (selected != null) {
                SavingsScopePicker(state.savingsScope, selected.month, onScope)
                Spacer(Modifier.height(Spacing.S2))
            }
            if (savings.months == 0) {
                // Under "only" it is that one month that had no plan.
                val none = if (state.savingsScope == SavingsScope.Only && selected != null) stringResource(R.string.history_savings_only_none_format, longMonth(selected.month))
                    else stringResource(R.string.history_savings_none)
                Text(none, style = FinovaType.TextSM, color = FinovaColors.Gray500)
            } else {
                Text(
                    Money.formatMasked(savings.net, state.currencyCode, hidden),
                    style = FinovaType.TitleLG.copy(fontSize = 24.sp), color = outcomeTint(savings.net, hidden, state.isSoFar), maxLines = 1,
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    // Both sides only when both have something; the net above already says one side.
                    if (!hidden && savings.saved > 0 && savings.overspent > 0) {
                        Text(
                            stringResource(if (state.isSoFar) R.string.history_savings_so_far_detail_format else R.string.history_savings_detail_format, Money.format(savings.saved, state.currencyCode), Money.format(savings.overspent, state.currencyCode)),
                            style = FinovaType.TextXS, color = FinovaColors.Gray500,
                        )
                    }
                    Text(savingsPeriod(state, savings), style = FinovaType.TextXS, color = FinovaColors.Gray500)
                }
            }
        }
    }
}

/**
 * "Up to Sep | Only Sep": the running total, or the selected month on its own. Named after the month so
 * it reads as a choice about that month, and it changes as the chart is scrubbed.
 */
@Composable
private fun SavingsScopePicker(selected: SavingsScope, month: YearMonth, onScope: (SavingsScope) -> Unit) {
    val name = stringArrayResource(R.array.month_short)[month.monthValue - 1]
    Row(
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.fillMaxWidth().clip(CircleShape).background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, CircleShape).padding(3.dp),
    ) {
        SavingsScope.entries.forEach { scope ->
            val isSelected = scope == selected
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(28.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) FinovaColors.MainMagenta else Color.Transparent)
                    .clickable(enabled = !isSelected) { onScope(scope) },
            ) {
                Text(
                    stringResource(if (scope == SavingsScope.UpTo) R.string.history_savings_through_format else R.string.history_savings_only_format, name),
                    fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    color = if (isSelected) Color.White else FinovaColors.Gray500,
                )
            }
        }
    }
}

/** "Up to September 2026 · 5 closed months": which months the figure adds up, so it is clear it moves with the chart. */
@Composable
private fun savingsPeriod(state: BudgetHistoryUiState, savings: BudgetHistorySeries.Savings): String {
    if (state.isSoFar) state.selectedMonth?.let { return stringResource(R.string.history_savings_so_far_format, longMonth(it.month)) }
    if (state.savingsScope == SavingsScope.Only) state.savingsEndMonth?.let { return longMonth(it) }
    val months = if (savings.months == 1) stringResource(R.string.history_savings_months_one) else stringResource(R.string.history_savings_months_format, savings.months)
    val end = state.savingsEndMonth ?: return months
    return stringResource(R.string.history_savings_through_format, longMonth(end)) + " · " + months
}

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
            androidx.compose.material3.HorizontalDivider(color = FinovaColors.Gray300)
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

// ---- What made Saved -------------------------------------------------------------------------------

/**
 * What made the Saved figure: the few parts that moved it most, then everything else in one line,
 * then the total, which is the Saved figure. Categories for the whole month, months otherwise.
 */
@Composable
private fun ContributorsCard(
    state: BudgetHistoryUiState,
    contributors: SavingsContributors,
    onDrill: (BudgetHistoryFilter) -> Unit,
    onOpenTransaction: (Long) -> Unit,
) {
    val hidden = state.valuesHidden
    var expanded by remember(state.filter) { mutableStateOf<SavingsContributors.Part?>(null) }
    var showsOthers by remember(state.filter) { mutableStateOf(false) }
    val title = if (hidden) stringResource(R.string.history_explain_header_hidden)
        else stringResource(R.string.history_explain_header_format, Money.format(contributors.total, state.currencyCode))

    @Composable
    fun row(item: SavingsContributors.Item) {
        ContributorItem(
            state, item, isOpen = expanded == item.part,
            onToggle = { expanded = if (expanded == item.part) null else item.part },
            onDrill = onDrill, onOpenTransaction = onOpenTransaction,
        )
    }

    SectionCard(title) {
        if (contributors.savers.isNotEmpty()) {
            GroupLabel(
                stringResource(if (state.isSoFar) R.string.history_contrib_left_so_far else R.string.history_contrib_saved),
                if (state.isSoFar) FinovaColors.Gray500 else FinovaColors.MainGreen,
            )
            contributors.savers.forEach { Separator(); row(it) }
        }
        if (contributors.overspenders.isNotEmpty()) {
            if (contributors.savers.isNotEmpty()) Separator()
            GroupLabel(stringResource(R.string.history_contrib_over), FinovaColors.MainRed)
            contributors.overspenders.forEach { Separator(); row(it) }
        }
        if (contributors.othersCount > 0) {
            Separator()
            // Opens to the parts it sums, biggest effect first, so nothing stays hidden.
            ContributorRow(
                icon = { Icon(Icons.Filled.MoreHoriz, null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(16.dp)) },
                title = stringResource(R.string.history_contrib_others_format, contributors.othersCount),
                amount = Money.formatMasked(contributors.others, state.currencyCode, hidden),
                // Coloured by direction like every named line, so it is clear which way the rest moved Saved.
                tint = outcomeTint(contributors.others, hidden, state.isSoFar),
                accessory = if (showsOthers) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
            ) { showsOthers = !showsOthers }
            if (showsOthers) contributors.rest.forEach { Separator(); row(it) }
        }
        val first = contributors.firstMonth
        val last = contributors.lastMonth
        CardFooter(
            label = stringResource(if (state.isSoFar) R.string.history_contrib_total_so_far else R.string.history_contrib_total),
            caption = if (first != null && last != null) periodTitle(first, last) else null,
            value = Money.formatMasked(contributors.total, state.currencyCode, hidden),
            tint = outcomeTint(contributors.total, hidden, state.isSoFar),
        )
    }
}

/** A category or Outside opens as its own view; a month or a difference opens in place. */
@Composable
private fun ContributorItem(
    state: BudgetHistoryUiState,
    item: SavingsContributors.Item,
    isOpen: Boolean,
    onToggle: () -> Unit,
    onDrill: (BudgetHistoryFilter) -> Unit,
    onOpenTransaction: (Long) -> Unit,
) {
    val hidden = state.valuesHidden
    val amount = Money.formatMasked(item.net, state.currencyCode, hidden)
    val tint = outcomeTint(item.net, hidden, state.isSoFar)
    val toggleIcon = if (isOpen) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown
    when (val part = item.part) {
        is SavingsContributors.Part.Category -> ContributorRow(
            icon = { FilterIcon(BudgetHistoryFilter.Category(part.category), FinovaColors.MainMagenta, 16.dp) },
            title = stringResource(part.category.label), amount = amount, tint = tint,
            accessory = Icons.AutoMirrored.Filled.KeyboardArrowRight,
        ) { onDrill(BudgetHistoryFilter.Category(part.category)) }
        SavingsContributors.Part.OutsideAllocations -> ContributorRow(
            icon = { FilterIcon(BudgetHistoryFilter.OutsideAllocations, FinovaColors.MainMagenta, 16.dp) },
            title = stringResource(R.string.history_outside_title), amount = amount, tint = tint,
            accessory = Icons.AutoMirrored.Filled.KeyboardArrowRight,
        ) { onDrill(BudgetHistoryFilter.OutsideAllocations) }
        is SavingsContributors.Part.Difference -> {
            val difference = state.outsideDifferences.firstOrNull { it.reason == part.reason }
            val label = difference?.let { differenceLabel(it) }
            ContributorRow(
                icon = { DashedSquare(FinovaColors.MainMagenta, 16.dp) },
                title = label?.first.orEmpty(), subtitle = label?.second, amount = amount, tint = tint, accessory = toggleIcon,
                onClick = onToggle,
            )
            if (isOpen && difference != null) DifferenceDetail(state, difference, onOpenTransaction)
        }
        is SavingsContributors.Part.Month -> {
            ContributorRow(
                icon = { Icon(Icons.Outlined.CalendarMonth, null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(16.dp)) },
                title = longMonth(part.month), amount = amount, tint = tint, accessory = toggleIcon, onClick = onToggle,
            )
            if (isOpen) MonthDetail(state, part.month, onOpenTransaction)
        }
    }
}

/** A short name that fits one row, and the detail for the grey line under it. */
@Composable
private fun differenceLabel(difference: BudgetHistory.OutsideDifference): Pair<String, String> {
    val months = monthList(difference.months)
    return when (difference.reason) {
        BudgetHistory.OutsideDifference.Reason.CategoriesAboveBudget ->
            stringResource(R.string.history_outside_diff_above_budget_title) to stringResource(R.string.history_outside_diff_above_budget_format, months)
        BudgetHistory.OutsideDifference.Reason.SpentOutsideWithNoRoom ->
            stringResource(R.string.history_outside_diff_spent_no_room_title) to stringResource(R.string.history_outside_diff_spent_no_room_format, months)
        BudgetHistory.OutsideDifference.Reason.NoMonthBudget ->
            stringResource(R.string.history_outside_diff_no_budget_title) to stringResource(R.string.history_outside_diff_no_budget_format, months)
        BudgetHistory.OutsideDifference.Reason.OtherMonth ->
            stringResource(R.string.history_outside_diff_other_month_title) to stringResource(R.string.history_outside_timing)
    }
}

@Composable
private fun planLabel(state: BudgetHistoryUiState): String = when (val filter = state.filter) {
    BudgetHistoryFilter.WholeMonth -> stringResource(R.string.history_explain_plan_whole_month)
    is BudgetHistoryFilter.Category -> stringResource(R.string.history_explain_plan_category_format, stringResource(filter.category.label))
    BudgetHistoryFilter.OutsideAllocations -> stringResource(R.string.history_explain_plan_outside)
}

/**
 * The month's own sum first (plan, spent, result) so its number adds up on the spot, then only the
 * three biggest expenses: enough to see what drove it, without repeating the dashboard list.
 */
@Composable
private fun MonthDetail(state: BudgetHistoryUiState, month: YearMonth, onOpenTransaction: (Long) -> Unit) {
    val detail = state.monthDetail(month) ?: return
    val hidden = state.valuesHidden
    val code = state.currencyCode
    DetailBand {
        val split = detail.budgetSplit
        if (split != null) {
            DetailLine(stringResource(R.string.history_explain_plan_whole_month), Money.formatMasked(split.first, code, hidden))
            DetailLine(stringResource(R.string.history_explain_in_categories), Money.formatMasked(-split.second, code, hidden))
            DetailLine("= " + planLabel(state), Money.formatMasked(detail.month.planned, code, hidden), bold = true)
        } else {
            DetailLine(planLabel(state), Money.formatMasked(detail.month.planned, code, hidden))
        }
        DetailLine(stringResource(R.string.history_explain_spent_format, detail.expenseCount), Money.formatMasked(-detail.month.spent, code, hidden))
        DetailLine("= " + longMonth(month), Money.formatMasked(detail.month.difference, code, hidden), tint = outcomeTint(detail.month.difference, hidden, state.isSoFar).takeIf { !hidden } ?: FinovaColors.Gray600, bold = true)
        // The question this answers: which expense made this number? None did.
        if (split != null && detail.month.difference > 0) Note(stringResource(R.string.history_explain_outside_unspent))
    }
    if (detail.biggest.isNotEmpty()) {
        Separator()
        GroupLabel(stringResource(R.string.history_contrib_top_expenses), FinovaColors.Gray500)
        detail.biggest.forEach { transaction ->
            Separator()
            ExpenseRow(transaction, hidden, code) { onOpenTransaction(transaction.id) }
        }
    }
}

/**
 * What a named difference is made of: the subtraction for months whose categories took the budget,
 * the very expenses for spending outside categories, a sentence for month timing.
 */
@Composable
private fun DifferenceDetail(state: BudgetHistoryUiState, difference: BudgetHistory.OutsideDifference, onOpenTransaction: (Long) -> Unit) {
    val hidden = state.valuesHidden
    val code = state.currencyCode
    when (difference.reason) {
        BudgetHistory.OutsideDifference.Reason.CategoriesAboveBudget, BudgetHistory.OutsideDifference.Reason.NoMonthBudget -> DetailBand {
            difference.months.forEach { month ->
                val (budget, inCategories) = state.budgetSplit(month)
                DetailLine(longMonth(month), "", bold = true)
                DetailLine(stringResource(R.string.history_explain_plan_whole_month), Money.formatMasked(budget, code, hidden))
                DetailLine(stringResource(R.string.history_explain_in_categories), Money.formatMasked(-inCategories, code, hidden))
                DetailLine("=", Money.formatMasked(budget - inCategories, code, hidden), tint = if (hidden) FinovaColors.Gray600 else FinovaColors.MainRed, bold = true)
            }
            Note(stringResource(R.string.history_diff_note_above_budget))
        }
        BudgetHistory.OutsideDifference.Reason.SpentOutsideWithNoRoom -> {
            DetailBand { Note(stringResource(R.string.history_diff_note_spent_no_room)) }
            state.outsideExpenses(difference.months).forEach { transaction ->
                Separator()
                ExpenseRow(transaction, hidden, code) { onOpenTransaction(transaction.id) }
            }
        }
        BudgetHistory.OutsideDifference.Reason.OtherMonth -> DetailBand { Note(stringResource(R.string.history_diff_note_other_month)) }
    }
}

// ---- At a glance -----------------------------------------------------------------------------------

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
    SectionCard(stringResource(R.string.history_section_insights)) {
        Row(Modifier.height(IntrinsicSize.Min)) {
            InsightTile(Icons.Filled.Verified, FinovaColors.MainGreen, stringResource(R.string.history_insight_on_plan_title), onPlan,
                stringResource(R.string.history_insight_on_plan_caption), Modifier.weight(1f))
            VerticalSeparator()
            InsightTile(Icons.Filled.SwapHoriz, FinovaColors.MainMagenta, stringResource(R.string.history_insight_range_title), range,
                stringResource(R.string.history_insight_range_caption), Modifier.weight(1f))
            VerticalSeparator()
            InsightTile(Icons.Filled.LocalFireDepartment, if (streak > 0) FinovaColors.WarningAmber else FinovaColors.Gray400,
                stringResource(R.string.history_insight_streak_title), streakValue, stringResource(R.string.history_insight_streak_caption), Modifier.weight(1f))
        }
    }
}

@Composable
private fun VerticalSeparator() = Box(Modifier.width(1.dp).fillMaxHeight().background(FinovaColors.Gray300))

@Composable
private fun InsightTile(icon: ImageVector, tint: Color, title: String, value: String, caption: String, modifier: Modifier) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1), modifier = modifier.padding(horizontal = Spacing.S4, vertical = Spacing.S3)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(12.dp))
            Text(title, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = FinovaColors.Gray500, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(value, style = FinovaType.TitleMD, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(caption, fontSize = 10.sp, lineHeight = 13.sp, color = FinovaColors.Gray400, maxLines = 2)
    }
}

// ---- Filter picker ---------------------------------------------------------------------------------

/**
 * Every filter in one list, each with what it saved over the same months as the Saved card, so the
 * list that picks a category also compares them. A system sheet on iOS, a Material bottom sheet here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterPickerSheet(state: BudgetHistoryUiState, onDismiss: () -> Unit, onPick: (BudgetHistoryFilter) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(), containerColor = FinovaColors.Gray100) { CoachMarkSheet {
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S1),
            modifier = Modifier.padding(start = Spacing.S5, end = Spacing.S5, bottom = Spacing.S3),
        ) {
            Text(stringResource(R.string.history_picker_title), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            // The months the amounts below count, in the words the Saved card uses.
            val selected = state.selectedMonth
            val period = if (state.savingsScope == SavingsScope.Only && selected != null) {
                if (state.isSoFar) stringResource(R.string.history_savings_so_far_format, longMonth(selected.month)) else longMonth(selected.month)
            }
                else savingsStartTitle(state.savingsStart) +
                    state.savingsEndMonth?.let { " · " + stringResource(R.string.history_savings_through_format, longMonth(it)) }.orEmpty()
            Text(
                stringResource(R.string.history_savings_title) + " · " + period,
                style = FinovaType.TextXS, color = FinovaColors.Gray500,
            )
        }
        LazyColumn(Modifier.heightIn(max = 560.dp).navigationBarsPadding()) {
            item { Separator() }
            items(state.filters, key = { it.toString() }) { filter ->
                FilterRow(state, filter, onPick)
                Separator()
            }
            state.outsideAllocations?.let { amount ->
                item {
                    OutsideRow(amount, state, onPick)
                    Separator()
                }
            }
        }
    } }
}

@Composable
private fun FilterRow(state: BudgetHistoryUiState, filter: BudgetHistoryFilter, onPick: (BudgetHistoryFilter) -> Unit) {
    val isSelected = filter == state.filter
    val savings = state.savings(filter)
    val hidden = state.valuesHidden
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
        modifier = Modifier.fillMaxWidth().heightIn(min = RowHeight).clickable { onPick(filter) }.padding(horizontal = Spacing.S5, vertical = Spacing.S3),
    ) {
        IconBox { FilterIcon(filter, FinovaColors.MainMagenta, 16.dp) }
        Text(filter.title(), style = FinovaType.TextSMBold, color = FinovaColors.Gray700, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(
            if (savings.months == 0) stringResource(R.string.history_insight_none) else Money.formatMasked(savings.net, state.currencyCode, hidden),
            style = FinovaType.TextSMBold, maxLines = 1,
            color = if (savings.months == 0 || hidden) FinovaColors.Gray500 else outcomeTint(savings.net, false, state.isSoFar),
        )
        Icon(Icons.Filled.Check, null, tint = if (isSelected) FinovaColors.MainMagenta else Color.Transparent, modifier = Modifier.size(16.dp))
    }
}

/**
 * The remainder, so the category rows plus this one add up to the whole month. Tapping it shows it
 * like a category: the unallocated budget as the plan, unplanned spending as what was spent.
 */
@Composable
private fun OutsideRow(amount: Long, state: BudgetHistoryUiState, onPick: (BudgetHistoryFilter) -> Unit) {
    val hidden = state.valuesHidden
    val isSelected = state.filter == BudgetHistoryFilter.OutsideAllocations
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3),
        modifier = Modifier.fillMaxWidth().heightIn(min = RowHeight).clickable { onPick(BudgetHistoryFilter.OutsideAllocations) }
            .padding(horizontal = Spacing.S5, vertical = Spacing.S3),
    ) {
        IconBox { DashedSquare(FinovaColors.MainMagenta, 16.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
            Text(stringResource(R.string.history_outside_title), style = FinovaType.TextSMBold, color = FinovaColors.Gray700)
            Text(stringResource(R.string.history_outside_caption), style = FinovaType.TextXS, color = FinovaColors.Gray500)
        }
        Text(
            if (hidden) HiddenValue else Money.format(amount, state.currencyCode),
            style = FinovaType.TextSMBold, maxLines = 1,
            color = if (hidden) FinovaColors.Gray500 else outcomeTint(amount, false, state.isSoFar),
        )
        Icon(Icons.Filled.Check, null, tint = if (isSelected) FinovaColors.MainMagenta else Color.Transparent, modifier = Modifier.size(16.dp))
    }
}

// ---- Empty -----------------------------------------------------------------------------------------

@Composable
private fun EmptyState() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S3, Alignment.CenterVertically),
        modifier = Modifier.fillMaxSize().padding(Spacing.S8),
    ) {
        Icon(Icons.Outlined.BarChart, null, tint = FinovaColors.Gray400, modifier = Modifier.size(40.dp))
        Text(stringResource(R.string.history_empty_title), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
        Text(stringResource(R.string.history_empty_message), style = FinovaType.TextSM, color = FinovaColors.Gray500, textAlign = TextAlign.Center)
    }
}

/** The white, bordered card every section on the light screens uses. */
private fun Modifier.card() = fillMaxWidth()
    .clip(CardShape)
    .background(FinovaColors.Gray100)
    .border(1.dp, FinovaColors.Gray300, CardShape)
