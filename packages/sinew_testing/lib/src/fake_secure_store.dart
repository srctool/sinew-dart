import 'package:sinew_storage/sinew_storage.dart';

import 'storage_errors.dart';

/// A [SecureStore] in memory, without encryption. A test can fail the next
/// read or write with a platform storage error, or [loseKey] as a restore
/// onto a new device does: every secret stored so far then reads as absent
/// (and is deleted, as the real store deletes what it can't decrypt), while
/// later writes work.
final class FakeSecureStore implements SecureStore {
  /// An empty store for [name], the namespace.
  FakeSecureStore({this.name = 'fake'});

  @override
  final String name;

  final _values = <String, String>{};
  Object? _nextReadError;
  Object? _nextWriteError;
  bool _keyLost = false;

  /// Every stored secret by key, for assertions.
  Map<String, String> get snapshot => Map.unmodifiable(_values);

  /// Makes the next read throw [error], once.
  void failNextRead([Object? error]) =>
      _nextReadError = error ?? platformStorageError('Read failed');

  /// Makes the next write (`write`, `delete` or `clearUserData`) throw
  /// [error], once, writing nothing.
  void failNextWrite([Object? error]) =>
      _nextWriteError = error ?? platformStorageError('Write failed');

  /// Loses the key: every secret stored so far reads as absent.
  void loseKey() => _keyLost = true;

  void _checkRead() {
    if (_nextReadError case final error?) {
      _nextReadError = null;
      throw error;
    }
    if (_keyLost) {
      _values.clear();
      _keyLost = false;
    }
  }

  Future<void> _write(void Function(Map<String, String> values) change) async {
    if (_nextWriteError case final error?) {
      _nextWriteError = null;
      throw error;
    }
    change(_values);
  }

  @override
  Future<String?> read(String key) async {
    _checkRead();
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) =>
      _write((values) => values[key] = value);

  @override
  Future<void> delete(String key) => _write((values) => values.remove(key));

  @override
  Future<void> clearUserData() => _write((values) => values.clear());

  @override
  Future<List<String>> keys() async {
    _checkRead();
    return _values.keys.toList()..sort();
  }
}
