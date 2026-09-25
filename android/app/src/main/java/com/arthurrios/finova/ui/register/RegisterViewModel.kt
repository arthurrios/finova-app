package com.arthurrios.finova.ui.register

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.auth.AuthError
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.Biometrics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class RegisterUiState(
    val name: String = "",
    val email: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val loading: Boolean = false,
    val error: AuthError? = null,
    val offerBiometrics: Boolean = false,
    val registered: Boolean = false,
) {
    val canSubmit: Boolean
        get() = RegisterValidation.isFormValid(name, email, password, confirmPassword)
}

/** Port of RegisterViewModel.swift plus the post-sign-up flow in RegisterViewController.swift. */
class RegisterViewModel(
    private val authRepository: AuthRepository,
    private val settings: UserSettingsStore,
    private val biometrics: Biometrics,
) : ViewModel() {

    private val _state = MutableStateFlow(RegisterUiState())
    val state: StateFlow<RegisterUiState> = _state.asStateFlow()

    fun onNameChange(value: String) = _state.update { it.copy(name = value) }
    fun onEmailChange(value: String) = _state.update { it.copy(email = value) }
    fun onPasswordChange(value: String) = _state.update { it.copy(password = value) }
    fun onConfirmPasswordChange(value: String) = _state.update { it.copy(confirmPassword = value) }

    fun register() {
        val current = _state.value
        // The button is disabled until the form is valid; this guards a double tap.
        if (current.loading || !current.canSubmit) return
        _state.update { it.copy(loading = true) }
        viewModelScope.launch {
            try {
                val user = authRepository.register(current.name.trim(), current.email, current.password)
                settings.saveSignedInUser(user)
                // A new account is always offered biometrics, but only when they are ready to use.
                if (biometrics.isAvailable) {
                    _state.update { it.copy(loading = false, offerBiometrics = true) }
                } else {
                    finish()
                }
            } catch (e: AuthError) {
                _state.update { it.copy(loading = false, error = e) }
            }
        }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    fun onEnableBiometrics() {
        // iOS stores this on the user; login reads the global switch, so set that one here too.
        settings.biometricEnabled = true
        finish()
    }

    fun onSkipBiometrics() = finish()

    private fun finish() {
        settings.setCurrentUserSaved(true)
        _state.update { it.copy(loading = false, offerBiometrics = false, registered = true) }
    }
}
