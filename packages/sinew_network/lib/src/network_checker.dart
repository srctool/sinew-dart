import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device has a usable network.
enum NetworkStatus {
  /// A network interface is connected.
  online,

  /// No network interface is connected.
  offline,
}

/// The device's connectivity, for the UI: an offline banner, a disabled
/// submit button. It never decides a request's error type, which comes from
/// the request's own failure: "connected to Wi-Fi" doesn't mean "the backend is
/// reachable".
///
/// Monitoring starts when it's created and stops on [dispose]. Create one per
/// app, at the composition root: `connectivity_plus` listens through one
/// platform channel, so a second checker would take it over.
abstract interface class NetworkChecker {
  /// The platform's checker, on `connectivity_plus`: online when any interface
  /// is connected (Wi-Fi, mobile, ethernet, VPN…). That's the interface only,
  /// so a captive portal counts as online. On a platform `connectivity_plus`
  /// doesn't implement, the checker stays [NetworkStatus.online].
  ///
  /// It needs the plugin, so a widget test uses `sinew_testing`'s
  /// `FakeNetworkChecker` instead: without a running app, Flutter's platform
  /// channel reports a missing binding or plugin as an error of its own.
  factory NetworkChecker() = ConnectivityNetworkChecker;

  /// The last status the platform reported. Starts [NetworkStatus.online]
  /// until it first reports, so an app doesn't flash an offline banner at
  /// launch.
  NetworkStatus get status;

  /// Whether [status] is [NetworkStatus.online] right now.
  bool get isOnline;

  /// Each change of [status], as a broadcast stream. It doesn't repeat the
  /// current status on listen: start from [status] (a `StreamBuilder`'s
  /// `initialData`).
  Stream<NetworkStatus> get changes;

  /// Stops monitoring and closes [changes]. [status] keeps its last value.
  Future<void> dispose();
}

/// The `connectivity_plus` checker behind [NetworkChecker.new].
final class ConnectivityNetworkChecker implements NetworkChecker {
  /// Starts monitoring [connectivity], `Connectivity()` by default.
  ConnectivityNetworkChecker([Connectivity? connectivity]) {
    try {
      final source = connectivity ?? Connectivity();
      _subscription = source.onConnectivityChanged.listen(
        (results) {
          _heard = true;
          _report(results);
        },
        // A platform error keeps the last status.
        onError: (Object _) {},
      );
      // The stream may only report on a change: the check gives the starting
      // status, unless the stream has already reported a newer one.
      source.checkConnectivity().then((results) {
        if (!_heard) _report(results);
      }, onError: (Object _) {});
    } on Object {
      // A platform connectivity_plus doesn't implement: stay online.
    }
  }

  final _changes = StreamController<NetworkStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  NetworkStatus _status = NetworkStatus.online;
  bool _heard = false;
  bool _reported = false;
  bool _disposed = false;

  /// Whether the platform has answered yet, from the check or a change.
  @visibleForTesting
  bool get reported => _reported;

  @override
  NetworkStatus get status => _status;

  @override
  bool get isOnline => _status == NetworkStatus.online;

  @override
  Stream<NetworkStatus> get changes => _changes.stream;

  void _report(List<ConnectivityResult> results) {
    if (_disposed) return;
    _reported = true;
    final status = statusOf(results);
    if (status == _status) return;
    _status = status;
    _changes.add(status);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _changes.close();
  }
}

/// Online when any interface other than [ConnectivityResult.none] is reported.
/// `connectivity_plus` never reports an empty list; one counts as offline.
NetworkStatus statusOf(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none)
    ? NetworkStatus.online
    : NetworkStatus.offline;
