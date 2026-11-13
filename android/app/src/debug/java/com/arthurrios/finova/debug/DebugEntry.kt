package com.arthurrios.finova.debug

import android.content.Intent
import com.arthurrios.finova.AppContainer
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId

/**
 * The launch extras for checking screens on the emulator. This file exists in debug builds only; the
 * one in src/release turns every extra off, so a release build carries none of them.
 */
object DebugEntry {
    const val ENABLED = true

    /**
     * `--ez finova.debug.freshUser true` wipes this account's data and guide memory first, for a
     * first-time user. `--es finova.debug.guide firstBudget` opens one guide, as its Settings row would.
     */
    fun applyLaunchExtras(intent: Intent, container: AppContainer) {
        if (intent.getBooleanExtra("finova.debug.freshUser", false)) container.clearLocalData(container.currentUid())
        CoachMarkGuideId.fromKey(intent.getStringExtra("finova.debug.guide"))?.let(container.coachMarks::queueReplay)
    }
}
