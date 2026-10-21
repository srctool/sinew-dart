import 'package:sinew_network/sinew_network.dart';

import 'storage_errors.dart';

/// A [RefreshTokenStore] in memory, for `SessionTokenSource` tests. A test
/// can fail the next read or write with a platform storage error, as a secure
/// store can.
final class FakeRefreshTokenStore implements RefreshTokenStore {
  /// A store holding [token].
  FakeRefreshTokenStore([this._token]);

  String? _token;
  Object? _nextReadError;
  Object? _nextWriteError;

  /// The stored refresh token.
  String? get token => _token;

  /// Makes the next read throw [error], once.
  void failNextRead([Object? error]) =>
      _nextReadError = error ?? platformStorageError('Read failed');

  /// Makes the next write or delete throw [error], once, changing nothing.
  void failNextWrite([Object? error]) =>
      _nextWriteError = error ?? platformStorageError('Write failed');

  void _checkWrite() {
    if (_nextWriteError case final error?) {
      _nextWriteError = null;
      throw error;
    }
  }

  @override
  Future<String?> read() async {
    if (_nextReadError case final error?) {
      _nextReadError = null;
      throw error;
    }
    return _token;
  }

  @override
  Future<void> write(String token) async {
    _checkWrite();
    _token = token;
  }

  @override
  Future<void> delete() async {
    _checkWrite();
    _token = null;
  }
}
