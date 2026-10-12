@TestOn('vm')
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_testing/sinew_testing.dart';

/// Two certificate authorities, made with openssl for this run: the pinned
/// one and another. A server signed by each, on 127.0.0.1.
void main() {
  late Directory dir;
  late String pinned;
  late String other;
  var openssl = true;

  Future<void> run(List<String> args) async {
    final result = await Process.run(
      'openssl',
      args,
      workingDirectory: dir.path,
    );
    if (result.exitCode != 0) {
      throw StateError('openssl ${args.first}: ${result.stderr}');
    }
  }

  /// A CA called [name], and a 127.0.0.1 server certificate it signs. The
  /// extensions are what Apple's trust evaluation (used by dart:io on macOS
  /// and iOS) requires: a CA marked as one, and a server certificate for
  /// serverAuth with its IP in subjectAltName.
  Future<void> authority(String name) async {
    File('${dir.path}/ca.ext').writeAsStringSync(
      'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n',
    );
    File('${dir.path}/server.ext').writeAsStringSync(
      'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
      'extendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n',
    );
    await run([
      'req',
      '-new',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-subj',
      '/CN=$name CA',
      '-keyout',
      '$name-ca.key',
      '-out',
      '$name-ca.csr',
    ]);
    await run([
      'x509',
      '-req',
      '-sha256',
      '-days',
      '2',
      '-in',
      '$name-ca.csr',
      '-signkey',
      '$name-ca.key',
      '-extfile',
      'ca.ext',
      '-out',
      '$name-ca.pem',
    ]);
    await run([
      'req',
      '-new',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-subj',
      '/CN=127.0.0.1',
      '-keyout',
      '$name-server.key',
      '-out',
      '$name-server.csr',
    ]);
    await run([
      'x509',
      '-req',
      '-sha256',
      '-days',
      '1',
      '-in',
      '$name-server.csr',
      '-CA',
      '$name-ca.pem',
      '-CAkey',
      '$name-ca.key',
      '-CAcreateserial',
      '-extfile',
      'server.ext',
      '-out',
      '$name-server.pem',
    ]);
  }

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sinew_pinning');
    try {
      await authority('pinned');
      await authority('other');
    } on ProcessException {
      openssl = false;
      return;
    }
    pinned = File('${dir.path}/pinned-ca.pem').readAsStringSync();
    other = File('${dir.path}/other-ca.pem').readAsStringSync();
  });

  tearDownAll(() => dir.delete(recursive: true));

  /// A server presenting [name]'s certificate; [requests] counts what reached it.
  Future<(HttpServer, List<String>)> serve(String name) async {
    final context = SecurityContext()
      ..useCertificateChain('${dir.path}/$name-server.pem')
      ..usePrivateKey('${dir.path}/$name-server.key');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final requests = <String>[];
    server.listen((r) {
      requests.add(
        '${r.method} ${r.uri.path} ${r.headers.value('authorization')}',
      );
      r.response
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}')
        ..close();
    }, onError: (Object _) {}); // the failed handshake surfaces here too
    addTearDown(() => server.close(force: true));
    return (server, requests);
  }

  Dio client(HttpServer server) => SinewHttp.dio(
    SinewConfig(
      baseUrl: 'https://127.0.0.1:${server.port}',
      locale: () => 'en',
    ),
    FakeTokenSource(),
  );

  test('a server signed by the pinned authority is reached', () async {
    if (!openssl) return markTestSkipped('openssl is unavailable');
    final (server, requests) = await serve('pinned');
    final dio = client(server);
    pinCertificateAuthorities(dio, [pinned]);
    final response = await dio.get<Map<String, dynamic>>('a');
    expect(response.data, {'ok': true});
    expect(requests, ['GET /a Bearer token-1']);
  });

  test(
    'an unpinned chain fails the handshake, and the server sees no request',
    () async {
      if (!openssl) return markTestSkipped('openssl is unavailable');
      final (server, requests) = await serve('other');
      final dio = client(server);
      pinCertificateAuthorities(dio, [pinned]);
      // The call returns its status: had TLS let it through, the result would be a Success and the test would fail.
      final result = await processCall<int?>(
        'ORD',
        'GET',
        ExceptionLayer.repository,
        apiHandlers('ORD', 'GET'),
        () async => (await dio.get<Object?>('a')).statusCode,
      );
      expect((result as Failure<int?>).error, isA<UnexpectedException>());
      expect(requests, isEmpty); // no header, no token, no body left the device
    },
  );

  test('a backup authority is trusted too', () async {
    if (!openssl) return markTestSkipped('openssl is unavailable');
    final (server, requests) = await serve('other');
    final dio = client(server);
    pinCertificateAuthorities(dio, [pinned, other]);
    await dio.get<Object?>('a');
    expect(requests, hasLength(1));
  });

  test('without pinning, the same server is untrusted: the pinned authority is what admits it', () async {
    if (!openssl) return markTestSkipped('openssl is unavailable');
    final (server, requests) = await serve('pinned');
    final unpinned = client(server);
    final error = await unpinned
        .get<Object?>('a')
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<DioException>());
    expect(requests, isEmpty);
  });

  test('a pinned client refuses a publicly trusted certificate too', () async {
    // The real check that no system root is trusted: a public site that an
    // unpinned client reaches must fail the handshake once pinned elsewhere.
    if (!openssl) return markTestSkipped('openssl is unavailable');
    const site = 'https://pub.dev/robots.txt';
    final reachable = await Dio()
        .get<Object?>(site)
        .then((_) => true, onError: (Object _) => false);
    if (!reachable) return markTestSkipped('$site is unreachable: offline');
    final dio = Dio();
    pinCertificateAuthorities(dio, [pinned]);
    final error = await dio
        .get<Object?>(site)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect((error as DioException?)?.error, isA<HandshakeException>());
  });

  test('pinning keeps an IO adapter the app already set up', () {
    if (!openssl) return markTestSkipped('openssl is unavailable');
    final dio = Dio();
    final adapter = dio.httpClientAdapter;
    pinCertificateAuthorities(dio, [pinned]);
    expect(identical(dio.httpClientAdapter, adapter), isTrue);
  });
}
