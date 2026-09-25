package com.arthurrios.finova.ui.register

import androidx.annotation.StringRes
import com.arthurrios.finova.R

/**
 * The live checks from ValidatedInput.swift. Each returns null when the field is fine or empty
 * (an empty field shows no hint, it only keeps the button disabled).
 */
object RegisterValidation {
    private val EmailPattern =
        Regex("^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9](?:[A-Za-z0-9\\-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9\\-]*[A-Za-z0-9])?)+$")
    private val SpecialCharacter = Regex("[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>/?]")

    @StringRes
    fun nameError(name: String): Int? =
        if (name.isNotEmpty() && name.isBlank()) R.string.validation_error_name_required else null

    fun isEmailValid(email: String): Boolean = EmailPattern.matches(email)

    @StringRes
    fun emailError(email: String): Int? =
        if (email.isNotEmpty() && !isEmailValid(email)) R.string.email_validation_invalid else null

    /** The password rules still missing, in the order iOS lists them. */
    @StringRes
    fun missingPasswordRules(password: String): List<Int> = buildList {
        if (password.length < 6) add(R.string.password_validation_min_length)
        if (password.none { it in 'A'..'Z' }) add(R.string.password_validation_has_uppercase)
        // iOS shows "Uppercase letter" here by mistake; the lowercase copy exists and is used.
        if (password.none { it in 'a'..'z' }) add(R.string.password_validation_has_lowercase)
        if (password.none { it in '0'..'9' }) add(R.string.password_validation_has_number)
        if (!SpecialCharacter.containsMatchIn(password)) add(R.string.password_validation_has_special_character)
    }

    @StringRes
    fun confirmPasswordError(confirm: String, password: String): Int? =
        if (confirm.isNotEmpty() && confirm != password) R.string.validation_error_passwords_do_not_match else null

    fun isFormValid(name: String, email: String, password: String, confirm: String): Boolean =
        name.isNotBlank() &&
            isEmailValid(email) &&
            missingPasswordRules(password).isEmpty() &&
            confirm.isNotEmpty() && confirm == password
}
