package com.arthurrios.finova.ui.history

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.history.BudgetHistoryMonth
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.FinovaColors
import java.time.YearMonth
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/**
 * One bar per month: what was spent, drawn over what was planned. Port of BudgetHistoryChartView.
 *
 * Each column is up to four marks, all from zero so none stack:
 * - a grey bar to the plan: the room the month had;
 * - a red bar to what was spent, only when the month went over;
 * - a magenta bar to the smaller of spent and plan, over the red one, so the red left showing is
 *   exactly the overspend;
 * - a dark tick at the plan, so the line the month was measured against stays visible.
 *
 * iOS draws it with Swift Charts; Compose has no chart component, so it is drawn on a Canvas.
 */
@Composable
fun BudgetHistoryChart(
    months: List<BudgetHistoryMonth>,
    selected: YearMonth?,
    valuesHidden: Boolean,
    currencyCode: String,
    modifier: Modifier = Modifier,
    /** The chart in the allocation details preview: no amount axis, no percent labels, no touch. */
    compact: Boolean = false,
    contentDescription: String? = null,
    onSelect: (YearMonth) -> Unit = {},
) {
    val measurer = rememberTextMeasurer()
    val shortMonths = stringArrayResource(R.array.month_short)
    val currentMonths by rememberUpdatedState(months)
    val currentSelect by rememberUpdatedState(onSelect)

    // Percent labels only while they have room: twelve columns on a phone are narrower than "112%".
    val showsPercent = !compact && months.size <= 6
    val barRatio = if (months.size <= 6) 0.5f else 0.62f
    val maxValue = (months.maxOfOrNull { maxOf(it.planned, it.spent) } ?: 0L).coerceAtLeast(1)
    val yTop = maxValue * (if (showsPercent) 1.2 else 1.06)
    val ticks = if (compact) emptyList() else niceTicks(yTop)

    val axisStyle = TextStyle(fontSize = 10.sp, color = FinovaColors.Gray400)
    val axisLabels = if (valuesHidden) emptyList() else ticks.map { Money.compact(it.toLong(), currencyCode) }
    val axisWidthPx = axisLabels.maxOfOrNull { measurer.measure(it, axisStyle).size.width } ?: 0

    var gesture = modifier.semantics { contentDescription?.let { this.contentDescription = it } }
    if (!compact) {
        // A tap selects a month; a sideways drag scrubs across months, as on iOS. Sideways only, so the
        // screen still scrolls up and down over the chart.
        gesture = gesture
            .pointerInput(axisWidthPx) {
                val left = plotLeft(axisWidthPx, 6.dp.toPx())
                detectTapGestures { offset -> column(offset.x, left, size.width, currentMonths)?.let(currentSelect) }
            }
            .pointerInput(axisWidthPx) {
                val left = plotLeft(axisWidthPx, 6.dp.toPx())
                detectHorizontalDragGestures { change, _ ->
                    column(change.position.x, left, size.width, currentMonths)?.let(currentSelect)
                }
            }
    }

    Canvas(gesture) {
        if (months.isEmpty()) return@Canvas
        val left = plotLeft(axisWidthPx, 6.dp.toPx())
        val xLabelHeight = (if (compact) 14.dp else 30.dp).toPx()
        val plotTop = 4.dp.toPx()
        val plotBottom = size.height - xLabelHeight
        val plotHeight = plotBottom - plotTop
        val band = (size.width - left) / months.size
        fun y(value: Number) = plotBottom - (value.toDouble() / yTop * plotHeight).toFloat()

        // Gridlines and the amount scale. The scale hides with every other amount; the lines stay,
        // since proportions are not what the user asked to hide.
        ticks.forEachIndexed { index, tick ->
            val ty = y(tick)
            drawLine(
                FinovaColors.Gray300, Offset(left, ty), Offset(size.width, ty), strokeWidth = 0.5.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())),
            )
            axisLabels.getOrNull(index)?.let { label ->
                val layout = measurer.measure(label, axisStyle)
                drawText(layout, topLeft = Offset(axisWidthPx - layout.size.width.toFloat(), ty - layout.size.height / 2f))
            }
        }

        val radius = 4.dp.toPx()
        months.forEachIndexed { index, month ->
            val centre = left + band * (index + 0.5f)
            val barWidth = band * barRatio
            val barLeft = centre - barWidth / 2
            val isSelected = month.month == selected

            if (!compact && isSelected) {
                val width = band * 0.94f
                drawRoundRect(
                    FinovaColors.Gray200, Offset(centre - width / 2, y(yTop)), Size(width, plotBottom - y(yTop)),
                    CornerRadius(8.dp.toPx()),
                )
            }
            if (month.hasPlan) bar(FinovaColors.Gray300, barLeft, barWidth, y(month.planned), plotBottom, radius)
            if (month.spentOverPlan > 0) bar(FinovaColors.MainRed, barLeft, barWidth, y(month.spent), plotBottom, radius)
            bar(spentColor(month), barLeft, barWidth, y(month.spentWithinPlan), plotBottom, radius)
            if (month.hasPlan) {
                val tickWidth = band * minOf(barRatio + 0.16f, 0.9f)
                val height = 2.dp.toPx()
                drawRect(FinovaColors.Gray600, Offset(centre - tickWidth / 2, y(month.planned) - height / 2), Size(tickWidth, height))
            }
            if (showsPercent) month.percentUsed?.let { percent ->
                val layout = measurer.measure(
                    "$percent%",
                    TextStyle(
                        fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
                        color = if (month.status == BudgetHistoryMonth.Status.Over) FinovaColors.MainRed else FinovaColors.Gray500,
                    ),
                )
                val top = y(maxOf(month.planned, month.spent)) - 4.dp.toPx() - layout.size.height
                drawText(layout, topLeft = Offset(centre - layout.size.width / 2f, top))
            }

            // Month axis: the selected month in bold magenta, and a year mark under each January.
            val name = shortMonths[month.month.monthValue - 1].let { if (months.size > 6) it.take(3) else it }
            val label = measurer.measure(
                name,
                TextStyle(
                    fontSize = if (compact) 9.sp else 11.sp,
                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                    color = if (isSelected) FinovaColors.MainMagenta else FinovaColors.Gray500,
                ),
            )
            val labelTop = plotBottom + 4.dp.toPx()
            drawText(label, topLeft = Offset(centre - label.size.width / 2f, labelTop))
            if (!compact && month.month.monthValue == 1) {
                val year = measurer.measure("’" + "%02d".format(month.month.year % 100), TextStyle(fontSize = 9.sp, color = FinovaColors.Gray400))
                drawText(year, topLeft = Offset(centre - year.size.width / 2f, labelTop + label.size.height))
            }
        }
    }
}

