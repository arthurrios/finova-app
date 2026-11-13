package com.arthurrios.finova.notifications

import android.content.Context
import androidx.core.content.edit
import com.arthurrios.finova.domain.notifications.NotificationPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

/** The reminder switches. Port of NotificationPreferencesManager; device-wide, as on iOS. */
class NotificationSettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("finova_notification_prefs", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(read())
    val preferences: StateFlow<NotificationPreferences> = state

    fun update(change: (NotificationPreferences) -> NotificationPreferences) {
        val next = change(state.value)
        prefs.edit {
            putBoolean("allDisabled", next.allDisabled)
            putBoolean("transactions", next.transactions)
            putBoolean("appUpdates", next.appUpdates)
            putBoolean("negativeBalance", next.negativeBalance)
            putBoolean("creditCardStatement", next.cardStatements)
        }
        state.value = next
    }

    private fun read() = NotificationPreferences(
        allDisabled = prefs.getBoolean("allDisabled", false),
        transactions = prefs.getBoolean("transactions", true),
        appUpdates = prefs.getBoolean("appUpdates", true),
        negativeBalance = prefs.getBoolean("negativeBalance", true),
        cardStatements = prefs.getBoolean("creditCardStatement", true),
    )
}

data class NotificationHistoryItem(
    val id: String,
    val title: String,
    val body: String,
    val timeMillis: Long,
    val type: String,
    val isRead: Boolean,
    /** An encoded NotificationTarget, or null. */
    val target: String? = null,
)

/**
 * Notifications already sent, newest first, at most 50. Port of NotificationHistoryManager, but kept
 * per account: iOS keeps one list for the whole device, so a second account sees the first one's.
 */
class NotificationHistoryStore(context: Context, val uid: String) {
    private val prefs = context.getSharedPreferences("finova_notification_history", Context.MODE_PRIVATE)
    private val key = "history_$uid"
    private val state = MutableStateFlow(read())
    val items: StateFlow<List<NotificationHistoryItem>> = state

    /** Adds an item; returns false when this id was already recorded (it was sent before). */
    fun add(id: String, title: String, body: String, type: String, target: String? = null, now: Long = System.currentTimeMillis()): Boolean {
        if (state.value.any { it.id == id }) return false
        write((listOf(NotificationHistoryItem(id, title, body, now, type, false, target)) + state.value).take(MAX))
        return true
    }

    fun markAllRead() {
        if (state.value.any { !it.isRead }) write(state.value.map { it.copy(isRead = true) })
    }

    fun markRead(id: String) {
        if (state.value.any { it.id == id && !it.isRead }) write(state.value.map { if (it.id == id) it.copy(isRead = true) else it })
    }

    fun delete(id: String) = write(state.value.filterNot { it.id == id })
    fun clear() = write(emptyList())
    fun removeAll() = prefs.edit { remove(key) }

    private fun write(items: List<NotificationHistoryItem>) {
        state.value = items
        prefs.edit {
            putString(key, JSONArray().apply {
                items.forEach { item ->
                    put(JSONObject().apply {
                        put("id", item.id); put("title", item.title); put("body", item.body)
                        put("time", item.timeMillis); put("type", item.type); put("read", item.isRead)
                        item.target?.let { put("target", it) }
                    })
                }
            }.toString())
        }
    }

    private fun read(): List<NotificationHistoryItem> = runCatching {
        val array = JSONArray(prefs.getString(key, null) ?: return emptyList())
        (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            NotificationHistoryItem(
                o.getString("id"), o.getString("title"), o.getString("body"), o.getLong("time"), o.optString("type"), o.optBoolean("read"),
                o.optString("target").takeIf { it.isNotEmpty() },
            )
        }
    }.getOrDefault(emptyList())

    private companion object { const val MAX = 50 }
}
