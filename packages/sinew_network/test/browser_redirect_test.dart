@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// In the browser, Dio can't turn redirects off: the browser follows them
/// itself. Sinew relies on the Fetch standard dropping `Authorization` on a
/// redirect to another origin; this checks the browser really does.
void main() {
  test('a cross-origin redirect drops Authorization', () async {
    final servers = spawnHybridCode(r'''
      import 'dart:io';
      import 'package:stream_channel/stream_channel.dart';

      void cors(HttpResponse r) => r.headers
        ..set('access-control-allow-origin', '*')
        ..set('access-control-allow-headers', 'authorization')
        ..set('access-control-allow-methods', 'GET');

      Future<void> hybridMain(StreamChannel<Object?> channel) async {
        final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        other.listen((r) {
          cors(r.response);
          if (r.method == 'OPTIONS') { r.response..statusCode = 204..close(); return; }
          r.response..write('other auth=${r.headers.value('authorization')}')..close();
        });
        final own = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        own.listen((r) {
          cors(r.response);
          if (r.method == 'OPTIONS') { r.response..statusCode = 204..close(); return; }
          r.response
            ..statusCode = 302
            ..headers.set('location', 'http://localhost:${other.port}/x')
            ..close();
        });
        channel.sink.add(own.port);
      }
    ''');
    final ownPort = await servers.stream.first as int;
    final response = await Dio().get<String>(
      'http://127.0.0.1:$ownPort/cross',
      options: Options(
        headers: {'Authorization': 'Bearer t'},
        responseType: ResponseType.plain,
      ),
    );
    expect(response.data, 'other auth=null');
  });
}
