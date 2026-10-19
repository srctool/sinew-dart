import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One small secret, typically the refresh token, that can be read only after a
/// real biometric match. The secret is protected **by** the biometric key or
/// access control, never by a prompt in front of a normal read, and enrolling a
/// new face or fingerprint makes it unreadable.
///
/// | Platform | Protected by |
/// |---|---|
/// | Android | an Android Keystore AES-256-GCM key usable only after a strong biometric match, through `BiometricPrompt` |
/// | iOS | a Keychain item with `biometryCurrentSet` access control, this device only, needing a passcode |
/// | macOS, Linux, Windows, web | nothing: [availability] is [BiometricAvailability.unavailable] and every call fails with it |
///
/// Offer it only after a real sign-in, keep a password fallback, and store a
/// refresh token, never a password. On Android the app's `MainActivity` must
/// extend `FlutterFragmentActivity`; on iOS, `Info.plist` needs
/// `NSFaceIDUsageDescription`.
abstract interface class BiometricVault {
  /// The platform's vault for [keyAlias]. With [clearOnReinstall] (iOS), the
  /// first use after an install deletes an item the previous install left in
  /// the Keychain, so a reinstalled app never unlocks an old session.
  static BiometricVault create({
    String keyAlias = 'sinew.biometric',
    bool clearOnReinstall = true,
  }) {
    if (keyAlias.trim().isEmpty) {
      throw ArgumentError.value(keyAlias, 'keyAlias', 'must not be blank');
    }
    if (kIsWeb) return const UnavailableBiometricVault();
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => ChannelBiometricVault(
        keyAlias,
        clearOnReinstall: clearOnReinstall,
      ),
      _ => const UnavailableBiometricVault(),
    };
  }

  /// Whether biometrics can be offered now.
  Future<BiometricAvailability> availability();

  /// Whether a secret is stored, without a prompt: decides whether to offer
  /// biometric sign-in.
  Future<bool> isStored();

  /// Stores [secret], replacing any stored one. On Android this shows the
  /// biometric prompt with [reason] as its title, because the key needs a
  /// match to encrypt too; iOS stores without a prompt.
  Future<BiometricStore> store(String secret, {required String reason});

  /// Shows the system prompt with [reason] and returns the secret after a
  /// match.
  Future<BiometricUnlock> unlock({required String reason});

  /// Deletes the secret and its key.
  Future<void> disable();
}

/// Whether to offer biometrics.
enum BiometricAvailability {
  /// Biometric hardware with an enrolled face or finger.
  available,

  /// The hardware is there, but nothing is enrolled: the app may suggest
  /// enrolling in Settings.
  notEnrolled,

  /// No usable biometrics (no hardware, no passcode, a desktop or a browser):
  /// never offer it.
  unavailable,
}

/// Why [BiometricVault.store] or [BiometricVault.unlock] didn't complete. A
/// user outcome, not an error.
enum BiometricFailure {
  /// The user, the app or the system dismissed the prompt: offer the password.
  cancelled,

  /// Too many failed attempts: offer the password.
  lockedOut,

  /// Nothing is stored, or the enrollment changed and the secret was deleted:
  /// sign in with the password, offer opt-in again.
  invalidated,

  /// Biometrics can't be used here now.
  unavailable,
}

/// The outcome of [BiometricVault.store]: [Stored] or [BiometricFailed].
sealed class BiometricStore {}

/// The outcome of [BiometricVault.unlock]: [Unlocked] or [BiometricFailed].
sealed class BiometricUnlock {}

/// The secret is stored.
final class Stored implements BiometricStore {
  /// The one stored outcome.
  const Stored();

  @override
  bool operator ==(Object other) => other is Stored;

  @override
  int get hashCode => (Stored).hashCode;

  @override
  String toString() => 'Stored()';
}

/// A real biometric match released [secret].
final class Unlocked implements BiometricUnlock {
  /// The outcome carrying [secret].
  const Unlocked(this.secret);

  /// The secret that was stored.
  final String secret;

