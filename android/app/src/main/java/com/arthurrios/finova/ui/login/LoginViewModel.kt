package com.arthurrios.finova.ui.login

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.R
import com.arthurrios.finova.auth.AuthError
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.auth.AuthUser
import com.arthurrios.finova.auth.SignInCancelled
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.Biometrics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class SignInMethod { Email, Google }

/** The dialogs login can show after a successful sign-in. */
enum class BiometricDialog { OfferEnable, NotEnrolled }

data class LoginUiState(
    val email: String = "",
    val password: String = "",
    val emailError: Boolean = false,
    val passwordError: Boolean = false,
    val loading: SignInMethod? = null,
    val error: AuthError? = null,
    val biometricDialog: BiometricDialog? = null,
    val signedIn: Boolean = false,
    /** Non-null while the "Forgot password?" dialog is open; holds the email typed there. */
    val resetEmail: String? = null,
    val resetSending: Boolean = false,
    /** The address a reset link was just sent to; shows the "check your email" dialog. */
    val resetSentTo: String? = null,
)

/** Port of LoginViewModel.swift plus the post-login flow in LoginViewController.swift. */
class LoginViewModel(
    private val authRepository: AuthRepository,
    private val settings: UserSettingsStore,
    private val biometrics: Biometrics,
) : ViewModel() {

    private val _state = MutableStateFlow(LoginUiState())
    val state: StateFlow<LoginUiState> = _state.asStateFlow()

    fun onEmailChange(value: String) = _state.update { it.copy(email = value, emailError = false) }

    fun onPasswordChange(value: String) = _state.update { it.copy(password = value, passwordError = false) }

    /** Same check as iOS: both fields must have text; empty ones turn red. */
    fun signInWithEmail() {
        val current = _state.value
        val emailMissing = current.email.isEmpty()
        val passwordMissing = current.password.isEmpty()
        if (emailMissing || passwordMissing) {
            _state.update { it.copy(emailError = emailMissing, passwordError = passwordMissing) }
            return
        }
        signIn(SignInMethod.Email) { authRepository.signInWithEmail(current.email, current.password) }
    }

    fun signInWithGoogle(activity: Activity) =
        signIn(SignInMethod.Google) { authRepository.signInWithGoogle(activity) }

    fun dismissError() = _state.update { it.copy(error = null) }

    /** Opens the reset dialog with the email already typed on the login form, like iOS. */
    fun onForgotPassword() = _state.update { it.copy(resetEmail = it.email.trim()) }

    fun onResetEmailChange(value: String) = _state.update { it.copy(resetEmail = value) }

    fun dismissReset() = _state.update { it.copy(resetEmail = null) }

    fun dismissResetSent() = _state.update { it.copy(resetSentTo = null) }

    fun sendPasswordReset() {
        val current = _state.value
        if (current.resetSending) return
        val email = current.resetEmail?.trim().orEmpty()
        if (email.isEmpty()) {
            val invalid = AuthError(R.string.auth_error_title, R.string.auth_error_invalid_email)
            _state.update { it.copy(resetEmail = null, error = invalid) }
            return
        }
        _state.update { it.copy(resetSending = true) }
        viewModelScope.launch {
            try {
                authRepository.sendPasswordReset(email)
                _state.update { it.copy(resetSending = false, resetEmail = null, resetSentTo = email) }
            } catch (e: AuthError) {
                _state.update { it.copy(resetSending = false, resetEmail = null, error = e) }
            }
        }
    }

    fun onEnableBiometrics() {
        settings.setCurrentUserSaved(true)
        if (biometrics.isAvailable) {
            settings.biometricEnabled = true
            finish()
        } else {
            _state.update { it.copy(biometricDialog = BiometricDialog.NotEnrolled) }
        }
    }

    fun onSkipBiometrics() {
        // "Skip" on the offer still saves the user; on the not-enrolled dialog it was saved already.
        settings.setCurrentUserSaved(true)
        finish()
    }

    fun onOpenBiometricSettings() {
        biometrics.openEnrollSettings()
        finish()
    }

    private fun signIn(method: SignInMethod, block: suspend () -> AuthUser) {
        if (_state.value.loading != null) return
        _state.update { it.copy(loading = method) }
        viewModelScope.launch {
            try {
                val user = block()
                settings.saveSignedInUser(user)
                afterSignIn()
            } catch (e: SignInCancelled) {
                _state.update { it.copy(loading = null) }
            } catch (e: AuthError) {
                _state.update { it.copy(loading = null, error = e) }
            }
        }
    }

    private fun afterSignIn() {
        // Offer biometrics whenever the device has them and they are not switched on yet.
        if (biometrics.deviceSupportsBiometrics && !settings.biometricEnabled) {
            _state.update { it.copy(loading = null, biometricDialog = BiometricDialog.OfferEnable) }
        } else {
            finish()
        }
    }

    private fun finish() =
        _state.update { it.copy(loading = null, biometricDialog = null, signedIn = true) }
}
