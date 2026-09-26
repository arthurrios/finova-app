package com.arthurrios.finova.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Port of SettingsView: security, preferences, notifications, about and account. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    onBack: () -> Unit,
    onNotifications: () -> Unit,
    onSignedOut: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val activity = LocalContext.current as? FragmentActivity
    var pickingCurrency by rememberSaveable { mutableStateOf(false) }
    val deviceCurrency = remember { runCatching { java.util.Currency.getInstance(java.util.Locale.getDefault()).currencyCode }.getOrDefault("BRL") }
    val biometricName = stringResource(R.string.biometric_name)
    val promptTitle = stringResource(R.string.biometric_prompt_title)
    val enableReason = stringResource(R.string.settings_biometric_enable_reason)
    val cancel = stringResource(R.string.alert_cancel)

    LifecycleResumeEffect(Unit) {
        viewModel.refresh()
        onPauseOrDispose { }
    }
    LaunchedEffect(state.signedOut) { if (state.signedOut) onSignedOut() }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
            ScreenHeader(title = stringResource(R.string.settings_title), subtitle = null, onBack = onBack)
            Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.S4),
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .navigationBarsPadding()
                    .padding(Spacing.S4),
            ) {
                Section(stringResource(R.string.settings_section_security))
                Row(Icons.Outlined.Fingerprint, biometricName) {
                    Switch(
                        checked = state.biometricEnabled,
                        onCheckedChange = { viewModel.setBiometric(it, activity, promptTitle, enableReason, cancel) },
                        colors = SwitchDefaults.colors(checkedTrackColor = FinovaColors.MainMagenta),
                    )
                }
                Section(stringResource(R.string.settings_section_preferences))
                Row(Icons.Outlined.Payments, stringResource(R.string.settings_currency), onClick = { pickingCurrency = true }) {
                    Text(currencyLabel(state.currency, deviceCurrency), style = FinovaType.TextSM, color = FinovaColors.Gray500)
                    Spacer(Modifier.width(Spacing.S2))
                    Chevron()
                }
                Section(stringResource(R.string.settings_section_notifications))
                Row(Icons.Outlined.Notifications, stringResource(R.string.settings_notifications), onClick = onNotifications) { Chevron() }
                Section(stringResource(R.string.settings_section_about))
                Row(Icons.Outlined.Info, stringResource(R.string.settings_version)) {
                    Text(viewModel.appVersion, style = FinovaType.TextSM, color = FinovaColors.Gray500)
                }
                Section(stringResource(R.string.settings_section_account))
                Row(Icons.Outlined.Delete, stringResource(R.string.settings_delete_account), tint = FinovaColors.MainRed, onClick = viewModel::askDelete) {}
            }
        }
        if (state.deleting) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.S3),
                    modifier = Modifier.clip(RoundedCornerShape(CornerRadius.ExtraLarge)).background(FinovaColors.Gray100).padding(Spacing.S6)) {
                    CircularProgressIndicator(color = FinovaColors.MainMagenta)
                    Text(stringResource(R.string.settings_delete_processing), style = FinovaType.TextSM, color = FinovaColors.Gray700)
                }
            }
        }
    }

    if (pickingCurrency) {
        ModalBottomSheet(
            onDismissRequest = { pickingCurrency = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
            containerColor = FinovaColors.Gray100,
        ) {
            Text(stringResource(R.string.settings_currency_picker_title), style = FinovaType.TitleSM, color = FinovaColors.Gray700,
                modifier = Modifier.padding(horizontal = Spacing.S6))
            Text(stringResource(R.string.settings_currency_picker_message), style = FinovaType.TextSM, color = FinovaColors.Gray500,
                modifier = Modifier.padding(start = Spacing.S6, end = Spacing.S6, top = Spacing.S1, bottom = Spacing.S3))
            val options = listOf(UserSettingsStore.CURRENCY_AUTO to currencyLabel(UserSettingsStore.CURRENCY_AUTO, deviceCurrency)) +
                SettingsViewModel.currencies.map { (code, name) -> code to "$code - $name" }
            LazyColumn(Modifier.navigationBarsPadding()) {
                items(options, key = { it.first }) { (code, label) ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectable(selected = state.currency == code, role = Role.RadioButton) {
                                viewModel.setCurrency(code)
                                pickingCurrency = false
                            }
                            .padding(horizontal = Spacing.S5, vertical = Spacing.S3),
                    ) {
                        RadioButton(selected = state.currency == code, onClick = null,
                            colors = RadioButtonDefaults.colors(selectedColor = FinovaColors.MainMagenta))
                        Spacer(Modifier.width(Spacing.S3))
                        Text(label, style = FinovaType.TextSM, color = FinovaColors.Gray700)
                    }
                }
            }
        }
    }

    when (state.dialog) {
        SettingsDialog.BiometricNotEnrolled -> SimpleDialog(
            title = biometricName,
            text = stringResource(R.string.settings_biometric_not_enrolled_message, biometricName),
            confirm = stringResource(R.string.settings_biometric_open_settings),
            onConfirm = viewModel::openBiometricSettings,
            onDismiss = viewModel::dismissDialog,
        )
        SettingsDialog.BiometricError -> SimpleDialog(
            title = stringResource(R.string.settings_biometric_error_title),
            text = stringResource(R.string.settings_biometric_error_message),
            confirm = stringResource(R.string.alert_ok),
            onConfirm = viewModel::dismissDialog,
            onDismiss = null,
        )
        SettingsDialog.DeleteConfirm -> SimpleDialog(
            title = stringResource(R.string.settings_delete_account),
            text = stringResource(R.string.settings_delete_warning),
            confirm = stringResource(R.string.settings_delete_confirm),
            danger = true,
            onConfirm = viewModel::deleteAccount,
            onDismiss = viewModel::dismissDialog,
        )
        SettingsDialog.NeedsRecentLogin -> SimpleDialog(
            title = stringResource(R.string.settings_reauth_title),
            text = stringResource(R.string.settings_reauth_message),
            confirm = stringResource(R.string.settings_reauth_signout),
            onConfirm = viewModel::signOutAndClear,
            onDismiss = viewModel::dismissDialog,
        )
        SettingsDialog.Deleted -> SimpleDialog(
            title = stringResource(R.string.settings_deleted_title),
            text = stringResource(R.string.settings_deleted_message),
            confirm = stringResource(R.string.alert_ok),
            onConfirm = viewModel::finishDeleted,
            onDismiss = null,
        )
        SettingsDialog.DeleteFailed -> SimpleDialog(
            title = stringResource(R.string.settings_delete_error_title),
            text = stringResource(R.string.settings_delete_error_message),
            confirm = stringResource(R.string.alert_ok),
            onConfirm = viewModel::dismissDialog,
            onDismiss = null,
        )
        null -> Unit
    }
}

