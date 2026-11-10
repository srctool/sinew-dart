# sinew_storage

[![pub package](https://img.shields.io/pub/v/sinew_storage.svg)](https://pub.dev/packages/sinew_storage)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**`SecureStore`, `KeyValueStore`, `processStorageCall` and `pagedQuery`.**

Local storage with the same error model as the network: a corrupted file, a full disk or an unreadable value becomes a typed exception instead of a crash, and a reinstall starts with an empty secure store.

## Features

- `KeyValueStore`: plain preferences, namespaced by name, typed reads that return `null` for a value of another type
- `SecureStore`: small secrets, encrypted with `FieldCipher`, with an undecryptable value read as absent
- `processStorageCall` and `storageHandlers`: turn storage failures into `LocalStorageCorruptionException`, `StorageFullException`, `StorageReadException` and `StorageWriteException`
- `pagedQuery`: a local list that pages with `Pager.offset` exactly like a remote one, and `InspectableStore` for the devtools

## Getting started

```sh
flutter pub add sinew_storage
```

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

## The storage guard

Guard every store or database call in a repository, as `processApiCall` guards HTTP:

```dart
Future<Result<String?>> refreshToken() =>
    processStorageCall('AUTH', 'READ_TOKEN', StorageAccess.read, () => secrets.read('refreshToken'));
```

| Failure | Becomes |
|---|---|
| `DecryptionFailed`, a `FormatException` decoding stored data, a plugin's failed decryption (`BadPaddingException`) | `LocalStorageCorruptionException` |
| out of space (`ENOSPC`, "database or disk is full", `QuotaExceededError`) | `StorageFullException` |
| any other `PlatformException`, `IOException`, `SqliteException` or browser storage error | `StorageReadException` / `StorageWriteException` |
| an envelope with no payload | `ParseException`, reported |
| anything else (a bug) | `UnexpectedException`, reported |

`storageHandlers` is public: add rows for your database package's own errors and guard with `processCall`.

## Paging a local query

`pagedQuery` gives a local table the same `PagingEntity` a remote list returns, for `Pager.offset`. It asks your
`LIMIT/OFFSET` query for one row more than the page, so it knows whether a next page exists without a `COUNT(*)`:

```dart
Future<PagingEntity<OrderRow>> page(int page, int limit) => pagedQuery(page, limit, (offset, count) =>
    (db.select(db.orders)..orderBy([(o) => OrderingTerm.desc(o.placedAt)])..limit(count, offset: offset)).get());
```

`total` and `totalPage` stay 0. 0-based pages pass `firstPage: 0`.

## InspectableStore

`KeyValueStore` and `SecureStore` are `InspectableStore`s (`name`, sorted `keys()`, `read(key)` as text), which the
devtools browse; implement it on a DAO to show up there too.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_security`](https://pub.dev/packages/sinew_security)
- [`sinew_exception`](https://pub.dev/packages/sinew_exception)
- [`sinew_paging`](https://pub.dev/packages/sinew_paging)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_storage](https://pub.dev/documentation/sinew_storage/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
