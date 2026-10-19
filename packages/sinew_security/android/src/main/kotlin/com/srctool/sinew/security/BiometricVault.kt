package com.srctool.sinew.security

import android.app.Activity
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The shared-preferences file holding each alias's IV and ciphertext. Exclude it from backup. */
internal const val VAULT_PREFS: String = "sinew.security.biometric"

internal enum class Availability(val wire: String) { Available("available"), NotEnrolled("notEnrolled"), Unavailable("unavailable") }

internal enum class Failure(val wire: String) {
    Cancelled("cancelled"), LockedOut("lockedOut"), Invalidated("invalidated"), Unavailable("unavailable")
}

internal sealed interface Unlock {
    class Unlocked(val secret: String) : Unlock
    class Failed(val reason: Failure) : Unlock
}

/**
 * The secret is AES-256-GCM encrypted by an Android Keystore key that needs a fresh strong biometric match for every
 * use, encrypting included, and that enrolling a new fingerprint invalidates. The key is unlocked by `BiometricPrompt`
 * with a `CryptoObject`, so no match means no key. A store makes a new key, so opting in again resets an invalidation.
 * The flows are Kotlin's `sinew-security` vault, with the activity coming from the Flutter plugin binding.
 */
internal class BiometricVault(context: Context, private val activity: () -> Activity?) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences(VAULT_PREFS, Context.MODE_PRIVATE)
    private val lock = Mutex()

    fun availability(): Availability = availabilityOf(BiometricManager.from(app).canAuthenticate(BIOMETRIC_STRONG))

    suspend fun isStored(alias: String): Boolean =
        withContext(Dispatchers.IO) { prefs.contains("$alias.value") && keyStore().containsAlias(alias) }

    /** Stores [secret] after a match, returning `null`, or why not. */
    suspend fun store(alias: String, secret: String, reason: String): Failure? = lock.withLock {
        if (availability() != Availability.Available) return@withLock Failure.Unavailable
        val cipher = withContext(Dispatchers.IO) {
            deleteAll(alias)
            Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, newKey(alias)) }   // the Keystore picks the IV
        }
        when (val outcome = authenticate(reason, cipher)) {
            is Authenticated -> {
                val sealed = outcome.cipher.doFinal(secret.encodeToByteArray())
                withContext(Dispatchers.IO) {
                    prefs.edit()
                        .putString("$alias.iv", Base64.encodeToString(outcome.cipher.iv, Base64.NO_WRAP))
                        .putString("$alias.value", Base64.encodeToString(sealed, Base64.NO_WRAP))
                        .commit()
                }
                null
            }
            is NotAuthenticated -> {
                withContext(Dispatchers.IO) { deleteAll(alias) }
                outcome.reason
            }
        }
    }

    suspend fun unlock(alias: String, reason: String): Unlock = lock.withLock {
        val iv = prefs.getString("$alias.iv", null)
        val value = prefs.getString("$alias.value", null)
        val key = withContext(Dispatchers.IO) { keyStore().getKey(alias, null) as SecretKey? }
        if (iv == null || value == null || key == null) return@withLock Unlock.Failed(Failure.Invalidated)
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
            }
        } catch (_: KeyPermanentlyInvalidatedException) {
            withContext(Dispatchers.IO) { deleteAll(alias) }              // a new fingerprint was enrolled
            return@withLock Unlock.Failed(Failure.Invalidated)
        }
        when (val outcome = authenticate(reason, cipher)) {
            is Authenticated -> try {
                Unlock.Unlocked(outcome.cipher.doFinal(Base64.decode(value, Base64.NO_WRAP)).decodeToString())
            } catch (_: GeneralSecurityException) {
                withContext(Dispatchers.IO) { deleteAll(alias) }          // the stored value was changed
                Unlock.Failed(Failure.Invalidated)
            }
            is NotAuthenticated -> Unlock.Failed(outcome.reason)
        }
    }

    suspend fun disable(alias: String) {
        lock.withLock { withContext(Dispatchers.IO) { deleteAll(alias) } }
    }

    /** For the device tests: `missing`, `usable`, or `invalidated` by a new enrollment. */
    suspend fun keyState(alias: String): String = withContext(Dispatchers.IO) {
        val key = keyStore().getKey(alias, null) as SecretKey? ?: return@withContext "missing"
        try {
            Cipher.getInstance(TRANSFORMATION).init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, ByteArray(12)))
            "usable"
        } catch (_: KeyPermanentlyInvalidatedException) {
            "invalidated"
        }
    }

    private fun deleteAll(alias: String) {
        prefs.edit().remove("$alias.iv").remove("$alias.value").commit()
        keyStore().deleteEntry(alias)
    }

    private fun newKey(alias: String): SecretKey {
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)   // every use needs a fresh match
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(-1)
                }
                if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) setIsStrongBoxBacked(true)
            }
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        return try {
            generator.init(spec(strongBox = true))
            generator.generateKey()
        } catch (_: StrongBoxUnavailableException) {
            generator.init(spec(strongBox = false))
            generator.generateKey()
        }
    }

    /**
     * Shows the prompt on the current `FragmentActivity` and returns the unlocked cipher, or why not.
     *
     * `BiometricPrompt` silently drops a request made while a previous prompt is still closing, and the caller would
     * wait forever. So this waits for any prompt to be gone before showing one, and for its own to be gone before
     * returning, still holding the vault's lock.
     */
    private suspend fun authenticate(reason: String, cipher: Cipher): Authentication {
        val host = activity().asPromptHost()
        if (host == null) {
            Log.w(TAG, "BiometricVault needs MainActivity to extend FlutterFragmentActivity; reporting unavailable")
            return NotAuthenticated(Failure.Unavailable)
        }
        awaitPromptGone(host)
        val outcome = CompletableDeferred<Authentication>()
        withContext(Dispatchers.Main.immediate) {
            val prompt = BiometricPrompt(
                host,
                ContextCompat.getMainExecutor(host),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        val unlocked = result.cryptoObject?.cipher
                        outcome.complete(if (unlocked != null) Authenticated(unlocked) else NotAuthenticated(Failure.Unavailable))
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        outcome.complete(NotAuthenticated(failureOf(errorCode)))
                    }
                    // onAuthenticationFailed: a finger that didn't match; the prompt stays up for another try.
                },
            )
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle(reason)
                .setNegativeButtonText(host.getString(android.R.string.cancel))
                .setAllowedAuthenticators(BIOMETRIC_STRONG)
                .build()
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        }
        return outcome.await().also { withContext(NonCancellable) { awaitPromptGone(host) } }
    }

    /** Waits, up to 2 s, until no AndroidX biometric prompt is attached to [host]. */
    private suspend fun awaitPromptGone(host: FragmentActivity) {
        withContext(Dispatchers.Main.immediate) {
            withTimeoutOrNull(2_000) {
                while (host.supportFragmentManager.findFragmentByTag(PROMPT_FRAGMENT) != null) delay(50)
            }
        }
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG = "SinewBiometricVault"
        const val PROMPT_FRAGMENT = "androidx.biometric.BiometricFragment"     // AndroidX BiometricPrompt's own tag

        fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
    }
}

private sealed interface Authentication
private class Authenticated(val cipher: Cipher) : Authentication
private class NotAuthenticated(val reason: Failure) : Authentication

internal fun availabilityOf(canAuthenticate: Int): Availability = when (canAuthenticate) {
    BiometricManager.BIOMETRIC_SUCCESS -> Availability.Available
    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> Availability.NotEnrolled
    else -> Availability.Unavailable
}

internal fun failureOf(errorCode: Int): Failure = when (errorCode) {
    BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON, BiometricPrompt.ERROR_CANCELED,
    BiometricPrompt.ERROR_TIMEOUT -> Failure.Cancelled
    BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> Failure.LockedOut
    else -> Failure.Unavailable                                           // no hardware, nothing enrolled, an update required
}
