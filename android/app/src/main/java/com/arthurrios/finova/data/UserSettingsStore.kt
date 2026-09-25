package com.arthurrios.finova.data

import android.content.Context
import androidx.core.content.edit
import com.arthurrios.finova.auth.AuthUser

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
    }
}
