import 'package:flutter/foundation.dart';

import 'exception_recorder.dart';
import 'network_recorder.dart';

/// Devtools' capture, shared by the network hooks, the crash reporter and the
/// dashboard. Everything here is in memory only, and every entry point sits
/// behind `DevToolsGate.enabled`, so production builds tree-shake it away.
abstract final class DevTools {
  /// The Network Monitor's records.
  static final NetworkRecorder network = NetworkRecorder();

  /// The Exception Log's records.
  static final ExceptionRecorder exceptions = ExceptionRecorder();

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
