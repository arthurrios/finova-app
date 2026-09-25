package com.arthurrios.finova.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

enum class FinovaTextFieldType {
    Normal,
    Name,
    Email,
    Password,

    /** A password being created: autofill offers to generate and save one. */
    NewPassword;

    val isPassword get() = this == Password || this == NewPassword
}

/**
 * A single-line input: the Material 3 outlined text field, at the iOS Input.swift size (48dp) and
 * colors. The border turns magenta once there is text and red on [isError], like iOS. Email and
 * password fields tell Android autofill what they hold, so password managers can fill them.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FinovaTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    type: FinovaTextFieldType = FinovaTextFieldType.Normal,
    isError: Boolean = false,
    enabled: Boolean = true,
    imeAction: ImeAction = ImeAction.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    @DrawableRes leadingIcon: Int? = null,
    containerColor: Color = FinovaColors.Gray200,
    /** Shows an x that empties the field while it has text (the search field). */
    clearable: Boolean = false,
) {
    var passwordHidden by rememberSaveable { mutableStateOf(true) }
    val interactionSource = remember { MutableInteractionSource() }
    val filled = value.isNotEmpty()
    val restingBorder = if (filled) FinovaColors.MainMagenta else FinovaColors.Gray300
    val colors = OutlinedTextFieldDefaults.colors(
        focusedContainerColor = containerColor,
        unfocusedContainerColor = containerColor,
        disabledContainerColor = containerColor,
        errorContainerColor = containerColor,
        focusedBorderColor = FinovaColors.MainMagenta,
        unfocusedBorderColor = restingBorder,
        errorBorderColor = FinovaColors.MainRed,
        focusedTextColor = FinovaColors.Gray700,
        unfocusedTextColor = FinovaColors.Gray700,
        cursorColor = FinovaColors.Gray700,
        focusedPlaceholderColor = FinovaColors.Gray400,
        unfocusedPlaceholderColor = FinovaColors.Gray400,
        errorPlaceholderColor = FinovaColors.Gray400,
        errorTextColor = FinovaColors.Gray700,
        errorCursorColor = FinovaColors.Gray700,
        focusedLeadingIconColor = FinovaColors.Gray600,
        unfocusedLeadingIconColor = FinovaColors.Gray600,
        focusedTrailingIconColor = FinovaColors.Gray600,
        unfocusedTrailingIconColor = FinovaColors.Gray600,
        errorTrailingIconColor = FinovaColors.MainRed,
    )
    val visualTransformation =
        if (type.isPassword && passwordHidden) PasswordVisualTransformation()
        else VisualTransformation.None
    val keyboardOptions = when (type) {
        FinovaTextFieldType.Email -> KeyboardOptions(
            keyboardType = KeyboardType.Email,
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            imeAction = imeAction,
        )
        FinovaTextFieldType.Password, FinovaTextFieldType.NewPassword -> KeyboardOptions(
            keyboardType = KeyboardType.Password,
            autoCorrectEnabled = false,
            imeAction = imeAction,
        )
        FinovaTextFieldType.Name -> KeyboardOptions(
            capitalization = KeyboardCapitalization.Words,
            imeAction = imeAction,
        )
        FinovaTextFieldType.Normal -> KeyboardOptions(imeAction = imeAction)
    }
    val autofill = when (type) {
        FinovaTextFieldType.Email -> ContentType.EmailAddress
        FinovaTextFieldType.Password -> ContentType.Password
        FinovaTextFieldType.NewPassword -> ContentType.NewPassword
        FinovaTextFieldType.Name -> ContentType.PersonFullName
        FinovaTextFieldType.Normal -> null
    }

    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        singleLine = true,
        textStyle = FinovaType.Input.copy(color = FinovaColors.Gray700),
        cursorBrush = SolidColor(FinovaColors.Gray700),
        visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        interactionSource = interactionSource,
        modifier = modifier
            .fillMaxWidth()
            .height(Spacing.InputHeight)
            .semantics { if (autofill != null) contentType = autofill },
        decorationBox = { innerTextField ->
            OutlinedTextFieldDefaults.DecorationBox(
                value = value,
                innerTextField = innerTextField,
                enabled = enabled,
                singleLine = true,
                visualTransformation = visualTransformation,
                interactionSource = interactionSource,
                isError = isError,
                placeholder = { Text(placeholder, style = FinovaType.Input) },
                leadingIcon = leadingIcon?.let { icon ->
                    { Icon(painterResource(icon), contentDescription = null, modifier = Modifier.size(20.dp)) }
                },
                trailingIcon = when {
                    type.isPassword -> {
                        { PasswordToggle(hidden = passwordHidden, onToggle = { passwordHidden = !passwordHidden }) }
                    }
                    clearable && value.isNotEmpty() -> {
                        {
                            IconButton(onClick = { onValueChange("") }) {
                                Icon(painterResource(R.drawable.ic_x), contentDescription = null, modifier = Modifier.size(16.dp))
                            }
                        }
                    }
                    else -> null
                },
                colors = colors,
                contentPadding = PaddingValues(horizontal = Spacing.S4, vertical = Spacing.S3),
                container = {
                    OutlinedTextFieldDefaults.Container(
                        enabled = enabled,
                        isError = isError,
                        interactionSource = interactionSource,
                        colors = colors,
                        shape = RoundedCornerShape(CornerRadius.Large),
                        focusedBorderThickness = 1.dp,
                        unfocusedBorderThickness = 1.dp,
                    )
                },
            )
        },
    )
}

@Composable
private fun PasswordToggle(hidden: Boolean, onToggle: () -> Unit) {
    IconButton(onClick = onToggle) {
        Icon(
            painter = painterResource(if (hidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
            contentDescription = stringResource(
                if (hidden) R.string.input_show_password else R.string.input_hide_password
            ),
            modifier = Modifier.size(20.dp),
        )
    }
}
