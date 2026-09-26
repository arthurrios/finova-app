package com.arthurrios.finova.ui.settings

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.AppContainer
import com.arthurrios.finova.auth.AuthRepository.DeleteResult
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.BiometricResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What a dialog on the screen should show. */
enum class SettingsDialog { BiometricNotEnrolled, BiometricError, DeleteConfirm, NeedsRecentLogin, Deleted, DeleteFailed }

data class SettingsUiState(
    val biometricEnabled: Boolean = false,
    /** A currency code or [UserSettingsStore.CURRENCY_AUTO]. */
    val currency: String = UserSettingsStore.CURRENCY_AUTO,
    val deleting: Boolean = false,
    val dialog: SettingsDialog? = null,
    /** Set once the user is signed out, so the screen goes to login. */
    val signedOut: Boolean = false,
)

/** Port of SettingsViewModel.swift (tag translation is iOS 26 only and not ported). */
class SettingsViewModel(private val container: AppContainer, val appVersion: String) : ViewModel() {
    private val settings get() = container.settings
    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    /** Also runs on return from the system settings, where biometrics may have been set up. */
    fun refresh() {
        // A switch left on after biometrics were removed from the phone is turned off, as on iOS.
        if (!container.biometrics.isAvailable) settings.biometricEnabled = false
        _state.update { it.copy(biometricEnabled = settings.biometricEnabled, currency = settings.currencySetting) }
    }

    fun setBiometric(on: Boolean, activity: FragmentActivity?, title: String, reason: String, cancel: String) {
        if (!on) {
            settings.biometricEnabled = false
            refresh()
            return
        }
        if (!container.biometrics.isAvailable || activity == null) {
            _state.update { it.copy(dialog = SettingsDialog.BiometricNotEnrolled) }
            return
        }
        viewModelScope.launch {
            // Turning it on asks for the biometric once, so it is known to work.
            when (container.biometrics.authenticate(activity, title, reason, cancel)) {
                BiometricResult.Success -> settings.biometricEnabled = true
                BiometricResult.Cancelled -> Unit
                else -> _state.update { it.copy(dialog = SettingsDialog.BiometricError) }
            }
            refresh()
        }
    }

    fun openBiometricSettings() {
        dismissDialog()
        container.biometrics.openEnrollSettings()
    }

    fun setCurrency(code: String) {
        settings.currencySetting = code
        refresh()
    }

    fun askDelete() = _state.update { it.copy(dialog = SettingsDialog.DeleteConfirm) }

    fun dismissDialog() = _state.update { it.copy(dialog = null) }

    /**
     * Deletes the account first and clears this phone's copy only once that worked. (iOS clears
     * first, so a deletion Firebase refuses still wipes the data.) Without a Firebase account (a
     * build without Firebase) there is only local data, so that is what goes.
     */
    fun deleteAccount() {
        val uid = container.currentUid()
        _state.update { it.copy(dialog = null, deleting = true) }
        viewModelScope.launch {
            val result = container.authRepository.deleteAccount()
            _state.update { it.copy(deleting = false) }
            when (result) {
                DeleteResult.Deleted, DeleteResult.NoAccount -> {
                    container.clearLocalData(uid)
                    _state.update { it.copy(dialog = SettingsDialog.Deleted) }
                }
                DeleteResult.NeedsRecentLogin -> _state.update { it.copy(dialog = SettingsDialog.NeedsRecentLogin) }
                DeleteResult.Failed -> _state.update { it.copy(dialog = SettingsDialog.DeleteFailed) }
            }
        }
    }

    /** "Sign Out & Clear Data" when Firebase wants a recent sign-in before deleting. */
    fun signOutAndClear() {
        val uid = container.currentUid()
        container.authRepository.signOut()
        container.clearLocalData(uid)
        _state.update { it.copy(dialog = null, signedOut = true) }
    }

    fun finishDeleted() {
        container.authRepository.signOut()
        _state.update { it.copy(dialog = null, signedOut = true) }
    }

    companion object {
        /** SettingsViewModel.availableCurrencies on iOS, same order. */
        val currencies = listOf(
            "USD" to "US Dollar", "EUR" to "Euro", "GBP" to "British Pound", "JPY" to "Japanese Yen",
            "BRL" to "Brazilian Real", "CAD" to "Canadian Dollar", "AUD" to "Australian Dollar", "CHF" to "Swiss Franc",
            "CNY" to "Chinese Yuan", "INR" to "Indian Rupee", "MXN" to "Mexican Peso", "KRW" to "South Korean Won",
            "SGD" to "Singapore Dollar", "HKD" to "Hong Kong Dollar", "NOK" to "Norwegian Krone", "SEK" to "Swedish Krona",
            "DKK" to "Danish Krone", "NZD" to "New Zealand Dollar", "ZAR" to "South African Rand", "RUB" to "Russian Ruble",
            "TRY" to "Turkish Lira", "PLN" to "Polish Zloty", "THB" to "Thai Baht", "IDR" to "Indonesian Rupiah",
            "MYR" to "Malaysian Ringgit", "PHP" to "Philippine Peso", "CZK" to "Czech Koruna", "ILS" to "Israeli Shekel",
            "CLP" to "Chilean Peso", "COP" to "Colombian Peso", "ARS" to "Argentine Peso", "PEN" to "Peruvian Sol",
            "AED" to "UAE Dirham", "SAR" to "Saudi Riyal",
        )
    }
}
