import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_security/sinew_security.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// sqlite3's error as it prints: the guard matches it by its text.
final class FakeSqliteException implements Exception {
  const FakeSqliteException(this.text);
  final String text;
  @override
  String toString() => 'SqliteException($text)';
}

final class _Recording implements CrashReporter {
  final reported = <SinewException>[];
  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) =>
      reported.add(error);
}

/// One test per row of the storage handler table, on every platform; the
/// dart:io and browser rows are in storage_guard_io_test and the web test.
void main() {
  late _Recording reporter;
  setUp(() => CrashReporter.install(reporter = _Recording()));
  tearDown(() => CrashReporter.install(CrashReporter.none));

  Future<SinewException> fail(
    Object error, [
    StorageAccess access = StorageAccess.read,
  ]) async {
    final result = await processStorageCall<void>(
      'AUTH',
      'READ_TOKEN',
      access,
      () async => throw error,
    );
    return (result as Failure).error;
  }

  test('a value comes back', () async {
    final result = await processStorageCall(
      'AUTH',
      'READ_TOKEN',
      StorageAccess.read,
      () async => 'refresh-token',
    );
    expect((result as Success<String>).data, 'refresh-token');
  });

  test(
    'corruption is LocalStorageCorruptionException, on reads and writes',
    () async {
      for (final error in <Object>[
        const DecryptionFailed(),
        const FormatException('Unexpected character'),
        PlatformException(
          code: 'Exception encountered',
          message: 'javax.crypto.BadPaddingException: error:1e000065',
        ),
        PlatformException(
          code: 'read',
          details: 'javax.crypto.AEADBadTagException: Tag mismatch',
        ),
      ]) {
        for (final access in StorageAccess.values) {
          final mapped = await fail(error, access);
          expect(
            mapped,
            isA<LocalStorageCorruptionException>(),
            reason: '$error',
          );
          expect(mapped.cause, same(error));
          expect(mapped.code, 'AUTH-R-READ_TOKEN-LSC');
        }
      }
      expect(reporter.reported, isEmpty);
    },
  );

  test('a full device is StorageFullException, on reads and writes', () async {
    for (final error in <Object>[
      PlatformException(
        code: 'Error',
        message: 'java.io.IOException: No space left on device',
      ),
      PlatformException(code: 'write', details: 'ENOSPC'),
      const FakeSqliteException('13): database or disk is full'),
      const FakeSqliteException('SQLITE_FULL'),
    ]) {
      for (final access in StorageAccess.values) {
        expect(
          await fail(error, access),
          isA<StorageFullException>(),
          reason: '$error',
        );
      }
    }
    expect(reporter.reported, isEmpty);
  });

  test('another storage error is a read or write failure, by access', () async {
    for (final error in <Object>[
      PlatformException(
        code: 'Unexpected security result code',
        message: 'Code: -34018',
      ),
      const FakeSqliteException('5): database is locked'),
    ]) {
      final read = await fail(error, StorageAccess.read);
      final write = await fail(error, StorageAccess.write);
      expect(read, isA<StorageReadException>(), reason: '$error');
      expect(read.retryable, isTrue);
      expect(write, isA<StorageWriteException>(), reason: '$error');
    }
    expect(reporter.reported, isEmpty);
  });

  test('a missing envelope payload is a parse failure, and reported', () async {
    final mapped = await fail(const EnvelopeDataMissing());
    expect(mapped, isA<ParseException>());
    expect(reporter.reported, [mapped]);
  });

  test(
    'a bug is unexpected, and reported, even one that mentions space',
    () async {
      for (final error in <Object>[
        StateError('No space left on device'), // not a storage error
        MissingPluginException('no implementation'), // setup, not storage
        TypeError(),
      ]) {
        expect(await fail(error), isA<UnexpectedException>(), reason: '$error');
      }
      expect(reporter.reported, hasLength(3));
    },
  );

  test('a SinewException passes through', () async {
    const own = StorageWriteException(
      'AUTH',
      ExceptionLayer.repository,
      'SAVE',
    );
    expect(await fail(own, StorageAccess.read), same(own));
  });

  test('storageHandlers end with the envelope row', () {
    final handlers = storageHandlers('AUTH', 'READ', StorageAccess.read);
    expect(handlers, hasLength(4));
    expect(handlers.last.matches(const EnvelopeDataMissing()), isTrue);
  });
}
