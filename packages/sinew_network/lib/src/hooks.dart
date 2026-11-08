import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Devtools' way into a client: fault injection, a host override and
/// recording. Only devtools implements it. Every member has a default that
/// leaves the request alone, and [none] is what a client gets without
/// devtools, so production code paths never change.
abstract class SinewHttpHooks {
  /// Hooks that leave every request alone. Extend this to override only what
  /// you need.
  const SinewHttpHooks();

  /// Leaves every request alone. The default.
  static const SinewHttpHooks none = _NoHooks();

  /// Called once, when a client is built with these hooks: devtools keeps it
  /// to replay records and expire tokens.
  void attached(Dio dio) {}

  /// The base URL to send to instead of the client's own (devtools' API host
  /// page), or `null` to keep it.
  String? hostOverride() => null;

  /// A fault to apply to a request instead of sending it as it is, or `null`
  /// to send it.
  Future<FaultDecision?> fault(String method, Uri uri) async => null;

  /// Called once per exchange that reached the network or a fault, with the
  /// raw values: devtools redacts them.
  void record(HttpExchange exchange) {}
}

final class _NoHooks extends SinewHttpHooks {
  const _NoHooks();
}

/// What a fault does to a request, inside the auth layer: wait [delay], then
/// fail as a dropped connection ([drop]), answer [status] with [body] without
/// reaching the network, or, with neither, send the request after the delay.
final class FaultDecision {
  /// A fault. Throws an [ArgumentError] for a status outside 100–599, or for
  /// both a drop and a status.
  FaultDecision({this.delay, this.status, this.body, this.drop = false}) {
    if (status != null && (status! < 100 || status! > 599)) {
      throw ArgumentError.value(status, 'status', 'must be an HTTP status');
    }
    if (drop && status != null) {
      throw ArgumentError(
        'A fault either drops the connection or answers a status, not both',
      );
    }
  }

  /// How long to wait first.
  final Duration? delay;

  /// The status to answer with, without reaching the network.
  final int? status;

  /// The body to answer [status] with.
  final String? body;

  /// Whether to fail as a dropped connection.
  final bool drop;
}

/// One request and its response, as sent: after the auth layer and the host
/// override. Values are **not** redacted; only devtools receives this, and it
/// redacts before storing anything.
final class HttpExchange {
  /// An exchange.
  const HttpExchange({
    required this.dio,
    required this.method,
    required this.url,
    required this.requestedUrl,
    required this.requestHeaders,
    required this.requestBody,
    required this.requestBodyStreamed,
    required this.status,
    required this.responseHeaders,
    required this.responseBody,
    required this.startedAt,
    required this.duration,
    required this.error,
    required this.defaultHeaderNames,
    required this.extra,
  });

  /// The client that sent it, to replay through.
  final Dio dio;

  /// The request method, upper case.
  final String method;

  /// The URL as sent, after a host override.
  final String url;

  /// The URL the caller asked for, before a host override: what a replay
  /// asks for again.
  final String requestedUrl;

  /// The request headers, with its content type.
  final Map<String, List<String>> requestHeaders;

  /// The request body, or `null` when there was none or it was streamed.
  final List<int>? requestBody;

  /// Whether the request body was streamed or multipart, so it couldn't be
  /// read or sent again.
  final bool requestBodyStreamed;

  /// The response status, or `null` when the request failed before one.
  final int? status;

  /// The response headers.
  final Map<String, List<String>> responseHeaders;

  /// The response body, or `null` when there was none or it was streamed.
  final List<int>? responseBody;

  /// When the request started.
  final DateTime startedAt;

  /// How long the exchange took.
  final Duration duration;

  /// The failure, if the exchange failed.
  final Object? error;

  /// The names of the client's default headers when it was sent: devtools
  /// redacts them.
  final Set<String> defaultHeaderNames;

  /// The request's `extra`, where devtools marks its own replays.
  final Map<String, dynamic> extra;
}

/// A connection dropped by a devtools fault. Raised as a connection error, so
/// the guard treats it as no connection, like a real one.
final class InjectedConnectionDrop implements Exception {
  /// The error.
  const InjectedConnectionDrop();

  @override
  String toString() => 'Connection dropped by a devtools fault rule';
}

/// An invalid token, sent once after `SinewHttp.debugExpireToken`.
const expiredToken = 'sinew-devtools-expired';

const _started = 'sinew.hooks.started';
const _clock = 'sinew.hooks.clock';
const _requested = 'sinew.hooks.requested';

/// Hands every exchange to [hooks] once, with the URL the caller asked for.
/// Installed **before** the auth interceptor: it sees a 401 before the auth
/// layer replays it, and each replay is recorded on its own.
final class SinewRecorderInterceptor extends Interceptor {
  /// Creates the interceptor for [dio].
  SinewRecorderInterceptor(this.dio, {required this.hooks, this.defaults});

  /// The client it's installed on.
  final Dio dio;

  /// The hooks to hand exchanges to.
  final SinewHttpHooks hooks;

