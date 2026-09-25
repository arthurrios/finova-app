package com.arthurrios.finova.ui.theme

import androidx.compose.ui.graphics.Color

// Mirrors Finova/Sources/Core/Constants/Colors.swift on iOS.
object FinovaColors {
    val MainMagenta = Color(0xFFDA4BDD)
    val MainRed = Color(0xFFD93A4A)
    val BrightRed = Color(0xFFFF6B6B)
    val WarningAmber = Color(0xFFF59E0B)
    val LowAmber = Color(0xFFF59E0B).copy(alpha = 0.05f)
    val MainGreen = Color(0xFF1FA342)
    val BrightGreen = Color(0xFF34D399)

    val LowMagenta = Color(red = 220, green = 84, blue = 222).copy(alpha = 0.05f)
    val OpaqueWhite = Color(red = 249, green = 251, blue = 249).copy(alpha = 0.05f)
    val LightGreen = Color(red = 31, green = 163, blue = 66).copy(alpha = 0.05f)
    val LightRed = Color(red = 217, green = 58, blue = 74).copy(alpha = 0.05f)

    val Gray100 = Color(0xFFF9FBF9)
    val Gray200 = Color(0xFFEFF0EF)
    val Gray300 = Color(0xFFE5E6E5)
    val Gray400 = Color(0xFFA1A2A1)
    val Gray500 = Color(0xFF676767)
    val Gray600 = Color(0xFF494A49)
    val Gray700 = Color(0xFF0F0F0F)

    /** The end stop of iOS `Colors.gradientBlack` (Gray700 → this, at 102°). */
    val GradientBlackEnd = Color(0xFF2D2D2D)
}
