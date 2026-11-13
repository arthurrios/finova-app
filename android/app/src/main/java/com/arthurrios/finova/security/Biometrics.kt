package com.arthurrios.finova.security

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

enum class BiometricResult { Success, Cancelled, LockedOut, Unavailable }

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

    /**
     * Shows the system biometric sheet. Port of FaceIDManager.authenticateWithBiometrics on iOS.
     * Needs a FragmentActivity, which MainActivity is.
     */
    suspend fun authenticate(
        activity: FragmentActivity,
        title: String,
        subtitle: String,
        cancel: String,
    ): BiometricResult = suspendCancellableCoroutine { continuation ->
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (continuation.isActive) continuation.resume(BiometricResult.Success)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    val result = when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_CANCELED -> BiometricResult.Cancelled
                        // Too many failed tries: iOS signs the user out here.
                        BiometricPrompt.ERROR_LOCKOUT,
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> BiometricResult.LockedOut
                        else -> BiometricResult.Unavailable
                    }
                    if (continuation.isActive) continuation.resume(result)
                }
                // onAuthenticationFailed is one wrong finger; the sheet stays up, so no result yet.
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText(cancel)
            .setAllowedAuthenticators(authenticators)
            .build()
        prompt.authenticate(info)
        continuation.invokeOnCancellation { prompt.cancelAuthentication() }
    }

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
