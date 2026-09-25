package com.arthurrios.finova.auth

/** The signed-in person, as the rest of the app sees them. Mirrors the iOS `User` fields we use. */
data class AuthUser(
    val firebaseUid: String,
    val name: String,
    val email: String,
)
