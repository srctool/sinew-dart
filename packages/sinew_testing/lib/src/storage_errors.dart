import 'package:flutter/services.dart';

/// The error a storage plugin throws when it can't read or write: a
/// [PlatformException], on every platform. Through `processStorageCall` it
/// becomes a `StorageReadException` or `StorageWriteException` with the
/// app's own module and function, exactly as a real store's failure does.
/// The fakes throw it; an app's own fake DAO can too.
PlatformException platformStorageError([String message = 'Storage failed']) =>
    PlatformException(code: 'storage', message: message);

/// A storage error saying the device is full: `processStorageCall` makes it a
/// `StorageFullException`.
PlatformException diskFullError() =>
    platformStorageError('No space left on device');
