package com.arthurrios.finova.ui.dashboard

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.FinovaOutlinedButton
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius as FinovaCorners
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import com.arthurrios.finova.ui.format.localizedDayOfMonth

/**
 * The dark card at the top of each month. Port of MonthBudgetCard.swift: the balance for the
 * chosen day, a day slider, used vs. limit, and a status bar along the bottom edge.
 *
 * [balanceForDay] answers what the balance is on a given day of this month; the slider asks it
 * as the user drags.
 */
@Composable
fun MonthCard(
    page: MonthPageUi,
    currencyCode: String,
    valuesHidden: Boolean,
    balanceForDay: (Int) -> Long,
    onToggleValues: () -> Unit,
    onAdjustBalance: () -> Unit,
    onBudgetView: () -> Unit,
    onSettings: () -> Unit,
    onDefineBudget: () -> Unit,
    modifier: Modifier = Modifier,
    /** Set while a search or filter is on: the card shows the shown rows' total instead. */
    filteredTotal: Long? = null,
) {
    val daysInMonth = page.month.lengthOfMonth()
    val today = java.time.LocalDate.now().dayOfMonth
    // Current month opens on today; every other month on its last day, like iOS.
    val startDay = if (page.isCurrentMonth) today else daysInMonth
    var selectedDay by remember(page.month) { mutableStateOf(startDay) }
    val monthNames = stringArrayResource(R.array.month_short)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(FinovaCorners.ExtraLarge))
            .background(CardGradient),
    ) {
        Column(
            modifier = Modifier.padding(
                start = Spacing.S6, end = Spacing.S6, top = Spacing.S6, bottom = Spacing.S7,
            ),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = monthNames[page.month.monthValue - 1].uppercase(),
                    style = FinovaType.TitleSM,
                    color = FinovaColors.Gray100,
                )
                Spacer(Modifier.width(Spacing.S2))
                Text(text = "/ ${page.month.year}", style = FinovaType.TitleXS, color = FinovaColors.Gray400)
                Spacer(Modifier.weight(1f))
                if (!page.hasBudget) {
                    HideValuesButton(valuesHidden, onToggleValues)
                    Spacer(Modifier.width(Spacing.S2))
                }
                CompactIconButton(onClick = onBudgetView, size = Spacing.S6) {
                    Icon(
                        imageVector = Icons.Filled.PieChart,
                        contentDescription = stringResource(R.string.month_card_budget_view),
                        tint = FinovaColors.Gray100,
                        // Same box as the gear; the Material glyph has its own padding inside.
                        modifier = Modifier.size(Spacing.S6),
                    )
                }
                Spacer(Modifier.width(Spacing.S3))
                CompactIconButton(onClick = onSettings, size = Spacing.S6) {
                    Icon(
                        painter = painterResource(R.drawable.ic_settings_icon),
                        contentDescription = stringResource(R.string.month_card_settings),
                        tint = FinovaColors.Gray100,
                        modifier = Modifier.size(Spacing.S6),
                    )
                }
            }
            Spacer(Modifier.height(Spacing.S4))
            HorizontalDivider(color = FinovaColors.OpaqueWhite)
            Spacer(Modifier.height(Spacing.S3))

            if (filteredTotal != null && !page.hasBudget) {
                // No budget, so no balance row to borrow: the total takes the button's place.
                FilteredLabel()
                Spacer(Modifier.height(Spacing.S3))
                Text(
                    text = Money.formatMasked(filteredTotal, currencyCode, valuesHidden),
                    style = FinovaType.TitleLG,
                    color = FinovaColors.Gray100,
                )
            } else if (page.hasBudget) {
                val balance = filteredTotal ?: balanceForDay(selectedDay)
                if (filteredTotal != null) {
                    FilteredLabel()
                } else {
                    Text(
                        text = stringResource(R.string.month_card_balance_on_day, localizedDayOfMonth(selectedDay)),
                        style = FinovaType.TextSM,
                        color = FinovaColors.Gray400,
                    )
                }
                Spacer(Modifier.height(Spacing.S3))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
                    val adjustLabel = stringResource(R.string.month_card_adjust_balance)
                    Text(
                        text = Money.formatMasked(balance, currencyCode, valuesHidden),
                        style = FinovaType.TitleLG,
                        color = FinovaColors.Gray100,
                        // Holding the balance adjusts it, as on iOS (the button next to it does too).
                        modifier = Modifier
                            .weight(1f)
                            .pointerInput(onAdjustBalance) {
                                detectTapGestures(onLongPress = {
                                    haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                                    onAdjustBalance()
                                })
                            }
                            .semantics { onLongClick(label = adjustLabel) { onAdjustBalance(); true } },
                    )
                    AdjustBalanceButton(onAdjustBalance)
                    HideValuesButton(valuesHidden, onToggleValues)
                }
                Spacer(Modifier.height(Spacing.S3))
                DaySlider(
                    day = selectedDay,
                    daysInMonth = daysInMonth,
                    todayInMonth = if (page.isCurrentMonth) today else null,
                    onDayChange = { selectedDay = it },
                )
            } else {
                FinovaOutlinedButton(
                    text = stringResource(R.string.month_card_define_budget),
                    onClick = onDefineBudget,
                )
            }
            Spacer(Modifier.height(Spacing.S2))

            Row {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2), modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.month_card_used_budget), style = FinovaType.TextXS, color = FinovaColors.Gray400)
                    Text(
                        Money.formatMasked(page.usedValue, currencyCode, valuesHidden),
                        style = FinovaType.TextSM,
                        color = FinovaColors.Gray100,
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2), horizontalAlignment = Alignment.End) {
                    Text(stringResource(R.string.month_card_limit_budget), style = FinovaType.TextXS, color = FinovaColors.Gray400)
                    if (page.hasBudget) {
                        Text(
                            Money.formatMasked(page.budgetLimit ?: 0, currencyCode, valuesHidden),
                            style = FinovaType.TextSM,
                            color = FinovaColors.Gray100,
                        )
                    } else {
                        Image(painterResource(R.drawable.ic_infinity), contentDescription = null, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
        if (page.hasBudget) {
            BudgetStatusBar(
                used = page.usedValue,
                limit = page.budgetLimit ?: 0,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }
}

/** MonthBudgetCard's filtered indicator: a small magenta filter badge and "Filtered total". */
@Composable
private fun FilteredLabel() {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(20.dp).background(FinovaColors.MainMagenta, RoundedCornerShape(4.dp)),
        ) {
            Icon(
                painterResource(R.drawable.ic_filter),
                contentDescription = null,
                tint = FinovaColors.Gray100,
                modifier = Modifier.size(12.dp),
            )
        }
        Spacer(Modifier.width(Spacing.S2))
        Text(stringResource(R.string.filter_result_label), style = FinovaType.TextSM, color = FinovaColors.MainMagenta)
    }
}

/** The bar along the card's bottom edge: magenta under 75%, amber from 75%, red over the limit. */
@Composable
internal fun BudgetStatusBar(used: Long, limit: Long, modifier: Modifier = Modifier) {
    val fraction = if (limit > 0) used.toFloat() / limit else 0f
    val color = when {
        fraction > 1f -> FinovaColors.MainRed
        fraction >= 0.75f -> FinovaColors.WarningAmber
        else -> FinovaColors.MainMagenta
    }
    val progress by animateFloatAsState(fraction.coerceIn(0f, 1f), label = "budget")
    LinearProgressIndicator(
        progress = { progress },
        color = color,
        trackColor = FinovaColors.Gray600,
        strokeCap = StrokeCap.Round,
        gapSize = 0.dp,
        drawStopIndicator = {},
        modifier = modifier.fillMaxWidth().height(8.dp),
    )
}

/**
 * Picks the day whose balance the card shows. It is the Material 3 slider (native drag and
 * accessibility) drawn like the iOS DaySlider: a 4dp track, a round white thumb with a soft
 * shadow, a small tick per day, and a tall white tick on today in the current month.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DaySlider(day: Int, daysInMonth: Int, todayInMonth: Int?, onDayChange: (Int) -> Unit) {
    Slider(
        value = day.toFloat(),
        onValueChange = { onDayChange(it.roundToInt()) },
        valueRange = 1f..daysInMonth.toFloat(),
        steps = (daysInMonth - 2).coerceAtLeast(0),
        thumb = {
            Box(
                Modifier
                    .size(24.dp)
                    .shadow(4.dp, CircleShape, ambientColor = FinovaColors.Gray700, spotColor = FinovaColors.Gray700)
                    .background(FinovaColors.Gray100, CircleShape),
            )
        },
        track = { sliderState ->
            DaySliderTrack(
                fraction = (sliderState.value - 1f) / (daysInMonth - 1).coerceAtLeast(1),
                selectedDay = day,
                daysInMonth = daysInMonth,
                todayInMonth = todayInMonth,
            )
        },
        modifier = Modifier.fillMaxWidth().height(40.dp),
    )
}

@Composable
private fun DaySliderTrack(fraction: Float, selectedDay: Int, daysInMonth: Int, todayInMonth: Int?) {
    Canvas(Modifier.fillMaxWidth().height(16.dp)) {
        val trackHeight = 4.dp.toPx()
        val y = size.height / 2
        val radius = CornerRadius(trackHeight / 2)
        drawRoundRect(
            color = FinovaColors.Gray600,
            topLeft = Offset(0f, y - trackHeight / 2),
            size = Size(size.width, trackHeight),
            cornerRadius = radius,
        )
        drawRoundRect(
            color = FinovaColors.MainMagenta,
            topLeft = Offset(0f, y - trackHeight / 2),
            size = Size(size.width * fraction.coerceIn(0f, 1f), trackHeight),
            cornerRadius = radius,
        )
        val tickWidth = 2.dp.toPx()
        for (d in 1..daysInMonth) {
            val x = if (daysInMonth == 1) 0f else size.width * (d - 1) / (daysInMonth - 1)
            val (color, height) = when {
                d == selectedDay -> FinovaColors.MainMagenta to 1.5.dp.toPx()
                d == todayInMonth -> FinovaColors.Gray100 to 16.dp.toPx()
                else -> FinovaColors.Gray400.copy(alpha = 0.6f) to 1.dp.toPx()
            }
            drawRoundRect(
                color = color,
                topLeft = Offset(x - tickWidth / 2, y - height / 2),
                size = Size(tickWidth, height),
                cornerRadius = CornerRadius(tickWidth / 2),
            )
        }
    }
}

@Composable
private fun HideValuesButton(hidden: Boolean, onToggle: () -> Unit) {
    CompactIconButton(onClick = onToggle, size = HideValuesButtonSize) {
        Icon(
            painter = painterResource(if (hidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
            contentDescription = stringResource(
                if (hidden) R.string.month_card_show_values else R.string.month_card_hide_values
            ),
            tint = FinovaColors.Gray100,
            modifier = Modifier.size(24.dp),
        )
    }
}

/** iOS opens a menu from this button; so does Android. */
@Composable
private fun AdjustBalanceButton(onAdjust: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        CompactIconButton(onClick = { open = true }, size = HideValuesButtonSize) {
            Icon(
                imageVector = Icons.Outlined.Edit,
                contentDescription = stringResource(R.string.month_card_adjust_balance),
                tint = FinovaColors.Gray100,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text(
                text = stringResource(R.string.month_card_balance_menu_title),
                style = FinovaType.TextXS,
                color = FinovaColors.Gray500,
                modifier = Modifier.padding(horizontal = Spacing.S4, vertical = Spacing.S2),
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.month_card_adjust_balance)) },
                leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) },
                onClick = {
                    open = false
                    onAdjust()
                },
            )
        }
    }
}

/** Metrics.hideValuesButtonSize on iOS. */
private val HideValuesButtonSize = 36.dp

/**
 * An icon button at the iOS size. Material pads every icon button out to a 48dp touch area,
 * which made the card taller than on iOS; these keep the iOS footprint instead.
 */
@Composable
internal fun CompactIconButton(onClick: () -> Unit, size: Dp, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides Dp.Unspecified) {
        IconButton(onClick = onClick, modifier = Modifier.size(size), content = content)
    }
}

/** Colors.gradientBlack on iOS. */
internal val CardGradient = Brush.horizontalGradient(listOf(FinovaColors.Gray700, FinovaColors.GradientBlackEnd))
