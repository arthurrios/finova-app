package com.arthurrios.finova.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.arthurrios.finova.R
import com.arthurrios.finova.auth.AuthError

/** The "Try again" alert iOS shows for any sign-in or sign-up failure. */
@Composable
fun AuthErrorDialog(error: AuthError, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(error.titleRes)) },
        text = { Text(stringResource(error.messageRes)) },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.error_try_again)) }
        },
    )
}

/** "Enable biometrics?" after sign-in or sign-up. */
@Composable
fun EnableBiometricsDialog(onEnable: () -> Unit, onSkip: () -> Unit) {
    val name = stringResource(R.string.biometric_name)
    AlertDialog(
        onDismissRequest = {},
        title = { Text(stringResource(R.string.faceid_enable_title, name)) },
        text = { Text(stringResource(R.string.faceid_enable_message, name)) },
        confirmButton = {
            TextButton(onClick = onEnable) { Text(stringResource(R.string.faceid_enable_button, name)) }
        },
        dismissButton = {
            TextButton(onClick = onSkip) { Text(stringResource(R.string.skip)) }
        },
    )
}
