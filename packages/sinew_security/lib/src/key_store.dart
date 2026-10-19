import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where a cipher's keyring is kept: `flutter_secure_storage` in apps, memory
/// in tests.
abstract interface class KeyStore {
  /// The value under [key], or `null` when there's none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any earlier value.
  Future<void> write(String key, String value);
}

/// [KeyStore] on `flutter_secure_storage`, readable after the first unlock, on
/// this device only, so a key never travels in a backup (Keychain
/// this-device-only on iOS and macOS, Keystore-protected on Android).
final class SecureKeyStore implements KeyStore {
  /// The store over [storage].
  SecureKeyStore(this.storage);

  /// The store over the default `FlutterSecureStorage`, shared by every cipher
  /// that doesn't pass its own.
  static final SecureKeyStore standard = SecureKeyStore(
    const FlutterSecureStorage(),
  );

  /// The plugin instance.
  final FlutterSecureStorage storage;

  static const _iOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _mOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  @override
  Future<String?> read(String key) =>
      storage.read(key: key, iOptions: _iOptions, mOptions: _mOptions);

  @override
  Future<void> write(String key, String value) => storage.write(
    key: key,
    value: value,
    iOptions: _iOptions,
    mOptions: _mOptions,
  );
}
