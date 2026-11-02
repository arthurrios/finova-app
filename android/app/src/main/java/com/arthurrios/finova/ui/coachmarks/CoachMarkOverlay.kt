package com.arthurrios.finova.ui.coachmarks

import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.compose.animation.core.animateRectAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionContext
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCompositionContext
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.platform.AbstractComposeView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.findViewTreeViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.findViewTreeSavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.CornerRadius as FinovaCorners
import com.arthurrios.finova.ui.theme.Spacing
import kotlin.math.ceil
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlin.math.roundToInt

private val Dim = Color.Black.copy(alpha = 0.62f)

private const val RING_DP = 2f

/** Above any elevation a sheet's content is given, without casting a shadow. */
private const val LAYER_Z = 10_000f

/** Past this the card would not fit next to the thing it points at. */
private const val MAX_CARD_FONT_SCALE = 1.6f

/**
 * Puts a mark layer into the window this composable lives in.
 *
 * Android has no spare window that stays above dialogs the way the iOS overlay window does, and each
 * bottom sheet is a window of its own, above anything drawn in the activity. So there is one layer per
 * window: a view added to that window's content, on top of it, which draws only while its window is
 * the one on top. Being in the same window keeps keyboard focus where it is and leaves pickers,
 * dropdowns and dialogs above the mark, since those are windows too. A touch the layer declines falls
 * to the views beneath it in the normal way, so the target behaves exactly as it does with no mark up.
 */
@Composable
internal fun CoachMarkWindowLayer(center: CoachMarkCenter, host: Any) {
    val anchor = LocalView.current
    val parent = rememberCompositionContext()
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    // Only while a guide runs: everyone else's windows stay exactly as they were.
    val running by remember(center) { center.session.map { it != null }.distinctUntilChanged() }.collectAsState(center.session.value != null)
    DisposableEffect(anchor, host, running) {
        if (!running) return@DisposableEffect onDispose { }
        val content = anchor.rootView.findViewById<ViewGroup>(android.R.id.content)
        val layer = CoachMarkLayerView(anchor.context, center, host, parent) {
            focus.clearFocus()
            keyboard?.hide()
        }
        layer.setViewTreeLifecycleOwner(anchor.findViewTreeLifecycleOwner())
        layer.setViewTreeViewModelStoreOwner(anchor.findViewTreeViewModelStoreOwner())
        layer.setViewTreeSavedStateRegistryOwner(anchor.findViewTreeSavedStateRegistryOwner())
        content.addView(layer, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        center.registry?.attach(host, layer)
        onDispose {
            center.registry?.detach(host)
            // A sheet going away disposes this while its window walks its views to detach them, and
            // removing one mid-walk crashes that walk. Afterwards it is safe, even with no window.
            android.os.Handler(android.os.Looper.getMainLooper()).post { content.removeView(layer) }
        }
    }
}

/** Holds the overlay, and decides who gets each touch. */
@SuppressLint("ViewConstructor")
internal class CoachMarkLayerView(
    context: Context,
    private val center: CoachMarkCenter,
    private val host: Any,
    parent: CompositionContext,
    private val onDimTap: () -> Unit,
) : AbstractComposeView(context) {
    private var route = CoachMarkTouchRoute.Through

    /** Where the card landed, in this view's pixels. */
    var card: MarkRect? = null

    /** The drawn hole, in this view's pixels. */
    var hole: MarkRect? = null

    init {
        setParentCompositionContext(parent)
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
        // A sheet's content has an elevation, and siblings are stacked by it, for touches as well.
        outlineProvider = null
        translationZ = LAYER_Z
    }

    @Composable
    override fun Content() {
        CoachMarkOverlay(center, host, this, onDimTap)
    }

    /** Declining the first event hands the whole gesture to the view underneath. */
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            val shown = center.presentation.value?.takeIf { it.host === host }
            route = CoachMarkTouch.route(
                event.x, event.y,
                isActive = shown != null,
                card = card?.takeIf { shown?.isBetweenSteps == false },
                hole = hole,
                isHoleTouchable = shown?.isBetweenSteps == false,
            )
        }
        return when (route) {
            CoachMarkTouchRoute.Through -> false
            CoachMarkTouchRoute.Card -> super.dispatchTouchEvent(event)
            CoachMarkTouchRoute.Dim -> {
                if (event.actionMasked == MotionEvent.ACTION_UP) onDimTap()
                true
            }
        }
    }
}

