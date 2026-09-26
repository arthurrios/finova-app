package com.arthurrios.finova.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

private val ButtonShape = RoundedCornerShape(CornerRadius.Large)

/**
 * The main call-to-action. Material 3 [Button] in Finova's colors; port of Button.swift (.base).
 * [loading] swaps the label for a spinner and blocks taps, like `startLoading()` on iOS.
 */
@Composable
fun FinovaButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    Button(
        onClick = { if (!loading) onClick() },
        enabled = enabled,
        shape = ButtonShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = FinovaColors.MainMagenta,
            contentColor = FinovaColors.Gray100,
            // iOS dims a disabled button to 60%.
            disabledContainerColor = FinovaColors.MainMagenta.copy(alpha = 0.6f),
            disabledContentColor = FinovaColors.Gray100.copy(alpha = 0.6f),
        ),
        modifier = modifier.fillMaxWidth().height(Spacing.ButtonHeight),
    ) {
        ButtonContent(text = text, loading = loading, style = FinovaType.ButtonMD, spinner = FinovaColors.Gray100)
    }
}

/** Button.swift `.outlined`: magenta text and border on a faint magenta fill (e.g. Delete). */
@Composable
fun FinovaAccentOutlinedButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        shape = ButtonShape,
        border = BorderStroke(1.dp, FinovaColors.MainMagenta),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = FinovaColors.LowMagenta,
            contentColor = FinovaColors.MainMagenta,
        ),
        modifier = modifier.fillMaxWidth().height(Spacing.ButtonHeight),
    ) {
        Text(text = text, style = FinovaType.ButtonMD)
    }
}

/** A secondary, outlined button with an optional trailing icon (the social sign-in buttons). */
@Composable
fun FinovaOutlinedButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    @DrawableRes trailingIcon: Int? = null,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    OutlinedButton(
        onClick = { if (!loading) onClick() },
        enabled = enabled,
        shape = ButtonShape,
        border = BorderStroke(1.dp, FinovaColors.Gray300),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = FinovaColors.Gray100,
            contentColor = FinovaColors.Gray700,
            disabledContainerColor = FinovaColors.Gray100,
            disabledContentColor = FinovaColors.Gray400,
        ),
        modifier = modifier.fillMaxWidth().height(Spacing.ButtonHeight),
    ) {
        ButtonContent(text = text, loading = loading, style = FinovaType.ButtonSM, spinner = FinovaColors.MainMagenta)
        if (trailingIcon != null && !loading) {
            Spacer(Modifier.width(Spacing.S2))
            Image(painterResource(trailingIcon), contentDescription = null, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun ButtonContent(text: String, loading: Boolean, style: androidx.compose.ui.text.TextStyle, spinner: Color) {
    Box(contentAlignment = Alignment.Center) {
        // The label keeps its space while loading so the button does not change size.
        Text(text = text, style = style, color = if (loading) Color.Transparent else Color.Unspecified)
        if (loading) {
            CircularProgressIndicator(color = spinner, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        }
    }
}
