package com.arthurrios.finova

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaTheme
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            FinovaTheme {
                SkeletonScreen()
            }
        }
    }
}

/** Placeholder until the first real screen is ported. */
@Composable
private fun SkeletonScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(FinovaColors.Gray100)
            .safeDrawingPadding()
            .padding(Spacing.S6),
        verticalArrangement = Arrangement.spacedBy(Spacing.S2),
    ) {
        Text(
            text = stringResource(R.string.skeleton_title),
            style = FinovaType.TitleLG,
            color = FinovaColors.MainMagenta,
        )
        Text(
            text = stringResource(R.string.skeleton_body),
            style = FinovaType.TextSM,
            color = FinovaColors.Gray600,
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun SkeletonScreenPreview() {
    FinovaTheme { SkeletonScreen() }
}
