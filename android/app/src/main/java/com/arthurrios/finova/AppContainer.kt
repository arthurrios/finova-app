package com.arthurrios.finova

import android.app.Application
import android.content.Context
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.db.UserDatabaseProvider
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.security.Biometrics

/** The app's shared objects, built once. Plays the role of the iOS singletons (`.shared`). */
class AppContainer(context: Context) {
    val authRepository = AuthRepository(context)
    val settings = UserSettingsStore(context)
    val biometrics = Biometrics(context)
    val databases = UserDatabaseProvider(context)

    /** The money data of whoever is signed in (or the local account in a build without Firebase). */
    fun financeRepository(): FinanceRepository {
        val uid = authRepository.currentUser()?.firebaseUid ?: UserDatabaseProvider.LOCAL_UID
        return FinanceRepository(databases.forUser(uid))
    }
}

class FinovaApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}

val Context.appContainer: AppContainer get() = (applicationContext as FinovaApplication).container
