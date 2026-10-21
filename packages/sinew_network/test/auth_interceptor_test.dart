import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_network/src/http_status_error.dart';
import 'package:sinew_testing/sinew_testing.dart';

import 'support/fake_adapter.dart';
import 'support/memory_store.dart';

/// A backend that accepts only [serverToken], through the preset. `/v1/auth/login`
/// is anonymous; `hold/…` paths wait for [hold] before answering.
final class AuthBackend {
  AuthBackend({TokenSource? tokens, this.serverToken = 'token-1'})
    : tokens = tokens ?? FakeTokenSource() {
    adapter = FakeAdapter(_answer);
    dio = SinewHttp.dio(
      SinewConfig(
        baseUrl: 'https://api.example.com/v1',
        locale: () => 'en',
        anonymousPaths: const {'/auth/login'},
      ),
      this.tokens,
    )..httpClientAdapter = adapter;
  }

  final TokenSource tokens;
  String? serverToken;
  late final FakeAdapter adapter;
  late final Dio dio;
  final hold = Completer<void>();
  String? failReplaysOf;

  Future<ResponseBody> _answer(RequestOptions options) async {
    final uri = options.uri;
    if (uri.path.contains('/hold/')) await hold.future;
    final auth = options.headers['Authorization'] as String?;
    final authorized = auth == 'Bearer $serverToken';
    if (uri.host != 'api.example.com' || uri.port != 443) {
      return json('{}', status: 401);
    }
    if (uri.path == '/v1/auth/login') return json('{}', status: 401);
    if (authorized && uri.path == failReplaysOf) return json('{}', status: 500);
    if (authorized && uri.path == '/v1/json') return json('{"replayed":true}');
    if (authorized) return text(auth!);
    return json('{}', status: 401);
  }

  /// The `Authorization` each request to [path] carried, in order.
  List<Object?> sentTokens(String path) => [
    for (final r in adapter.sent)
      if (r.uri.path == path) r.headers['Authorization'],
  ];

  Future<String?> get(
    String path, {
    CancelToken? cancelToken,
    Object? data,
    Map<String, Object?>? headers,
  }) async => (await dio.request<String>(
    path,
    data: data,
    cancelToken: cancelToken,
    options: Options(
      method: data == null ? 'GET' : 'POST',
      responseType: ResponseType.plain,
      headers: headers,
    ),
  )).data;
}

/// The error a call ended with, or `null`.
Future<DioException?> failure(Future<Object?> call) => call.then<DioException?>(
  (_) => null,
  onError: (Object e) => e as DioException,
);

int? status(DioException? e) => (e?.error as HttpStatusError?)?.status;

const offline = NoInternetConnectionException(
  'AUTH',
  ExceptionLayer.repository,
  'REFRESH',
);

