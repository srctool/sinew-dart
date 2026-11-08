import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_testing/sinew_testing.dart';

/// Hooks that answer with [faults] by path, override the host with [host],
/// and keep every exchange.
final class _TestHooks extends SinewHttpHooks {
  _TestHooks({this.host});

  String? host;
  final faults = <String, List<FaultDecision>>{};
  final exchanges = <HttpExchange>[];
  final clients = <Dio>[];

  @override
  void attached(Dio dio) => clients.add(dio);

  @override
  String? hostOverride() => host;

  @override
  Future<FaultDecision?> fault(String method, Uri uri) async {
    final queue = faults[uri.path];
    return queue == null || queue.isEmpty ? null : queue.removeAt(0);
  }

  @override
  void record(HttpExchange exchange) => exchanges.add(exchange);

  void failNext(String path, FaultDecision decision) =>
      (faults[path] ??= []).add(decision);
}

void main() {
  final config = SinewConfig(
    baseUrl: 'https://test.local/v1/',
    locale: () => 'en',
    defaultHeaders: () => {'X-Device-Id': 'device-7'},
  );

  test('the client is handed to the hooks once', () {
    final hooks = _TestHooks();
    final http = mockHttp((_) {}, config: config, hooks: hooks);
    expect(hooks.clients, [http.dio]);
  });

  test('an exchange is recorded with its raw values', () async {
    final hooks = _TestHooks();
    final http = mockHttp(
      (r) => r.on('POST', '/v1/orders').respond(201, body: '{"id":7}'),
      config: config,
      hooks: hooks,
    );
    final response = await http.dio.post<dynamic>(
      'orders',
      data: {'name': 'ana'},
      options: Options(extra: {'mark': true}),
    );
    expect(response.data, {'id': 7});
    final exchange = hooks.exchanges.single;
    expect(exchange.dio, same(http.dio));
    expect(exchange.method, 'POST');
    expect(exchange.url, 'https://test.local/v1/orders');
    expect(exchange.requestedUrl, exchange.url);
    // Inside the auth layer: the token is attached by the time it's recorded.
    expect(exchange.requestHeaders['Authorization'], ['Bearer token-1']);
    expect(exchange.requestHeaders['X-Device-Id'], ['device-7']);
    expect(exchange.requestHeaders['Content-Type']!.single, contains('json'));
    expect(utf8.decode(exchange.requestBody!), '{"name":"ana"}');
    expect(exchange.requestBodyStreamed, isFalse);
    expect(exchange.status, 201);
    expect(utf8.decode(exchange.responseBody!), '{"id":7}');
    expect(exchange.defaultHeaderNames, {'X-Device-Id'});
    expect(exchange.extra['mark'], isTrue);
    expect(exchange.error, isNull);
  });

  test('a form body is recorded as sent', () async {
    final hooks = _TestHooks();
    final http = mockHttp(
      (r) => r.on('POST', '/v1/token').respond(200, body: '{}'),
      config: config,
      hooks: hooks,
    );
    await http.dio.post<dynamic>(
      'token',
      data: {'grant_type': 'password', 'username': 'ana'},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    expect(
      utf8.decode(hooks.exchanges.single.requestBody!),
      'grant_type=password&username=ana',
    );
  });

  test('a multipart body is flagged as streamed', () async {
    final hooks = _TestHooks();
    final http = mockHttp(
      (r) => r.on('POST', '/v1/upload').respond(204),
      config: config,
      hooks: hooks,
    );
    await http.dio.post<dynamic>('upload', data: FormData.fromMap({'a': 'b'}));
    final exchange = hooks.exchanges.single;
    expect(exchange.requestBodyStreamed, isTrue);
    expect(exchange.requestBody, isNull);
  });

  test('a forced 401 runs the real refresh once', () async {
    final hooks = _TestHooks();
    final tokens = FakeTokenSource();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(200, body: '{"ok":true}'),
      config: config,
      tokenSource: tokens,
      hooks: hooks,
    );
    hooks.failNext('/v1/orders', FaultDecision(status: 401));
    final response = await http.dio.get<dynamic>('orders');
    expect(response.data, {'ok': true});
    expect(tokens.refreshes, 1);
    expect([for (final e in hooks.exchanges) e.status], [401, 200]);
    expect(
      [
        for (final e in hooks.exchanges)
          e.requestHeaders['Authorization']!.single,
      ],
      ['Bearer token-1', 'Bearer token-2'],
    );
    expect(http.requests, hasLength(1)); // the fault never reached the network
  });

  test('a forced status answers with its body without the network', () async {
    final hooks = _TestHooks();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(200, body: '"real"'),
      config: config,
      hooks: hooks,
    );
    hooks.failNext(
      '/v1/orders',
      FaultDecision(status: 200, body: '{"fake":true}'),
    );
    expect((await http.dio.get<dynamic>('orders')).data, {'fake': true});
    expect(http.requests, isEmpty);

    hooks.failNext(
      '/v1/orders',
      FaultDecision(status: 503, body: '{"message":"down"}'),
    );
    final result = await processApiCall<Object?>(
      'ORD',
      'list',
      () async => _Raw((await http.dio.get<dynamic>('orders')).data),
    );
    final error = (result as Failure<Object?>).error;
    expect(error, isA<ServiceUnavailableException>());
    expect([for (final e in hooks.exchanges) e.status], [200, 503]);
  });

  test('a dropped connection is no connection, and is recorded', () async {
    final hooks = _TestHooks();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(200),
      config: config,
      hooks: hooks,
    );
    hooks.failNext('/v1/orders', FaultDecision(drop: true));
    final result = await processApiCall<Object?>(
      'ORD',
      'list',
      () async => _Raw((await http.dio.get<dynamic>('orders')).data),
    );
    expect(
      (result as Failure<Object?>).error,
      isA<NoInternetConnectionException>(),
    );
    final exchange = hooks.exchanges.single;
    expect(exchange.status, isNull);
    expect(exchange.error, isA<InjectedConnectionDrop>());
    expect(http.requests, isEmpty);
  });

  test('a delay waits, then sends', () async {
    final hooks = _TestHooks();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(200, body: '"ok"'),
      config: config,
      hooks: hooks,
    );
    hooks.failNext(
      '/v1/orders',
      FaultDecision(delay: const Duration(milliseconds: 60)),
    );
    final watch = Stopwatch()..start();
    expect((await http.dio.get<dynamic>('orders')).data, 'ok');
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(60));
    expect(http.requests, hasLength(1));
  });

  test('the host override sends to another base, keeping the token', () async {
    final hooks = _TestHooks(host: 'https://staging.local/v2');
    final http = mockHttp(
      (r) => r.on('GET', '/v2/orders/7').respond(200, body: '"staging"'),
      config: config,
      hooks: hooks,
    );
    final response = await http.dio.get<dynamic>(
      'orders/7',
      queryParameters: {'full': '1'},
    );
    expect(response.data, 'staging');
    final sent = http.requests.single;
    expect(sent.uri.host, 'staging.local');
    expect(sent.headers['Authorization'], 'Bearer token-1');
    final exchange = hooks.exchanges.single;
    expect(exchange.url, 'https://staging.local/v2/orders/7?full=1');
    expect(exchange.requestedUrl, 'https://test.local/v1/orders/7?full=1');
  });

  test('the host override leaves other hosts alone', () async {
    final hooks = _TestHooks(host: 'https://staging.local/v2');
    final http = mockHttp(
      (r) => r.on('GET', '/cdn/a.png').respond(200),
      config: config,
      hooks: hooks,
    );
    await http.dio.get<dynamic>('https://cdn.local/cdn/a.png');
    expect(http.requests.single.uri.host, 'cdn.local');
  });

  test('the host override moves only the base host, under its path', () async {
    final hooks = _TestHooks(host: 'https://staging.local/v2');
    final http = mockHttp(
      (r) => r
        ..on('GET', '/v1/a.png').respond(200)
        ..on('GET', '/health').respond(200),
      config: config,
      hooks: hooks,
    );
    await http.dio.get<dynamic>(
      'https://cdn.local/v1/a.png',
    ); // another host, the same path
    await http.dio.get<dynamic>(
      'https://test.local/health',
    ); // the own host, outside the base path
    expect(
      [for (final r in http.requests) r.uri.host],
      ['cdn.local', 'test.local'],
    );
  });

  test('expiring the token sends an invalid one once, and refreshes', () async {
    final tokens = FakeTokenSource();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(401).respond(200, body: '"ok"'),
      config: config,
      tokenSource: tokens,
    );
    SinewHttp.debugExpireToken(http.dio);
    expect((await http.dio.get<dynamic>('orders')).data, 'ok');
    expect(tokens.refreshes, 1);
    expect(
      [for (final r in http.requests) r.headers['Authorization']],
      ['Bearer $expiredToken', 'Bearer token-2'],
    );
    await http.dio.get<dynamic>('orders');
    expect(http.requests.last.headers['Authorization'], 'Bearer token-2');
  });

  test('expiring waits for a request that carries a token', () async {
    final http = mockHttp(
      (r) => r
        ..on('POST', '/v1/auth/login').respond(200)
        ..on('GET', '/v1/orders').respond(200),
      config: SinewConfig(
        baseUrl: 'https://test.local/v1/',
        locale: () => 'en',
        anonymousPaths: {'/auth/login'},
      ),
    );
    SinewHttp.debugExpireToken(http.dio);
    await http.dio.post<dynamic>('auth/login'); // anonymous: nothing to expire
    expect(http.requests.single.headers['Authorization'], isNull);
    await http.dio.get<dynamic>('orders');
    expect(http.requests[1].headers['Authorization'], 'Bearer $expiredToken');
  });

  test('a fault cannot both drop and answer', () {
    expect(() => FaultDecision(status: 500, drop: true), throwsArgumentError);
    expect(() => FaultDecision(status: 99), throwsArgumentError);
  });
}

final class _Raw implements Envelope<Object?> {
  const _Raw(this.data);

  final Object? data;

  @override
  EnvelopeFailure? failure() => null;

  @override
  String? message() => null;

  @override
  Object? toDomain() => data;
}
