import 'package:sinew_network/sinew_network.dart';

/// A [RefreshTokenStore] in memory, with the stored [token] readable.
class MemoryStore implements RefreshTokenStore {
  MemoryStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> delete() async => token = null;
}
