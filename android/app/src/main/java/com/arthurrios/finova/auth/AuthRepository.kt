package com.arthurrios.finova.auth

import android.app.Activity
import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.OAuthProvider
import com.google.firebase.auth.userProfileChangeRequest
import kotlinx.coroutines.tasks.await

/** Thrown when the person closes a sign-in picker. The UI stays quiet about it. */
class SignInCancelled : Exception()

/**
 * Firebase sign-in. Port of the sign-in half of AuthenticationManager.swift on iOS.
 * Every call throws [AuthError] or [SignInCancelled] on failure.
 */
class AuthRepository(private val context: Context) {

    private val auth: FirebaseAuth
        get() {
            // No google-services.json means no default FirebaseApp; getInstance() would crash.
            if (FirebaseApp.getApps(context).isEmpty()) throw AuthError.NotConfigured
            return FirebaseAuth.getInstance()
        }

    suspend fun signInWithEmail(email: String, password: String): AuthUser = wrap {
        auth.signInWithEmailAndPassword(email, password).await().user.toAuthUser()
    }

    /** Creates the account, then stores the name on the Firebase profile, like iOS. */
    suspend fun register(name: String, email: String, password: String): AuthUser = wrap {
        val user = auth.createUserWithEmailAndPassword(email, password).await().user
            ?: throw AuthError.from(IllegalStateException("Firebase returned no user"))
        // iOS carries on when the name update fails; the name is still kept locally.
        runCatching {
            user.updateProfile(userProfileChangeRequest { displayName = name }).await()
        }
        user.toAuthUser(extractedName = name)
    }

    /** Google through Credential Manager, the system account picker. */
    suspend fun signInWithGoogle(activity: Activity): AuthUser = wrap {
        val firebaseAuth = auth
        val option = GetSignInWithGoogleOption.Builder(webClientId()).build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val credential = try {
            CredentialManager.create(activity).getCredential(activity, request).credential
        } catch (e: GetCredentialCancellationException) {
            throw SignInCancelled()
        }
        if (credential !is CustomCredential ||
            credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            throw AuthError.GoogleTokenFailure
        }
        val google = GoogleIdTokenCredential.createFrom(credential.data)
        val firebaseCredential = GoogleAuthProvider.getCredential(google.idToken, null)
        val user = firebaseAuth.signInWithCredential(firebaseCredential).await().user
        user.toAuthUser(extractedName = google.displayName)
    }

    /** Apple through Firebase's web flow (a Custom Tab); Android has no native Apple sign-in. */
    suspend fun signInWithApple(activity: Activity): AuthUser = wrap {
        val provider = OAuthProvider.newBuilder("apple.com")
            .setScopes(listOf("email", "name"))
            .build()
        val firebaseAuth = auth
        val pending = firebaseAuth.pendingAuthResult
        val result = pending?.await()
            ?: firebaseAuth.startActivityForSignInWithProvider(activity, provider).await()
        result.user.toAuthUser()
    }

    private fun webClientId(): String {
        // Generated from google-services.json by the Google Services plugin. Looked up by name
        // so the app still compiles without that file.
        val id = context.resources.getIdentifier("default_web_client_id", "string", context.packageName)
        if (id == 0) throw AuthError.NotConfigured
        return context.getString(id)
    }

    private inline fun wrap(block: () -> AuthUser): AuthUser = try {
        block()
    } catch (e: SignInCancelled) {
        throw e
    } catch (e: Exception) {
        if (e is kotlinx.coroutines.CancellationException) throw e
        throw AuthError.from(e)
    }
}

private fun FirebaseUser?.toAuthUser(extractedName: String? = null): AuthUser {
    this ?: throw AuthError.from(IllegalStateException("Firebase returned no user"))
    // Same fallback order as iOS: the provider's name, then Firebase's, then "User".
    val name = listOf(extractedName, displayName).firstOrNull { !it.isNullOrBlank() && it != "User" }
    return AuthUser(firebaseUid = uid, name = name ?: "User", email = email.orEmpty())
}
