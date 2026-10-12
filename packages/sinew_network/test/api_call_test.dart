import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_testing/sinew_testing.dart';

import 'support/fake_adapter.dart';
import 'support/orders.dart';

final class _Recording implements CrashReporter {
  final reported = <SinewException>[];

  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) =>
      reported.add(error);
}

/// A stand-in for json_annotation's checked-mode error, matched by name.
final class CheckedFromJsonException implements Exception {}

const order = Order('7', OrderStatus.open);

void main() {
  late _Recording reporter;
  setUp(() => CrashReporter.install(reporter = _Recording()));
  tearDown(() => CrashReporter.install(CrashReporter.none));

  Dio backend(Future<ResponseBody> Function(RequestOptions o) answer) =>
      SinewHttp.dio(
        SinewConfig(baseUrl: 'https://api.example.com/v1', locale: () => 'en'),
        FakeTokenSource(null),
      )..httpClientAdapter = FakeAdapter(answer);

  Future<Result<Order>> call(Dio dio, {bool strict = false}) => processApiCall(
    'ORD',
    'GET',
    () async => OrderResponse.fromJson(
      (await dio.get<Map<String, dynamic>>('orders/7')).data!,
      strict: strict,
    ),
  );

  Future<Result<Order>> answer(
    int status, [
    String body = '{}',
    Map<String, List<String>> headers = const {},
  ]) =>
      call(backend((_) async => json(body, status: status, headers: headers)));

  Future<E> failsWith<E extends SinewException>(
    int status, [
    String body = '{}',
  ]) async {
    final result = await answer(status, body);
    final error = (result as Failure<Order>).error;
    expect(error, isA<E>(), reason: 'status $status');
    expect(error.layer, ExceptionLayer.repository);
    return error as E;
  }

  String? key(SinewException e) => (e.message as LocalMessage?)?.key;

  group('success and the envelope hooks', () {
    test("a success carries the backend's message", () async {
      expect(
        await answer(
          200,
          '{"data":{"id":"7","status":"open"},"message":"Here you go."}',
        ),
        const Success(order, message: 'Here you go.'),
      );
    });

    test('a success without a message has an empty one', () async {
      expect(
        await answer(200, '{"data":{"id":"7","status":"open"}}'),
        const Success(order),
      );
    });

    test(
      'an envelope failure with field errors is a ValidationException',
      () async {
        final e = await failsWith<ValidationException>(
          200,
          '{"success":false,"message":"Check the form.","errors":{"reason":["Required."]}}',
        );
        expect(e.fieldErrors, {
          'reason': ['Required.'],
        });
        expect(e.message, const ServerMessage('Check the form.'));
        expect(e.code, 'ORD-R-GET-VAL');
      },
    );

    test(
      'an envelope failure without field errors is an ApiErrorException',
      () async {
        final e = await failsWith<ApiErrorException>(
          200,
          '{"success":false,"message":"Already shipped."}',
        );
        expect(e.message, const ServerMessage('Already shipped.'));
      },
    );

    test(
      'an envelope failure with an empty errors object is an ApiErrorException',
      () async {
        await failsWith<ApiErrorException>(
          200,
          '{"success":false,"message":"No.","errors":{}}',
        );
      },
    );

    test(
      'an envelope failure with a blank message uses the local one',
      () async {
        expect(
          key(
            await failsWith<ApiErrorException>(
              200,
              '{"success":false,"message":" "}',
            ),
          ),
          'sinew.error.generic',
        );
        expect(
          key(
            await failsWith<ValidationException>(
              200,
              '{"success":false,"errors":{"a":["b"]}}',
            ),
          ),
          'sinew.error.validation',
        );
      },
    );

    test('an envelope failure is checked before toDomain', () async {
      await failsWith<ApiErrorException>(
        200,
        '{"success":false,"message":"No."}',
      ); // no data
      expect(reporter.reported, isEmpty);
    });
  });

  group('the handler table, one test per row', () {
    test("a SinewException the auth interceptor wrapped passes through, unreported", () async {
      const offline = NoInternetConnectionException(
        'AUTH',
        ExceptionLayer.repository,
        'REFRESH',
      );
      final tokens = FakeTokenSource()
        ..onRefresh = (_) async => const Unavailable(offline);
      final dio = SinewHttp.dio(
        SinewConfig(baseUrl: 'https://api.example.com/v1', locale: () => 'en'),
        tokens,
      )..httpClientAdapter = FakeAdapter((_) async => json('{}', status: 401));
      final error = ((await call(dio)) as Failure<Order>).error;
      expect(identical(error, offline), isTrue);
      expect(reporter.reported, isEmpty);
    });

    test('a wrapped unexpected cause is not reported a second time', () async {
      const bug = UnexpectedException(
        'AUTH',
        ExceptionLayer.repository,
        'REFRESH',
      ); // already reported by its own guard
      final tokens = FakeTokenSource()
        ..onRefresh = (_) async => const Unavailable(bug);
      final dio = SinewHttp.dio(
        SinewConfig(baseUrl: 'https://api.example.com/v1', locale: () => 'en'),
        tokens,
      )..httpClientAdapter = FakeAdapter((_) async => json('{}', status: 401));
      final error = ((await call(dio)) as Failure<Order>).error;
      expect(identical(error, bug), isTrue);
      expect(reporter.reported, isEmpty);
    });

    test('apiHandlers alone unwraps a wrapped SinewException', () async {
      const offline = NoInternetConnectionException(
        'AUTH',
        ExceptionLayer.repository,
        'REFRESH',
      );
      final result = await processCall<Never>(
        'ORD',
        'GET',
        ExceptionLayer.repository,
        apiHandlers('ORD', 'GET'),
        () async => throw DioException(
          requestOptions: RequestOptions(),
          error: offline,
        ),
      );
      expect(identical((result as Failure<Never>).error, offline), isTrue);
    });

    test('a deadline is a RequestTimeOutException', () async {
      final dio = SinewHttp.dio(
        SinewConfig(
          baseUrl: 'https://api.example.com/v1',
          locale: () => 'en',
          readTimeout: const Duration(milliseconds: 20),
        ),
        FakeTokenSource(null),
      )..httpClientAdapter = FakeAdapter(never);
      final error = ((await call(dio)) as Failure<Order>).error;
      expect(error, isA<RequestTimeOutException>());
      expect(error.code, 'ORD-R-GET-RTO');
    });

    test("Dio's own timeouts are RequestTimeOutExceptions", () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final dio = backend(
          (o) async => throw DioException(requestOptions: o, type: type),
        );
        expect(
          ((await call(dio)) as Failure<Order>).error,
          isA<RequestTimeOutException>(),
          reason: '$type',
        );
      }
    });

    test('a cancel is a CancelException, never reported', () async {
      final token = CancelToken();
      final dio = backend(never);
      final pending = processApiCall(
        'ORD',
        'GET',
        () async => OrderResponse.fromJson(
          (await dio.get<Map<String, dynamic>>('a', cancelToken: token)).data!,
        ),
      );
      await pumpEventQueue();
      token.cancel('page closed');
      final error = ((await pending) as Failure<Order>).error;
      expect(error, isA<CancelException>());
      expect(error.code, 'ORD-R-GET-CNL');
      expect(reporter.reported, isEmpty);
    });

    test('a connection error is NoInternetConnectionException', () async {
      final dio = backend(
        (o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'down',
        ),
      );
      expect(
        ((await call(dio)) as Failure<Order>).error,
        isA<NoInternetConnectionException>(),
      );
    });

    test(
      'a bad certificate is a reported UnexpectedException, never offline',
      () async {
        final dio = backend(
          (o) async => throw DioException.badCertificate(requestOptions: o),
        );
        expect(
          ((await call(dio)) as Failure<Order>).error,
          isA<UnexpectedException>(),
        );
        expect(reporter.reported.single, isA<UnexpectedException>());
      },
    );

    test('400 or 422 with field errors is a ValidationException', () async {
      for (final status in [400, 422]) {
        final e = await failsWith<ValidationException>(
          status,
          '{"message":"Check the form.","errors":{"email":["Taken."]}}',
        );
        expect(e.fieldErrors, {
          'email': ['Taken.'],
        });
        expect(e.message, const ServerMessage('Check the form.'));
      }
      expect(
        key(
          await failsWith<ValidationException>(
            422,
            '{"errors":{"email":["Taken."]}}',
          ),
        ),
        'sinew.error.validation',
      );
    });

    test('400 without field errors falls to the catch-all rows', () async {
      expect(
        (await failsWith<ApiErrorException>(
          400,
          '{"message":"Bad input."}',
        )).message,
        const ServerMessage('Bad input.'),
      );
      expect(
        (await failsWith<UndefinedErrorResponseException>(400)).status,
        400,
      );
    });

    test('401, 403, 404 and 409', () async {
      expect(
        (await failsWith<UnauthorizedException>(401)).code,
        'ORD-R-GET-UNA',
      );
      expect(
        (await failsWith<UnauthorizedException>(
          401,
          '{"message":"Wrong password."}',
        )).message,
        const ServerMessage('Wrong password.'),
      );
      await failsWith<ForbiddenException>(403);
      await failsWith<NotFoundException>(404);
      expect(
        (await failsWith<ConflictException>(
          409,
          '{"message":"Taken."}',
        )).message,
        const ServerMessage('Taken.'),
      );
    });

    test('429 carries Retry-After in seconds or as a date', () async {
      final seconds = await answer(429, '{}', {
        'retry-after': ['30'],
      });
      expect(
        ((seconds as Failure<Order>).error as RateLimitedException).retryAfter,
        const Duration(seconds: 30),
      );
      final date = await answer(429, '{}', {
        'retry-after': ['Wed, 21 Oct 2015 07:28:00 GMT'],
      });
      expect(
        ((date as Failure<Order>).error as RateLimitedException).retryAfter,
        Duration.zero,
      ); // a past date
      expect((await failsWith<RateLimitedException>(429)).retryAfter, isNull);
    });

    test('every 5xx except 503 and 504 is a ServerException', () async {
      for (final status in [500, 501, 502, 505, 507, 599]) {
        expect((await failsWith<ServerException>(status)).status, status);
      }
      for (final status in [503, 504]) {
        expect(
          (await failsWith<ServiceUnavailableException>(status)).status,
          status,
        );
      }
    });

    test('an HTML 502 page has the local server message', () async {
      final result = await call(
        backend((_) async => text('<html><h1>502</h1></html>', status: 502)),
      );
      expect(key((result as Failure<Order>).error), 'sinew.error.server');
    });

    test('any other status: readable or not', () async {
      expect(
        (await failsWith<ApiErrorException>(
          418,
          '{"message":"I am a teapot."}',
        )).message,
        const ServerMessage('I am a teapot.'),
      );
      expect(
        (await failsWith<UndefinedErrorResponseException>(418)).status,
        418,
      );
    });

    test('a 408 status is not a timeout', () async {
      await failsWith<ApiErrorException>(408, '{"message":"Took too long."}');
      expect(
        (await failsWith<UndefinedErrorResponseException>(408)).status,
        408,
      );
    });

    test('JSON that does not fit is a reported ParseException', () async {
      expect(
        ((await answer(
          200,
          '{"data":{"id":{"nested":true}}}',
        )) as Failure<Order>).error,
        isA<ParseException>(),
      );
      final strict = await call(
        backend((_) async => json('{"data":{"id":"7","status":"refunded"}}')),
        strict: true,
      );
      expect(
        (strict as Failure<Order>).error,
        isA<ParseException>(),
      ); // an enum with no fallback
      final checked = await processApiCall<Order>(
        'ORD',
        'GET',
        () async => throw CheckedFromJsonException(),
      );
      expect((checked as Failure<Order>).error, isA<ParseException>());
      expect(reporter.reported.whereType<ParseException>(), hasLength(3));
    });

    test('a malformed JSON body is a reported ParseException', () async {
      final result = await call(backend((_) async => json('{"data":')));
      expect((result as Failure<Order>).error, isA<ParseException>());
    });

    test('a missing payload is a reported ParseException', () async {
      final error =
          ((await answer(200, '{"data":null}')) as Failure<Order>).error;
      expect(error, isA<ParseException>());
      expect(error.code, 'ORD-R-GET-DF');
      expect(identical(reporter.reported.single, error), isTrue);
    });

    test('an unknown enum value with a fallback is unknown', () async {
      expect(
        await answer(200, '{"data":{"id":"7","status":"refunded"}}'),
        const Success(Order('7', OrderStatus.unknown)),
      );
    });

    test('a bug is a reported UnexpectedException, an unrelated ArgumentError included', () async {
      final bug = await processApiCall<Order>(
        'ORD',
        'GET',
        () async => throw StateError('a bug'),
      );
      expect((bug as Failure<Order>).error, isA<UnexpectedException>());
      final argument = await processApiCall<Order>(
        'ORD',
        'GET',
        () async => throw ArgumentError.value(-1, 'page'),
      );
      expect((argument as Failure<Order>).error, isA<UnexpectedException>());
      expect(reporter.reported, hasLength(2));
    });
  });

  group('the optional variant', () {
    Future<Result<Order?>> find(Dio dio) => processOptionalApiCall(
      'ORD',
      'FIND',
      () async => OrderResponse.fromJson(
        (await dio.get<Map<String, dynamic>>('orders/7')).data!,
      ),
    );

    test('a 404 is null', () async {
      expect(
        await find(
          backend((_) async => json('{"message":"Gone."}', status: 404)),
        ),
        const Success<Order?>(null),
      );
    });

    test('a found item and other failures are unchanged', () async {
      expect(
        await find(
          backend(
            (_) async =>
                json('{"data":{"id":"7","status":"open"},"message":"Ok."}'),
          ),
        ),
        const Success<Order?>(order, message: 'Ok.'),
      );
      expect(
        ((await find(
          backend((_) async => json('{}', status: 500)),
        )) as Failure<Order?>).error,
        isA<ServerException>(),
      );
    });
  });

  test("a plain Dio's failed status is classified by status", () async {
    final plain = Dio()
      ..httpClientAdapter = FakeAdapter(
        (_) async => json(
          '{"message":"Gone."}',
          status: 404,
          headers: {
            'retry-after': ['5'],
          },
        ),
      );
    final result = await processApiCall(
      'ORD',
      'GET',
      () async => OrderResponse.fromJson(
        (await plain.get<Map<String, dynamic>>('https://x.example/a')).data!,
      ),
    );
    final error = (result as Failure<Order>).error;
    expect(error, isA<NotFoundException>());
    expect(
      key(error),
      'sinew.error.notFound',
    ); // the body isn't read without the interceptor

    final limited = Dio()
      ..httpClientAdapter = FakeAdapter(
        (_) async => json(
          '{}',
          status: 429,
          headers: {
            'retry-after': ['5'],
          },
        ),
      );
    final slowDown = await processApiCall(
      'ORD',
      'GET',
      () async => OrderResponse.fromJson(
        (await limited.get<Map<String, dynamic>>('https://x.example/a')).data!,
      ),
    );
    expect(
      ((slowDown as Failure<Order>).error as RateLimitedException).retryAfter,
      const Duration(seconds: 5),
    );
  });

  group('RefreshResult.from', () {
    const l = ExceptionLayer.repository;
    RefreshResult failure(SinewException e) => RefreshResult.from(Failure(e));

    test('tokens pass through', () {
      const tokens = RefreshTokens(access: 'a', refresh: 'r');
      expect(
        identical(RefreshResult.from(const Success(tokens)), tokens),
        isTrue,
      );
    });

    test('a refusal is RefreshRejected', () {
      for (final e in <SinewException>[
        const UnauthorizedException('AUTH', l, 'REFRESH'),
        const ForbiddenException('AUTH', l, 'REFRESH'),
        const ValidationException('AUTH', l, 'REFRESH'),
        const ApiErrorException(
          'AUTH',
          l,
          'REFRESH',
          message: ServerMessage('invalid_grant'),
        ),
        const NotFoundException('AUTH', l, 'REFRESH'),
        const ConflictException('AUTH', l, 'REFRESH'),
        const UndefinedErrorResponseException(
          'AUTH',
          l,
          'REFRESH',
          status: 400,
        ),
        const UndefinedErrorResponseException(
          'AUTH',
          l,
          'REFRESH',
          status: 410,
        ),
      ]) {
        expect(failure(e), isA<RefreshRejected>(), reason: e.code);
      }
    });

    test('anything else keeps the session', () {
      for (final e in <SinewException>[
        const NoInternetConnectionException('AUTH', l, 'REFRESH'),
        const RequestTimeOutException('AUTH', l, 'REFRESH'),
        const CancelException('AUTH', l, 'REFRESH'),
        const ServerException('AUTH', l, 'REFRESH', status: 500),
        const ServiceUnavailableException('AUTH', l, 'REFRESH', status: 503),
        const RateLimitedException('AUTH', l, 'REFRESH'),
        const UndefinedErrorResponseException(
          'AUTH',
          l,
          'REFRESH',
          status: 408,
        ),
        const ParseException('AUTH', l, 'REFRESH'),
        const UnexpectedException('AUTH', l, 'REFRESH'),
      ]) {
        final result = failure(e);
        expect(result, isA<RefreshUnavailable>(), reason: e.code);
        expect(identical((result as RefreshUnavailable).cause, e), isTrue);
      }
    });
  });
}
