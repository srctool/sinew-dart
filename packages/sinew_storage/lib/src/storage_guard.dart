import 'package:flutter/services.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_security/sinew_security.dart';

import 'storage_errors.dart';

/// Which kind of storage call failed: a failed read can be retried freely, a
/// failed write may need the user.
enum StorageAccess {
  /// The call reads stored data.
  read,

  /// The call writes or deletes stored data.
  write,
}

/// The source guard for storage, the counterpart of `processApiCall`: a store,
/// a DAO or a local source called in [block] fails with a typed exception (in
/// the repository layer) instead of throwing. See [storageHandlers].
///
/// ```dart
/// Future<Result<String?>> refreshToken() =>
///     processStorageCall('AUTH', 'READ_TOKEN', StorageAccess.read, () => secrets.read('refreshToken'));
/// ```
Future<Result<T>> processStorageCall<T>(
  String module,
  String function,
  StorageAccess access,
  Future<T> Function() block,
) => processCall(
  module,
  function,
  ExceptionLayer.repository,
  storageHandlers(module, function, access),
  block,
);

/// The storage handler table, first match wins. Public, so an app can guard
/// a call with `processCall` and its own rows added (a database package's
/// errors, for example).
///
/// | Matches | Produces |
/// |---|---|
/// | [DecryptionFailed]; a `FormatException` decoding stored data; a [PlatformException] from a failed decryption of a plugin's own data (Android's `BadPaddingException`, `AEADBadTagException`) | [LocalStorageCorruptionException] |
/// | a storage error saying the device is out of space: `ENOSPC` (`FileSystemException` with errno 28, or 39/112 on Windows), "No space left on device", SQLite's "database or disk is full", the browser's `QuotaExceededError` | [StorageFullException] |
/// | any other storage error: a [PlatformException], an `IOException`, a `SqliteException`, a browser storage `DOMException` | [StorageReadException] / [StorageWriteException], by [access] |
/// | an envelope with no payload | [ParseException], reported |
///
/// Anything else, a bug in the block, is an [UnexpectedException], reported.
List<ExceptionHandler> storageHandlers(
  String module,
  String function,
  StorageAccess access,
) {
  const layer = ExceptionLayer.repository;
  return [
    ExceptionHandler(
      isStorageCorruption,
      (e) => LocalStorageCorruptionException(module, layer, function, cause: e),
    ),
    ExceptionHandler(
      isStorageFull,
      (e) => StorageFullException(module, layer, function, cause: e),
    ),
    ExceptionHandler(
      isStorageError,
      (e) => switch (access) {
        StorageAccess.read => StorageReadException(
          module,
          layer,
          function,
          cause: e,
        ),
        StorageAccess.write => StorageWriteException(
          module,
          layer,
          function,
          cause: e,
        ),
      },
    ),
    envelopeDataMissing(module, function, layer),
  ];
}

/// Stored data that can't be read back.
bool isStorageCorruption(Object error) =>
    error is DecryptionFailed ||
    error is FormatException ||
    (error is PlatformException &&
        _mentions(error, const ['badpaddingexception', 'aeadbadtagexception']));

/// A storage error saying the device is out of space.
bool isStorageFull(Object error) =>
    isPlatformStorageFull(error) ||
    (isStorageError(error) && _mentions(error, _outOfSpace));

const _outOfSpace = [
  'no space left on device',
  'enospc',
  'database or disk is full',
  'sqlite_full',
];

/// A storage error, as opposed to a bug: a plugin's [PlatformException], a
/// file or database error, a browser storage error.
bool isStorageError(Object error) =>
    error is PlatformException ||
    // sqlite3's error, matched by its own text so Sinew needs no database
    // dependency (and a minified web build still matches).
    error.toString().startsWith('SqliteException') ||
    isPlatformStorageError(error);

/// Whether [error]'s text mentions one of [needles], ignoring case.
bool _mentions(Object error, List<String> needles) {
  final text = switch (error) {
    PlatformException(:final code, :final message, :final details) =>
      '$code $message $details',
    _ => error.toString(),
  }.toLowerCase();
  return needles.any(text.contains);
}
