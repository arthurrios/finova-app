package com.arthurrios.finova.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.arthurrios.finova.appContainer
import com.arthurrios.finova.domain.notifications.NotificationPlanner
import kotlinx.coroutines.flow.first
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.concurrent.TimeUnit

/**
 * Runs each morning and sends the day's reminders for whoever is signed in. Android's answer to the
 * iOS pending-notification schedule: nothing to reschedule when data changes, and no 64-item limit.
 */
class DailyNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val container = applicationContext.appContainer
        // Signed out, this reads the empty local account, so nothing is sent.
        val repo = container.financeRepository()
        val planned = NotificationPlanner.plan(
            today = LocalDate.now(),
            rows = repo.ledgerRows.first(),
            statements = repo.statements.first(),
            cards = repo.allCards.first(),
            balanceOffset = repo.balanceOffset.first(),
            prefs = container.notificationSettings.preferences.value,
        )
        FinovaNotifier(applicationContext).send(planned, container.settings.currencyCode, container.notificationHistory())
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "finova_daily_reminders"
        private val SendAt: LocalTime = LocalTime.of(8, 0)

        /** Schedules the morning run once; later calls keep the existing schedule. */
        fun schedule(context: Context, now: LocalDateTime = LocalDateTime.now()) {
            var next = now.toLocalDate().atTime(SendAt)
            if (!next.isAfter(now)) next = next.plusDays(1)
            val request = PeriodicWorkRequestBuilder<DailyNotificationWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(Duration.between(now, next).toMinutes(), TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
