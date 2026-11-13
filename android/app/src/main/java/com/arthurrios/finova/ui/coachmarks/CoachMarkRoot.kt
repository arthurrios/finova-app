package com.arthurrios.finova.ui.coachmarks

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.NavController
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** How often a running guide looks at the screen. Thirty times a second, as on iOS. */
private const val TICK_MILLIS = 33L

/**
 * Connects the guides to this activity: the stage they look at, the layer they draw in, and the tick
 * that runs while one is up. Must come before the screens, so their targets find the stage set.
 */
@Composable
fun CoachMarkRoot(center: CoachMarkCenter, navController: NavController, dashboardRoute: String) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val scope = rememberCoroutineScope()
    val registry = remember(center, navController) { CoachMarkRegistry(navController, lifecycle, scope, dashboardRoute) }
    DisposableEffect(center, registry) {
        center.stage = registry
        registry.onSheetClosed = center::sheetDidClose
        onDispose { if (center.stage === registry) center.stage = null }
    }
    CoachMarkWindowLayer(center, registry.rootHost)
    LaunchedEffect(center) {
        center.session.map { it != null }.distinctUntilChanged().collectLatest { running ->
            while (running) {
                center.tick()
                delay(TICK_MILLIS)
            }
        }
    }
}

/** While [isLoading], steps on this screen do not judge what is missing from it. */
@Composable
fun CoachMarkLoading(isLoading: Boolean) {
    val center = LocalCoachMarks.current
    val token = remember { Any() }
    DisposableEffect(center, token, isLoading) {
        center?.registry?.setLoading(token, isLoading)
        onDispose { center?.registry?.setLoading(token, false) }
    }
}
