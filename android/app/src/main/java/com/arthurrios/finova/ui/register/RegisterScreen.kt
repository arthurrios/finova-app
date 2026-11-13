package com.arthurrios.finova.ui.register

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.AuthErrorDialog
import com.arthurrios.finova.ui.components.EnableBiometricsDialog
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextFieldType
import com.arthurrios.finova.ui.components.ValidatedTextField
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaTheme
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

@Composable
fun RegisterRoute(
    viewModel: RegisterViewModel,
    onRegistered: () -> Unit,
    onBackToLogin: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    LaunchedEffect(state.registered) { if (state.registered) onRegistered() }

    RegisterScreen(
        state = state,
        onNameChange = viewModel::onNameChange,
        onEmailChange = viewModel::onEmailChange,
        onPasswordChange = viewModel::onPasswordChange,
        onConfirmPasswordChange = viewModel::onConfirmPasswordChange,
        onRegister = viewModel::register,
        onBackToLogin = onBackToLogin,
    )

    state.error?.let { AuthErrorDialog(error = it, onDismiss = viewModel::dismissError) }
    if (state.offerBiometrics) {
        EnableBiometricsDialog(onEnable = viewModel::onEnableBiometrics, onSkip = viewModel::onSkipBiometrics)
    }
}

/** Port of RegisterView.swift: the form sits in the middle of the screen. */
@Composable
fun RegisterScreen(
    state: RegisterUiState,
    onNameChange: (String) -> Unit,
    onEmailChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onConfirmPasswordChange: (String) -> Unit,
    onRegister: () -> Unit,
    onBackToLogin: () -> Unit,
) {
    val focusManager = LocalFocusManager.current
    val next = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })

    val formAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) { formAlpha.animateTo(1f, tween(durationMillis = 700)) }

    val passwordMessage = RegisterValidation.missingPasswordRules(state.password)
        .takeIf { state.password.isNotEmpty() && it.isNotEmpty() }
        ?.map { stringResource(it) }
        ?.let { rules -> stringResource(R.string.password_must_contain) + ":\n" + rules.joinToString("\n") { "• $it" } }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(FinovaColors.Gray100)
            .pointerInput(Unit) { detectTapGestures { focusManager.clearFocus() } }
            .safeDrawingPadding(),
    ) {
        Column(
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .heightIn(min = maxHeight)
                .alpha(formAlpha.value)
                .padding(start = Spacing.S8, end = Spacing.S8, top = Spacing.S7, bottom = Spacing.S3),
        ) {
            Image(
                painter = painterResource(R.drawable.finova_logo),
                contentDescription = null,
                modifier = Modifier.size(100.dp).align(Alignment.CenterHorizontally),
            )
            Spacer(Modifier.height(Spacing.S8))
            Text(
                text = stringResource(R.string.register_welcome_title).uppercase(),
                style = FinovaType.TitleSM,
                color = FinovaColors.Gray700,
            )
            Spacer(Modifier.height(Spacing.S2))
            Text(
                text = stringResource(R.string.register_welcome_subtitle),
                style = FinovaType.TextSM,
                color = FinovaColors.Gray500,
            )
            Spacer(Modifier.height(Spacing.S7))
            ValidatedTextField(
                value = state.name,
                onValueChange = onNameChange,
                placeholder = stringResource(R.string.input_name),
                errorMessage = RegisterValidation.nameError(state.name)?.let { stringResource(it) },
                type = FinovaTextFieldType.Name,
                enabled = !state.loading,
                imeAction = ImeAction.Next,
                keyboardActions = next,
            )
            Spacer(Modifier.height(Spacing.S3))
            ValidatedTextField(
                value = state.email,
                onValueChange = onEmailChange,
                placeholder = stringResource(R.string.input_email),
                errorMessage = RegisterValidation.emailError(state.email)?.let { stringResource(it) },
                type = FinovaTextFieldType.Email,
                enabled = !state.loading,
                imeAction = ImeAction.Next,
                keyboardActions = next,
            )
            Spacer(Modifier.height(Spacing.S3))
            ValidatedTextField(
                value = state.password,
                onValueChange = onPasswordChange,
                placeholder = stringResource(R.string.input_password),
                errorMessage = passwordMessage,
                type = FinovaTextFieldType.NewPassword,
                enabled = !state.loading,
                imeAction = ImeAction.Next,
                keyboardActions = next,
            )
            Spacer(Modifier.height(Spacing.S3))
            ValidatedTextField(
                value = state.confirmPassword,
                onValueChange = onConfirmPasswordChange,
                placeholder = stringResource(R.string.input_confirm_password),
                errorMessage = RegisterValidation.confirmPasswordError(state.confirmPassword, state.password)
                    ?.let { stringResource(it) },
                type = FinovaTextFieldType.NewPassword,
                enabled = !state.loading,
                imeAction = ImeAction.Done,
                keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
            )
            Spacer(Modifier.height(Spacing.S7))
            HorizontalDivider(color = FinovaColors.Gray300)
            Spacer(Modifier.height(Spacing.S7))
            FinovaButton(
                text = stringResource(R.string.register_button),
                onClick = {
                    focusManager.clearFocus()
                    onRegister()
                },
                enabled = state.canSubmit || state.loading,
                loading = state.loading,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = Spacing.S3)
                    .height(44.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.register_already_have_account),
                    style = FinovaType.TextSM,
                    color = FinovaColors.Gray500,
                )
                TextButton(onClick = onBackToLogin, enabled = !state.loading) {
                    Text(
                        text = stringResource(R.string.register_login_link),
                        style = FinovaType.TextSM,
                        color = FinovaColors.MainMagenta,
                    )
                }
            }
        }
    }
}

@Preview(showBackground = true, heightDp = 915)
@Composable
private fun RegisterScreenPreview() {
    FinovaTheme {
        RegisterScreen(RegisterUiState(), {}, {}, {}, {}, {}, {})
    }
}
