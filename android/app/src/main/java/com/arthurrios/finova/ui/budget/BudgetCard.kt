package com.arthurrios.finova.ui.budget

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.outlined.PieChart
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.AllocationBalanceProjection
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.dashboard.BudgetStatusBar
import com.arthurrios.finova.ui.dashboard.CardGradient
import com.arthurrios.finova.ui.dashboard.CompactIconButton
import com.arthurrios.finova.ui.dashboard.MonthPageUi
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import kotlin.math.atan2
import kotlin.math.hypot

/** One slice of the donut: an allocation, off-plan spending, or budget no allocation covers. */
private sealed interface Slice {
    val amount: Long
    data class Allocated(val category: TransactionCategory, override val amount: Long) : Slice
    data class OffPlan(val category: TransactionCategory, override val amount: Long) : Slice
    data class Headroom(override val amount: Long) : Slice
}

/**
 * The back of the month card: port of BudgetCard.swift. The month's allocations as a donut, the
 * closing balance and the projection in its top corners, a bar comparing what survives the plan
 * with what was saved and overspent, and the unallocated and used amounts underneath.
 */
@Composable
fun BudgetCard(
    page: MonthPageUi,
    currencyCode: String,
    valuesHidden: Boolean,
    onFlipBack: () -> Unit,
    onSettings: () -> Unit,
    onDefineBudget: () -> Unit,
    onOpenCategory: (TransactionCategory) -> Unit,
    modifier: Modifier = Modifier,
) {
    val monthNames = stringArrayResource(R.array.month_short)
    val summary = page.unallocated
    val hasContent = summary.totalBudget > 0 || page.allocations.isNotEmpty()
    val projection = page.finalBalance?.let { base ->
        AllocationBalanceProjection.of(
            base = base,
            allocations = page.allocations,
            unallocatedSpending = summary.usedInUnallocatedCategories,
            unallocatedHeadroom = summary.unallocated,
            deferredCardSpending = page.deferredCardSpending,
            tense = if (page.isPastMonth) AllocationBalanceProjection.Tense.Actual else AllocationBalanceProjection.Tense.Projected,
        )
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(CornerRadius.ExtraLarge))
            .background(CardGradient),
    ) {
        Column(Modifier.padding(start = Spacing.S6, end = Spacing.S6, top = Spacing.S6, bottom = Spacing.S7)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(monthNames[page.month.monthValue - 1].uppercase(), style = FinovaType.TitleSM, color = FinovaColors.Gray100)
                Spacer(Modifier.width(Spacing.S2))
                Text("/ ${page.month.year}", style = FinovaType.TitleXS, color = FinovaColors.Gray400)
                Spacer(Modifier.weight(1f))
                // The pie shows filled while this face is up, like the iOS flip button.
                CompactIconButton(onClick = onFlipBack, size = Spacing.S6) {
                    Icon(Icons.Outlined.PieChart, contentDescription = stringResource(R.string.budget_flip_back),
                        tint = FinovaColors.MainMagenta, modifier = Modifier.size(Spacing.S6))
                }
                Spacer(Modifier.width(Spacing.S3))
                CompactIconButton(onClick = onSettings, size = Spacing.S6) {
                    Icon(painterResource(R.drawable.ic_settings_icon), contentDescription = stringResource(R.string.month_card_settings),
                        tint = FinovaColors.Gray100, modifier = Modifier.size(Spacing.S6))
                }
            }
            Spacer(Modifier.height(Spacing.S4))
            HorizontalDivider(color = FinovaColors.OpaqueWhite)
            Spacer(Modifier.height(Spacing.S3))

            if (!hasContent) {
                // No budget and no allocations: invite the user to set one.
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(Spacing.S4),
                    modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.S4),
                ) {
                    Icon(Icons.Filled.PieChart, contentDescription = null, tint = FinovaColors.Gray500, modifier = Modifier.size(40.dp))
                    Text(stringResource(R.string.budget_no_budget), style = FinovaType.TextSM, color = FinovaColors.Gray400, textAlign = TextAlign.Center)
                    FinovaAccentOutlinedButton(text = stringResource(R.string.month_card_define_budget), onClick = onDefineBudget)
                }
                return@Column
            }

            Box(Modifier.fillMaxWidth()) {
                Donut(page, currencyCode, valuesHidden, onOpenCategory, Modifier.align(Alignment.Center).size(170.dp))
                page.finalBalance?.let { balance ->
                    CornerBlock(
                        caption = stringResource(R.string.budget_by_day, "${monthNames[page.month.monthValue - 1]} ${page.month.lengthOfMonth()}"),
                        value = Money.compactMasked(balance, currencyCode, valuesHidden),
                        color = if (!valuesHidden && balance < 0) FinovaColors.BrightRed else FinovaColors.Gray100,
                        alignEnd = false,
                        modifier = Modifier.align(Alignment.TopStart),
                    )
                }
                projection?.let { p ->
                    val (caption, value) = when (p.tense) {
                        AllocationBalanceProjection.Tense.Projected ->
                            stringResource(R.string.budget_if_fully_used) to Money.compactMasked(p.projected, currencyCode, valuesHidden)
                        AllocationBalanceProjection.Tense.Actual ->
                            stringResource(if (p.netSaved < 0) R.string.budget_overspent_label else R.string.budget_saved_label) to
                                Money.compactMasked(kotlin.math.abs(p.netSaved), currencyCode, valuesHidden)
                    }
                    val bad = p.netSaved < 0 || p.isOverCommitted
                    CornerBlock(
                        caption = caption,
                        value = value,
                        color = when {
                            valuesHidden -> FinovaColors.Gray100
                            bad -> FinovaColors.BrightRed
                            else -> FinovaColors.BrightGreen
                        },
                        alignEnd = true,
                        modifier = Modifier.align(Alignment.TopEnd),
                    )
                }
            }
            projection?.let {
                Spacer(Modifier.height(Spacing.S3))
                ProjectionBar(it)
            }
            Spacer(Modifier.height(Spacing.S3))
            Row {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2), modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.budget_unallocated), style = FinovaType.TextXS, color = FinovaColors.Gray400)
                    val unallocated = summary.unallocated
                    Text(
                        when {
                            valuesHidden -> Money.formatMasked(0, currencyCode, true)
                            unallocated >= 0 -> Money.format(unallocated, currencyCode)
                            else -> "-" + Money.format(-unallocated, currencyCode)
                        },
                        style = FinovaType.TextSM,
                        // Amber when more is allocated than the budget allows.
                        color = if (!valuesHidden && unallocated < 0) FinovaColors.WarningAmber else FinovaColors.Gray100,
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2), horizontalAlignment = Alignment.End) {
                    Text(stringResource(R.string.budget_used), style = FinovaType.TextXS, color = FinovaColors.Gray400)
                    Text(Money.formatMasked(page.usedValue, currencyCode, valuesHidden), style = FinovaType.TextSM, color = FinovaColors.Gray100)
                }
            }
        }
        if (hasContent) {
            // The same spend gauge as the front face: used against the budget limit.
            BudgetStatusBar(used = page.usedValue, limit = page.budgetLimit ?: 0, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun CornerBlock(caption: String, value: String, color: Color, alignEnd: Boolean, modifier: Modifier) {
    Column(
        horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(Spacing.S1),
        modifier = modifier.width(72.dp),
    ) {
        Text(caption, style = FinovaType.Title2XS, color = FinovaColors.Gray400, maxLines = 2, textAlign = if (alignEnd) TextAlign.End else TextAlign.Start)
        Text(value, style = FinovaType.TextSMBold, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Projected (magenta), saved (green) and overspent (red) shares, on the gray track. */
@Composable
private fun ProjectionBar(projection: AllocationBalanceProjection) {
    val (projected, saved, overspent) = projection.barShares
    Canvas(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp))) {
        drawRect(FinovaColors.Gray600)
        var x = 0f
        listOf(projected to FinovaColors.MainMagenta, saved to FinovaColors.BrightGreen, overspent to FinovaColors.BrightRed).forEach { (share, color) ->
            val w = size.width * share
            if (w > 0) drawRect(color, topLeft = Offset(x, 0f), size = Size(w, size.height))
            x += w
        }
    }
}

/**
 * Port of BudgetDonutChartView (without the tag ring). Slices: allocations biggest first, then
 * off-plan spending, then unallocated headroom. Tapping a slice shows it in the centre; tapping an
 * allocation again opens it.
 */
@Composable
private fun Donut(
    page: MonthPageUi,
    currencyCode: String,
    valuesHidden: Boolean,
    onOpenCategory: (TransactionCategory) -> Unit,
    modifier: Modifier,
) {
    val slices = remember(page.allocations, page.offPlan, page.unallocated) {
        buildList<Slice> {
            page.allocations.sortedWith(compareByDescending<com.arthurrios.finova.domain.allocation.BudgetAllocation> { it.allocated }.thenBy { it.category.key })
                .forEach { add(Slice.Allocated(it.category, it.allocated)) }
            page.offPlan.sortedWith(compareByDescending<com.arthurrios.finova.domain.allocation.UnallocatedSpending> { it.spent }.thenBy { it.category.key })
                .forEach { add(Slice.OffPlan(it.category, it.spent)) }
            page.unallocated.unallocated.takeIf { it > 0 }?.let { add(Slice.Headroom(it)) }
        }
    }
    var selected by remember(page.month) { mutableStateOf<Slice?>(null) }
    val total = slices.sumOf { it.amount }.coerceAtLeast(1)
    val maxAllocated = page.allocations.maxOfOrNull { it.allocated }?.coerceAtLeast(1) ?: 1

    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(
            Modifier
                .matchParentSize()
                .pointerInput(slices) {
                    detectTapGestures { tap ->
                        val center = Offset(size.width / 2f, size.height / 2f)
                        val radius = size.width / 2f
                        val distance = hypot(tap.x - center.x, tap.y - center.y)
                        if (distance < radius * 0.65f || distance > radius) {
                            selected = null
                            return@detectTapGestures
                        }
                        // Angle from 12 o'clock, clockwise, as the slices are drawn.
                        var angle = Math.toDegrees(atan2((tap.y - center.y).toDouble(), (tap.x - center.x).toDouble())) + 90
                        if (angle < 0) angle += 360
                        var start = 0.0
                        val hit = slices.firstOrNull { slice ->
                            val sweep = slice.amount.toDouble() / total * 360
                            (angle >= start && angle < start + sweep).also { start += sweep }
                        }
                        if (hit is Slice.Allocated && hit == selected) onOpenCategory(hit.category)
                        selected = if (hit == selected) null else hit
                    }
                },
        ) {
            val stroke = size.minDimension * 0.35f / 2f
            val arcSize = Size(size.width - stroke, size.height - stroke)
            val topLeft = Offset(stroke / 2, stroke / 2)
            if (slices.isEmpty()) {
                drawArc(FinovaColors.Gray600.copy(alpha = 0.5f), 0f, 360f, false, topLeft, arcSize, style = Stroke(stroke))
                return@Canvas
            }
            var start = -90f
            slices.forEach { slice ->
                val sweep = slice.amount.toFloat() / total * 360f
                val gap = if (slices.size > 1) 2f else 0f
                val base = when (slice) {
                    is Slice.Allocated -> allocationColor(slice.amount, maxAllocated)
                    is Slice.OffPlan -> FinovaColors.Gray500.copy(alpha = 0.8f)
                    is Slice.Headroom -> FinovaColors.Gray600.copy(alpha = 0.5f)
                }
                val dimmed = selected != null && selected != slice
                drawArc(
                    color = if (dimmed) base.copy(alpha = base.alpha * 0.35f) else base,
                    startAngle = start + gap / 2,
                    sweepAngle = (sweep - gap).coerceAtLeast(0.5f),
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(stroke),
                )
                start += sweep
            }
        }
        DonutCenter(selected, page, currencyCode, valuesHidden)
    }
}

/** Magenta, darker for smaller allocations (the iOS brightness ramp, 35% to 100%). */
private fun allocationColor(amount: Long, max: Long): Color {
    val hsv = FloatArray(3)
    android.graphics.Color.colorToHSV(android.graphics.Color.rgb(220, 84, 222), hsv)
    hsv[2] = hsv[2] * (0.35f + 0.65f * (amount.toFloat() / max))
    return Color(android.graphics.Color.HSVToColor(hsv))
}

@Composable
private fun DonutCenter(selected: Slice?, page: MonthPageUi, currencyCode: String, valuesHidden: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.width(85.dp)) {
        when (selected) {
            is Slice.Allocated -> {
                Icon(painterResource(selected.category.icon(TransactionType.Expense)), null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(24.dp))
                CenterLabel(stringResource(selected.category.label))
                CenterValue(Money.compactMasked(selected.amount, currencyCode, valuesHidden))
            }
            is Slice.OffPlan -> {
                Icon(painterResource(selected.category.icon(TransactionType.Expense)), null, tint = FinovaColors.Gray400, modifier = Modifier.size(24.dp))
                CenterLabel(stringResource(selected.category.label))
                CenterValue(Money.compactMasked(selected.amount, currencyCode, valuesHidden))
            }
            is Slice.Headroom -> {
                Icon(Icons.AutoMirrored.Outlined.HelpOutline, null, tint = FinovaColors.Gray400, modifier = Modifier.size(24.dp))
                CenterLabel(stringResource(R.string.budget_unallocated))
                CenterValue(Money.compactMasked(selected.amount, currencyCode, valuesHidden))
            }
            null -> if (page.allocations.isEmpty() && page.offPlan.isEmpty()) {
                Text("0%", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = FinovaColors.Gray400)
                Text(stringResource(R.string.budget_allocated_label), fontSize = 11.sp, color = FinovaColors.Gray500)
            } else {
                Text(Money.compactMasked(page.unallocated.totalBudget, currencyCode, valuesHidden), fontSize = 16.sp,
                    fontWeight = FontWeight.Bold, color = FinovaColors.Gray100, maxLines = 1)
                Text(stringResource(R.string.budget_total_label), fontSize = 11.sp, color = FinovaColors.Gray400, maxLines = 1)
            }
        }
    }
}

@Composable
private fun CenterLabel(text: String) =
    Text(text, fontSize = 10.sp, fontWeight = FontWeight.Medium, color = FinovaColors.Gray300, maxLines = 1, overflow = TextOverflow.Ellipsis)

@Composable
private fun CenterValue(text: String) = Text(text, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = FinovaColors.Gray100, maxLines = 1)
