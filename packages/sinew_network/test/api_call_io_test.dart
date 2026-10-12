@TestOn('vm')
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';

/// dart:io's own failure types, as Dio's IO adapter wraps them.
void main() {
  setUp(() => CrashReporter.install(CrashReporter.none));

  Future<SinewException> classify(Object cause, DioExceptionType type) async {
    final result = await processApiCall<Never>('ORD', 'GET', () async {
      throw DioException(
        requestOptions: RequestOptions(),
        type: type,
        error: cause,
      );
    });
    return (result as Failure<int?>).error;
  }

  test('a socket failure is NoInternetConnectionException', () async {
    for (final cause in [
      const SocketException('Failed host lookup'),
      const SocketException('Connection refused'),
      const HttpException('Connection closed before full header was received'),
    ]) {
      expect(
        await classify(cause, DioExceptionType.unknown),
        isA<NoInternetConnectionException>(),
        reason: '$cause',
      );
      expect(
        await classify(cause, DioExceptionType.connectionError),
        isA<NoInternetConnectionException>(),
        reason: '$cause',
      );
    }
  });

  test('a TLS failure is UnexpectedException, never offline, even as a connection error', () async {
    for (final cause in [
      const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      const TlsException('bad record mac'),
    ]) {
      expect(
        await classify(cause, DioExceptionType.unknown),
        isA<UnexpectedException>(),
        reason: '$cause',
      );
      expect(
        await classify(cause, DioExceptionType.connectionError),
        isA<UnexpectedException>(),
        reason: '$cause',
      );
    }
  });

  test(
    'a real server presenting an untrusted certificate is UnexpectedException',
    () async {
      // A throwaway self-signed certificate, trusted by nobody, made for this run.
      final dir = await Directory.systemTemp.createTemp('sinew_tls');
      addTearDown(() => dir.delete(recursive: true));
      final made = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-subj',
        '/CN=127.0.0.1',
        '-keyout',
        '${dir.path}/key.pem',
        '-out',
        '${dir.path}/cert.pem',
      ]);
      if (made.exitCode != 0) {
        return markTestSkipped('openssl is unavailable: ${made.stderr}');
      }
      final context = SecurityContext()
        ..useCertificateChain('${dir.path}/cert.pem')
        ..usePrivateKey('${dir.path}/key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      server.listen(
        (r) => r.response
          ..write('{}')
          ..close(),
      );
      addTearDown(() => server.close(force: true));

      final dio = Dio();
      // The call returns its status: had TLS let it through, the result would be a Success and the test would fail.
      final result = await processCall<int?>(
        'ORD',
        'GET',
        ExceptionLayer.repository,
        apiHandlers('ORD', 'GET'),
        () async =>
            (await dio.get<Object?>('https://127.0.0.1:${server.port}/a'))
                .statusCode,
      );
      final error = (result as Failure<int?>).error;
      expect(error, isA<UnexpectedException>(), reason: '${error.cause}');
    },
  );
}
