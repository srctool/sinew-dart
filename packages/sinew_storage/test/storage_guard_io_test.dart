@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// The storage handler rows for dart:io's file errors.
void main() {
  setUp(() => CrashReporter.install(CrashReporter.none));

  Future<SinewException> fail(Object error, StorageAccess access) async {
    final result = await processStorageCall<void>(
      'AUTH',
      'SAVE',
      access,
      () async => throw error,
    );
    return (result as Failure).error;
  }

  FileSystemException fileError(int errno, String message) =>
      FileSystemException(
        'Cannot write',
        '/data/prefs',
        OSError(message, errno),
      );

  test('ENOSPC is StorageFullException, on reads and writes', () async {
    final full = Platform.isWindows
        ? fileError(112, 'There is not enough space on the disk.')
        // A localized message: only the errno says the device is full.
        : fileError(28, 'Kein Speicherplatz mehr verfügbar');
    for (final access in StorageAccess.values) {
      expect(await fail(full, access), isA<StorageFullException>());
    }
  });

  test('another file error is a read or write failure, by access', () async {
    final denied = fileError(13, 'Permission denied');
    expect(await fail(denied, StorageAccess.read), isA<StorageReadException>());
    expect(
      await fail(denied, StorageAccess.write),
      isA<StorageWriteException>(),
    );
    final noErrno = const FileSystemException('Cannot open', '/data/prefs');
    expect(
      await fail(noErrno, StorageAccess.read),
      isA<StorageReadException>(),
    );
  });

  test('an out-of-space errno on another platform is not ENOSPC', () async {
    final other = Platform.isWindows
        ? fileError(28, 'The media is write protected.')
        : fileError(112, 'Some other failure');
    expect(await fail(other, StorageAccess.read), isA<StorageReadException>());
  });
}
