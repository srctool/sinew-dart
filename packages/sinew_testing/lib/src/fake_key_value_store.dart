import 'package:sinew_storage/sinew_storage.dart';

import 'storage_errors.dart';

/// A [KeyValueStore] in memory, behaving like the real one: a value read as
/// another type than it was written is absent, and `clear` empties only this
/// store. A test can fail the next read or write with a platform storage
/// error, or the next write with a full disk; through `processStorageCall`
/// they become `StorageReadException`, `StorageWriteException` and
/// `StorageFullException`.
final class FakeKeyValueStore implements KeyValueStore {
  /// An empty store named [name].
  FakeKeyValueStore({this.name = 'fake_prefs'});

  @override
  final String name;

  final _values = <String, Object>{};
  Object? _nextReadError;
  Object? _nextWriteError;

  /// Every stored value by key, for assertions.
  Map<String, Object> get snapshot => Map.unmodifiable(_values);

  /// Makes the next read throw [error], once.
  void failNextRead([Object? error]) =>
      _nextReadError = error ?? platformStorageError('Read failed');

  /// Makes the next write (a set, `remove` or `clear`) throw [error], once,
  /// writing nothing.
  void failNextWrite([Object? error]) =>
      _nextWriteError = error ?? platformStorageError('Write failed');

  /// Makes the next write fail as the device being full.
  void failNextWriteWithDiskFull() => failNextWrite(diskFullError());

  Map<String, Object> _read() {
    if (_nextReadError case final error?) {
      _nextReadError = null;
      throw error;
    }
    return _values;
  }

  Future<void> _write(void Function(Map<String, Object> values) change) async {
    if (_nextWriteError case final error?) {
      _nextWriteError = null;
      throw error;
    }
    change(_values);
  }

  Future<T?> _get<T>(String key) async {
    final value = _read()[key];
    return value is T ? value : null;
  }

  @override
  Future<String?> getString(String key) => _get<String>(key);

  @override
  Future<void> setString(String key, String value) =>
      _write((values) => values[key] = value);

  @override
  Future<int?> getInt(String key) => _get<int>(key);

  @override
  Future<void> setInt(String key, int value) =>
      _write((values) => values[key] = value);

  @override
  Future<bool?> getBool(String key) => _get<bool>(key);

  @override
  Future<void> setBool(String key, bool value) =>
      _write((values) => values[key] = value);

  @override
  Future<double?> getDouble(String key) => _get<double>(key);

  @override
  Future<void> setDouble(String key, double value) =>
      _write((values) => values[key] = value);

  @override
  Future<void> remove(String key) => _write((values) => values.remove(key));

  @override
  Future<void> clear() => _write((values) => values.clear());

  @override
  Future<List<String>> keys() async => _read().keys.toList()..sort();

  @override
  Future<String?> read(String key) async => _read()[key]?.toString();
}
