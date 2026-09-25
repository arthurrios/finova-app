package com.arthurrios.finova

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.arthurrios.finova.ui.navigation.FinovaNavHost
import com.arthurrios.finova.ui.theme.FinovaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            FinovaTheme {
                FinovaNavHost()
            }
        }
    }
}
