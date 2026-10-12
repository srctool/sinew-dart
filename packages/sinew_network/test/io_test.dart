@TestOn('vm')
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_network/src/http_status_error.dart';

/// Against real servers through Dio's default adapter: the deadline, and the
/// redirect rules Sinew relies on dart:io for.
void main() {
  late HttpServer own;
  late HttpServer other;

  setUp(() async {
    other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    other.listen((r) {
      r.response
        ..write(
          'other auth=${r.headers.value('authorization')} cookie=${r.headers.value('cookie')}',
        )
        ..close();
    });
    own = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    own.listen((r) async {
      switch (r.uri.path) {
        case '/trickle':
          r.response.bufferOutput = false;
          for (var i = 0; i < 20; i++) {
            r.response.write('.');
            await r.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await r.response.close();
        case '/same' || '/post':
          r.response
            ..statusCode = 302
            ..headers.set('location', '/target');
          await r.response.close();
        case '/cross':
          r.response
            ..statusCode = 302
            ..headers.set('location', 'http://127.0.0.1:${other.port}/x');
          await r.response.close();
        case '/loop':
          r.response
            ..statusCode = 302
            ..headers.set('location', '/loop');
          await r.response.close();
        default:
          r.response.write(
            'own ${r.method} auth=${r.headers.value('authorization')} cookie=${r.headers.value('cookie')}',
          );
          await r.response.close();
      }
    });
  });

  tearDown(() async {
    await own.close(force: true);
    await other.close(force: true);
  });

  Dio dio() => SinewHttp.dio(
    SinewConfig(
      baseUrl: 'http://127.0.0.1:${own.port}',
      locale: () => 'en',
      readTimeout: const Duration(milliseconds: 500),
    ),
  );

  Options auth() => Options(
    headers: {'Authorization': 'Bearer t', 'Cookie': 'session=s'},
    responseType: ResponseType.plain,
  );

  test('a response trickling in past the deadline is cancelled as DeadlineExceeded', () async {
    final error = await dio()
        .get<String>(
          'trickle',
          options: Options(responseType: ResponseType.plain),
        )
        .then<DioException?>(
          (_) => null,
          onError: (Object e) => e as DioException,
        );
    expect(error!.type, DioExceptionType.cancel);
    expect(error.error, isA<DeadlineExceeded>());
  });

  test('a same-host redirect keeps Authorization and cookies', () async {
    final response = await dio().get<String>('same', options: auth());
    expect(response.data, 'own GET auth=Bearer t cookie=session=s');
  });

  test('a cross-host redirect drops Authorization and cookies', () async {
    final response = await dio().get<String>('cross', options: auth());
    expect(response.data, 'other auth=null cookie=null');
  });

  test('a POST redirect is not followed', () async {
    final error = await dio()
        .post<String>('post', options: auth())
        .then<DioException?>(
          (_) => null,
          onError: (Object e) => e as DioException,
        );
    expect((error!.error! as HttpStatusError).status, 302);
  });

  test('a redirect loop stops', () async {
    final error = await dio()
        .get<String>('loop', options: auth())
        .then<DioException?>(
          (_) => null,
          onError: (Object e) => e as DioException,
        );
    expect(error, isNotNull);
  });
}
