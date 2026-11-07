import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools/src/network_recorder.dart' show formatSize;
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

void main() {
  final at = DateTime.utc(2026, 11, 7, 10);
  final mask = Redaction.standard.mask;
  const json = {
    'Content-Type': ['application/json'],
  };
  const form = {
    'Content-Type': ['application/x-www-form-urlencoded'],
  };

  NetworkExchange exchange({
    String method = 'GET',
    String url = 'https://api.test/v1/orders',
    Map<String, List<String>> requestHeaders = const {},
    String? requestBody,
    int? status = 200,
    Map<String, List<String>> responseHeaders = json,
    String? responseBody = '{"items":[]}',
    Object? error,
    Set<String> clientHeaders = const {},
    bool isReplay = false,
  }) => NetworkExchange(
    method: method,
    url: url,
    startedAt: at,
    requestHeaders: requestHeaders,
    requestBody: requestBody == null ? null : utf8.encode(requestBody),
    status: status,
    responseHeaders: responseHeaders,
    responseBody: responseBody == null ? null : utf8.encode(responseBody),
    duration: const Duration(milliseconds: 245),
    error: error,
    clientHeaders: clientHeaders,
    isReplay: isReplay,
  );

  tearDown(DevTools.network.clear);

  test('the capacity drops the oldest record', () {
    final recorder = NetworkRecorder(capacity: 3);
    for (var i = 0; i < 5; i++) {
      recorder.record(exchange(url: 'https://api.test/$i'));
    }
    expect(
      [for (final r in recorder.records.value) r.url],
      ['https://api.test/4', 'https://api.test/3', 'https://api.test/2'],
    );
  });

  test('the response body is redacted by its own content type', () {
    final record = NetworkRecorder().record(
      exchange(
        method: 'POST',
        responseHeaders: form,
        responseBody: 'access_token=abc&expires_in=3600',
      ),
    );
    expect(
      (record.responseBody as TextBody).text,
      'access_token=$mask&expires_in=3600',
    );
  });

  test('nothing unredacted is ever stored', () {
    const secrets = [
      'Bearer-abc123',
      'device-77',
      'qs-token-1',
      'hunter2',
      'otp-445566',
      'cookie-s3cr3t',
      'refresh-r1',
    ];
    final recorder = NetworkRecorder()
      ..record(
        exchange(
          method: 'POST',
          url: 'https://api.test/v1/login?token=qs-token-1&lang=en',
          requestHeaders: {
            'Authorization': ['Bearer Bearer-abc123'],
            'X-Device-Id': ['device-77'],
            ...json,
          },
          requestBody:
              '{"user":{"name":"ana","credentials":[{"password":"hunter2"}]},'
              '"otp":"otp-445566"}',
          responseHeaders: {
            'Set-Cookie': ['session=cookie-s3cr3t'],
            ...json,
          },
          responseBody: '{"data":{"refreshToken":"refresh-r1","name":"ana"}}',
          clientHeaders: {'X-Device-Id'},
        ),
      );
    final record = recorder.records.value.single;
    final stored = [
      record.toString(),
      record.asText(),
      record.asCurl(),
      '${record.requestHeaders}',
      '${record.responseHeaders}',
      (record.requestBody as TextBody).text,
      (record.responseBody as TextBody).text,
    ];
    for (final text in stored) {
      for (final secret in secrets) {
        expect(text, isNot(contains(secret)));
      }
    }
    expect(record.asText(), contains('ana'));
  });

  test(
    'a request that only lost the client\'s own headers can be replayed',
    () {
      final recorder = NetworkRecorder();
      final record = recorder.record(
        exchange(
          requestHeaders: {
            'Authorization': ['Bearer t'],
            'X-Device-Id': ['d'],
            'Accept': ['*/*'],
          },
          clientHeaders: {'X-Device-Id'},
        ),
      );
      expect(record.replayable, isTrue);
      expect(record.requestHeaders['Authorization'], [mask]);
      expect(record.requestHeaders['X-Device-Id'], [mask]);
      expect(
        recorder
            .record(
              exchange(
                method: 'POST',
                requestBody: '{"name":"ana"}',
                requestHeaders: json,
              ),
            )
            .replayable,
        isTrue,
      );
    },
  );

  test('a request that lost a secret of its own cannot be replayed', () {
    final recorder = NetworkRecorder();
    expect(
      recorder
          .record(exchange(url: 'https://api.test/v1/me?token=abc'))
          .replayable,
      isFalse,
      reason: 'query',
    );
    expect(
      recorder
          .record(
            exchange(
              requestHeaders: {
                'X-Api-Key': ['k'],
              },
            ),
          )
          .replayable,
      isFalse,
      reason: 'own header',
    );
    expect(
      recorder
          .record(
            exchange(
              requestHeaders: {
                'Cookie': ['a=1'],
              },
            ),
          )
          .replayable,
      isFalse,
      reason: 'cookie',
    );
    expect(
      recorder
          .record(
            exchange(
              method: 'POST',
              requestBody: '{"otp":"1"}',
              requestHeaders: json,
            ),
          )
          .replayable,
      isFalse,
      reason: 'body',
    );
    expect(
      recorder
          .record(
            exchange(
              method: 'POST',
              requestBody: 'password=p',
              requestHeaders: form,
            ),
          )
          .replayable,
      isFalse,
      reason: 'form',
    );
  });

  test('a cut or binary request body cannot be replayed', () {
    final small = NetworkRecorder(
      redaction: Redaction.standard.extend(maxBodyBytes: 4),
    );
    expect(
      small
          .record(
            exchange(
              method: 'POST',
              requestBody: '{"name":"ana"}',
              requestHeaders: json,
            ),
          )
          .replayable,
      isFalse,
    );
    final upload = NetworkRecorder().record(
      NetworkExchange(
        method: 'PUT',
        url: 'https://api.test/v1/avatar',
        startedAt: at,
        requestHeaders: const {
          'Content-Type': ['image/png'],
        },
        requestBody: const [1, 2, 3],
      ),
    );
    expect(upload.requestBody, const BinaryBody('image/png', 3));
    expect(upload.replayable, isFalse);
  });

  test('a record keeps the exchange\'s facts', () {
    const error = NoInternetConnectionException(
      'ORD',
      ExceptionLayer.repository,
      'list',
    );
    final record = NetworkRecorder().record(
      exchange(
        method: 'get',
        status: null,
        responseBody: null,
        error: error,
        isReplay: true,
      ),
    );
    expect(record.method, 'GET');
    expect(record.status, isNull);
    expect(record.errorType, 'NoInternetConnectionException');
    expect(record.errorCode, error.code);
    expect(record.startedAt, at);
    expect(record.duration, const Duration(milliseconds: 245));
    expect(record.isReplay, isTrue);
    expect(record.fromCache, isFalse);
    expect(record.responseBody, const NoBody());
  });

  test('a plain error keeps its type', () {
    final record = NetworkRecorder().record(exchange(error: StateError('x')));
    expect(record.errorType, 'StateError');
    expect(record.errorCode, isNull);
  });

  test('a cache serve is redacted and never replayable', () {
    final recorder = NetworkRecorder();
    final record = recorder.recordCacheServe(
      'https://api.test/v1/me?token=abc',
      'disk',
      body: utf8.encode('{"name":"ana","pin":"1234"}'),
      contentType: 'application/json',
      at: at,
    );
    expect(record.fromCache, isTrue);
    expect(record.cacheSource, 'disk');
    expect(record.replayable, isFalse);
    expect(record.method, 'CACHE');
    expect(record.url, 'https://api.test/v1/me?token=$mask');
    final body = (record.responseBody as TextBody).text;
    expect(body, isNot(contains('1234')));
    expect(body, contains('ana'));
    expect(recorder.records.value, [record]);
  });

  test('clear empties it, and clearUserData empties the shared one', () {
    final recorder = NetworkRecorder()..record(exchange());
    recorder.clear();
    expect(recorder.records.value, isEmpty);
    DevTools.network.record(exchange());
    DevTools.clearUserData();
    expect(DevTools.network.records.value, isEmpty);
  });

  test('the records notify their listeners and cannot be changed', () {
    final recorder = NetworkRecorder();
    var calls = 0;
    recorder.records.addListener(() => calls++);
    recorder
      ..record(exchange())
      ..clear();
    expect(calls, 2);
    recorder.record(exchange());
    expect(() => recorder.records.value.clear(), throwsUnsupportedError);
  });

  test('the capacity must be positive', () {
    expect(() => NetworkRecorder(capacity: 0), throwsArgumentError);
    expect(NetworkRecorder.defaultCapacity, 200);
  });

  group('copy and copy as cURL', () {
    test('asText shows the record redacted', () {
      final record = NetworkRecorder().record(
        exchange(
          method: 'POST',
          requestHeaders: {
            'Authorization': ['Bearer t'],
            ...json,
          },
          requestBody: '{"name":"ana"}',
          status: 201,
          responseBody: '{"id":7}',
          isReplay: true,
        ),
      );
      expect(
        record.asText(),
        'POST https://api.test/v1/orders\n'
        '→ 201 · 245 ms · replay\n'
        '\n'
        'Request headers\n'
        'Authorization: $mask\n'
        'Content-Type: application/json\n'
        '\n'
        'Request body\n'
        '{"name":"ana"}\n'
        '\n'
        'Response headers\n'
        'Content-Type: application/json\n'
        '\n'
        'Response body\n'
        '{"id":7}',
      );
    });

    test('asText names the error, a cut body and a binary body', () {
      final recorder = NetworkRecorder(
        redaction: Redaction.standard.extend(maxBodyBytes: 4),
      );
      const error = NoInternetConnectionException(
        'ORD',
        ExceptionLayer.repository,
        'list',
      );
      final text = recorder
          .record(
            NetworkExchange(
              method: 'PUT',
              url: 'https://api.test/a',
              startedAt: at,
              requestHeaders: const {
                'Content-Type': ['image/png'],
              },
              requestBody: List.filled(2048, 0),
              responseHeaders: const {
                'Content-Type': ['text/plain'],
              },
              responseBody: utf8.encode('abcdefgh'),
              error: error,
            ),
          )
          .asText();
      expect(text, contains('→ no response'));
      expect(
        text,
        contains('Error: NoInternetConnectionException ${error.code}'),
      );
      expect(text, contains('image/png, 2 KB (not recorded)'));
      expect(text, contains('abcd\n(cut at 4 B of 8 B)'));
      expect(
        NetworkRecorder().recordCacheServe('k', 'memory', at: at).asText(),
        contains('from cache (memory)'),
      );
    });

    test('asCurl is a redacted command', () {
      final record = NetworkRecorder().record(
        exchange(
          method: 'POST',
          url: 'https://api.test/v1/notes?token=abc',
          requestHeaders: {
            'Authorization': ['Bearer t'],
            ...json,
          },
          requestBody: '{"text":"it\'s"}',
        ),
      );
      expect(
        record.asCurl(),
        "curl -X POST 'https://api.test/v1/notes?token=$mask' \\\n"
        "  -H 'Authorization: $mask' \\\n"
        "  -H 'Content-Type: application/json' \\\n"
        "  --data-raw '{\"text\":\"it'\\''s\"}'",
      );
    });

    test('asCurl leaves out what it cannot send', () {
      expect(
        NetworkRecorder().record(exchange()).asCurl(),
        "curl 'https://api.test/v1/orders'",
      );
      final upload = NetworkRecorder().record(
        NetworkExchange(
          method: 'PUT',
          url: 'https://api.test/a',
          startedAt: at,
          requestHeaders: const {
            'Content-Type': ['image/png'],
          },
          requestBody: const [0, 0, 0],
        ),
      );
      expect(
        upload.asCurl(),
        "curl -X PUT 'https://api.test/a' \\\n"
        "  -H 'Content-Type: image/png'\n"
        '# body not included: image/png, 3 B',
      );
      final cut =
          NetworkRecorder(redaction: Redaction.standard.extend(maxBodyBytes: 4))
              .record(
                exchange(
                  method: 'POST',
                  requestBody: 'abcdefgh',
                  requestHeaders: {
                    'Content-Type': ['text/plain'],
                  },
                ),
              );
      expect(
        cut.asCurl(),
        endsWith("--data-raw 'abcd'\n# body cut at 4 B of 8 B"),
      );
    });
  });

  test('sizes read naturally', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(1024), '1 KB');
    expect(formatSize(12 * 1024), '12 KB');
    expect(formatSize(1800), '2 KB'); // rounded, not cut
    expect(formatSize(1024 * 1024), '1 MB');
    expect(formatSize(1024 * 1024 * 3 ~/ 2), '1.5 MB');
    expect(formatSize(20 * 1024 * 1024), '20 MB');
  });
}
