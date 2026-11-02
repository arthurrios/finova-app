package com.arthurrios.finova.ui.coachmarks

import android.view.View
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.navigation.NavController
import com.arthurrios.finova.domain.coachmarks.CoachMarkEvent
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** The running guides, for screens that report to them. Null in previews, where nothing runs. */
val LocalCoachMarks = staticCompositionLocalOf<CoachMarkCenter?> { null }

/** The sheet a composable is inside. Outside any sheet its screen is its nav entry. */
internal val LocalCoachMarkScreen = compositionLocalOf<Any?> { null }

internal class CoachMarkTargetEntry(val target: CoachMarkTarget, val requester: BringIntoViewRequester) {
    var screen: Any? = null
    var coordinates: LayoutCoordinates? = null
}

/**
 * The shared registry of what is on screen: Compose's stand-in for the iOS walk of the view tree.
 *
 * Each marked control registers itself with the screen it belongs to and keeps its live coordinates
 * here. Only the screen on top is searched, as on iOS: the dashboard stays composed behind a sheet,
 * and a target behind a sheet is not something the user can reach. Rects are in screen pixels,
 * because a sheet's fields and the activity's controls are in different windows.
 */
class CoachMarkRegistry(
    private val navController: NavController,
    private val lifecycle: Lifecycle,
    private val scope: CoroutineScope,
    private val dashboardRoute: String,
) : CoachMarkStage {
    private val entries = mutableListOf<CoachMarkTargetEntry>()
    private val sheets = mutableListOf<Any>()
    private val layers = mutableMapOf<Any, View>()
    private val loading = mutableSetOf<Any>()
    private val fills = mutableMapOf<CoachMarkTarget, () -> Boolean>()
    var onSheetClosed: () -> Unit = {}

    /** Stands for the activity's own window, which has no sheet to name it. */
    val rootHost = Any()

    private val baseEntry get() = navController.currentBackStackEntry

    override val isAppActive: Boolean get() = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
    override val topScreen: Any? get() = sheets.lastOrNull() ?: baseEntry
    override val topRoute: String? get() = if (sheets.isEmpty()) baseEntry?.destination?.route else null
    override val isDashboardOnTop: Boolean get() = topRoute == dashboardRoute
    override val isLoadingScreen: Boolean get() = loading.isNotEmpty()
    override val overlayHost: Any get() = sheets.lastOrNull() ?: rootHost

    private val topLayer: View? get() = layers[overlayHost]

    override val keyboardTop: Float?
        get() {
            val view = topLayer ?: return null
            val insets = ViewCompat.getRootWindowInsets(view) ?: return null
            if (!insets.isVisible(WindowInsetsCompat.Type.ime())) return null
            val bottom = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            if (bottom <= 0) return null
            val origin = IntArray(2).also(view::getLocationOnScreen)
            return (origin[1] + view.height - bottom).toFloat()
        }

    override fun find(target: CoachMarkTarget): MarkRect? {
        val top = topScreen
        val width = topLayer?.width?.toFloat() ?: return null
        return entries.asSequence()
            .filter { it.target == target && it.screen === top }
            .mapNotNull { entry ->
                val coordinates = entry.coordinates?.takeIf { it.isAttached } ?: return@mapNotNull null
                val origin = coordinates.localToScreen(Offset.Zero)
                val size = coordinates.size
                MarkRect(origin.x, origin.y, origin.x + size.width, origin.y + size.height)
            }
            .filter { CoachMarkLayout.isAcross(it, width) }
            // A pager holds one copy per month: take the one most of which is on screen.
            .maxByOrNull { minOf(it.right, width) - maxOf(it.left, 0f) }
    }

    override fun isFilled(target: CoachMarkTarget): Boolean = fills[target]?.invoke() == true

    override fun scrollIntoView(target: CoachMarkTarget) {
        val top = topScreen
        val entry = entries.firstOrNull { it.target == target && it.screen === top } ?: return
        scope.launch { entry.requester.bringIntoView() }
    }

    override fun prepareDashboardForGuide() {
        if (baseEntry?.destination?.route != dashboardRoute) navController.popBackStack(dashboardRoute, inclusive = false)
    }

    internal fun addFill(target: CoachMarkTarget, isFilled: () -> Boolean) {
        fills[target] = isFilled
    }

    internal fun removeFill(target: CoachMarkTarget) {
        fills -= target
    }

    internal fun add(entry: CoachMarkTargetEntry) {
        entries += entry
    }

    internal fun remove(entry: CoachMarkTargetEntry) {
        entries -= entry
    }

    internal fun pushSheet(sheet: Any) {
        sheets += sheet
    }

    internal fun popSheet(sheet: Any) {
        sheets -= sheet
        onSheetClosed()
    }

    internal fun attach(host: Any, layer: View) {
        layers[host] = layer
    }

    internal fun detach(host: Any) {
        layers -= host
    }

    internal fun setLoading(token: Any, isLoading: Boolean) {
        if (isLoading) loading += token else loading -= token
    }

    /** The safe area of the window a layer sits in. */
    internal fun safeInsets(layer: View): MarkInsets {
        val insets = ViewCompat.getRootWindowInsets(layer) ?: return MarkInsets()
        val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
        return MarkInsets(safe.left.toFloat(), safe.top.toFloat(), safe.right.toFloat(), safe.bottom.toFloat())
    }
}