  @override
  bool operator ==(Object other) => other is Unlocked && other.secret == secret;

  @override
  int get hashCode => secret.hashCode;

  /// Never the secret: an outcome may be logged.
  @override
  String toString() => 'Unlocked(secret: ***)';
}

/// Nothing was stored, or the secret wasn't released, because of [reason].
final class BiometricFailed implements BiometricStore, BiometricUnlock {
  /// The outcome for [reason].
  const BiometricFailed(this.reason);

  /// Why.
  final BiometricFailure reason;

  @override
  bool operator ==(Object other) =>
      other is BiometricFailed && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'BiometricFailed(${reason.name})';
}

/// The vault where there are no biometrics (desktop, web).
@visibleForTesting
final class UnavailableBiometricVault implements BiometricVault {
  /// The one unavailable vault.
  const UnavailableBiometricVault();

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.unavailable;

  @override
  Future<bool> isStored() async => false;

  @override
  Future<BiometricStore> store(String secret, {required String reason}) async =>
      const BiometricFailed(BiometricFailure.unavailable);

  @override
  Future<BiometricUnlock> unlock({required String reason}) async =>
      const BiometricFailed(BiometricFailure.unavailable);

  @override
  Future<void> disable() async {}
}

/// The vault on Android and iOS: the plugin's native code, over
/// [biometricVaultChannel]. Every call names its alias; the native side runs
/// one call at a time.
@visibleForTesting
final class ChannelBiometricVault implements BiometricVault {
  /// The native vault for [alias].
  ChannelBiometricVault(this.alias, {required this.clearOnReinstall});

  /// The key alias (Android) or Keychain service (iOS).
  final String alias;

  /// Whether iOS clears an item left by a previous install.
  final bool clearOnReinstall;

  Map<String, Object?> _args([Map<String, Object?> extra = const {}]) => {
    'alias': alias,
    'clearOnReinstall': clearOnReinstall,
    ...extra,
  };

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.values.byName(
        (await biometricVaultChannel.invokeMethod<String>('availability'))!,
      );

  @override
  Future<bool> isStored() async =>
      (await biometricVaultChannel.invokeMethod<bool>('isStored', _args()))!;

  @override
  Future<BiometricStore> store(String secret, {required String reason}) async {
    final failure = await biometricVaultChannel.invokeMethod<String>(
      'store',
      _args({'secret': secret, 'reason': reason}),
    );
    return failure == null
        ? const Stored()
        : BiometricFailed(BiometricFailure.values.byName(failure));
  }

  @override
  Future<BiometricUnlock> unlock({required String reason}) async {
    final outcome = (await biometricVaultChannel
        .invokeMapMethod<String, String>('unlock', _args({'reason': reason})))!;
    return switch (outcome) {
      {'secret': final secret} => Unlocked(secret),
      {'failure': final failure} => BiometricFailed(
        BiometricFailure.values.byName(failure),
      ),
      _ => throw StateError('unexpected unlock outcome: ${outcome.keys}'),
    };
  }

  @override
  Future<void> disable() =>
      biometricVaultChannel.invokeMethod<void>('disable', _args());
}

/// The plugin's channel, implemented by `SinewSecurityPlugin` on Android and
/// iOS.
@visibleForTesting
const biometricVaultChannel = MethodChannel(
  'com.srctool.sinew/biometric_vault',
);

/// For the device tests: what protects [alias]'s secret, never the secret. On
/// Android `key` is `missing`, `usable` or `invalidated`; on iOS `pdmn` and
/// `accc` are the Keychain item's protection class and access control, absent
/// with no item.
@visibleForTesting
Future<Map<String, String>> debugVaultState(String alias) async =>
    (await biometricVaultChannel.invokeMapMethod<String, String>('debugState', {
      'alias': alias,
    }))!;

/// For the device tests on iOS: deletes [alias]'s install marker, as an
/// uninstall does.
@visibleForTesting
Future<void> debugRemoveInstallMarker(String alias) => biometricVaultChannel
    .invokeMethod<void>('debugRemoveInstallMarker', {'alias': alias});
