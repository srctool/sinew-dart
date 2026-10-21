@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_storage/sinew_storage.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import 'key_value_store_contract.dart';
import 'secure_store_contract.dart';

/// The contracts on the browser's real storage (`localStorage`, and Web
/// Crypto for the secure store's key): Flutter can't run integration tests on
/// the web, and `flutter test --platform chrome` doesn't register the web
/// plugins by itself.
void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncWeb();
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();
  });

  group('KeyValueStore on localStorage', keyValueStoreContract);
  group('SecureStore on localStorage and Web Crypto', secureStoreContract);

  group('the storage guard', () {
    setUp(() => CrashReporter.install(CrashReporter.none));

    Future<SinewException> fail(
      Future<void> Function() block, [
      StorageAccess access = StorageAccess.write,
    ]) async => ((await processStorageCall(
      'PREF',
      'SAVE',
      access,
      block,
    )) as Failure).error;

    JSObject domException(String name) =>
        (globalContext['DOMException']! as JSFunction).callAsConstructor(
          'from the test'.toJS,
          name.toJS,
        );

    test('a full localStorage is StorageFullException', () async {
      final store = KeyValueStore.create(name: 'quota');
      try {
        // Larger than any browser's localStorage quota for an origin.
        final error = await fail(() => store.setString('big', 'x' * 12000000));
        expect(error, isA<StorageFullException>());
      } finally {
        await store.clear();
      }
    });

    test('another storage DOMException is a read or write failure', () async {
      final error = domException('SecurityError');
      expect(
        await fail(() async => throw error, StorageAccess.read),
        isA<StorageReadException>(),
      );
      expect(await fail(() async => throw error), isA<StorageWriteException>());
    });

    test('a JavaScript TypeError is a bug, not a storage error', () async {
      final typeError = (globalContext['TypeError']! as JSFunction)
          .callAsConstructor<JSObject>('undefined is not a function'.toJS);
      expect(
        await fail(() async => throw typeError),
        isA<UnexpectedException>(),
      );
    });
  });
}
