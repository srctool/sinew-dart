import 'dart:async';

import 'package:dio/dio.dart';

import 'token_source.dart';

/// One refresh at a time. Every 401 that arrives while a refresh runs waits
/// for that refresh's outcome instead of starting its own: with rotating
/// refresh tokens, a second refresh would invalidate the first.
///
/// Dart runs one event at a time, so checking for a finished refresh and
/// joining the running one happen together, with no `await` between them: a
/// 401 can't slip in as a refresh completes. The refresh isn't tied to any
/// request's cancel token, so cancelling the request that started it cancels
/// only that request.
final class _SingleFlightRefresher {
  _SingleFlightRefresher(this._source);

  final TokenSource _source;
  Completer<RefreshOutcome>? _inFlight;

  /// For a 401 on a request sent with [sentWith]: [Refreshed] at once when
  /// the token already changed, otherwise joins the running refresh or starts
  /// one. A refresh that threw rethrows in every waiter.
  Future<RefreshOutcome> refresh(String? sentWith) {
    final running = _inFlight;
    if (running != null) return running.future;
    final current = _source.accessToken();
    if (current != null && current != sentWith) {
      return Future.value(const Refreshed());
    }
    final started = _inFlight = Completer<RefreshOutcome>();
    unawaited(_run(started));
    return started.future;
  }

  Future<void> _run(Completer<RefreshOutcome> started) async {
    try {
      final outcome = await _source.refresh();
      _finish(started, () => started.complete(outcome));
    } on Object catch (e, stackTrace) {
      _finish(started, () => started.completeError(e, stackTrace));
    }
  }

  void _finish(Completer<RefreshOutcome> started, void Function() answer) {
    if (identical(_inFlight, started)) _inFlight = null;
    if (!started.isCompleted) answer();
  }

  /// Sign-out: answers the running refresh's waiters as [Rejected] at once.
  /// The refresh itself can't be stopped; its late result is answered to
  /// nobody, and the token source's epoch keeps it from storing anything.
  void reset() {
    final running = _inFlight;
    _inFlight = null;
    if (running != null && !running.isCompleted) {
      running.complete(const Rejected());
    }
  }
}

const _attached = 'sinew.auth.attached';
const _sentWith = 'sinew.auth.sentWith';
const _replayed = 'sinew.auth.replayed';

/// The auth layer. For a request to the client's own host and port (from
/// `options.baseUrl`, or [baseUrl]), outside [anonymousPaths], it attaches
/// the current access token and handles a 401:
///
/// - sent with an older token than the current one: a refresh already
///   finished, so it replays at once;
/// - sent with a token that has since been cleared: the user signed out, so
///   it passes the 401 on without refreshing;
/// - otherwise it joins or starts the single refresh, then replays once with
///   the new token ([Refreshed]), passes the 401 on for the guard to classify
///   as `UnauthorizedException` ([Rejected]), or fails with the cause,
///   keeping the session ([Unavailable]).
///
/// The replay goes out on [dio] itself, through every interceptor, marked so
/// a second 401 on it is passed on instead of refreshing again. A plain
/// interceptor that awaits a replay can't deadlock, unlike a
/// `QueuedInterceptor`. A request to another host, an anonymous path and a
/// request with its own `Authorization` are left alone; a one-shot streamed
/// body still triggers the refresh but isn't replayed, so the app's retry
/// carries the new token.
///
/// ```dart
/// dio.interceptors.add(SinewAuthInterceptor(dio, tokenSource: tokens, anonymousPaths: {'/auth/login'}));
/// ```
///
/// On sign-out, call `SinewHttp.resetAuth(dio)` and `tokenSource.clear()`.
final class SinewAuthInterceptor extends Interceptor {
  /// Creates the interceptor for [dio]. Throws an [ArgumentError] for an
  /// anonymous path without a leading `/`.
  SinewAuthInterceptor(
    this.dio, {
    required this.tokenSource,
    this.anonymousPaths = const {},
    this.baseUrl,
  }) : _refresher = _SingleFlightRefresher(tokenSource) {
    final relative = anonymousPaths.where((p) => !p.startsWith('/')).toList();
    if (relative.isNotEmpty) {
      throw ArgumentError.value(
        relative,
        'anonymousPaths',
        "must start with '/'",
      );
    }
  }

  /// The client this interceptor is installed on: replays go out on it.
  final Dio dio;

  /// Where the tokens live and how they refresh.
  final TokenSource tokenSource;

  /// Paths that never get a token and never trigger a refresh (sign-in,
  /// register, OTP, password reset, the refresh call), matched exactly,
  /// relative to the base URL's path: with `https://api.example.com/v1`,
  /// `/auth/login` matches `/v1/auth/login`, not `/v1/auth/login/history`.
  final Set<String> anonymousPaths;

  /// The backend's base URL, when it isn't the request's `baseUrl`. Only its
  /// host and port receive the token.
  final String? baseUrl;

  final _SingleFlightRefresher _refresher;

  /// Sign-out: answers requests waiting on a running refresh with a 401 at
  /// once. Called by `SinewHttp.resetAuth`.
  void reset() => _refresher.reset();

  bool _ownsToken(RequestOptions options) {
    final base = Uri.parse(baseUrl ?? options.baseUrl);
    final uri = options.uri;
    if (uri.host != base.host || uri.port != base.port) return false;
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final path = uri.path;
    final relative = path.startsWith('$basePath/')
        ? path.substring(basePath.length)
        : path;
    return !anonymousPaths.contains(relative);
  }

  static void _attach(RequestOptions options, String? token) {
    options.extra[_attached] = true;
    options.extra[_sentWith] = token;
    if (token == null) {
      options.headers.remove('Authorization');
    } else {
      options.headers['Authorization'] = 'Bearer $token';
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final callersOwn =
        options.headers.containsKey('Authorization') &&
        options.extra[_attached] != true;
    if (!callersOwn && _ownsToken(options)) {
      _attach(options, tokenSource.accessToken());
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        options.extra[_attached] != true ||
        options.extra[_replayed] == true) {
      return handler.next(err);
    }
    final sentWith = options.extra[_sentWith] as String?;
    if (tokenSource.accessToken() == null && sentWith != null) {
      return handler.next(err); // signed out meanwhile
    }

    final RefreshOutcome outcome;
    try {
      outcome = await _refresher.refresh(sentWith);
    } on Object catch (e, stackTrace) {
      return handler.next(
        DioException(requestOptions: options, error: e, stackTrace: stackTrace),
      );
    }
    switch (outcome) {
      case Refreshed():
        final token = tokenSource.accessToken();
        if (token == null || options.data is Stream) {
          return handler.next(err); // can't be sent twice: the app retries
        }
        options.extra[_replayed] = true;
        _attach(options, token);
        try {
          // The replay already ran through every interceptor: hand its result straight to the caller.
          handler.resolve(await dio.fetch<Object?>(options));
        } on DioException catch (e) {
          handler.reject(e);
        }
      case Rejected():
        handler.next(err);
      case Unavailable(:final cause):
        handler.next(DioException(requestOptions: options, error: cause));
    }
  }
}
