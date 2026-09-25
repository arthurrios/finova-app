package com.arthurrios.finova.data.db

import android.content.Context

/**
 * Hands out the database of whoever is signed in, and swaps it when the account changes. Port of
 * the role SecureLocalDataManager.authenticateUser / signOut plays on iOS.
 */
class UserDatabaseProvider(private val context: Context) {
    private var current: Pair<String, FinovaDatabase>? = null

    @Synchronized
    fun forUser(uid: String): FinovaDatabase {
        current?.let { (openUid, db) -> if (openUid == uid) return db else db.close() }
        return FinovaDatabase.open(context, uid).also { current = uid to it }
    }

    @Synchronized
    fun close() {
        current?.second?.close()
        current = null
    }

    companion object {
        /** Used when no Firebase account exists yet (a build without google-services.json). */
        const val LOCAL_UID = "local"
    }
}
