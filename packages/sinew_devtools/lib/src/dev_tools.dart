import 'package:flutter/foundation.dart';

import 'package:sinew_network/sinew_network.dart';

import 'dev_tools_http_hooks.dart';
import 'exception_recorder.dart';
import 'fault_rules.dart';
import 'host_override.dart';
import 'network_recorder.dart';

/// Devtools' capture, shared by the network hooks, the crash reporter and the
/// dashboard. Everything here is in memory only, and every entry point sits
/// behind `DevToolsGate.enabled`, so production builds tree-shake it away.
abstract final class DevTools {
  /// The Network Monitor's records.
  static final NetworkRecorder network = NetworkRecorder();

  /// The Exception Log's records.
  static final ExceptionRecorder exceptions = ExceptionRecorder();

  /// The active fault rules, in memory only.
  static final FaultRules faults = FaultRules();

  /// The API Host page's choice.
  static final HostOverride hosts = HostOverride();

  static final _hooks = DevToolsHttpHooks(network, faults, hosts);

  /// The hooks to build each client with, from `main`, behind
  /// `DevToolsGate.enabled`:
  /// `SinewHttp.dio(config, tokens, hooks: DevTools.httpHooks)`. They record
  /// every exchange in [network], apply [faults] and the [hosts] override
  /// inside the auth layer, and let [replay] and [expireAccessToken] reach
  /// the client.
  static SinewHttpHooks get httpHooks => _hooks;

  /// Whether [record] can be sent again: it kept everything it needs, and
  /// it's still in [network] with its client.
  static bool canReplay(NetworkRecord record) => _hooks.canReplay(record);

  /// Sends [record]'s request again through the client that sent it, with a
  /// fresh token, and records the result as a new record marked as a replay.
  /// Throws an [ArgumentError] for a record that isn't replayable and a
  /// [StateError] for one that was dropped; a failed response is in the new
  /// record, not thrown.
  static Future<void> replay(NetworkRecord record) => _hooks.replay(record);

  /// "Expire access token": the next request of each client that carries a
  /// token sends an invalid one, so the real refresh runs.
  static void expireAccessToken() => _hooks.expireAccessToken();

  static var _capturing = false;

  /// Records uncaught errors in the Exception Log, through
  /// `FlutterError.onError` and `PlatformDispatcher.instance.onError`. The
  /// previous handlers run first, as before. Calling it again does nothing.
  static void captureUncaughtErrors() {
    if (_capturing) return;
    _capturing = true;
    installUncaughtHooks(
      (error, stack) =>
          exceptions.record(error, stack, source: ExceptionSource.uncaught),
    );
  }

  /// Forgets what belongs to the signed-in user: the network records. Call it
  /// from the app's sign-out.
  static void clearUserData() => network.clear();
}

/// Chains [onError] into `FlutterError.onError` and
/// `PlatformDispatcher.instance.onError`. The previous handler runs first;
/// [onError] runs even if it throws, and a failure in [onError] is swallowed,
/// so recording never changes what the app's handlers do.
void installUncaughtHooks(
  void Function(Object error, StackTrace? stack) onError,
) {
  void safely(Object error, StackTrace? stack) {
    try {
      onError(error, stack);
    } on Object {
      // Recording must never break the app's own handlers.
    }
  }

  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      previousFlutter?.call(details);
    } finally {
      safely(details.exception, details.stack);
    }
  };

  final dispatcher = PlatformDispatcher.instance;
  final previousPlatform = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    try {
      return previousPlatform?.call(error, stack) ?? false;
    } finally {
      safely(error, stack);
    }
  };
}
