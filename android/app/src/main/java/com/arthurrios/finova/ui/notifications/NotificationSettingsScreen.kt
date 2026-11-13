package com.arthurrios.finova.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.notifications.NotificationPreferences
import com.arthurrios.finova.notifications.NotificationSettingsStore
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * Port of NotificationSettingsView: one switch to turn everything off, then each reminder kind.
 * While everything is off the others stay visible but cannot change, as on iOS.
 */
@Composable
fun NotificationSettingsScreen(store: NotificationSettingsStore, onBack: () -> Unit) {
    val prefs by store.preferences.collectAsStateWithLifecycle()
    val enabled = !prefs.allDisabled
    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.notif_settings_title), subtitle = null, onBack = onBack)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S2),
            modifier = Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(Spacing.S4),
        ) {
            Section(stringResource(R.string.notif_settings_general))
            ToggleRow(Icons.Outlined.NotificationsOff, R.string.notif_settings_all_title, R.string.notif_settings_all_description, prefs.allDisabled) {
                store.update { p -> p.copy(allDisabled = it) }
            }
            Section(stringResource(R.string.notif_settings_local))
            ToggleRow(Icons.Outlined.ReceiptLong, R.string.notif_settings_transactions_title, R.string.notif_settings_transactions_description,
                prefs.transactions, enabled) { store.update { p -> p.copy(transactions = it) } }
            ToggleRow(Icons.Outlined.AccountBalanceWallet, R.string.notif_settings_negative_title, R.string.notif_settings_negative_description,
                prefs.negativeBalance, enabled) { store.update { p -> p.copy(negativeBalance = it) } }
            ToggleRow(Icons.Outlined.CreditCard, R.string.notif_settings_statements_title, R.string.notif_settings_statements_description,
                prefs.cardStatements, enabled) { store.update { p -> p.copy(cardStatements = it) } }
            Section(stringResource(R.string.notif_settings_push))
            ToggleRow(Icons.Outlined.SystemUpdate, R.string.notif_settings_updates_title, R.string.notif_settings_updates_description,
                prefs.appUpdates, enabled) { store.update { p -> p.copy(appUpdates = it) } }
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(title.uppercase(), style = FinovaType.TextXS, color = FinovaColors.Gray500, modifier = Modifier.padding(start = Spacing.S2, top = Spacing.S3))
}

@Composable
private fun ToggleRow(icon: ImageVector, title: Int, description: Int, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clip(RoundedCornerShape(CornerRadius.Large))
            .background(FinovaColors.Gray100)
            .alpha(if (enabled) 1f else 0.5f)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = Spacing.S4, vertical = Spacing.S3),
    ) {
        Icon(icon, contentDescription = null, tint = FinovaColors.Gray600, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.S3))
        Column(Modifier.weight(1f)) {
            Text(stringResource(title), style = FinovaType.TitleSM, color = FinovaColors.Gray700)
            Text(stringResource(description), style = FinovaType.TextXS, color = FinovaColors.Gray500)
        }
        Spacer(Modifier.width(Spacing.S2))
        Switch(
            checked = checked,
            // The row handles taps, so the switch is one target for touch and TalkBack.
            onCheckedChange = null,
            enabled = enabled,
            colors = SwitchDefaults.colors(checkedTrackColor = FinovaColors.MainMagenta),
        )
    }
}