/** The open month is lighter: it is still filling, and a full-strength bar reads as final. */
private fun spentColor(month: BudgetHistoryMonth): Color = when {
    !month.hasPlan -> FinovaColors.Gray400
    month.isCurrent -> FinovaColors.MainMagenta.copy(alpha = 0.6f)
    else -> FinovaColors.MainMagenta
}

private fun DrawScope.bar(color: Color, left: Float, width: Float, top: Float, bottom: Float, radius: Float) {
    val height = bottom - top
    if (height <= 0f) return
    val r = minOf(radius, height / 2, width / 2)
    drawRoundRect(color, Offset(left, top), Size(width, height), CornerRadius(r))
}

/** The month whose column holds [x]. Columns are equal bands, so it is plain arithmetic. */
private fun column(x: Float, left: Float, width: Int, months: List<BudgetHistoryMonth>): YearMonth? {
    if (months.isEmpty()) return null
    val band = (width - left) / months.size
    val index = floor((x - left) / band).toInt()
    return months.getOrNull(index)?.month
}

/** Where the bars start: after the amount scale and a gap, or at the edge with no scale. */
private fun plotLeft(axisWidthPx: Int, gapPx: Float) = if (axisWidthPx > 0) axisWidthPx + gapPx else 0f

/** About three round gridline values from zero to [top], as Swift Charts' automatic marks give. */
private fun niceTicks(top: Double): List<Double> {
    if (top <= 0) return listOf(0.0)
    val raw = top / 3
    val magnitude = 10.0.pow(floor(log10(raw)))
    val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0).map { it * magnitude }.first { it >= raw }
    return generateSequence(0.0) { it + step }.takeWhile { it <= top }.toList()
}