void main() {
  test('a replay keeps the caller\'s response type', () async {
    // The replayed response is JSON, read as text: Dio's fetch<T> would decode
    // it as JSON for any T but dynamic, and the caller's String cast would fail.
    final backend = AuthBackend(serverToken: 'token-2');
    expect(await backend.get('json'), '{"replayed":true}');
    expect(backend.sentTokens('/v1/json'), [
      'Bearer token-1',
      'Bearer token-2',
    ]);
  });

  test('a valid token is attached', () async {
    expect(await AuthBackend().get('orders'), 'Bearer token-1');
  });

  test(
    'ten parallel 401s cause one refresh, and all ten replay once',
    () async {
      final gate = Completer<void>();
      final tokens = FakeTokenSource()
        ..onRefresh = (s) async {
          await gate.future;
          s.rotate();
          return const Refreshed();
        };
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
      final calls = [for (var i = 0; i < 10; i++) backend.get('orders/$i')];
      await pumpEventQueue();
      expect(backend.adapter.sent, hasLength(10)); // all ten got 401 and wait
      expect(tokens.refreshes, 1);

      gate.complete();
      expect(await Future.wait(calls), List.filled(10, 'Bearer token-2'));
      expect(tokens.refreshes, 1);
      for (var i = 0; i < 10; i++) {
        expect(backend.sentTokens('/v1/orders/$i'), [
          'Bearer token-1',
          'Bearer token-2',
        ]);
      }
    },
  );

  test(
    'Rejected ends the session once and fails every waiter with 401',
    () async {
      final gate = Completer<void>();
      final tokens = FakeTokenSource()
        ..onRefresh = (_) async {
          await gate.future;
          return const Rejected();
        };
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
      final calls = [
        for (var i = 0; i < 10; i++) failure(backend.get('orders/$i')),
      ];
      await pumpEventQueue();
      gate.complete();
      for (final e in await Future.wait(calls)) {
        expect(status(e), 401);
      }
      expect(tokens.refreshes, 1);
      expect(tokens.clears, 1);
      expect(tokens.accessToken(), isNull);
      expect(backend.adapter.sent, hasLength(10)); // nothing replayed
    },
  );

  test(
    'Unavailable fails every waiter with its cause and keeps the session',
    () async {
      final gate = Completer<void>();
      final tokens = FakeTokenSource()
        ..onRefresh = (_) async {
          await gate.future;
          return const Unavailable(offline);
        };
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
      final calls = [
        for (var i = 0; i < 10; i++) failure(backend.get('orders/$i')),
      ];
      await pumpEventQueue();
      gate.complete();
      for (final e in await Future.wait(calls)) {
        expect(identical(e!.error, offline), isTrue);
      }
      expect(tokens.clears, 0);
      expect(tokens.accessToken(), 'token-1');
    },
  );

  test('a replayed 401 fails without a second refresh, and the client still works (no deadlock)', () async {
    final tokens = FakeTokenSource();
    final backend = AuthBackend(tokens: tokens, serverToken: 'never');
    expect(status(await failure(backend.get('orders'))), 401);
    expect(tokens.refreshes, 1);
    expect(backend.sentTokens('/v1/orders'), [
      'Bearer token-1',
      'Bearer token-2',
    ]);

    backend.serverToken = 'token-2';
    expect(
      await backend.get('orders').timeout(const Duration(seconds: 5)),
      'Bearer token-2',
    );
  });

  test(
    'a replay returning 500 fails its caller, and the next request works',
    () async {
      final tokens = FakeTokenSource();
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2')
        ..failReplaysOf = '/v1/flaky';
      expect(status(await failure(backend.get('flaky'))), 500);
      expect(await backend.get('orders'), 'Bearer token-2');
      expect(tokens.refreshes, 1);
    },
  );

  test(
    'a 401 for a request sent with an older token replays without refreshing',
    () async {
      final tokens = FakeTokenSource();
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
      final slow = backend.get(
        'hold/slow',
      ); // sent with token-1, answered later
      await pumpEventQueue();
      expect(
        await backend.get('orders'),
        'Bearer token-2',
      ); // 401, refresh, replay
      backend.hold.complete();
      expect(await slow, 'Bearer token-2'); // its 401 replays at once
      expect(tokens.refreshes, 1);
    },
  );

  test(
    'the first request cancelled mid-refresh leaves the others the outcome',
    () async {
      final gate = Completer<void>();
      final tokens = FakeTokenSource()
        ..onRefresh = (s) async {
          await gate.future;
          s.rotate();
          return const Refreshed();
        };
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
      final mine = CancelToken();
      final first = failure(backend.get('orders/0', cancelToken: mine));
      await pumpEventQueue(); // it started the refresh
      final others = [for (var i = 1; i < 10; i++) backend.get('orders/$i')];
      await pumpEventQueue();
      mine.cancel('page closed');
      gate.complete();
      expect(await Future.wait(others), List.filled(9, 'Bearer token-2'));
      expect((await first)!.type, DioExceptionType.cancel);
      expect(tokens.refreshes, 1);
    },
  );

  test('a refresh that throws fails every waiter with the bug', () async {
    final bug = StateError('a bug in the token source');
    final tokens = FakeTokenSource()..onRefresh = (_) async => throw bug;
    final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
    final calls = [
      for (var i = 0; i < 3; i++) failure(backend.get('orders/$i')),
    ];
    for (final e in await Future.wait(calls)) {
      expect(identical(e!.error, bug), isTrue);
    }
    expect(tokens.accessToken(), 'token-1');
  });

  test('a request without a token yet refreshes and replays', () async {
    final tokens = FakeTokenSource(null); // a cold start: only a refresh token
    final backend = AuthBackend(tokens: tokens, serverToken: 'token-1');
    expect(await backend.get('orders'), 'Bearer token-1');
    expect(backend.sentTokens('/v1/orders'), [null, 'Bearer token-1']);
  });

  test('a 401 arriving after sign-out does not refresh', () async {
    final tokens = FakeTokenSource();
    final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
    final slow = failure(backend.get('hold/slow')); // sent with token-1
    await pumpEventQueue();
    await tokens.clear(); // the user signs out
    backend.hold.complete();
    expect(status(await slow), 401);
    expect(tokens.refreshes, 0);
  });

  test(
    'anonymous paths under the base path never get a token or a refresh',
    () async {
      final tokens = FakeTokenSource();
      final backend = AuthBackend(tokens: tokens);
      expect(status(await failure(backend.get('auth/login'))), 401);
      expect(backend.sentTokens('/v1/auth/login'), [null]);
      expect(tokens.refreshes, 0);
    },
  );

  test('a path that only starts like an anonymous one gets a token', () async {
    final backend = AuthBackend();
    await backend.get('auth/login/history');
    expect(backend.sentTokens('/v1/auth/login/history'), ['Bearer token-1']);
  });

  test('another host or port never gets a token or a refresh', () async {
    final tokens = FakeTokenSource();
    final backend = AuthBackend(tokens: tokens);
    await failure(backend.get('https://cdn.example.net/v1/a.png'));
    await failure(backend.get('https://api.example.com:8443/v1/orders'));
    expect(
      backend.adapter.sent.every((r) => r.headers['Authorization'] == null),
      isTrue,
    );
    expect(tokens.refreshes, 0);
  });

  test("a request's own Authorization is left alone", () async {
    final tokens = FakeTokenSource();
    final backend = AuthBackend(tokens: tokens);
    await failure(
      backend.get('orders', headers: {'Authorization': 'Basic dXNlcg=='}),
    );
    expect(backend.sentTokens('/v1/orders'), ['Basic dXNlcg==']);
    expect(tokens.refreshes, 0);
  });

  test('a one-shot body refreshes but is not replayed', () async {
    final tokens = FakeTokenSource();
    final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
    Stream<List<int>> file() => Stream.value('file'.codeUnits);
    expect(status(await failure(backend.get('uploads', data: file()))), 401);
    expect(tokens.refreshes, 1);
    expect(backend.adapter.sent, hasLength(1));
    expect(await backend.get('uploads', data: file()), 'Bearer token-2');
  });

  test(
    'resetAuth answers the waiters at once, and a later 401 refreshes afresh',
    () async {
      final gate = Completer<void>();
      final tokens = FakeTokenSource()
        ..onRefresh = (s) async {
          await gate.future;
          return const Unavailable(offline);
        };
      final backend = AuthBackend(tokens: tokens, serverToken: 'token-2');
      final waiting = failure(backend.get('orders'));
      await pumpEventQueue();
      SinewHttp.resetAuth(backend.dio);
      expect(status(await waiting), 401); // without waiting for the refresh
      tokens.onRefresh = (s) async {
        s.rotate();
        return const Refreshed();
      };
      expect(await backend.get('orders'), 'Bearer token-2');
      expect(tokens.refreshes, 2);
      gate.complete();
    },
  );

  test('sign-out mid-refresh stores nothing and fails the waiters', () async {
    final store = MemoryStore();
    final answer = Completer<RefreshResult>();
    var ended = 0;
    final tokens = SessionTokenSource(
      store,
      (_) => answer.future,
      onSessionEnded: () async => ended++,
    );
    await tokens.start(accessToken: 'a-1', refreshToken: 'r-1');
    final backend = AuthBackend(tokens: tokens, serverToken: 'a-2');
    final calls = [
      for (var i = 0; i < 3; i++) failure(backend.get('orders/$i')),
    ];
    await pumpEventQueue(); // the refresh waits on the backend

    SinewHttp.resetAuth(backend.dio);
    await tokens.clear();
    for (final e in await Future.wait(calls)) {
      expect(status(e), 401);
    }
    answer.complete(
      const RefreshTokens(access: 'a-2', refresh: 'r-2'),
    ); // too late
    await pumpEventQueue();
    expect(tokens.accessToken(), isNull);
    expect(store.token, isNull);
    expect(ended, greaterThan(0));
  });

  test('sign-out mid-refresh without resetAuth still stores nothing', () async {
    final store = MemoryStore();
    final answer = Completer<RefreshResult>();
    final tokens = SessionTokenSource(store, (_) => answer.future);
    await tokens.start(accessToken: 'a-1', refreshToken: 'r-1');
    final backend = AuthBackend(tokens: tokens, serverToken: 'a-2');
    final calls = [
      for (var i = 0; i < 3; i++) failure(backend.get('orders/$i')),
    ];
    await pumpEventQueue();
    await tokens.clear();
    answer.complete(
      const RefreshTokens(access: 'a-2', refresh: 'r-2'),
    ); // the epoch moved: Rejected
    for (final e in await Future.wait(calls)) {
      expect(status(e), 401);
    }
    expect(tokens.accessToken(), isNull);
    expect(store.token, isNull);
  });

  test(
    'a rejection arriving after another user signed in leaves their session',
    () async {
      final store = MemoryStore();
      final answer = Completer<RefreshResult>();
      final tokens = SessionTokenSource(store, (_) => answer.future);
      await tokens.start(accessToken: 'a-1', refreshToken: 'r-1');
      final backend = AuthBackend(tokens: tokens, serverToken: 'b-1');
      final call = failure(backend.get('orders'));
      await pumpEventQueue();
      await tokens.start(
        accessToken: 'b-1',
        refreshToken: 's-1',
      ); // a new user signs in mid-refresh
      answer.complete(const RefreshRejected());
      await call;
      expect(tokens.accessToken(), 'b-1');
      expect(store.token, 's-1');
    },
  );

  test('an anonymous path must start with a slash', () {
    expect(
      () => SinewAuthInterceptor(
        Dio(),
        tokenSource: FakeTokenSource(),
        anonymousPaths: {'auth/login'},
      ),
      throwsArgumentError,
    );
  });

  test(
    'an explicit baseUrl decides the token when the request has none',
    () async {
      final adapter = FakeAdapter((o) async => text('ok'));
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(
        SinewAuthInterceptor(
          dio,
          tokenSource: FakeTokenSource(),
          baseUrl: 'https://auth.example.com',
        ),
      );
      await dio.get<String>('https://auth.example.com/me');
      await dio.get<String>('https://api.example.com/me');
      expect(adapter.sent.map((r) => r.headers['Authorization']), [
        'Bearer token-1',
        null,
      ]);
    },
  );
}
