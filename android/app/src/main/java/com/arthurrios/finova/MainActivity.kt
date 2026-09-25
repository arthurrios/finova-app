package com.arthurrios.finova

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.fragment.app.FragmentActivity
import com.arthurrios.finova.ui.navigation.FinovaNavHost
import com.arthurrios.finova.ui.theme.FinovaTheme

/** A FragmentActivity because BiometricPrompt needs one. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Drop the system launch screen the moment the app draws, with no fade: the Compose
        // splash shows the same picture, and a fade would dim the logo for a moment.
        installSplashScreen().setOnExitAnimationListener { it.remove() }
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            FinovaTheme {
                FinovaNavHost(startRoute = debugStartRoute())
            }
        }
    }

    /**
     * Debug builds only: `adb shell am start -n com.arthurrios.finova/.MainActivity
     * --es finova.debug.route dashboard` opens a screen directly, for checking screens on the
     * emulator without signing in.
     */
    private fun debugStartRoute(): String? {
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        return if (debuggable) intent.getStringExtra("finova.debug.route") else null
    }
}
