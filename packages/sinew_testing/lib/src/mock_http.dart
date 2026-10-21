import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinew_network/sinew_network.dart';

import 'dropped_connection_io.dart'
    if (dart.library.js_interop) 'dropped_connection_web.dart';
import 'fake_token_source.dart';

/// A Sinew `Dio` ([SinewHttp.dio], with the deadline, header, auth and
/// error-body interceptors) whose adapter answers by method and path and
/// records every request. Call it inside a test.
///
/// ```dart
/// test('orders load', () async {
///   final http = mockHttp((routes) => routes
///       .on('GET', '/v1/orders').respond(200, body: fixture('orders_page.json')));
///   final result = await OrderRepository(OrderApi(http.dio)).page(1);
///   expect(http.requests.single.uri.path, '/v1/orders');
/// });
/// ```
///
/// A route answers with its responses in order, repeating the last one. A
/// request no route matches fails with a `DioException` whose error names it.
/// Delays are
/// real time: keep them short, with a short deadline in [config] to test a
/// timeout.
MockHttp mockHttp(
  void Function(MockRoutes routes) routes, {
  SinewConfig? config,
  TokenSource? tokenSource,
}) {
  final table = MockRoutes._();
  routes(table);
  final adapter = _MockAdapter(table);
  final dio = SinewHttp.dio(
    config ??
        SinewConfig(baseUrl: 'https://test.local/v1/', locale: () => 'en'),
    tokenSource ?? FakeTokenSource(),
  )..httpClientAdapter = adapter;
  return MockHttp._(dio, adapter._requests);
}

/// A [mockHttp] `Dio` and what it was asked.
final class MockHttp {
  MockHttp._(this.dio, this._requests);

  /// The Sinew `Dio`: give it to the API class under test.
  final Dio dio;

  final List<MockRequest> _requests;

  /// Every request the adapter received, replays included, in order.
  List<MockRequest> get requests => List.unmodifiable(_requests);

  /// The requests for [method] and [path].
  List<MockRequest> requestsTo(String method, String path) => [
    for (final request in _requests)
      if (request.method == method.toUpperCase() && request.uri.path == path)
        request,
  ];
}

/// One request as it was sent: a replay reuses Dio's `RequestOptions`, so
/// this keeps what each attempt carried.
final class MockRequest {
  MockRequest._(this.method, this.uri, this.headers, this.data);

  /// The HTTP method, upper case.
  final String method;

  /// The full URL.
  final Uri uri;

  /// The headers sent, `Authorization` included.
  final Map<String, Object?> headers;

  /// The request body, as the caller passed it.
  final Object? data;

  @override
  String toString() => '$method ${uri.path}';
}

/// The routes of a [mockHttp] `Dio`:
/// `routes.on('GET', '/v1/orders').respond(200, body: '{}')`.
final class MockRoutes {
  MockRoutes._();

  final _routes = <String, MockRoute>{};

  /// The route for [method] and the request's whole [path] (`/v1/orders`,
  /// without the query).
  MockRoute on(String method, String path) =>
      _routes.putIfAbsent('${method.toUpperCase()} $path', MockRoute._);

  _Answer? _answer(String method, String path) =>
      _routes['$method $path']?._next();
}

/// One route's answers, given in order; the last one repeats.
final class MockRoute {
  MockRoute._();

  final _answers = <_Answer>[];
  var _given = 0;

  /// Answers with [status], [body] (JSON) and [headers], after [delay].
  MockRoute respond(
    int status, {
    String body = '',
    Map<String, String> headers = const {},
    Duration delay = Duration.zero,
  }) {
    _answers.add(_Respond(status, body, headers, delay));
    return this;
  }

  /// Drops the connection, with the error the platform's adapter throws then.
  MockRoute drop() {
    _answers.add(const _Drop());
    return this;
  }

  _Answer? _next() => _answers.isEmpty
      ? null
      : _answers[_given < _answers.length ? _given++ : _answers.length - 1];
}

sealed class _Answer {
  const _Answer();
}

final class _Respond extends _Answer {
  const _Respond(this.status, this.body, this.headers, this.delay);
  final int status;
  final String body;
  final Map<String, String> headers;
  final Duration delay;
}

final class _Drop extends _Answer {
  const _Drop();
}

final class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._routes);

  final MockRoutes _routes;
  final _requests = <MockRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = MockRequest._(
      options.method.toUpperCase(),
      options.uri,
      Map.of(options.headers),
      options.data,
    );
    _requests.add(request);
    switch (_routes._answer(request.method, request.uri.path)) {
      case null:
        throw StateError('No mock route for $request');
      case _Drop():
        throw droppedConnection(options);
      case _Respond(:final status, :final body, :final headers, :final delay):
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        return ResponseBody.fromString(
          body,
          status,
          headers: {
            if (body.isNotEmpty)
              Headers.contentTypeHeader: [Headers.jsonContentType],
            for (final MapEntry(:key, :value) in headers.entries) key: [value],
          },
        );
    }
  }

  @override
  void close({bool force = false}) {}
}
