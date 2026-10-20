@TestOn('browser')
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
