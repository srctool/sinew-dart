@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import 'key_value_store_contract.dart';

/// The contract on the browser's real `localStorage`: Flutter can't run
/// integration tests on the web, and `flutter test --platform chrome` doesn't
/// register the web plugin by itself.
void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncWeb(),
  );

  group('KeyValueStore on localStorage', keyValueStoreContract);
}
