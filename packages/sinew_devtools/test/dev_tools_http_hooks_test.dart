import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools/src/dev_tools_http_hooks.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  final mask = Redaction.standard.mask;
  late NetworkRecorder recorder;
  late FaultRules faults;
  late HostOverride hosts;
  late DevToolsHttpHooks hooks;
  final config = SinewConfig(
    baseUrl: 'https://test.local/v1/',
    locale: () => 'en',
    defaultHeaders: () => {'X-Device-Id': 'device-7'},
  );
  List<NetworkRecord> records() => recorder.records.value;

  setUp(() {
    recorder = NetworkRecorder();
    faults = FaultRules();
    hosts = HostOverride();
    hooks = DevToolsHttpHooks(recorder, faults, hosts);
  });

  test('recorded exchanges are redacted', () async {
    final http = mockHttp(
      (r) => r
          .on('GET', '/v1/me')
          .respond(200, body: '{"name":"ana","refreshToken":"r-1"}'),
      config: config,
      hooks: hooks,
    );
    await http.dio.get<dynamic>('me', queryParameters: {'token': 'abc'});
    final record = records().single;
    expect(record.url, 'https://test.local/v1/me?token=$mask');
    expect(record.requestHeaders['Authorization'], [mask]);
    expect(record.requestHeaders['X-Device-Id'], [mask]);
    final body = (record.responseBody as TextBody).text;
    expect(body, isNot(contains('r-1')));
    expect(body, contains('ana'));
    expect(
      '${record.asText()}${record.asCurl()}$record',
      isNot(contains('token-1')),
    );
  });

  test('a forced 401 triggers exactly one refresh', () async {
    final tokens = FakeTokenSource();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(200),
      config: config,
      tokenSource: tokens,
      hooks: hooks,
    );
    faults.add(FaultRule(pathPattern: '/orders', status: 401));
    // The replay gets the fault too.
    await expectLater(
      http.dio.get<dynamic>('orders'),
      throwsA(isA<DioException>()),
    );
    expect(tokens.refreshes, 1);
    expect([for (final r in records()) r.status], [401, 401]);
    expect(http.requests, isEmpty);
  });

  test('a forced 503 on the refresh keeps the session', () async {
    final store = FakeRefreshTokenStore();
    var ended = false;
    final refreshHttp = mockHttp(
      (r) => r.on('POST', '/v1/auth/refresh').respond(200, body: '{}'),
      config: SinewConfig(
        baseUrl: 'https://test.local/v1/',
        locale: () => 'en',
        anonymousPaths: {'/auth/refresh'},
      ),
      tokenSource: FakeTokenSource(null),
      hooks: hooks,
    );
    final tokens = SessionTokenSource(store, (_) async {
      await refreshHttp.dio.post<dynamic>('auth/refresh');
      return const RefreshTokens(access: 'a-2', refresh: 'r-2');
    }, onSessionEnded: () async => ended = true);
    await tokens.start(accessToken: 'a-1', refreshToken: 'r-1');
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(401),
      config: config,
      tokenSource: tokens,
      hooks: hooks,
    );
    faults.add(
      FaultRule(method: 'POST', pathPattern: '/auth/refresh', status: 503),
    );

    await expectLater(
      http.dio.get<dynamic>('orders'),
      throwsA(isA<DioException>()),
    );
    expect(tokens.accessToken(), 'a-1'); // the session is kept
    expect(await store.read(), 'r-1');
    expect(ended, isFalse);
    // Newest first: the refresh, then the 401 that asked for it.
    expect([for (final r in records()) r.status], [503, 401]);
    expect(refreshHttp.requests, isEmpty);
  });

  test('fault rules live in memory only', () {
    faults.add(FaultRule(pathPattern: '/orders', status: 500));
    expect(faults.active.value, hasLength(1));
    expect(FaultRules().active.value, isEmpty); // what a restart starts with
  });

  test('the host override sends to the chosen host', () async {
    await hosts.configure(['https://staging.local/v2']);
    final http = mockHttp(
      (r) => r
        ..on('GET', '/v2/orders').respond(200, body: '"staging"')
        ..on('GET', '/v1/orders').respond(200, body: '"own"'),
      config: config,
      hooks: hooks,
    );
    await hosts.select('https://staging.local/v2');
    expect((await http.dio.get<dynamic>('orders')).data, 'staging');
    expect(records().first.url, 'https://staging.local/v2/orders');
    expect(http.requests.single.headers['Authorization'], 'Bearer token-1');
    await hosts.select(null);
    expect((await http.dio.get<dynamic>('orders')).data, 'own');
  });

  test('expiring the token runs the real refresh', () async {
    final tokens = FakeTokenSource();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(401).respond(200, body: '"ok"'),
      config: config,
      tokenSource: tokens,
      hooks: hooks,
    );
    hooks.expireAccessToken();
    expect((await http.dio.get<dynamic>('orders')).data, 'ok');
    expect(tokens.refreshes, 1);
    expect(
      [for (final r in http.requests) r.headers['Authorization']],
      ['Bearer $expiredToken', 'Bearer token-2'],
    );
  });

  group('replay', () {
    test('goes through the same client with a fresh token', () async {
      final tokens = FakeTokenSource();
      final http = mockHttp(
        (r) => r
            .on('GET', '/v1/orders')
            .respond(200, body: '"v1"')
            .respond(200, body: '"v2"'),
        config: config,
        tokenSource: tokens,
        hooks: hooks,
      );
      await http.dio.get<dynamic>('orders', queryParameters: {'page': '2'});
      final original = records().single;
      expect(original.replayable, isTrue);
      expect(hooks.canReplay(original), isTrue);
      tokens.rotate(); // the token changed since: the replay gets the new one

      await hooks.replay(original);

      final replay = records().first;
      expect(replay.isReplay, isTrue);
      expect(original.isReplay, isFalse);
      expect(replay.url, original.url);
      expect((replay.responseBody as TextBody).text, '"v2"');
      final sent = http.requests.last;
      expect(sent.headers['Authorization'], 'Bearer token-2');
      // The client's own value, not the record's mask.
      expect(sent.headers['X-Device-Id'], 'device-7');
      expect(sent.uri.queryParameters['page'], '2');
    });

    test('sends the body again', () async {
      final http = mockHttp(
        (r) => r.on('POST', '/v1/notes').respond(201),
        config: config,
        hooks: hooks,
      );
      await http.dio.post<dynamic>('notes', data: {'text': 'hi'});
      await hooks.replay(records().single);
      final sent = http.requests.last;
      expect(sent.data, '{"text":"hi"}');
      expect(sent.headers['content-type'], contains('application/json'));
    });

    test('faults and the host override apply to it', () async {
      await hosts.configure(['https://staging.local/v2']);
      final http = mockHttp(
        (r) => r
          ..on('GET', '/v1/orders').respond(200)
          ..on('GET', '/v2/orders').respond(200, body: '"staging"'),
        config: config,
        hooks: hooks,
      );
      await http.dio.get<dynamic>('orders');
      final original = records().single;
      await hosts.select('https://staging.local/v2');
      await hooks.replay(original);
      expect(records().first.url, 'https://staging.local/v2/orders');
      faults.add(FaultRule(pathPattern: '/orders', status: 503));
      await hooks.replay(original); // a failed replay isn't thrown
      expect(records().first.status, 503);
      expect(records().first.isReplay, isTrue);
    });

    test('a record that lost a secret cannot be replayed', () async {
      final http = mockHttp(
        (r) => r.on('POST', '/v1/auth/otp').respond(200),
        config: config,
        hooks: hooks,
      );
      await http.dio.post<dynamic>('auth/otp', data: {'otp': '123456'});
      final record = records().single;
      expect(record.replayable, isFalse);
      expect(hooks.canReplay(record), isFalse);
      expect(() => hooks.replay(record), throwsArgumentError);
    });

    test('a cleared record cannot be replayed', () async {
      final http = mockHttp(
        (r) => r.on('GET', '/v1/orders').respond(200),
        config: config,
        hooks: hooks,
      );
      await http.dio.get<dynamic>('orders');
      final record = records().single;
      recorder.clear(); // "Clear", or a sign-out
      expect(hooks.canReplay(record), isFalse);
      expect(() => hooks.replay(record), throwsStateError);
    });
  });

  test('a streamed body is recorded as binary of unknown size', () async {
    final http = mockHttp(
      (r) => r.on('POST', '/v1/upload').respond(204),
      config: config,
      hooks: hooks,
    );
    await http.dio.post<dynamic>('upload', data: FormData.fromMap({'a': 'b'}));
    final record = records().single;
    expect(record.requestBody, isA<BinaryBody>());
    expect((record.requestBody as BinaryBody).size, -1);
    expect(record.replayable, isFalse);
    expect(record.asText(), contains('unknown size'));
  });

  test('the global hooks record into the global recorder', () async {
    DevTools.network.clear();
    final http = mockHttp(
      (r) => r.on('GET', '/v1/orders').respond(200),
      hooks: DevTools.httpHooks,
    );
    await http.dio.get<dynamic>('orders');
    final record = DevTools.network.records.value.single;
    expect(DevTools.canReplay(record), isTrue);
    await DevTools.replay(record);
    expect(DevTools.network.records.value.first.isReplay, isTrue);
    DevTools.clearUserData();
  });
}
