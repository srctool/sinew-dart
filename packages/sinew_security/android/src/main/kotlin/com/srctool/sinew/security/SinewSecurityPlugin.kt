package com.srctool.sinew.security

import android.app.Activity
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** The channel side of `ChannelBiometricVault` in Dart: one [BiometricVault] serves every alias, one call at a time. */
class SinewSecurityPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var vault: BiometricVault
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vault = BiometricVault(binding.applicationContext) { activity }
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val alias = call.argument<String>("alias")
        scope.launch {
            try {
                result.success(
                    when (call.method) {
                        "availability" -> vault.availability().wire
                        "isStored" -> vault.isStored(alias!!)
                        "store" -> vault.store(alias!!, call.argument<String>("secret")!!, call.argument<String>("reason")!!)?.wire
                        "unlock" -> when (val outcome = vault.unlock(alias!!, call.argument<String>("reason")!!)) {
                            is Unlock.Unlocked -> mapOf("secret" to outcome.secret)
                            is Unlock.Failed -> mapOf("failure" to outcome.reason.wire)
                        }
                        "disable" -> vault.disable(alias!!).let { null }
                        "debugState" -> mapOf("key" to vault.keyState(alias!!))
                        "debugRemoveInstallMarker" -> null                // iOS only: an Android uninstall deletes the key
                        else -> return@launch result.notImplemented()
                    },
                )
            } catch (e: Exception) {
                result.error("sinew.biometric", e.toString(), null)
            }
        }
    }

    private companion object {
        const val CHANNEL = "com.srctool.sinew/biometric_vault"
    }
}

/** The resumed activity the prompt needs, if it's a `FragmentActivity` (Flutter's `FlutterFragmentActivity`). */
internal fun Activity?.asPromptHost(): FragmentActivity? =
    (this as? FragmentActivity)?.takeUnless { it.isFinishing || it.isDestroyed }