@Composable
private fun CoachMarkOverlay(center: CoachMarkCenter, host: Any, layer: CoachMarkLayerView, onDimTap: () -> Unit) {
    val presentation by center.presentation.collectAsState()
    val mine = presentation?.takeIf { it.host === host }
    // Kept for the fade out, which needs something to fade.
    val last = remember { arrayOfNulls<CoachMarkPresentation>(1) }
    if (mine != null) last[0] = mine
    val opacity by animateFloatAsState(
        targetValue = if (mine != null) 1f else 0f,
        animationSpec = tween(if (mine != null) 300 else 200),
        label = "mark",
    )
    val shown = last[0]
    if (shown == null || (mine == null && opacity == 0f)) {
        layer.card = null
        layer.hole = null
        return
    }

    val density = LocalDensity.current
    val view = LocalView.current
    val px = density.density
    val origin = remember(shown) { IntArray(2).also(view::getLocationOnScreen) }
    val hole = shown.hole?.offset(-origin[0].toFloat(), -origin[1].toFloat())?.inflated(CoachMarkLayout.HOLE_PADDING_DP * px)
        // A full-width control would push its ring off the sides of the screen.
        ?.clampedAcross(view.width.toFloat(), RING_DP * px)
    layer.hole = hole
    val bounds = MarkBounds(
        width = view.width.toFloat(),
        height = view.height.toFloat(),
        safe = center.registry?.safeInsets(view) ?: MarkInsets(),
    )

    Box(Modifier.fillMaxSize().graphicsLayer { alpha = opacity }) {
        DimLayer(hole, showRing = !shown.isBetweenSteps, animated = shown.animated, bounds = bounds)
        CardLayout(
            hole = hole,
            bounds = bounds,
            keyboardTop = shown.keyboardTop?.minus(origin[1]),
            onPlaced = { layer.card = it },
        ) {
            val cardOpacity by animateFloatAsState(
                targetValue = if (shown.isBetweenSteps) 0f else 1f,
                animationSpec = if (shown.isBetweenSteps) tween(150) else tween(250, delayMillis = 100),
                label = "card",
            )
            // Past this the card stops growing with the system's text size, so it can still sit
            // beside what it points at. The words wrap, and the card scrolls if it must.
            CompositionLocalProvider(LocalDensity provides Density(density.density, minOf(density.fontScale, MAX_CARD_FONT_SCALE))) {
                CoachMarkCard(
                    content = shown.content,
                    onNext = {
                        // Whatever was typed lands before the next step, and the keyboard is not
                        // left covering the field the next step points at.
                        onDimTap()
                        center.nextTapped()
                    },
                    onSkip = center::skipTapped,
                    onSkipAll = center::skipAllTapped,
                    modifier = Modifier.alpha(cardOpacity),
                )
            }
        }
    }
}

@Composable
private fun DimLayer(hole: MarkRect?, showRing: Boolean, animated: Boolean, bounds: MarkBounds) {
    // A zero-size hole rather than none, so the first target grows out of the middle.
    val middle = Offset(bounds.width / 2, bounds.height / 2)
    val target = hole?.let { Rect(it.left, it.top, it.right, it.bottom) } ?: Rect(middle, Size.Zero)
    val rect by animateRectAsState(target, if (animated) tween(350) else snap(), label = "hole")
    val density = LocalDensity.current
    val ringWidth = with(density) { RING_DP.dp.toPx() }
    val cardRadius = with(density) { FinovaCorners.ExtraLarge.toPx() }
    val roundWithin = with(density) { 8.dp.toPx() }
    val hasHole = hole != null
    Canvas(Modifier.fillMaxSize()) {
        val radius = if (hasHole) {
            CoachMarkLayout.holeRadius(MarkRect(rect.left, rect.top, rect.right, rect.bottom), cardRadius, roundWithin)
        } else 0f
        val shape = RoundRect(rect, CornerRadius(radius))
        val path = Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(Rect(Offset.Zero, size))
            addRoundRect(shape)
        }
        drawPath(path, Dim)
        if (hasHole && showRing) {
            drawPath(Path().apply { addRoundRect(shape) }, FinovaColors.MainMagenta, style = Stroke(ringWidth))
        }
    }
}

/** Measures the card, then asks [CoachMarkLayout] where it goes. A null answer leaves it unplaced. */
@Composable
private fun CardLayout(
    hole: MarkRect?,
    bounds: MarkBounds,
    keyboardTop: Float?,
    onPlaced: (MarkRect?) -> Unit,
    card: @Composable () -> Unit,
) {
    Layout(content = card, modifier = Modifier.fillMaxSize()) { measurables, constraints ->
        val margin = CoachMarkLayout.MARGIN_DP * density
        val gap = CoachMarkLayout.GAP_DP * density
        val width = minOf(
            bounds.width - 2 * margin - bounds.safe.left - bounds.safe.right,
            CoachMarkLayout.MAX_CARD_WIDTH_DP * density,
        ).roundToInt().coerceAtLeast(0)
        val maxHeight = (bounds.height - bounds.safe.top - bounds.safe.bottom - 2 * margin).roundToInt().coerceAtLeast(0)
        val placeable = measurables.first().measure(Constraints.fixedWidth(width).copy(maxHeight = maxHeight))
        val frame = CoachMarkLayout.cardFrame(
            placeable.width.toFloat(), placeable.height.toFloat(), hole, bounds, keyboardTop, gap, margin,
        )
        layout(constraints.maxWidth, constraints.maxHeight) {
            onPlaced(frame)
            if (frame != null) placeable.place(frame.left.roundToInt(), frame.top.roundToInt())
        }
    }
}

