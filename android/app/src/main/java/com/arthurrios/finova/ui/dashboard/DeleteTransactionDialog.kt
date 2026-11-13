package com.arthurrios.finova.ui.dashboard

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.domain.series.SeriesKind
import com.arthurrios.finova.ui.theme.FinovaColors

/**
 * The delete question. Port of `showTransactionDeletionOptions` on iOS: a plain "Are you sure?"
 * for a one-off, and three choices plus Cancel for a recurring or installment row.
 */
@Composable
fun DeleteTransactionDialog(kind: SeriesKind, onDelete: (SeriesDeleteOption) -> Unit, onDismiss: () -> Unit) {
    if (kind == SeriesKind.Simple) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.transaction_delete_title)) },
            text = { Text(stringResource(R.string.delete_confirmation)) },
            confirmButton = {
                TextButton(onClick = { onDelete(SeriesDeleteOption.ThisOnly) }) {
                    Text(stringResource(R.string.alert_delete), color = FinovaColors.MainRed)
                }
            },
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
        )
        return
    }
    val recurring = kind == SeriesKind.Recurring
    val choices = listOf(
        SeriesDeleteOption.ThisOnly to if (recurring) R.string.recurring_delete_current else R.string.installment_delete_current,
        SeriesDeleteOption.ThisAndLater to if (recurring) R.string.recurring_delete_future else R.string.installment_delete_remaining,
        SeriesDeleteOption.All to if (recurring) R.string.recurring_delete_all else R.string.installment_delete_all,
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(if (recurring) R.string.recurring_delete_title else R.string.installment_delete_title)) },
        text = {
            Column {
                Text(stringResource(if (recurring) R.string.recurring_delete_message else R.string.installment_delete_message))
                choices.forEach { (option, label) ->
                    TextButton(onClick = { onDelete(option) }, modifier = Modifier.fillMaxWidth().align(Alignment.End)) {
                        Text(
                            stringResource(label),
                            // iOS marks "all" as the destructive choice.
                            color = if (option == SeriesDeleteOption.All) FinovaColors.MainRed else FinovaColors.MainMagenta,
                            modifier = Modifier.fillMaxWidth(),
                            textAlign = androidx.compose.ui.text.style.TextAlign.End,
                        )
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}
