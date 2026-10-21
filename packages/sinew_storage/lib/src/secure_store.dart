import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sinew_security/sinew_security.dart';

import 'inspectable_store.dart';
import 'key_value_store.dart';

/// Small secrets: the refresh token, a data key, a device id. Never large data
/// or lists, which go in the app's database with [FieldCipher].
///
/// Every platform uses the same store, as Kotlin does (ADR-26): a dedicated
/// [KeyValueStore] (`<namespace>_secure`) whose values a [FieldCipher]
/// (`sinew.secure.<namespace>`) encrypts, with `<namespace>:<key>` bound as
/// associated data, so a value copied to another key doesn't decrypt. The
/// cipher's key is kept by `flutter_secure_storage` (the Keychain this-device-
/// only on iOS and macOS, Keystore-protected on Android).
///
/// - **A value that can't be decrypted is absent**, and is deleted: after a
///   restore onto another device, a reset keystore, or tampering. For a
///   session, absent means signed out.
/// - **A reinstall starts empty** on every platform: the values go with the
///   app, even where the key survives (the iOS Keychain).
/// - Writes are serialized, so the last one wins.
abstract interface class SecureStore implements InspectableStore {
  /// The store for [namespace], which must not be blank or contain a `.`.
  static Future<SecureStore> create({String namespace = 'sinew'}) async {
    _checkNamespace(namespace);
    return EncryptedSecureStore(
      namespace,
      KeyValueStore.create(name: '${namespace}_secure'),
      await FieldCipher.create(keyAlias: 'sinew.secure.$namespace'),
    );
  }

  /// The namespace.
  @override
  String get name;

  /// Every key holding a secret, sorted.
  @override
  Future<List<String>> keys();

  /// The secret for [key], or `null` when absent or undecryptable. The
  /// devtools show it masked.
  @override
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any secret there.
  Future<void> write(String key, String value);

  /// Deletes the secret under [key].
  Future<void> delete(String key);

  /// Deletes every secret of this store: call it on sign-out.
  Future<void> clearUserData();
}

void _checkNamespace(String namespace) {
  if (namespace.trim().isEmpty || namespace.contains('.')) {
    throw ArgumentError.value(
      namespace,
      'namespace',
      'must be non-blank, without "."',
    );
  }
}

/// [SecureStore] as [FieldCipher]-encrypted values in a [KeyValueStore]. Its
/// constructor lets a test supply its own cipher, since [FieldCipher.create]
/// keeps one open keyring per alias for the life of the process.
@visibleForTesting
final class EncryptedSecureStore implements SecureStore {
  /// The store [namespace] over [values], encrypted by [cipher].
  EncryptedSecureStore(this.namespace, this.values, this.cipher) {
    _checkNamespace(namespace);
  }

  /// The namespace, bound into every value.
  final String namespace;

  /// Where the encrypted values are.
  final KeyValueStore values;

  /// What encrypts them.
  final FieldCipher cipher;

  Future<void> _writes = Future.value();

  /// Runs [action] after every earlier write, and before any later one.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  String _context(String key) => '$namespace:$key';

  @override
  String get name => namespace;

  @override
  Future<List<String>> keys() => values.keys();

  @override
  Future<String?> read(String key) async {
    final sealed = await values.getString(key);
    if (sealed == null) return null;
    try {
      return await cipher.decrypt(sealed, context: _context(key));
    } on DecryptionFailed {
      // Fail closed, and tidy up: only if it's still the value that failed.
      await _serialized(() async {
        if (await values.getString(key) == sealed) await values.remove(key);
      });
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _serialized(
    () async => values.setString(
      key,
      await cipher.encrypt(value, context: _context(key)),
    ),
  );

  @override
  Future<void> delete(String key) => _serialized(() => values.remove(key));

  @override
  Future<void> clearUserData() => _serialized(values.clear);
}
