package com.arthurrios.finova.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * A [FinovaTextField] with a red hint under it that slides in while [errorMessage] is set.
 * Port of ValidatedInput.swift; the checks themselves live with the screen.
 */
@Composable
fun ValidatedTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    errorMessage: String?,
    modifier: Modifier = Modifier,
    type: FinovaTextFieldType = FinovaTextFieldType.Normal,
    enabled: Boolean = true,
    imeAction: ImeAction = ImeAction.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
) {
    // Keep the last message while the hint animates out, so it does not go blank mid-animation.
    var lastMessage by remember { mutableStateOf(errorMessage.orEmpty()) }
    if (errorMessage != null) lastMessage = errorMessage

    Column(modifier) {
        FinovaTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = placeholder,
            type = type,
            isError = errorMessage != null,
            enabled = enabled,
            imeAction = imeAction,
            keyboardActions = keyboardActions,
        )
        AnimatedVisibility(
            visible = errorMessage != null,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            Text(
                text = lastMessage,
                style = FinovaType.TextXS,
                color = FinovaColors.MainRed,
                modifier = Modifier.padding(start = Spacing.S2, end = Spacing.S2, top = Spacing.S1),
            )
        }
    }
}
