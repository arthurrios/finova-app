package com.arthurrios.finova.security

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK

/** Port of the checks FaceIDManager.swift does on iOS. */
class Biometrics(private val context: Context) {
    private val manager = BiometricManager.from(context)
    private val authenticators = BIOMETRIC_STRONG or BIOMETRIC_WEAK

    /** The device has biometric hardware, enrolled or not. */
    val deviceSupportsBiometrics: Boolean
        get() = when (manager.canAuthenticate(authenticators)) {
            BiometricManager.BIOMETRIC_SUCCESS,
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> true
            else -> false
        }

    /** A fingerprint or face is enrolled and ready. */
    val isAvailable: Boolean
        get() = manager.canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS

    /** Opens the system screen to enroll a fingerprint or face. */
    fun openEnrollSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_BIOMETRIC_ENROLL)
                .putExtra(Settings.EXTRA_BIOMETRIC_AUTHENTICATORS_ALLOWED, authenticators)
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
