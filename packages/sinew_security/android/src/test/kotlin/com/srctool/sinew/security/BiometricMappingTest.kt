package com.srctool.sinew.security

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import kotlin.test.Test
import kotlin.test.assertEquals

/** How `BiometricManager` and `BiometricPrompt` codes become the outcomes sent to Dart. */
class BiometricMappingTest {
    @Test
    fun availability() {
        assertEquals(Availability.Available, availabilityOf(BiometricManager.BIOMETRIC_SUCCESS))
        assertEquals(Availability.NotEnrolled, availabilityOf(BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED))
        for (code in listOf(
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE, BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE,
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED, BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED,
        )) assertEquals(Availability.Unavailable, availabilityOf(code), "$code")
    }

    @Test
    fun promptErrors() {
        for (code in listOf(
            BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_CANCELED, BiometricPrompt.ERROR_TIMEOUT,
        )) assertEquals(Failure.Cancelled, failureOf(code), "$code")
        for (code in listOf(BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT)) {
            assertEquals(Failure.LockedOut, failureOf(code), "$code")
        }
        for (code in listOf(
            BiometricPrompt.ERROR_HW_UNAVAILABLE, BiometricPrompt.ERROR_NO_BIOMETRICS, BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
        )) assertEquals(Failure.Unavailable, failureOf(code), "$code")
    }

    /** The names are Dart's enum values (`BiometricAvailability`, `BiometricFailure`), read with `byName`. */
    @Test
    fun wireNames() {
        assertEquals(listOf("available", "notEnrolled", "unavailable"), Availability.entries.map { it.wire })
        assertEquals(listOf("cancelled", "lockedOut", "invalidated", "unavailable"), Failure.entries.map { it.wire })
    }
}
