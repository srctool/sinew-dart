import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import 'error_body.dart';
import 'http_status_error.dart';

const _readMethods = {'GET', 'HEAD'};

/// The `extra` key for one request's own deadline, which wins over
/// [SinewTimeoutInterceptor]'s:
/// `Options(extra: {sinewDeadline: Duration(minutes: 2)})`.
const sinewDeadline = 'sinew.deadline';

/// Why [SinewTimeoutInterceptor] cancelled a request: its deadline passed.
/// The guard turns a cancellation with this reason into a
/// `RequestTimeOutException`, never a `CancelException`.
final class DeadlineExceeded {
  /// The reason, with the [deadline] that passed.
  const DeadlineExceeded(this.deadline);

  /// The deadline the request had.
  final Duration deadline;

  @override
  String toString() => 'Deadline of ${deadline.inMilliseconds} ms exceeded';
}

/// A **total** deadline on every request: [read] for `GET` and `HEAD`, [write]
/// for the rest. Dio's own `receiveTimeout` only limits the gap between data
/// chunks, so a response that trickles in never trips it; this cancels the
/// request when the whole exchange runs past its deadline. A request's own
/// [sinewDeadline] wins, for a slow endpoint.
///
/// The request gets a cancel token of its own, so a deadline never cancels a
/// token the caller shares with other requests; cancelling the caller's token
/// still cancels this request. It also sets [connect] as the connect timeout
/// unless the request has one.
final class SinewTimeoutInterceptor extends Interceptor {
  /// Creates the interceptor. Throws an [ArgumentError] for a duration that
  /// isn't positive.
  SinewTimeoutInterceptor({
    this.read = const Duration(seconds: 30),
    this.write = const Duration(seconds: 60),
    this.connect = const Duration(seconds: 15),
  }) {
    for (final (name, value) in [
      ('read', read),
      ('write', write),
      ('connect', connect),
    ]) {
      if (value <= Duration.zero) {
        throw ArgumentError.value(value, name, 'must be positive');
      }
    }
  }

  /// The total deadline for reads.
  final Duration read;

  /// The total deadline for writes, longer because repeating one is costly.
  final Duration write;

  /// The deadline to open a connection.
  final Duration connect;

  static const _timer = 'sinew.deadline.timer';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _stop(options);
    final deadline =
        options.extra[sinewDeadline] as Duration? ??
        (_readMethods.contains(options.method.toUpperCase()) ? read : write);
    options.connectTimeout ??= connect;
    final own = CancelToken();
    final callers = options.cancelToken;
    if (callers != null) {
      unawaited(
        callers.whenCancel.then((e) {
          if (!own.isCancelled) own.cancel(e.error);
        }),
      );
    }
    options.cancelToken = own;
    options.extra[_timer] = Timer(deadline, () {
      if (!own.isCancelled) own.cancel(DeadlineExceeded(deadline));
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _stop(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _stop(err.requestOptions);
    handler.next(err);
  }

  static void _stop(RequestOptions options) =>
      (options.extra.remove(_timer) as Timer?)?.cancel();
}

/// `Accept: application/json`, `Accept-Language` from [locale] and the
/// [defaults], read on every request so a language switch applies to the next
/// one. A header the request set itself wins.
final class SinewHeadersInterceptor extends Interceptor {
  /// Creates the interceptor.
  SinewHeadersInterceptor({required this.locale, this.defaults});

  /// The language for `Accept-Language`. A blank value sends none.
  final String Function() locale;

  /// Headers for every request (app version, API key, device id).
  final Map<String, String> Function()? defaults;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Dio keeps request headers in a case-insensitive map, so `accept` and
    // `Accept` are the same header here.
    final headers = options.headers;
    void putIfAbsent(String name, String value) {
      if (!headers.containsKey(name)) headers[name] = value;
    }

    putIfAbsent(Headers.acceptHeader, Headers.jsonContentType);
    final language = locale();
    if (language.trim().isNotEmpty) putIfAbsent('Accept-Language', language);
    defaults?.call().forEach(putIfAbsent);
    handler.next(options);
  }
}

/// Reads a failed response's body with [reader] and attaches it, with the
/// `Retry-After` wait, to the `DioException` as an `HttpStatusError`, for
/// `processApiCall` to classify. Any install order works: it only adds to the
/// error, so an auth interceptor still sees the 401.
final class SinewErrorBodyInterceptor extends Interceptor {
  /// Creates the interceptor.
  SinewErrorBodyInterceptor({this.reader = ErrorBodyReader.standard});

  /// How this backend's error bodies read.
  final ErrorBodyReader reader;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (err.type != DioExceptionType.badResponse ||
        response == null ||
        err.error is HttpStatusError) {
      return handler.next(err);
    }
    final status = response.statusCode ?? 0;
    handler.next(
      err.copyWith(
        error: HttpStatusError(
          status,
          reader.read(status, response.data),
          parseRetryAfter(response.headers.value('retry-after')),
        ),
      ),
    );
  }
}

/// Where [SinewLogInterceptor]'s lines go: pass the app's logger.
typedef HttpLogger = void Function(String line);

/// Writes to the `dart:developer` log, under the name `SinewHttp`.
void defaultHttpLogger(String line) => developer.log(line, name: 'SinewHttp');

/// One line per exchange: method, host, path, status and duration, or the
/// failure's type. Headers, bodies, query strings and error messages are
/// never read, so no token or credential can reach the log. Install it last,
/// so each replay after a refresh is its own line. Debug builds only.
final class SinewLogInterceptor extends Interceptor {
  /// Creates the interceptor.
  SinewLogInterceptor({this.logger = defaultHttpLogger});

  /// Where the lines go.
  final HttpLogger logger;

  static const _started = 'sinew.log.started';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_started] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _line(response.requestOptions, '${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    _line(
      err.requestOptions,
      status != null ? '$status' : 'failed: ${err.type.name}',
    );
    handler.next(err);
  }

  void _line(RequestOptions options, String outcome) {
    final watch = options.extra.remove(_started) as Stopwatch?;
    final uri = options.uri;
    logger(
      '${options.method.toUpperCase()} ${uri.host}${uri.path} → $outcome '
      '(${watch?.elapsedMilliseconds ?? 0} ms)',
    );
  }
}
