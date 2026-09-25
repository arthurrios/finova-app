package com.arthurrios.finova

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
                FinovaNavHost()
            }
        }
    }
}
