import 'dart:async';

import 'package:sinew_network/sinew_network.dart';

/// A [NetworkChecker] a test switches by hand.
final class FakeNetworkChecker implements NetworkChecker {
  /// Creates the checker reporting [initial].
  FakeNetworkChecker([NetworkStatus initial = NetworkStatus.online])
    : _status = initial;

  final _changes = StreamController<NetworkStatus>.broadcast(sync: true);
  NetworkStatus _status;

  bool _disposed = false;

  /// Whether [dispose] was called.
  bool get disposed => _disposed;

  @override
  NetworkStatus get status => _status;

  @override
  bool get isOnline => _status == NetworkStatus.online;

  @override
  Stream<NetworkStatus> get changes => _changes.stream;

  /// Reports the device offline.
  void goOffline() => _set(NetworkStatus.offline);

  /// Reports the device online.
  void goOnline() => _set(NetworkStatus.online);

  void _set(NetworkStatus status) {
    if (_disposed || status == _status) return;
    _status = status;
    _changes.add(status);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }
}
