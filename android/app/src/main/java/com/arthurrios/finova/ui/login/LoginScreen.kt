package com.arthurrios.finova.ui.login

import androidx.activity.compose.LocalActivity
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
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
import com.arthurrios.finova.ui.components.FinovaOutlinedButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.FinovaTextFieldType
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaTheme
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

@Composable
fun LoginRoute(
    viewModel: LoginViewModel,
    onSignedIn: () -> Unit,
    onRegister: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val activity = LocalActivity.current

    LaunchedEffect(state.signedIn) { if (state.signedIn) onSignedIn() }

    LoginScreen(
        state = state,
        onEmailChange = viewModel::onEmailChange,
        onPasswordChange = viewModel::onPasswordChange,
        onLogin = viewModel::signInWithEmail,
        onGoogle = { activity?.let(viewModel::signInWithGoogle) },
        onForgotPassword = viewModel::onForgotPassword,
        onRegister = onRegister,
    )

    state.resetEmail?.let { email ->
        ForgotPasswordDialog(
            email = email,
            sending = state.resetSending,
            onEmailChange = viewModel::onResetEmailChange,
            onSend = viewModel::sendPasswordReset,
            onDismiss = viewModel::dismissReset,
        )
    }
    state.resetSentTo?.let { email ->
        AlertDialog(
            onDismissRequest = viewModel::dismissResetSent,
            title = { Text(stringResource(R.string.login_forgot_password_sent_title)) },
            text = { Text(stringResource(R.string.login_forgot_password_sent_message, email)) },
            confirmButton = {
                TextButton(onClick = viewModel::dismissResetSent) { Text(stringResource(R.string.alert_ok)) }
            },
        )
    }

    state.error?.let { AuthErrorDialog(error = it, onDismiss = viewModel::dismissError) }

    val biometricName = stringResource(R.string.biometric_name)
    when (state.biometricDialog) {
        BiometricDialog.OfferEnable -> EnableBiometricsDialog(
            onEnable = viewModel::onEnableBiometrics,
            onSkip = viewModel::onSkipBiometrics,
        )
        BiometricDialog.NotEnrolled -> AlertDialog(
            onDismissRequest = {},
            title = { Text(biometricName) },
            text = { Text(stringResource(R.string.settings_biometric_not_enrolled_message, biometricName)) },
            confirmButton = {
                TextButton(onClick = viewModel::onOpenBiometricSettings) {
                    Text(stringResource(R.string.settings_biometric_open_settings))
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::onSkipBiometrics) { Text(stringResource(R.string.skip)) }
            },
        )
        null -> Unit
    }
}

