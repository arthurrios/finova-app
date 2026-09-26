package com.arthurrios.finova.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.arthurrios.finova.MainActivity
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.notifications.PlannedNotification
import com.arthurrios.finova.domain.series.SeriesKind
import com.arthurrios.finova.ui.format.Money
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Turns planned reminders into Android notifications and records each one in the history. */
class FinovaNotifier(private val context: Context) {

    fun send(planned: List<PlannedNotification>, currencyCode: String, history: NotificationHistoryStore) {
        if (planned.isEmpty()) return
        ensureChannel()
        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        planned.forEach { item ->
            val (title, body, type) = text(item, currencyCode)
            // Recorded first: an id already in the history was sent on an earlier run today.
            if (!history.add(item.id, title, body, type)) return@forEach
            if (!allowed) return@forEach
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_bell)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(openApp())
                .setAutoCancel(true)
                .build()
            @Suppress("MissingPermission")
            NotificationManagerCompat.from(context).notify(item.id.hashCode(), notification)
        }
    }

    private fun text(item: PlannedNotification, code: String): Triple<String, String, String> {
        fun s(id: Int, vararg args: Any) = context.getString(id, *args)
        fun money(cents: Long) = Money.format(cents, code)
        return when (item) {
            is PlannedNotification.TransactionDue -> Triple(
                s(if (item.type == TransactionType.Income) R.string.notif_transaction_title_income else R.string.notif_transaction_title_expense),
                s(R.string.notif_transaction_body, money(item.amount), item.title),
                "transaction",
            )
            is PlannedNotification.SeriesMonth -> if (item.kind == SeriesKind.Installments) Triple(
                s(R.string.notif_installment_title),
                context.resources.getQuantityString(R.plurals.notif_installment_body, item.count, item.count, money(item.total)),
                "installment",
            ) else Triple(
                s(R.string.notif_recurring_title),
                context.resources.getQuantityString(R.plurals.notif_recurring_body, item.count, item.count, money(item.total)),
                "recurring",
            )
            is PlannedNotification.StatementClosed -> Triple(
                s(R.string.notif_statement_closed_title), s(R.string.notif_statement_closed_body, item.cardName, money(item.amount)), "creditCardStatement",
            )
            is PlannedNotification.StatementDue -> Triple(
                s(R.string.notif_statement_due_title), s(R.string.notif_statement_due_body, item.cardName, money(item.amount)), "creditCardStatement",
            )
            is PlannedNotification.NegativeBalanceTomorrow -> {
                // Month first in English, day first elsewhere, as iOS formats it.
                val pattern = if (Locale.getDefault().language == "en") "MM/dd" else "dd/MM"
                Triple(s(R.string.notif_negative_title), s(R.string.notif_negative_tomorrow, item.day.format(DateTimeFormatter.ofPattern(pattern))), "negativeBalance")
            }
        }
    }

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.getString(R.string.notif_channel_name), NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }

    private companion object { const val CHANNEL_ID = "finova_reminders" }
}
