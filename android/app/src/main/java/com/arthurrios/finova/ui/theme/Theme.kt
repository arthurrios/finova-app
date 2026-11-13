package com.arthurrios.finova.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

// Light only, like the iOS app.
private val FinovaColorScheme = lightColorScheme(
    primary = FinovaColors.MainMagenta,
    error = FinovaColors.MainRed,
    background = FinovaColors.Gray100,
    surface = FinovaColors.Gray100,
    onBackground = FinovaColors.Gray700,
    onSurface = FinovaColors.Gray700,
    outline = FinovaColors.Gray300,
)

private val FinovaTypography = Typography(
    headlineLarge = FinovaType.TitleLG,
    titleMedium = FinovaType.TitleMD,
    bodyMedium = FinovaType.TextSM,
    bodySmall = FinovaType.TextXS,
    labelLarge = FinovaType.ButtonMD,
)

@Composable
fun FinovaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = FinovaColorScheme,
        typography = FinovaTypography,
        content = content,
    )
}