@Composable
private fun currencyLabel(setting: String, device: String): String =
    if (setting == UserSettingsStore.CURRENCY_AUTO) "${stringResource(R.string.settings_currency_auto)} ($device)" else setting

@Composable
private fun Section(title: String) {
    Text(title.uppercase(), style = FinovaType.TextXS, color = FinovaColors.Gray500, modifier = Modifier.padding(start = Spacing.S2, top = Spacing.S2))
}

@Composable
private fun Chevron() {
    Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(12.dp))
}

/** One 56dp settings row with whatever sits at its end (a switch, a value, a chevron). */
@Composable
private fun Row(
    icon: ImageVector,
    label: String,
    tint: Color = FinovaColors.Gray600,
    onClick: (() -> Unit)? = null,
    trailing: @Composable () -> Unit,
) {
    androidx.compose.foundation.layout.Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(CornerRadius.Large))
            .background(FinovaColors.Gray100)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = Spacing.S4),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.S3))
        Text(label, style = FinovaType.TitleSM, color = if (tint == FinovaColors.MainRed) tint else FinovaColors.Gray700, modifier = Modifier.weight(1f))
        trailing()
    }
}

@Composable
private fun SimpleDialog(
    title: String,
    text: String,
    confirm: String,
    onConfirm: () -> Unit,
    onDismiss: (() -> Unit)?,
    danger: Boolean = false,
) {
    AlertDialog(
        onDismissRequest = { onDismiss?.invoke() ?: onConfirm() },
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(confirm, color = if (danger) FinovaColors.MainRed else Color.Unspecified) }
        },
        dismissButton = onDismiss?.let { dismiss -> { TextButton(onClick = dismiss) { Text(stringResource(R.string.alert_cancel)) } } },
    )
}
