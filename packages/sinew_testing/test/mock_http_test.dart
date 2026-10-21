import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_testing/sinew_testing.dart';

/// The network scenarios, through mockHttp and the network guard's real
/// handlers.
void main() {
  Future<Result<String>> guardedGet(MockHttp http, String path) => processCall(
    'ORD',
    'GET',
    ExceptionLayer.repository,
    apiHandlers('ORD', 'GET'),
    () async => (await http.dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    )).data!,
  );

  test(
    'a route answers with its fixture, and the request is recorded',
    () async {
      final http = mockHttp(
        (routes) => routes
            .on('GET', '/v1/orders')
            .respond(200, body: fixture('orders_page.json')),
      );
      expect(
        await guardedGet(http, 'orders'),
        Result.success(fixture('orders_page.json')),
      );
      final request = http.requests.single;
      expect(request.toString(), 'GET /v1/orders');
      expect(request.headers['Authorization'], 'Bearer token-1');
      expect(request.headers['Accept-Language'], 'en');
    },
  );

  test('a 401 is refreshed once and replayed with the new token', () async {
    final tokens = FakeTokenSource();
    final http = mockHttp(
      (routes) => routes
          .on('GET', '/v1/orders')
          .respond(401)
          .respond(200, body: '{"data":[]}'),
      tokenSource: tokens,
    );
    expect(
      await guardedGet(http, 'orders'),
      const Result.success('{"data":[]}'),
    );
    expect(tokens.refreshes, 1);
    expect(
      [
        for (final r in http.requestsTo('GET', '/v1/orders'))
          r.headers['Authorization'],
      ],
      ['Bearer token-1', 'Bearer token-2'],
    );
  });

  test('a dropped connection is no connection', () async {
    final http = mockHttp((routes) => routes.on('GET', '/v1/orders').drop());
    final result = await guardedGet(http, 'orders');
    expect((result as Failure).error, isA<NoInternetConnectionException>());
  });

  test('a delayed response arrives within the deadline', () async {
    final http = mockHttp(
      (routes) => routes
          .on('GET', '/v1/orders')
          .respond(200, body: '{}', delay: const Duration(milliseconds: 50)),
    );
    expect(await guardedGet(http, 'orders'), const Result.success('{}'));
  });

  test('a response later than the read deadline times out', () async {
    final http = mockHttp(
      (routes) => routes
          .on('GET', '/v1/orders')
          .respond(200, body: '{}', delay: const Duration(seconds: 2)),
      config: SinewConfig(
        baseUrl: 'https://test.local/v1/',
        locale: () => 'en',
        readTimeout: const Duration(milliseconds: 100),
      ),
    );
    final result = await guardedGet(http, 'orders');
    expect((result as Failure).error, isA<RequestTimeOutException>());
  });

  test('a route repeats its last answer, with its headers', () async {
    final http = mockHttp(
      (routes) => routes
          .on('POST', '/v1/orders')
          .respond(201, body: '{}', headers: {'Location': '/v1/orders/9'}),
    );
    for (var i = 0; i < 2; i++) {
      final response = await http.dio.post<Object?>('orders', data: {'a': i});
      expect(response.statusCode, 201);
      expect(response.headers.value('Location'), '/v1/orders/9');
      expect(response.headers.value('content-type'), Headers.jsonContentType);
    }
    expect(
      [for (final r in http.requests) r.data],
      [
        {'a': 0},
        {'a': 1},
      ],
    );
  });

  test('after its answers run out, a route repeats the last one', () async {
    final http = mockHttp(
      (routes) => routes
          .on('get', '/v1/orders')
          .respond(500, body: '{}')
          .respond(200, body: '{"ok":1}'),
    );
    final statuses = <int>[];
    for (var i = 0; i < 3; i++) {
      final response = await http.dio.get<Object?>(
        'orders',
        options: Options(validateStatus: (_) => true),
      );
      statuses.add(response.statusCode!);
    }
    expect(statuses, [500, 200, 200]);
  });

  test('requests are filtered by method and path', () async {
    final http = mockHttp((routes) {
      routes.on('GET', '/v1/orders').respond(200, body: '[]');
      routes.on('POST', '/v1/orders').respond(201, body: '{}');
    });
    await http.dio.get<Object?>('orders');
    await http.dio.post<Object?>('orders', data: '{}');
    await http.dio.post<Object?>('orders', data: '{}');
    expect(http.requestsTo('GET', '/v1/orders'), hasLength(1));
    expect(http.requestsTo('post', '/v1/orders'), hasLength(2));
    expect(http.requests, hasLength(3));
  });

  test('a request no route matches fails, naming it', () async {
    final http = mockHttp(
      (routes) => routes.on('GET', '/v1/orders').respond(200),
    );
    await expectLater(
      http.dio.get<Object?>('customers'),
      throwsA(
        isA<DioException>().having(
          (e) => '${e.error}',
          'error',
          contains('GET /v1/customers'),
        ),
      ),
    );
  });

  group('helpers', () {
    test('a fixture reads the file, and a missing one names its path', () {
      expect(fixture('orders_page.json'), startsWith('{"data":[{"id":"o-1"'));
      expect(
        () => fixture('missing.json'),
        throwsA(
          isA<MissingFixture>().having(
            (e) => e.message,
            'message',
            contains('test/fixtures/missing.json'),
          ),
        ),
      );
    });

    test('installRecordingReporter records for the test', () async {
      final reporter = installRecordingReporter();
      await processCall<void>(
        'ORD',
        'GET',
        ExceptionLayer.repository,
        const [],
        () async => throw StateError('bug'),
      );
      expect(reporter.codes, ['ORD-R-GET-GEN']);
    });

    test('the previous test\'s reporter was put back', () {
      expect(identical(CrashReporter.current, CrashReporter.none), isTrue);
    });

    test('controlledFetch passes when every call is answered', () async {
      final fetch = controlledFetch<String>();
      final answer = fetch.call(1, '');
      fetch.succeed(0, ['a']);
      expect((await answer) is Success, isTrue);
    });
  });
}
