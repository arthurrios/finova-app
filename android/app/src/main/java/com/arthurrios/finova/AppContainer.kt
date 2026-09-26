package com.arthurrios.finova

import android.app.Application
import android.content.Context
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.ProfileImageStore
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.db.UserDatabaseProvider
import com.arthurrios.finova.data.repo.AllocationRepository
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.security.Biometrics

/** The app's shared objects, built once. Plays the role of the iOS singletons (`.shared`). */
class AppContainer(private val context: Context) {
    val authRepository = AuthRepository(context)
    val settings = UserSettingsStore(context)
    val biometrics = Biometrics(context)
    val databases = UserDatabaseProvider(context)
    val profileImages = ProfileImageStore(context)

    /** The signed-in account, or the local one in a build without Firebase. */
    fun currentUid(): String = authRepository.currentUser()?.firebaseUid ?: UserDatabaseProvider.LOCAL_UID

    /** The money data of whoever is signed in (or the local account in a build without Firebase). */
    fun financeRepository(): FinanceRepository =
        FinanceRepository(currentDatabase()) { settings.defaultBusinessDayRule }

    fun cardRepository(): CardRepository = CardRepository(currentDatabase())

    fun allocationRepository(): AllocationRepository = AllocationRepository(currentDatabase())

    private fun currentDatabase() = databases.forUser(currentUid())

    /** Deletes this account's data on this phone: its database, photo and saved details. */
    fun clearLocalData(uid: String) {
        databases.close()
        context.deleteDatabase(com.arthurrios.finova.data.db.FinovaDatabase.fileName(uid))
        profileImages.delete(uid)
        settings.forgetUser(uid)
    }
}

class FinovaApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}

val Context.appContainer: AppContainer get() = (applicationContext as FinovaApplication).container
