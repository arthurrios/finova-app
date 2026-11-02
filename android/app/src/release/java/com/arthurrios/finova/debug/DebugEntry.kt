package com.arthurrios.finova.debug

import android.content.Intent
import com.arthurrios.finova.AppContainer

/** Release builds have no debug extras. See the debug source set. */
object DebugEntry {
    const val ENABLED = false

    @Suppress("UNUSED_PARAMETER")
    fun applyLaunchExtras(intent: Intent, container: AppContainer) = Unit
}
