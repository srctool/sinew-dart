import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_network/src/http_status_error.dart';

import 'support/fake_adapter.dart';

Dio plain(FakeAdapter adapter, List<Interceptor> interceptors) =>
    Dio(BaseOptions(baseUrl: 'https://api.example.com/v1/'))
      ..httpClientAdapter = adapter
      ..interceptors.addAll(interceptors);

void main() {
  group('SinewHeadersInterceptor', () {
    test('sends Accept and Accept-Language', () async {
      final adapter = FakeAdapter();
      await plain(adapter, [
        SinewHeadersInterceptor(locale: () => 'en'),
      ]).get<Object?>('a');
      final headers = adapter.requests.single.headers;
      expect(headers['Accept'], 'application/json');
      expect(headers['Accept-Language'], 'en');
    });

    test(
      'Accept-Language follows a locale change between two requests',
      () async {
        var language = 'en';
        final adapter = FakeAdapter();
        final dio = plain(adapter, [
          SinewHeadersInterceptor(locale: () => language),
        ]);
        await dio.get<Object?>('a');
        language = 'id';
        await dio.get<Object?>('a');
        expect(adapter.requests.map((r) => r.headers['Accept-Language']), [
          'en',
          'id',
        ]);
      },
    );

    test('a blank locale sends no Accept-Language', () async {
      final adapter = FakeAdapter();
      await plain(adapter, [
        SinewHeadersInterceptor(locale: () => ' '),
      ]).get<Object?>('a');
      expect(
        adapter.requests.single.headers.containsKey('Accept-Language'),
        isFalse,
      );
    });

    test('default headers are read per request', () async {
      var build = 1;
      final adapter = FakeAdapter();
      final dio = plain(adapter, [
        SinewHeadersInterceptor(
          locale: () => 'en',
          defaults: () => {'X-Build': '$build'},
        ),
      ]);
      await dio.get<Object?>('a');
      build = 2;
      await dio.get<Object?>('a');
      expect(adapter.requests.map((r) => r.headers['X-Build']), ['1', '2']);
    });

    test("a header the request set wins, whatever its case", () async {
      final adapter = FakeAdapter();
      await plain(adapter, [
        SinewHeadersInterceptor(
          locale: () => 'en',
          defaults: () => {'X-Build': '1'},
        ),
      ]).get<Object?>(
        'a',
        options: Options(
          headers: {
            'accept-language': 'fr',
            'accept': 'text/csv',
            'x-build': '9',
          },
        ),
      );
      final headers = adapter.requests.single.headers;
      expect(
        headers.keys.where((k) => k.toLowerCase() == 'accept-language'),
        hasLength(1),
      );
      expect(headers['accept-language'], 'fr');
      expect(headers['accept'], 'text/csv');
      expect(headers['x-build'], '9');
    });
  });

  group('SinewTimeoutInterceptor', () {
    /// Starts [call] and returns a getter for the error it ends with, if any.
    DioException? Function() start(Future<Object?> call) {
      DioException? error;
      call.then<void>((_) {}, onError: (Object e) => error = e as DioException);
      return () => error;
    }

    test('a read past its deadline is cancelled with DeadlineExceeded', () {
      fakeAsync((async) {
        final dio = plain(FakeAdapter(never), [
          SinewTimeoutInterceptor(read: const Duration(seconds: 10)),
        ]);
        final error = start(dio.get<Object?>('a'));
        async.elapse(const Duration(milliseconds: 9999));
        expect(error(), isNull);
        async.elapse(const Duration(milliseconds: 2));
        expect(error()!.type, DioExceptionType.cancel);
        expect(error()!.error, isA<DeadlineExceeded>());
        expect(
          (error()!.error! as DeadlineExceeded).deadline,
          const Duration(seconds: 10),
        );
      });
    });

    test('writes use the write deadline, HEAD the read one', () {
      fakeAsync((async) {
        final dio = plain(FakeAdapter(never), [
          SinewTimeoutInterceptor(
            read: const Duration(seconds: 10),
            write: const Duration(seconds: 20),
          ),
        ]);
        for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
          final error = start(
            dio.request<Object?>('a', options: Options(method: method)),
          );
          async.elapse(const Duration(seconds: 15));
          expect(error(), isNull, reason: method);
          async.elapse(const Duration(seconds: 6));
          expect(error()?.error, isA<DeadlineExceeded>(), reason: method);
        }
        final head = start(dio.head<Object?>('a'));
        async.elapse(const Duration(seconds: 11));
        expect(head()?.error, isA<DeadlineExceeded>());
      });
    });

    test("a request's own deadline wins", () {
      fakeAsync((async) {
        final dio = plain(FakeAdapter(never), [
          SinewTimeoutInterceptor(read: const Duration(seconds: 10)),
        ]);
        final error = start(
          dio.get<Object?>(
            'a',
            options: Options(
              extra: {sinewDeadline: const Duration(minutes: 2)},
            ),
          ),
        );
        async.elapse(const Duration(seconds: 30));
        expect(error(), isNull);
        async.elapse(const Duration(minutes: 2));
        expect(error()?.error, isA<DeadlineExceeded>());
      });
    });

    test("the deadline never cancels the caller's shared token", () {
      fakeAsync((async) {
        final shared = CancelToken();
        final dio = plain(FakeAdapter(never), [
          SinewTimeoutInterceptor(read: const Duration(seconds: 10)),
        ]);
        final error = start(dio.get<Object?>('a', cancelToken: shared));
        async.elapse(const Duration(seconds: 11));
        expect(error()?.error, isA<DeadlineExceeded>());
        expect(shared.isCancelled, isFalse);
      });
    });

    test("cancelling the caller's token still cancels the request, with its reason", () {
      fakeAsync((async) {
        final mine = CancelToken();
        final dio = plain(FakeAdapter(never), [SinewTimeoutInterceptor()]);
        final error = start(dio.get<Object?>('a', cancelToken: mine));
        async.elapse(Duration.zero);
        mine.cancel('page closed');
        async.elapse(Duration.zero);
        expect(error()!.type, DioExceptionType.cancel);
        expect(error()!.error, 'page closed');
      });
    });

    // On the real clock: under Chrome, Dio decodes with browser APIs that a
    // fake clock doesn't drive. The interceptor keeps its timer in `extra`
    // under 'sinew.deadline.timer', and removes it when it stops it.
    test('the timer stops when the response arrives', () async {
      final dio = plain(FakeAdapter(), [SinewTimeoutInterceptor()]);
      final response = await dio.get<Object?>('a');
      expect(
        response.requestOptions.extra.containsKey('sinew.deadline.timer'),
        isFalse,
      );
    });

    test('the timer stops when the request fails', () async {
      final dio = plain(FakeAdapter((_) async => json('{}', status: 500)), [
        SinewTimeoutInterceptor(),
      ]);
      final error = await dio
          .get<Object?>('a')
          .then<DioException?>(
            (_) => null,
            onError: (Object e) => e as DioException,
          );
      expect(
        error!.requestOptions.extra.containsKey('sinew.deadline.timer'),
        isFalse,
      );
    });

    test('sets the connect timeout unless the request has one', () async {
      final adapter = FakeAdapter();
      Dio dio([Duration? base]) => Dio(BaseOptions(connectTimeout: base))
        ..httpClientAdapter = adapter
        ..interceptors.add(
          SinewTimeoutInterceptor(connect: const Duration(seconds: 7)),
        );
      await dio().get<Object?>('https://x.example/a');
      await dio(const Duration(seconds: 3)).get<Object?>('https://x.example/a');
      await dio().get<Object?>(
        'https://x.example/a',
        options: Options(sendTimeout: const Duration(seconds: 1)),
      );
      expect(adapter.requests.map((r) => r.connectTimeout), [
        const Duration(seconds: 7),
        const Duration(seconds: 3), // the client's own wins
        const Duration(seconds: 7),
      ]);
    });

    test('durations must be positive', () {
      expect(
        () => SinewTimeoutInterceptor(read: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => SinewTimeoutInterceptor(write: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => SinewTimeoutInterceptor(connect: Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('SinewErrorBodyInterceptor', () {
    test(
      'attaches the read body and Retry-After to a failed response',
      () async {
        final dio = plain(
          FakeAdapter(
            (_) async => json(
              '{"message":"Slow down.","errors":{"q":["Too many."]}}',
              status: 429,
              headers: {
                'retry-after': ['30'],
              },
            ),
          ),
          [SinewErrorBodyInterceptor()],
        );
        final error = await dio
            .get<Object?>('a')
            .then<DioException?>(
              (_) => null,
              onError: (Object e) => e as DioException,
            );
        final status = error!.error! as HttpStatusError;
        expect(status.status, 429);
        expect(
          status.errorBody,
          const ErrorBody(
            message: 'Slow down.',
            fieldErrors: {
              'q': ['Too many.'],
            },
          ),
        );
        expect(status.retryAfter, const Duration(seconds: 30));
      },
    );

    test('an HTML page has no error body', () async {
      final dio = plain(
        FakeAdapter((_) async => text('<html>502</html>', status: 502)),
        [SinewErrorBodyInterceptor()],
      );
      final error = await dio
          .get<Object?>('a')
          .then<DioException?>(
            (_) => null,
            onError: (Object e) => e as DioException,
          );
      final status = error!.error! as HttpStatusError;
      expect(status.status, 502);
      expect(status.errorBody, isNull);
    });

    test("the client's own reader is used", () async {
      final dio = plain(FakeAdapter((_) async => text('nope', status: 409)), [
        SinewErrorBodyInterceptor(
          reader: ErrorBodyReader.from((s, b) => ErrorBody(message: '$s/$b')),
        ),
      ]);
      final error = await dio
          .get<Object?>('a')
          .then<DioException?>(
            (_) => null,
            onError: (Object e) => e as DioException,
          );
      expect(
        (error!.error! as HttpStatusError).errorBody,
        const ErrorBody(message: '409/nope'),
      );
    });

    test('a success and other failures are left alone', () async {
      final ok = plain(FakeAdapter(), [SinewErrorBodyInterceptor()]);
      expect((await ok.get<Object?>('a')).statusCode, 200);
      final offline = plain(
        FakeAdapter(
          (o) async => throw DioException.connectionError(
            requestOptions: o,
            reason: 'down',
          ),
        ),
        [SinewErrorBodyInterceptor()],
      );
      final error = await offline
          .get<Object?>('a')
          .then<DioException?>(
            (_) => null,
            onError: (Object e) => e as DioException,
          );
      expect(error!.error, isNot(isA<HttpStatusError>()));
    });

    test('an interceptor after it still sees the status', () async {
      int? seen;
      final dio = plain(FakeAdapter((_) async => json('{}', status: 401)), [
        SinewErrorBodyInterceptor(),
        InterceptorsWrapper(
          onError: (e, h) {
            seen = e.response?.statusCode;
            h.next(e);
          },
        ),
      ]);
      await dio
          .get<Object?>('a')
          .then<Object?>((_) => null, onError: (Object _) => null);
      expect(seen, 401);
    });
  });

  group('SinewLogInterceptor', () {
    const secrets = [
      's3cr3t-access',
      'r3fresh-token',
      'hunter2',
      'q-token',
      'session=abc',
    ];

    test('one redacted line per exchange', () async {
      final lines = <String>[];
      final dio = plain(
        FakeAdapter(
          (o) async => o.path.contains('missing')
              ? json('{"message":"s3cr3t-access"}', status: 404)
              : json('{"access":"s3cr3t-access","refresh":"r3fresh-token"}'),
        ),
        [SinewLogInterceptor(logger: lines.add)],
      );
      await dio.post<Object?>(
        'auth/login',
        queryParameters: {'token': 'q-token'},
        data: {'user': 'jane', 'password': 'hunter2'},
        options: Options(
          headers: {
            'Authorization': 'Bearer s3cr3t-access',
            'Cookie': 'session=abc',
          },
        ),
      );
      await dio
          .get<Object?>('missing')
          .then<Object?>((_) => null, onError: (Object _) => null);
      expect(lines, hasLength(2));
      expect(
        lines[0],
        matches(
          RegExp(r'^POST api\.example\.com/v1/auth/login → 200 \(\d+ ms\)$'),
        ),
      );
      expect(
        lines[1],
        matches(RegExp(r'^GET api\.example\.com/v1/missing → 404 \(\d+ ms\)$')),
      );
      for (final line in lines) {
        for (final secret in secrets) {
          expect(
            line.contains(secret),
            isFalse,
            reason: '"$line" contains $secret',
          );
        }
        expect(line.contains('Bearer'), isFalse);
      }
    });

    test('a failure is logged by type only', () async {
      final lines = <String>[];
      final dio = plain(
        FakeAdapter(
          (o) async => throw DioException.connectionError(
            requestOptions: o,
            reason: 'connect to 10.0.0.1 with s3cr3t-access',
          ),
        ),
        [SinewLogInterceptor(logger: lines.add)],
      );
      await dio
          .get<Object?>('a')
          .then<Object?>((_) => null, onError: (Object _) => null);
      expect(
        lines.single,
        matches(
          RegExp(
            r'^GET api\.example\.com/v1/a → failed: connectionError \(\d+ ms\)$',
          ),
        ),
      );
    });
  });

  group('SinewHttp.dio', () {
    SinewConfig config({
      bool logHttp = false,
      String baseUrl = 'https://api.example.com/v1',
    }) => SinewConfig(
      baseUrl: baseUrl,
      locale: () => 'en',
      defaultHeaders: () => {'X-Build': '1'},
      logHttp: logHttp,
    );

    test(
      'relative paths resolve under the base path, with or without its slash',
      () async {
        for (final base in [
          'https://api.example.com/v1',
          'https://api.example.com/v1/',
        ]) {
          final adapter = FakeAdapter();
          await (SinewHttp.dio(
            config(baseUrl: base),
          )..httpClientAdapter = adapter).get<Object?>('orders/7');
          expect(
            adapter.requests.single.uri.toString(),
            'https://api.example.com/v1/orders/7',
            reason: base,
          );
        }
      },
    );

    test('installs the headers, timeout and error-body interceptors', () async {
      final adapter = FakeAdapter(
        (_) async => json('{"message":"No."}', status: 400),
      );
      final dio = SinewHttp.dio(config())..httpClientAdapter = adapter;
      final error = await dio
          .get<Object?>('a')
          .then<DioException?>(
            (_) => null,
            onError: (Object e) => e as DioException,
          );
      final sent = adapter.requests.single;
      expect(sent.headers['Accept-Language'], 'en');
      expect(sent.headers['X-Build'], '1');
      expect(sent.connectTimeout, const Duration(seconds: 15));
      expect(
        (error!.error! as HttpStatusError).errorBody,
        const ErrorBody(message: 'No.'),
      );
    });

    test('logs only when logHttp is on', () async {
      final quiet = <String>[];
      final loud = <String>[];
      await (SinewHttp.dio(
        config(),
        logger: quiet.add,
      )..httpClientAdapter = FakeAdapter()).get<Object?>('a');
      await (SinewHttp.dio(
        config(logHttp: true),
        logger: loud.add,
      )..httpClientAdapter = FakeAdapter()).get<Object?>('a');
      expect(quiet, isEmpty);
      expect(loud, hasLength(1));
    });

    test('extra interceptors run after Sinew\'s', () async {
      String? sawLanguage;
      final dio = SinewHttp.dio(
        config(),
        extraInterceptors: [
          InterceptorsWrapper(
            onRequest: (o, h) {
              sawLanguage = o.headers['Accept-Language'] as String?;
              h.next(o);
            },
          ),
        ],
      )..httpClientAdapter = FakeAdapter();
      await dio.get<Object?>('a');
      expect(sawLanguage, 'en');
    });
  });
}