/** The registry behind [LocalCoachMarks], which is the only stage the app has. */
internal val CoachMarkCenter.registry: CoachMarkRegistry? get() = stage as? CoachMarkRegistry

/**
 * Marks this control as a step's target. Takes no part in layout or touches, and does nothing unless
 * a guide looks for it. [enabled] is for a control only some data has.
 */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.coachMarkTarget(target: CoachMarkTarget, enabled: Boolean = true): Modifier =
    if (!enabled) this else composed {
        val center = LocalCoachMarks.current
        val requester = remember { BringIntoViewRequester() }
        val entry = remember(target, requester) { CoachMarkTargetEntry(target, requester) }
        val screen = LocalCoachMarkScreen.current ?: LocalViewModelStoreOwner.current
        DisposableEffect(center, entry, screen) {
            entry.screen = screen
            val registry = center?.registry
            registry?.add(entry)
            onDispose { registry?.remove(entry) }
        }
        Modifier
            .bringIntoViewRequester(requester)
            .onGloballyPositioned { entry.coordinates = it }
    }

/** Tells the guide when this text field has been left holding a value. */
fun Modifier.coachMarkFill(target: CoachMarkTarget, isFilled: () -> Boolean): Modifier = composed {
    val center = LocalCoachMarks.current
    val filled by rememberUpdatedState(isFilled)
    val focus = remember { booleanArrayOf(false) }
    DisposableEffect(center, target) {
        val registry = center?.registry
        registry?.addFill(target) { filled() }
        onDispose { registry?.removeFill(target) }
    }
    Modifier.onFocusChanged { state ->
        if (focus[0] && !state.hasFocus && filled()) center?.post(CoachMarkEvent.FieldFilled(target))
        focus[0] = state.hasFocus
    }
}

/**
 * Wraps a bottom sheet's content. A sheet is its own screen to the guides, and its own window, so it
 * brings its own overlay layer: see [CoachMarkWindowLayer].
 */
@Composable
fun CoachMarkSheet(content: @Composable () -> Unit) {
    val center = LocalCoachMarks.current
    val sheet = remember { Any() }
    if (center == null) return content()
    DisposableEffect(center, sheet) {
        val registry = center.registry
        registry?.pushSheet(sheet)
        onDispose { registry?.popSheet(sheet) }
    }
    CompositionLocalProvider(LocalCoachMarkScreen provides sheet) {
        content()
        CoachMarkWindowLayer(center, sheet)
    }
}