/** Port of LoginView.swift. Android has no "Sign in with Apple": email and Google only. */
@Composable
fun LoginScreen(
    state: LoginUiState,
    onEmailChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onLogin: () -> Unit,
    onGoogle: () -> Unit,
    onForgotPassword: () -> Unit,
    onRegister: () -> Unit,
) {
    val focusManager = LocalFocusManager.current
    // iOS swaps the big hero for the small logo on 667pt-tall phones (iPhone SE/8).
    val isSmallScreen = LocalConfiguration.current.screenHeightDp <= 700
    val busy = state.loading != null

    // The form fades in, like animateShow() on iOS.
    val formAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) { formAlpha.animateTo(1f, tween(durationMillis = 700)) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(FinovaColors.Gray100)
            .pointerInput(Unit) { detectTapGestures { focusManager.clearFocus() } }
            // Keeps the hero out of the status bar and the form above the gesture bar and keyboard.
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState()),
    ) {
        if (isSmallScreen) {
            Image(
                painter = painterResource(R.drawable.finova_logo),
                contentDescription = null,
                modifier = Modifier
                    .padding(top = Spacing.S5)
                    .size(100.dp)
                    .align(Alignment.CenterHorizontally),
            )
            Spacer(Modifier.height(Spacing.S5))
        } else {
            Image(
                painter = painterResource(R.drawable.login_image),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Spacing.S3)
                    .height(LoginHeroHeight),
            )
        }

        Column(
            modifier = Modifier
                .alpha(formAlpha.value)
                .padding(start = Spacing.S8, end = Spacing.S8, top = Spacing.S6, bottom = Spacing.S4),
        ) {
            Text(
                text = stringResource(R.string.login_welcome_title).uppercase(),
                style = FinovaType.TitleSM,
                color = FinovaColors.Gray700,
            )
            Spacer(Modifier.height(Spacing.S2))
            Text(
                text = stringResource(R.string.login_welcome_subtitle),
                style = FinovaType.TextSM,
                color = FinovaColors.Gray500,
            )
            Spacer(Modifier.height(Spacing.S5))
            FinovaTextField(
                value = state.email,
                onValueChange = onEmailChange,
                placeholder = stringResource(R.string.input_email),
                type = FinovaTextFieldType.Email,
                isError = state.emailError,
                enabled = !busy,
                imeAction = ImeAction.Next,
                keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
            )
            Spacer(Modifier.height(Spacing.S3))
            FinovaTextField(
                value = state.password,
                onValueChange = onPasswordChange,
                placeholder = stringResource(R.string.input_password),
                type = FinovaTextFieldType.Password,
                isError = state.passwordError,
                enabled = !busy,
                imeAction = ImeAction.Done,
                keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
            )
            TextButton(
                onClick = {
                    focusManager.clearFocus()
                    onForgotPassword()
                },
                enabled = !busy,
                modifier = Modifier.align(Alignment.End),
            ) {
                Text(
                    text = stringResource(R.string.login_forgot_password),
                    style = FinovaType.TextSM,
                    color = FinovaColors.MainMagenta,
                )
            }
            HorizontalDivider(color = FinovaColors.Gray300)
            Spacer(Modifier.height(Spacing.S3))
            FinovaButton(
                text = stringResource(R.string.login_button),
                onClick = {
                    focusManager.clearFocus()
                    onLogin()
                },
                enabled = !busy || state.loading == SignInMethod.Email,
                loading = state.loading == SignInMethod.Email,
            )
            Spacer(Modifier.height(Spacing.S3))
            FinovaOutlinedButton(
                text = stringResource(R.string.login_google_sign_in),
                onClick = onGoogle,
                trailingIcon = R.drawable.ic_google_logo,
                enabled = !busy || state.loading == SignInMethod.Google,
                loading = state.loading == SignInMethod.Google,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 1.dp)
                    .height(44.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.login_dont_have_account),
                    style = FinovaType.TextSM,
                    color = FinovaColors.Gray500,
                )
                TextButton(onClick = onRegister, enabled = !busy) {
                    Text(
                        text = stringResource(R.string.login_register_link),
                        style = FinovaType.TextSM,
                        color = FinovaColors.MainMagenta,
                    )
                }
            }
        }
    }
}

/** The iOS alert with an email field: sends a Firebase password reset link. */
@Composable
private fun ForgotPasswordDialog(
    email: String,
    sending: Boolean,
    onEmailChange: (String) -> Unit,
    onSend: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = { if (!sending) onDismiss() },
        title = { Text(stringResource(R.string.login_forgot_password_title)) },
        text = {
            Column {
                Text(stringResource(R.string.login_forgot_password_message))
                Spacer(Modifier.height(Spacing.S3))
                FinovaTextField(
                    value = email,
                    onValueChange = onEmailChange,
                    placeholder = stringResource(R.string.input_email),
                    type = FinovaTextFieldType.Email,
                    enabled = !sending,
                    imeAction = ImeAction.Send,
                    keyboardActions = KeyboardActions(onSend = { onSend() }),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onSend, enabled = !sending) {
                Text(stringResource(R.string.login_forgot_password_send))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !sending) { Text(stringResource(R.string.alert_cancel)) }
        },
    )
}

/** Metrics.loginHeroHeight on iOS. */
internal val LoginHeroHeight = 324.dp

@Preview(showBackground = true, heightDp = 915)
@Composable
private fun LoginScreenPreview() {
    FinovaTheme {
        LoginScreen(LoginUiState(), {}, {}, {}, {}, {}, {})
    }
}
