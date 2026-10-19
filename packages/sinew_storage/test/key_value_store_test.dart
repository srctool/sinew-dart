import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sinew_storage/sinew_storage.dart';

import 'key_value_store_contract.dart';

void main() {
  // SharedPreferencesAsync's in-memory platform: the async API's counterpart of
  // SharedPreferences.setMockInitialValues.
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  group('contract', keyValueStoreContract);

  group('create', () {
    test('a blank name or one with a "." is refused', () {
      for (final name in ['', ' ', 'a.b', '.']) {
        expect(
          () => KeyValueStore.create(name: name),
          throwsArgumentError,
          reason: '"$name"',
        );
      }
    });

    test('keys are stored under "<name>."', () async {
      await KeyValueStore.create().setString('theme', 'dark');
      await KeyValueStore.create(name: 'orders').setInt('filter', 2);
      expect(await SharedPreferencesAsync().getAll(), {
        'sinew_prefs.theme': 'dark',
        'orders.filter': 2,
      });
    });

    test('clear leaves keys outside every store alone', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('sinew_prefsX', 'unprefixed');
      await prefs.setString('plugin.key', 'another plugin');
      final store = KeyValueStore.create();
      await store.setString('theme', 'dark');
      await store.clear();
      expect(await prefs.getAll(), {
        'sinew_prefsX': 'unprefixed',
        'plugin.key': 'another plugin',
      });
    });
  });
}
