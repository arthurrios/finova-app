package com.arthurrios.finova.ui.splash

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.BiometricResult
import com.arthurrios.finova.security.Biometrics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Where the splash sends the user. */
enum class SplashStep {
    /** Still showing the logo. */
    Waiting,

    /** Ask for a fingerprint or face before opening the app. */
    AskBiometrics,

    /** Play the logo-up animation, then open login. */
    GoToLogin,

    /** Open login straight away (after a failed or cancelled unlock). */
    GoToLoginNow,

    GoToDashboard,
}

/** Port of the decision in SplashViewController.decideNavigationFlow() on iOS. */
class SplashViewModel(
    private val authRepository: AuthRepository,
    private val settings: UserSettingsStore,
    private val biometrics: Biometrics,
) : ViewModel() {

    private val _step = MutableStateFlow(SplashStep.Waiting)
    val step: StateFlow<SplashStep> = _step.asStateFlow()

    fun decide() {
        if (_step.value != SplashStep.Waiting) return
        // iOS also has a path for a saved user with no Firebase session, but every branch of it
        // ends on login, so Android goes there directly.
        val user = authRepository.currentUser() ?: return go(SplashStep.GoToLogin)
        settings.saveSignedInUser(user)

        val next = when {
            !settings.isUserSaved(user.firebaseUid) || !settings.biometricEnabled -> SplashStep.GoToLogin
            biometrics.isAvailable -> SplashStep.AskBiometrics
            // Biometrics were switched on but are gone now (e.g. fingerprints removed).
            else -> SplashStep.GoToDashboard
        }
        go(next)
    }

    suspend fun unlock(activity: FragmentActivity, title: String, reason: String, cancel: String) =
        onBiometricResult(biometrics.authenticate(activity, title, reason, cancel))

    fun onBiometricResult(result: BiometricResult) = when (result) {
        BiometricResult.Success -> go(SplashStep.GoToDashboard)
        BiometricResult.LockedOut -> {
            authRepository.signOut()
            settings.clearCurrentUser()
            go(SplashStep.GoToLoginNow)
        }
        BiometricResult.Cancelled, BiometricResult.Unavailable -> go(SplashStep.GoToLoginNow)
    }

    private fun go(step: SplashStep) {
        _step.value = step
    }
}
