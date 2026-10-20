# sinew_storage

SecureStore, KeyValueStore, processStorageCall and pagedQuery.

Part of [Sinew](https://github.com/srctool/sinew). Status: milestone S4.

## KeyValueStore

Plain preferences (the theme, onboarding seen), never tokens or personal data:

```dart
final prefs = KeyValueStore.create(); // or create(name: 'orders')
await prefs.setString('theme', 'dark');
final theme = await prefs.getString('theme'); // null when missing or of another type
```

It's `SharedPreferencesAsync` (no in-memory cache) with every key prefixed `<name>.`, so `clear()` removes only this
store's keys. In unit tests, set `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()`
(from `shared_preferences_platform_interface`).

## SecureStore

Small secrets (the refresh token, a data key), never large data:

```dart
final secrets = await SecureStore.create(); // or create(namespace: 'session')
await secrets.write('refreshToken', token);
final token = await secrets.read('refreshToken'); // null when absent or undecryptable
await secrets.clearUserData(); // on sign-out
```

As in Kotlin, the secrets are a `KeyValueStore` (`<namespace>_secure`) whose values `FieldCipher`
(`sinew.secure.<namespace>`) encrypts, with `<namespace>:<key>` bound to each value. Only the cipher's key is in
`flutter_secure_storage`. A value that can't be decrypted (a restore onto another device, tampering) reads as absent and
is deleted. A reinstall starts empty: the values go with the app.

Setup: `sinew_security`'s (CMake to build; on macOS, the Keychain Sharing entitlement). On Android, exclude the
`FlutterSecureStorage` files and the app's shared preferences from cloud backup and device transfer in
`data_extraction_rules.xml`: a restored value can't be decrypted on a new device anyway.

In unit tests, use `InMemorySharedPreferencesAsync` and `FlutterSecureStorage.setMockInitialValues({})`.
