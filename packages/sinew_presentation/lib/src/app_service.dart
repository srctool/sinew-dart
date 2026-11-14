import 'dart:async';

/// How long an [AppService] lives.
enum ServiceLifetime {
  /// From app start to process death: started by [AppServiceHost.startApp].
  app,

  /// From sign-in to sign-out: started by [AppServiceHost.startSession] and
  /// stopped by [AppServiceHost.stopSession].
  session,
}

/// The second kind of driver, beside a page handler: work with the app's or the
/// signed-in session's lifetime and no UI (a purchase from the store, a pub/sub
/// message, a push). It calls use cases and folds their `Result`, and writes to
/// repositories that pages observe. Name it for what it does, plus `Service`:
/// `BillingService`.
///
/// A service guards its own steps with
/// `processCall(module, function, ExceptionLayer.service, const [], body)`, so a
/// bug in one is reported with an `SV` code (`MSG-SV-INIT-GEN`). Whatever a step
/// still throws never stops the other services, or this one from listening (see
/// [AppServiceHost]).
abstract class AppService {
  /// A service of the given [lifetime]: the app's or the signed-in session's.
  AppService(this.lifetime);

  /// Whether the app or the signed-in session owns this service.
  final ServiceLifetime lifetime;

  /// Catches up on what happened while the app wasn't running (an
  /// unacknowledged purchase, unread messages), once per start and before
  /// [listen]. The use cases it calls must be idempotent.
  Future<void> init() async {}

  /// Subscribes to the sources (a store, a socket, a push). Keep the
  /// `StreamSubscription`s, and cancel them in [destroy].
  void listen();

  /// Stops listening and releases what the service holds. A session service
  /// clears what it holds for that user.
  Future<void> destroy() async {}
}

/// Starts and stops [services] with the app and the signed-in session.
///
/// Each service is isolated: a step that throws is surfaced as an unhandled
/// error of the current zone (in development and in crash reports, like any
/// bug), the service still listens, and the others still start. Build it in
/// `main()` before `runApp`, and keep it for the life of the app.
class AppServiceHost {
  /// A host for [services], which start in list order. The app decides which
  /// services exist.
  AppServiceHost(this.services);

  /// Every service, in the order they start.
  final List<AppService> services;

  bool _appStarted = false;
  final List<AppService> _appRunning = [];

  // Bumped by every stopSession, so a start that was running when it happened knows it was stopped.
  int _sessionRun = 0;
  bool _sessionStarted = false;
  final List<AppService> _sessionRunning = [];

  /// Runs `init`, then `listen`, for every [ServiceLifetime.app] service, in
  /// list order. A second call does nothing.
  Future<void> startApp() async {
    if (_appStarted) return;
    _appStarted = true;
    await _start(ServiceLifetime.app, _appRunning, () => true);
  }

  /// The same for [ServiceLifetime.session] services, after sign-in. A second
  /// call while a session runs does nothing.
  Future<void> startSession() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    final run = ++_sessionRun;
    await _start(
      ServiceLifetime.session,
      _sessionRunning,
      () => run == _sessionRun,
    );
  }

  /// Stops the session: calls `destroy` on the session services that started,
  /// in reverse order, at once. An `init` still running can't be cancelled in
  /// Dart, so its service never listens. A `destroy` that throws doesn't stop
  /// the others; the first failure is rethrown after all of them ran. Does
  /// nothing when no session runs.
  Future<void> stopSession() async {
    if (!_sessionStarted) return;
    _sessionStarted = false;
    _sessionRun++;
    await _destroyInReverse(_sessionRunning);
  }

  /// Stops the session, then destroys the app services in reverse order:
  /// shutdown and tests.
  Future<void> stopAll() async {
    Object? failure;
    StackTrace? trace;
    try {
      await stopSession();
    } catch (e, s) {
      failure = e;
      trace = s;
    }
    _appStarted = false;
    try {
      await _destroyInReverse(_appRunning);
    } catch (e, s) {
      if (failure == null) {
        failure = e;
        trace = s;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }

  Future<void> _start(
    ServiceLifetime lifetime,
    List<AppService> running,
    bool Function() current,
  ) async {
    for (final service in services) {
      if (service.lifetime != lifetime) continue;
      running.add(service);
      await _guard(service.init);
      if (!current()) return; // stopped while this init ran: never listen
      await _guard(() async => service.listen());
    }
  }

  /// Runs one step of a service. A throw goes to the zone's uncaught-error
  /// handler, so it's reported like any bug and nothing else ends.
  Future<void> _guard(Future<void> Function() step) async {
    try {
      await step();
    } catch (e, s) {
      Zone.current.handleUncaughtError(e, s);
    }
  }

  Future<void> _destroyInReverse(List<AppService> running) async {
    Object? failure;
    StackTrace? trace;
    final stopping = running.reversed.toList();
    running.clear();
    for (final service in stopping) {
      try {
        await service.destroy();
      } catch (e, s) {
        if (failure == null) {
          failure = e;
          trace = s;
        }
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }
}
