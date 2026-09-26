package com.arthurrios.finova.ui.filter

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Port of DayRangeSlider.swift. iOS hand-built this control because its thumbs may cross: a
 * start after the end picks a range that wraps round the month (20 → 13 keeps days 20-31 and
 * 1-13), drawn as two magenta segments. Material's RangeSlider cannot cross, so this is hand-built
 * too. Drag either thumb, or tap the track to move the closer thumb there.
 */
@Composable
fun DayRangeSlider(
    startDay: Int,
    endDay: Int,
    daysInMonth: Int,
    enabled: Boolean,
    onChange: (start: Int, end: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val latestStart by rememberUpdatedState(startDay)
    val latestEnd by rememberUpdatedState(endDay)
    val latestOnChange by rememberUpdatedState(onChange)
    // Which thumb the current drag holds: true = start.
    var draggingStart by remember { mutableStateOf<Boolean?>(null) }

    BoxWithConstraints(modifier.fillMaxWidth().height(SliderHeight).alpha(if (enabled) 1f else 0.4f)) {
        val density = LocalDensity.current
        // Thumb centres stay inside the box, as on iOS where the track is inset by the thumb.
        val inset = ThumbSize / 2
        val trackWidth = maxWidth - ThumbSize
        val trackWidthPx = with(density) { trackWidth.toPx() }
        val insetPx = with(density) { inset.toPx() }

        fun dayAt(x: Float): Int {
            if (trackWidthPx <= 0f || daysInMonth <= 1) return 1
            val progress = ((x - insetPx) / trackWidthPx).coerceIn(0f, 1f)
            return (progress * (daysInMonth - 1)).roundToInt() + 1
        }
        fun xOf(day: Int): Float =
            insetPx + if (daysInMonth <= 1) 0f else trackWidthPx * (day - 1) / (daysInMonth - 1)
        fun closerIsStart(x: Float): Boolean {
            val toStart = abs(x - xOf(latestStart))
            val toEnd = abs(x - xOf(latestEnd))
            // When the thumbs sit together, drag the one that can move that way without crossing.
            return if (toStart == toEnd) x < xOf(latestStart) else toStart < toEnd
        }
        fun move(isStart: Boolean, day: Int) {
            if (isStart) latestOnChange(day, latestEnd) else latestOnChange(latestStart, day)
        }

        val gestures = if (!enabled) Modifier else Modifier
            .pointerInput(daysInMonth, trackWidthPx) {
                detectTapGestures { offset -> move(closerIsStart(offset.x), dayAt(offset.x)) }
            }
            .pointerInput(daysInMonth, trackWidthPx) {
                detectDragGestures(
                    onDragStart = { offset -> draggingStart = closerIsStart(offset.x) },
                    onDragEnd = { draggingStart = null },
                    onDragCancel = { draggingStart = null },
                ) { change, _ ->
                    draggingStart?.let { move(it, dayAt(change.position.x)) }
                }
            }

        Box(Modifier.fillMaxWidth().height(SliderHeight).then(gestures)) {
            Canvas(Modifier.fillMaxWidth().height(ThumbSize)) {
                val trackHeight = 4.dp.toPx()
                val y = size.height / 2
                val top = y - trackHeight / 2
                val radius = CornerRadius(trackHeight / 2)
                val startX = xOf(startDay)
                val endX = xOf(endDay)
                drawRoundRect(FinovaColors.Gray600, Offset(insetPx, top), Size(trackWidthPx, trackHeight), radius)
                if (startDay <= endDay) {
                    drawRoundRect(FinovaColors.MainMagenta, Offset(startX, top), Size(endX - startX, trackHeight), radius)
                } else {
                    drawRoundRect(
                        FinovaColors.MainMagenta, Offset(startX, top),
                        Size(insetPx + trackWidthPx - startX, trackHeight), radius,
                    )
                    drawRoundRect(FinovaColors.MainMagenta, Offset(insetPx, top), Size(endX - insetPx, trackHeight), radius)
                }
                val tick = 2.dp.toPx()
                for (d in 1..daysInMonth) {
                    drawRoundRect(
                        color = FinovaColors.Gray400.copy(alpha = 0.6f),
                        topLeft = Offset(xOf(d) - tick / 2, y - tick / 2),
                        size = Size(tick, tick),
                        cornerRadius = CornerRadius(tick / 2),
                    )
                }
            }
            val startOffset = with(density) { xOf(startDay).toDp() }
            val endOffset = with(density) { xOf(endDay).toDp() }
            Thumb(R.drawable.ic_chevron_right, startOffset, lifted = draggingStart == true)
            Thumb(R.drawable.ic_chevron_left, endOffset, lifted = draggingStart == false)
            DayLabel(startDay, startOffset)
            DayLabel(endDay, endOffset)
        }
    }
}

@Composable
private fun Thumb(icon: Int, centerX: Dp, lifted: Boolean) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .offset(x = centerX - ThumbSize / 2)
            .size(ThumbSize)
            .shadow(if (lifted) 6.dp else 4.dp, CircleShape, ambientColor = FinovaColors.Gray700, spotColor = FinovaColors.Gray700)
            .background(FinovaColors.Gray100, CircleShape),
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = FinovaColors.Gray700, modifier = Modifier.size(12.dp))
    }
}

@Composable
private fun DayLabel(day: Int, centerX: Dp) {
    Text(
        text = day.toString(),
        style = FinovaType.TextXS,
        color = FinovaColors.Gray600,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .offset(x = centerX - LabelWidth / 2, y = ThumbSize + 2.dp)
            .width(LabelWidth),
    )
}

private val ThumbSize = 24.dp
private val LabelWidth = 32.dp
private val SliderHeight = 44.dp
