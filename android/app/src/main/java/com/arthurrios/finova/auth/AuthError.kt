package com.arthurrios.finova.auth

import androidx.annotation.StringRes
import com.arthurrios.finova.R
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.FirebaseAuthException

/** A sign-in failure the UI can show. Mirrors FirebaseErrorHandler.swift on iOS. */
class AuthError(
    @StringRes val titleRes: Int,
    @StringRes val messageRes: Int,
    cause: Throwable? = null,
) : Exception(cause) {

    companion object {
        val NotConfigured = AuthError(R.string.auth_error_title, R.string.auth_error_not_configured)
        val GoogleTokenFailure =
            AuthError(R.string.auth_error_title, R.string.auth_error_google_token_failure)

        fun from(error: Throwable): AuthError = when (error) {
            is AuthError -> error
            is FirebaseTooManyRequestsException ->
                AuthError(R.string.auth_error_title, R.string.auth_error_too_many_requests, error)
            is FirebaseNetworkException ->
                AuthError(R.string.auth_error_title, R.string.auth_error_network_error, error)
            is FirebaseAuthException ->
                AuthError(R.string.auth_error_title, messageFor(error.errorCode), error)
            else -> AuthError(
                R.string.validation_error_title,
                R.string.login_error_unexpected_error_message,
                error,
            )
        }

        @StringRes
        private fun messageFor(code: String): Int = when (code) {
            "ERROR_EMAIL_ALREADY_IN_USE" -> R.string.auth_error_email_already_in_use
            "ERROR_INVALID_EMAIL" -> R.string.auth_error_invalid_email
            "ERROR_WEAK_PASSWORD" -> R.string.auth_error_weak_password
            // Firebase's email-enumeration protection folds user-not-found and wrong-password
            // into INVALID_CREDENTIAL; all three show the same message, as on iOS.
            "ERROR_USER_NOT_FOUND",
            "ERROR_WRONG_PASSWORD",
            "ERROR_INVALID_CREDENTIAL" -> R.string.auth_error_invalid_credentials
            else -> R.string.login_error_unexpected_error_message
        }
    }
}
