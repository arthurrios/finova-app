package com.arthurrios.finova.ui.register

import com.arthurrios.finova.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RegisterValidationTest {

    @Test
    fun emptyFieldsShowNoHint() {
        assertNull(RegisterValidation.nameError(""))
        assertNull(RegisterValidation.emailError(""))
        assertNull(RegisterValidation.confirmPasswordError("", "Abc12!"))
    }

    @Test
    fun blankNameIsAnError() {
        assertEquals(R.string.validation_error_name_required, RegisterValidation.nameError("   "))
        assertNull(RegisterValidation.nameError("Arthur"))
    }

    @Test
    fun emailFormat() {
        assertTrue(RegisterValidation.isEmailValid("arthur@finova.app"))
        assertTrue(RegisterValidation.isEmailValid("a.b+c@sub.example.com.br"))
        assertFalse(RegisterValidation.isEmailValid("arthur@"))
        assertFalse(RegisterValidation.isEmailValid("arthur@finova"))
        assertFalse(RegisterValidation.isEmailValid("arthur finova@x.com"))
    }

    @Test
    fun passwordListsEveryMissingRule() {
        assertEquals(
            listOf(
                R.string.password_validation_min_length,
                R.string.password_validation_has_uppercase,
                R.string.password_validation_has_number,
                R.string.password_validation_has_special_character,
            ),
            RegisterValidation.missingPasswordRules("abc"),
        )
        assertEquals(
            listOf(R.string.password_validation_has_lowercase),
            RegisterValidation.missingPasswordRules("ABC12!"),
        )
        assertTrue(RegisterValidation.missingPasswordRules("Abc12!").isEmpty())
    }

    @Test
    fun formNeedsEveryFieldValidAndMatchingPasswords() {
        assertTrue(RegisterValidation.isFormValid("Arthur", "a@b.co", "Abc12!", "Abc12!"))
        assertFalse(RegisterValidation.isFormValid("Arthur", "a@b.co", "Abc12!", "Abc12?"))
        assertFalse(RegisterValidation.isFormValid(" ", "a@b.co", "Abc12!", "Abc12!"))
        assertFalse(RegisterValidation.isFormValid("Arthur", "a@b.co", "abc", "abc"))
    }
}