  /// The client's default headers: their names go with each exchange.
  final Map<String, String> Function()? defaults;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!identical(hooks, SinewHttpHooks.none)) {
      options.extra[_started] = DateTime.now();
      options.extra[_clock] = Stopwatch()..start();
      options.extra[_requested] = options.uri.toString();
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _record(response.requestOptions, response, null);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(err.requestOptions, err.response, err.error ?? err);
    handler.next(err);
  }

  void _record(
    RequestOptions options,
    Response<dynamic>? response,
    Object? error,
  ) {
    if (identical(hooks, SinewHttpHooks.none)) return;
    final clock = options.extra.remove(_clock) as Stopwatch?;
    final started = options.extra.remove(_started) as DateTime?;
    final requested = options.extra.remove(_requested) as String?;
    if (clock == null || started == null) return; // recorded already
    final (body, streamed) = _requestBody(options);
    final contentType = options.contentType;
    try {
      hooks.record(
        HttpExchange(
          dio: dio,
          method: options.method.toUpperCase(),
          url: options.uri.toString(),
          requestedUrl: requested ?? options.uri.toString(),
          requestHeaders: {
            for (final MapEntry(:key, :value) in options.headers.entries)
              if (key.toLowerCase() != 'content-type')
                key: [
                  if (value is Iterable)
                    ...value.map((v) => '$v')
                  else
                    '$value',
                ],
            if (contentType != null) 'Content-Type': [contentType],
          },
          requestBody: body,
          requestBodyStreamed: streamed,
          status: response?.statusCode,
          responseHeaders: response?.headers.map ?? const {},
          responseBody: _responseBody(response),
          startedAt: started,
          duration: clock.elapsed,
          error: error,
          defaultHeaderNames: {...?defaults?.call().keys},
          extra: Map.of(options.extra),
        ),
      );
    } on Object {
      // Recording must never change what the request does.
    }
  }

  static (List<int>?, bool) _requestBody(RequestOptions options) {
    final data = options.data;
    return switch (data) {
      null => (null, false),
      final String text => (utf8.encode(text), false),
      final List<int> bytes => (bytes, false),
      FormData() || Stream<dynamic>() => (null, true),
      final Map<String, dynamic> map
          when options.contentType == Headers.formUrlEncodedContentType =>
        (utf8.encode(Transformer.urlEncodeMap(map)), false),
      final Object other => (_encodeJson(other), false),
    };
  }

  /// The response body as bytes. Dio has already decoded a JSON body, so it's
  /// encoded back as JSON, a decoded JSON string included.
  static List<int>? _responseBody(Response<dynamic>? response) {
    final data = response?.data;
    final type = response?.headers.value(Headers.contentTypeHeader) ?? '';
    final json = type.contains('json');
    return switch (data) {
      null => null,
      ResponseBody() || Stream<dynamic>() => null,
      final List<int> bytes => bytes,
      final String text when !json => utf8.encode(text),
      final Object other => _encodeJson(other),
    };
  }

  static List<int>? _encodeJson(Object data) {
    try {
      return utf8.encode(jsonEncode(data));
    } on Object {
      return null;
    }
  }
}

/// Applies [hooks]' faults and host override, and `SinewHttp.debugExpireToken`.
/// Installed **after** the auth interceptor, so a forced 401 runs the real
/// refresh and a token is attached by the client's own host.
final class SinewHooksInterceptor extends Interceptor {
  /// Creates the interceptor.
  SinewHooksInterceptor({required this.hooks, this.baseUrl});

  /// The hooks to ask.
  final SinewHttpHooks hooks;

  /// The backend's base URL, for the host override. Unset: the request's own
  /// `baseUrl`.
  final String? baseUrl;

  var _expireNext = false;

  /// Makes the next request that carries a token send an invalid one.
  void expireNextToken() => _expireNext = true;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_expireNext && options.headers.containsKey('Authorization')) {
      _expireNext = false;
      options.headers['Authorization'] = 'Bearer $expiredToken';
    }
    if (identical(hooks, SinewHttpHooks.none)) return handler.next(options);

    final override = hooks.hostOverride();
    if (override != null) _overrideHost(options, Uri.parse(override));

    final FaultDecision? fault;
    try {
      fault = await hooks.fault(options.method.toUpperCase(), options.uri);
    } on Object catch (e, stackTrace) {
      return handler.reject(
        DioException(requestOptions: options, error: e, stackTrace: stackTrace),
        true,
      );
    }
    if (fault == null) return handler.next(options);
    final delay = fault.delay;
    if (delay != null) await Future<void>.delayed(delay);
    if (fault.drop) {
      return handler.reject(
        DioException.connectionError(
          requestOptions: options,
          reason: 'Connection dropped by a devtools fault rule',
          error: const InjectedConnectionDrop(),
        ),
        true,
      );
    }
    final status = fault.status;
    if (status == null) return handler.next(options);
    final body = fault.body;
    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: _decode(body),
      headers: body == null || body.isEmpty
          ? Headers()
          : Headers.fromMap({
              Headers.contentTypeHeader: [Headers.jsonContentType],
            }),
    );
    if (status >= 200 && status < 300) {
      handler.resolve(response, true);
    } else {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: options,
          response: response,
        ),
        true,
      );
    }
  }

  static Object? _decode(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  /// Sends a request for the client's own backend to [override] instead,
  /// keeping the path below the base path.
  void _overrideHost(RequestOptions options, Uri override) {
    final base = Uri.parse(baseUrl ?? options.baseUrl);
    final uri = options.uri;
    if (uri.host != base.host || uri.port != base.port) return;
    final basePath = _trimSlash(base.path);
    if (uri.path != basePath && !uri.path.startsWith('$basePath/')) return;
    final moved = uri.replace(
      scheme: override.scheme,
      host: override.host,
      port: override.port,
      path: _trimSlash(override.path) + uri.path.substring(basePath.length),
    );
    options
      ..path = moved.toString()
      ..queryParameters = {};
  }

  static String _trimSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