/** The message and the way out. */
@Composable
private fun CoachMarkCard(
    content: CoachMarkContent,
    onNext: () -> Unit,
    onSkip: () -> Unit,
    onSkipAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = RoundedCornerShape(FinovaCorners.ExtraLarge),
        color = FinovaColors.Gray100,
        shadowElevation = 8.dp,
        modifier = modifier,
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S2),
            modifier = Modifier.verticalScroll(rememberScrollState()).padding(Spacing.S4),
        ) {
            Text(
                stringResource(
                    com.arthurrios.finova.R.string.coach_marks_caption,
                    keyText(content.guideTitleKey), content.position, content.total,
                ),
                style = FinovaType.TextXS,
                color = FinovaColors.MainMagenta,
            )
            Text(
                keyText(content.messageKey),
                style = FinovaType.TextSM,
                color = FinovaColors.Gray700,
                modifier = Modifier
                    .padding(bottom = Spacing.S1)
                    .semantics { liveRegion = LiveRegionMode.Polite },
            )
            CardButtons(lastIsFilled = content.nextKey != null) {
                content.skipAllKey?.let { QuietButton(it, onSkipAll) }
                content.skipKey?.let { QuietButton(it, onSkip) }
                content.nextKey?.let { key ->
                    Button(
                        onClick = onNext,
                        shape = RoundedCornerShape(FinovaCorners.Large),
                        colors = ButtonDefaults.buttonColors(containerColor = FinovaColors.MainMagenta, contentColor = FinovaColors.Gray100),
                        contentPadding = ButtonPadding,
                        modifier = Modifier.heightIn(min = MinButtonHeight),
                    ) { ButtonTitle(key) }
                }
            }
        }
    }
}

private val MinButtonHeight = 44.dp
private val ButtonPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.S3, vertical = Spacing.S2)

@Composable
private fun QuietButton(key: String, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        shape = RoundedCornerShape(FinovaCorners.Large),
        colors = ButtonDefaults.textButtonColors(contentColor = FinovaColors.Gray600),
        contentPadding = ButtonPadding,
        modifier = Modifier.heightIn(min = MinButtonHeight),
    ) { ButtonTitle(key) }
}

@Composable
private fun ButtonTitle(key: String) {
    Text(keyText(key), style = FinovaType.ButtonSM, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip)
}

/**
 * One row when the titles fit it: quiet buttons at the start, the filled one at the end. pt-BR on a
 * narrow phone, or large text, stacks them instead, each as wide as the card.
 */
@Composable
private fun CardButtons(lastIsFilled: Boolean, buttons: @Composable () -> Unit) {
    Layout(content = buttons) { measurables, constraints ->
        val spacing = Spacing.S2.roundToPx()
        val widths = measurables.map { singleLineWidth(it) }
        val available = constraints.maxWidth
        val oneRow = CoachMarkLayout.buttonsFitOneRow(
            widths.map(Int::toFloat), available.toFloat(), spacing.toFloat(), Spacing.S4.toPx(),
        )
        if (oneRow) {
            val placeables = measurables.mapIndexed { index, it -> it.measure(Constraints(minWidth = widths[index], maxWidth = widths[index])) }
            val height = placeables.maxOfOrNull { it.height } ?: 0
            layout(available, height) {
                var x = 0
                placeables.forEachIndexed { index, placeable ->
                    val isLast = index == placeables.lastIndex
                    val left = if (isLast && lastIsFilled) available - placeable.width else x
                    placeable.place(left, (height - placeable.height) / 2)
                    x += placeable.width + spacing
                }
            }
        } else {
            val placeables = measurables.map { it.measure(Constraints.fixedWidth(available)) }
            val height = placeables.sumOf { it.height } + spacing * (placeables.size - 1).coerceAtLeast(0)
            layout(available, height) {
                var y = 0
                placeables.forEach {
                    it.place(0, y)
                    y += it.height + spacing
                }
            }
        }
    }
}

private fun androidx.compose.ui.layout.IntrinsicMeasureScope.singleLineWidth(measurable: Measurable): Int =
    ceil(measurable.maxIntrinsicWidth(Constraints.Infinity).toFloat()).toInt()

@Composable
internal fun keyText(key: String): String = CoachMarkStrings.resource(key)?.let { stringResource(it) }.orEmpty()
