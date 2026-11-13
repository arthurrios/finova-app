package com.arthurrios.finova.ui.profile

import android.graphics.Bitmap
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.AppContainer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ProfileUiState(val name: String = "", val email: String = "", val photo: Bitmap? = null)

/** Port of ProfileViewModel.swift plus the logout ProfileViewController runs. */
class ProfileViewModel(private val container: AppContainer, val appVersion: String) : ViewModel() {
    private val _state = MutableStateFlow(ProfileUiState())
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    init {
        reload()
    }

    fun reload() {
        val settings = container.settings
        _state.value = _state.value.copy(
            // iOS falls back to "User" when it has no name, as the dashboard greeting does.
            name = settings.currentUserName()?.takeIf { it.isNotBlank() } ?: "User",
            email = settings.currentUserEmail().orEmpty(),
        )
        viewModelScope.launch {
            val photo = withContext(Dispatchers.IO) { container.profileImages.load(container.currentUid()) }
            _state.value = _state.value.copy(photo = photo)
        }
    }

    fun setPhoto(picked: Uri) {
        viewModelScope.launch {
            val photo = withContext(Dispatchers.IO) { container.profileImages.save(container.currentUid(), picked) }
            if (photo != null) _state.value = _state.value.copy(photo = photo)
        }
    }

    /**
     * Signs out everywhere, as iOS does: Firebase, the open database, and who is signed in on this
     * device. The account's data stays on the phone for the next sign-in.
     */
    fun logout() {
        container.authRepository.signOut()
        container.databases.close()
        container.settings.clearCurrentUser()
    }
}
