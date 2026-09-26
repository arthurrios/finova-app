package com.arthurrios.finova.data

import android.content.Context
import androidx.core.content.edit
import com.arthurrios.finova.auth.AuthUser
import com.arthurrios.finova.domain.model.BusinessDayRule

/**
 * Small per-device settings. Port of the parts of UserDefaultsManager / UIDUserDefaultsManager
 * that login touches: the current user, whether they chose to stay saved, and the global
 * biometric switch.
 */
class UserSettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("finova_user_settings", Context.MODE_PRIVATE)

    var biometricEnabled: Boolean
        get() = prefs.getBoolean(KEY_BIOMETRIC_ENABLED, false)
        set(value) = prefs.edit { putBoolean(KEY_BIOMETRIC_ENABLED, value) }

    /** Hide amounts everywhere (iOS `hideValues`, a device-wide switch). */
    var hideValues: Boolean
        get() = prefs.getBoolean(KEY_HIDE_VALUES, false)
        set(value) = prefs.edit { putBoolean(KEY_HIDE_VALUES, value) }

    /**
     * The currency amounts are shown in. iOS stores "auto" (follow the phone's region) or an ISO
     * code; so does Android.
     */
    var currencySetting: String
        get() = prefs.getString(KEY_CURRENCY, CURRENCY_AUTO) ?: CURRENCY_AUTO
        set(value) = prefs.edit { putString(KEY_CURRENCY, value) }

    val currencyCode: String
        get() = currencySetting.takeUnless { it == CURRENCY_AUTO }
            ?: runCatching { java.util.Currency.getInstance(java.util.Locale.getDefault()).currencyCode }.getOrNull()
            ?: "BRL"

    /** The weekend rule new transactions start with (iOS `defaultBusinessDayRule`). */
    var defaultBusinessDayRule: BusinessDayRule
        get() = BusinessDayRule.fromKey(prefs.getString(KEY_DEFAULT_RULE, null))
        set(value) = prefs.edit { putString(KEY_DEFAULT_RULE, value.key) }

    fun currentUserName(): String? {
        val uid = prefs.getString(KEY_CURRENT_UID, null) ?: return null
        return prefs.getString(nameKey(uid), null)
    }

    /** Saves the signed-in user. A returning user keeps their saved name unless it was "User". */
    fun saveSignedInUser(user: AuthUser) {
        val savedName = prefs.getString(nameKey(user.firebaseUid), null)
        val bestName = if (savedName.isNullOrBlank() || savedName == "User") user.name else savedName
        prefs.edit {
            putString(KEY_CURRENT_UID, user.firebaseUid)
            putString(nameKey(user.firebaseUid), bestName)
            putString(emailKey(user.firebaseUid), user.email)
            putLong(lastSignInKey(user.firebaseUid), System.currentTimeMillis())
        }
    }

    /** Whether this user chose to stay signed in. A user with no record yet counts as saved. */
    fun isUserSaved(uid: String): Boolean = prefs.getBoolean(savedKey(uid), true)

    /** Forgets who is signed in on this device (their per-user settings stay). */
    fun clearCurrentUser() = prefs.edit { remove(KEY_CURRENT_UID) }

    fun setCurrentUserSaved(saved: Boolean) {
        val uid = prefs.getString(KEY_CURRENT_UID, null) ?: return
        prefs.edit { putBoolean(savedKey(uid), saved) }
    }

    private fun nameKey(uid: String) = "user_${uid}_name"
    private fun emailKey(uid: String) = "user_${uid}_email"
    private fun savedKey(uid: String) = "user_${uid}_is_saved"
    private fun lastSignInKey(uid: String) = "user_${uid}_last_sign_in"

    private companion object {
        const val KEY_CURRENT_UID = "current_user_uid"
        const val KEY_BIOMETRIC_ENABLED = "biometric_enabled"
        const val KEY_HIDE_VALUES = "hide_values"
        const val KEY_CURRENCY = "currency_code"
        const val CURRENCY_AUTO = "auto"
        const val KEY_DEFAULT_RULE = "default_business_day_rule"
    }
}
