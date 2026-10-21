import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// [SessionTokenSource]'s [RefreshTokenStore] in a [SecureStore], under
/// [key].
final class SecureRefreshTokenStore implements RefreshTokenStore {
  /// The refresh token in [store], under [key].
  SecureRefreshTokenStore(this.store, {this.key = 'session.refreshToken'});

  /// Where the token is kept.
  final SecureStore store;

  /// The token's key in [store].
  final String key;

  @override
  Future<String?> read() => store.read(key);

  @override
  Future<void> write(String token) => store.write(key, token);

  @override
  Future<void> delete() => store.delete(key);
}
