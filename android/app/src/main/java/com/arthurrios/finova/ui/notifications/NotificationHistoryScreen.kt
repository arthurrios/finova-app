package com.arthurrios.finova.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.notifications.NotificationHistoryItem
import com.arthurrios.finova.notifications.NotificationHistoryStore
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.DeleteBackground
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Port of NotificationHistoryView: the notifications already sent, newest first. Unread ones carry
 * a dot until the screen is left; swipe left deletes one, Clear All empties the list.
 */
@Composable
fun NotificationHistoryScreen(store: NotificationHistoryStore, onBack: () -> Unit) {
    val items by store.items.collectAsStateWithLifecycle()
    var confirmClear by remember { mutableStateOf(false) }
    // Seen once the list has been shown; marked on the way out so the dots are visible first.
    DisposableEffect(Unit) { onDispose { store.markAllRead() } }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.notif_history_title),
            subtitle = null,
            onBack = onBack,
            trailing = if (items.isEmpty()) null else {
                { TextButton(onClick = { confirmClear = true }) { Text(stringResource(R.string.notif_history_clear), color = FinovaColors.MainMagenta) } }
            },
        )
        if (items.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(Spacing.S8), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.Notifications, contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(40.dp))
                Spacer(Modifier.height(Spacing.S4))
                Text(stringResource(R.string.notif_history_empty_title), style = FinovaType.TitleSM, color = FinovaColors.Gray600)
                Text(stringResource(R.string.notif_history_empty_subtitle), style = FinovaType.TextSM, color = FinovaColors.Gray500)
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(Spacing.S4),
                verticalArrangement = Arrangement.spacedBy(Spacing.S2),
                modifier = Modifier.fillMaxSize().navigationBarsPadding(),
            ) {
                items(items, key = { it.id }) { item -> HistoryRow(item, onDelete = { store.delete(item.id) }) }
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(stringResource(R.string.notif_history_clear_title)) },
            text = { Text(stringResource(R.string.notif_history_clear_message)) },
            confirmButton = {
                TextButton(onClick = { confirmClear = false; store.clear() }) {
                    Text(stringResource(R.string.notif_history_clear), color = FinovaColors.MainRed)
                }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
}

@Composable
private fun HistoryRow(item: NotificationHistoryItem, onDelete: () -> Unit) {
    @Suppress("DEPRECATION")
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { if (it == SwipeToDismissBoxValue.EndToStart) onDelete(); false })
    val shape = RoundedCornerShape(CornerRadius.Large)
    Box(Modifier.clip(shape)) {
        SwipeToDismissBox(state = state, enableDismissFromStartToEnd = false, backgroundContent = { DeleteBackground() }) {
            Row(
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth().background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, shape).padding(Spacing.S4),
            ) {
                Box(Modifier.size(32.dp).clip(CircleShape).background(FinovaColors.LowMagenta), contentAlignment = Alignment.Center) {
                    Icon(item.icon, contentDescription = null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(Spacing.S3))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(item.title, style = FinovaType.TitleSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
                        Text(whenLabel(item.timeMillis), style = FinovaType.TextXS, color = FinovaColors.Gray500)
                        if (!item.isRead) {
                            Spacer(Modifier.width(Spacing.S2))
                            Box(Modifier.size(8.dp).clip(CircleShape).background(FinovaColors.MainMagenta))
                        }
                    }
                    Spacer(Modifier.height(Spacing.S1))
                    Text(item.body, style = FinovaType.TextSM, color = FinovaColors.Gray600)
                }
            }
        }
    }
}

/** Time today, "Yesterday", or the date. */
@Composable
private fun whenLabel(millis: Long): String {
    val moment = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault())
    val today = LocalDate.now()
    return when (moment.toLocalDate()) {
        today -> moment.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
        today.minusDays(1) -> stringResource(R.string.notif_history_yesterday)
        else -> moment.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT))
    }
}

private val NotificationHistoryItem.icon: ImageVector
    get() = when (type) {
        "transaction" -> Icons.Outlined.ReceiptLong
        "installment", "recurring" -> Icons.Outlined.Repeat
        "creditCardStatement" -> Icons.Outlined.CreditCard
        "negativeBalance" -> Icons.Outlined.AccountBalanceWallet
        "appUpdate" -> Icons.Outlined.SystemUpdate
        else -> Icons.Outlined.Notifications
    }
