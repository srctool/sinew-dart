import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// The suite every platform's [KeyValueStore] passes, over its real storage:
/// the unit tests run it in memory, and the example app's integration test on
/// each device. Both stores are emptied before each test.
void keyValueStoreContract() {
  late KeyValueStore store;
  late KeyValueStore other;

  setUp(() async {
    store = KeyValueStore.create(name: 'sinew_contract');
    other = KeyValueStore.create(name: 'sinew_contract_other');
    await store.clear();
    await other.clear();
  });

  test('each type round-trips', () async {
    for (final text in ['', 'dark', 'Ä 😀 日本語', 'x' * 5000]) {
      await store.setString('text', text);
      expect(await store.getString('text'), text);
    }
    // ±2^53 - 1: the widest integers every platform keeps, the web included.
    for (final number in [0, -1, 9007199254740991, -9007199254740991]) {
      await store.setInt('number', number);
      expect(await store.getInt('number'), number);
    }
    for (final flag in [true, false]) {
      await store.setBool('flag', flag);
      expect(await store.getBool('flag'), flag);
    }
    for (final decimal in [0.5, -2.5, 1e-300, double.maxFinite]) {
      await store.setDouble('decimal', decimal);
      expect(await store.getDouble('decimal'), decimal);
    }
  });

  test('a missing key is absent', () async {
    expect(await store.getString('missing'), isNull);
    expect(await store.getInt('missing'), isNull);
    expect(await store.getBool('missing'), isNull);
    expect(await store.getDouble('missing'), isNull);
  });

  test('a value read as another type is absent', () async {
    await store.setInt('key', 7);
    expect(await store.getString('key'), isNull);
    expect(await store.getBool('key'), isNull);
    expect(await store.getInt('key'), 7);
    await store.setString('text', 'true');
    expect(await store.getBool('text'), isNull);
    expect(await store.getInt('text'), isNull);
    await store.setBool('flag', true);
    expect(await store.getInt('flag'), isNull);
    expect(await store.getString('flag'), isNull);
    await store.setDouble('decimal', 2.5);
    expect(await store.getInt('decimal'), isNull);
    expect(await store.getString('decimal'), isNull);
  });

  test('writing another type replaces the value', () async {
    await store.setString('key', 'seven');
    await store.setInt('key', 7);
    expect(await store.getString('key'), isNull);
    expect(await store.getInt('key'), 7);
  });

  test('remove deletes one key whatever its type', () async {
    await store.setBool('flag', true);
    await store.setString('theme', 'dark');
    await store.remove('flag');
    await store.remove('never-written');
    expect(await store.getBool('flag'), isNull);
    expect(await store.getString('theme'), 'dark');
  });

  test('clear empties this store only', () async {
    await store.setString('theme', 'dark');
    await store.setInt('launches', 3);
    await other.setString('theme', 'light');
    await store.clear();
    expect(await store.getString('theme'), isNull);
    expect(await store.getInt('launches'), isNull);
    expect(await other.getString('theme'), 'light');
    await store.clear(); // nothing left to clear
  });

  test('stores with the same name share their values', () async {
    await store.setString('theme', 'dark');
    expect(
      await KeyValueStore.create(name: 'sinew_contract').getString('theme'),
      'dark',
    );
  });

  test('stores with other names keep their keys apart', () async {
    await store.setString('theme', 'dark');
    expect(await other.getString('theme'), isNull);
    await other.remove('theme');
    expect(await store.getString('theme'), 'dark');
  });

  test('concurrent writes all land', () async {
    await Future.wait([for (var i = 0; i < 50; i++) store.setInt('key$i', i)]);
    for (var i = 0; i < 50; i++) {
      expect(await store.getInt('key$i'), i);
    }
  });
}
