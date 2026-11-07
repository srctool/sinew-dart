import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';

void main() {
  final redaction = Redaction.standard;
  final mask = Redaction.standard.mask;

  Object? json(String body, {String? contentType = 'application/json'}) {
    final recorded = redaction.redactBody(utf8.encode(body), contentType);
    return jsonDecode((recorded as TextBody).text);
  }

  group('headers', () {
    test('the default headers are redacted', () {
      expect(
        redaction.redactHeaders({
          'Authorization': ['Bearer abc'],
          'Cookie': ['a=1', 'b=2'],
          'Set-Cookie': ['s=1'],
          'Proxy-Authorization': ['Basic xyz'],
          'Accept': ['application/json'],
        }),
        {
          'Authorization': [mask],
          'Cookie': [mask, mask],
          'Set-Cookie': [mask],
          'Proxy-Authorization': [mask],
          'Accept': ['application/json'],
        },
      );
    });

    test('header names match whatever their case', () {
      expect(
        redaction.redactHeaders({
          'authorization': ['x'],
        }),
        {
          'authorization': [mask],
        },
      );
      expect(
        redaction.redactHeaders({
          'SET_COOKIE': ['x'],
        }),
        {
          'SET_COOKIE': [mask],
        },
      );
    });

    test('a header named like a secret field is redacted', () {
      final redacted = redaction.redactHeaders({
        'X-Api-Key': ['k'],
        'X-Refresh-Token': ['t'],
        'X-Request-Id': ['r'],
      });
      expect(redacted['X-Api-Key'], [mask]);
      expect(redacted['X-Refresh-Token'], [mask]);
      expect(redacted['X-Request-Id'], ['r']);
    });

    test('every defaultHeaders name is redacted', () {
      const defaultHeaders = {
        'X-Device-Id': 'd-1',
        'X-Client': 'app',
        'Tenant': 'acme',
      };
      final forClient = redaction.withHeaders(defaultHeaders.keys);
      final redacted = forClient.redactHeaders({
        for (final MapEntry(:key, :value) in defaultHeaders.entries)
          key: [value],
        'Accept': ['*/*'],
      });
      expect(redacted['X-Device-Id'], [mask]);
      expect(redacted['X-Client'], [mask]);
      expect(redacted['Tenant'], [mask]);
      expect(redacted['Accept'], ['*/*']);
      expect(
        forClient.redactHeaders({
          'Authorization': ['x'],
        })['Authorization'],
        [mask],
      );
    });
  });

  group('field names', () {
    test('names are normalized before matching', () {
      for (final name in [
        'refreshToken',
        'refresh_token',
        'Refresh-Token',
        'newPassword',
        'idToken',
        'X-Api-Key',
        'otp.code',
        'PIN',
      ]) {
        expect(redaction.isSensitive(name), isTrue, reason: name);
      }
      for (final name in ['username', 'email', 'status', 'codename', 'id']) {
        expect(redaction.isSensitive(name), isFalse, reason: name);
      }
    });

    test('an exact field matches only the whole name', () {
      expect(redaction.isSensitive('code'), isTrue);
      expect(redaction.isSensitive('Code'), isTrue);
      expect(redaction.isSensitive('zipCode'), isFalse);
      expect(redaction.isSensitive('countryCode'), isFalse);
    });

    test('top-level fields are redacted', () {
      expect(
        json(
          '{"username":"ana","password":"hunter2","refreshToken":"r",'
          '"code":"123456","age":30}',
        ),
        {
          'username': 'ana',
          'password': mask,
          'refreshToken': mask,
          'code': mask,
          'age': 30,
        },
      );
    });

    test('fields nested in objects and arrays are redacted', () {
      expect(
        json(
          '{"user":{"name":"ana","credentials":[{"password":"p"}],'
          '"devices":[{"id":1,"pushToken":"t"},{"id":2,"pushToken":"u"}]},'
          '"items":[[{"idToken":"i"}]]}',
        ),
        {
          'user': {
            'name': 'ana',
            'credentials': mask, // the whole value, whatever its shape
            'devices': [
              {'id': 1, 'pushToken': mask},
              {'id': 2, 'pushToken': mask},
            ],
          },
          'items': [
            [
              {'idToken': mask},
            ],
          ],
        },
      );
    });

    test('a top-level array is walked', () {
      expect(json('[{"secret":"s"},{"name":"n"}]'), [
        {'secret': mask},
        {'name': 'n'},
      ]);
    });

    test('a JSON body without a JSON content type is still redacted', () {
      expect(json('{"password":"p"}', contentType: 'text/plain'), {
        'password': mask,
      });
      expect(json('  {"password":"p"}', contentType: null), {'password': mask});
    });

    test('a JSON body that does not parse is masked whole', () {
      final recorded = redaction.redactBody(
        utf8.encode('{"password":"p"'),
        'application/json',
      );
      expect(
        recorded,
        TextBody(mask, size: 15, truncated: false, masked: true),
      );
    });

    test('plain text is kept', () {
      expect(
        redaction.redactBody(utf8.encode('hello'), 'text/plain; charset=utf-8'),
        const TextBody('hello', size: 5, truncated: false),
      );
    });
  });

  test('a body tells whether anything was masked', () {
    bool masked(String body, String? type) =>
        (redaction.redactBody(utf8.encode(body), type) as TextBody).masked;
    expect(masked('{"user":{"password":"p"}}', 'application/json'), isTrue);
    expect(masked('[{"name":"n"},{"otp":"1"}]', 'application/json'), isTrue);
    // Masked whole.
    expect(masked('{"password":', 'application/json'), isTrue);
    expect(
      masked('user=ana&password=p', 'application/x-www-form-urlencoded'),
      isTrue,
    );
    expect(
      masked(
        '{ "user": { "name": "ana" }, "items": [1, 2] }',
        'application/json',
      ),
      isFalse,
    );
    expect(
      masked('user=ana&page=2', 'application/x-www-form-urlencoded'),
      isFalse,
    );
    // Plain text is kept as it is.
    expect(masked('password=p', 'text/plain'), isFalse);
    final big =
        '{"password":"p","filler":"${'x' * Redaction.defaultMaxBodyBytes}"}';
    expect(masked(big, 'application/json'), isTrue);
  });

  group('query parameters and form bodies', () {
    test('query parameters are redacted', () {
      expect(
        redaction.redactUrl(
          'https://api.example.com/v1/login?user=ana&token=abc'
          '&access_token=def&page=2#top',
        ),
        'https://api.example.com/v1/login?user=ana&token=$mask'
        '&access_token=$mask&page=2#top',
      );
      expect(
        redaction.redactUrl('https://api.example.com/v1/items'),
        'https://api.example.com/v1/items',
      );
      expect(
        redaction.redactUrl('https://x.test/?flag&code=9'),
        'https://x.test/?flag&code=$mask',
      );
      expect(
        redaction.redactUrl('https://x.test/?new%5Fpassword=p'),
        'https://x.test/?new%5Fpassword=$mask',
      );
      // Only decoded is it "password".
      expect(
        redaction.redactUrl('https://x.test/?pass%77ord=p'),
        'https://x.test/?pass%77ord=$mask',
      );
      expect(
        redaction.redactUrl('https://x.test/?a=1&token=abc#top'),
        'https://x.test/?a=1&token=$mask#top',
      );
    });

    test('fragment parameters are redacted', () {
      expect(
        redaction.redactUrl(
          'https://app.test/callback#access_token=abc&state=s1',
        ),
        'https://app.test/callback#access_token=$mask&state=s1',
      );
      expect(
        redaction.redactUrl('https://x.test/a?b=1#c'),
        'https://x.test/a?b=1#c',
      );
    });

    test('form bodies are redacted', () {
      final recorded = redaction.redactBody(
        utf8.encode(
          'grant_type=password&username=ana&password=p%26q&client_secret=s',
        ),
        'application/x-www-form-urlencoded',
      );
      expect(
        (recorded as TextBody).text,
        'grant_type=password&username=ana&password=$mask&client_secret=$mask',
      );
    });
  });

  group('size and binary bodies', () {
    test('a body over the cap is cut with its real size', () {
      final big = 'a' * (Redaction.defaultMaxBodyBytes * 3);
      final recorded =
          redaction.redactBody(utf8.encode(big), 'text/plain') as TextBody;
      expect(recorded.truncated, isTrue);
      expect(utf8.encode(recorded.text).length, Redaction.defaultMaxBodyBytes);
      expect(recorded.size, big.length);
    });

    test('an oversized JSON body is redacted before it is cut', () {
      final filler = 'x' * Redaction.defaultMaxBodyBytes;
      final recorded = redaction.redactBody(
        utf8.encode('{"password":"hunter2","filler":"$filler"}'),
        'application/json',
      ) as TextBody;
      expect(recorded.truncated, isTrue);
      expect(recorded.text, isNot(contains('hunter2')));
      expect(recorded.text, startsWith('{"password":"$mask"'));
    });

    test('a cut never splits a character', () {
      final text = 'é' * Redaction.defaultMaxBodyBytes; // 2 bytes each
      final cut =
          redaction
                  .extend(maxBodyBytes: 5)
                  .redactBody(utf8.encode(text), 'text/plain')
              as TextBody;
      expect(cut.text, 'éé');
    });

    test('a binary body keeps only its type and size', () {
      expect(
        redaction.redactBody(const [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ], 'image/png'),
        const BinaryBody('image/png', 8),
      );
      expect(
        redaction.redactBody(const [1, 2, 3], 'application/octet-stream'),
        const BinaryBody('application/octet-stream', 3),
      );
      expect(
        redaction.redactBody(
          utf8.encode('a=b\n'),
          'multipart/form-data; boundary=x',
        ),
        const BinaryBody('multipart/form-data', 4),
      );
    });

    test('bytes without a content type are sniffed', () {
      expect(
        redaction.redactBody(const [0xFF, 0xFE, 0x00], null),
        const BinaryBody(null, 3),
      );
      expect(
        redaction.redactBody(utf8.encode('ok'), null),
        const TextBody('ok', size: 2, truncated: false),
      );
      // Valid UTF-8, but a NUL.
      expect(
        redaction.redactBody(const [0x61, 0x00, 0x62], null),
        const BinaryBody(null, 3),
      );
    });

    test('the cap must be positive', () {
      expect(
        () => Redaction.standard.extend(maxBodyBytes: 0),
        throwsArgumentError,
      );
    });

    test('an empty body is none', () {
      expect(redaction.redactBody(null, 'application/json'), const NoBody());
      expect(
        redaction.redactBody(const [], 'application/json'),
        const NoBody(),
      );
    });
  });

  group('extending', () {
    test('extending the defaults keeps them', () {
      final extended = Redaction.standard.extend(
        headers: ['X-Tenant'],
        fieldParts: ['cardNumber', 'cvv'],
        exactFields: ['ssn'],
      );
      expect(
        extended.redactHeaders({
          'Authorization': ['x'],
        })['Authorization'],
        [mask],
      );
      expect(
        extended.redactHeaders({
          'x-tenant': ['x'],
        })['x-tenant'],
        [mask],
      );
      expect(extended.isSensitive('password'), isTrue);
      expect(extended.isSensitive('card_number'), isTrue);
      expect(extended.isSensitive('cvv2'), isTrue);
      expect(extended.isSensitive('SSN'), isTrue);
      expect(extended.isSensitive('ssnHint'), isFalse);
      expect(extended.headers.containsAll(Redaction.standard.headers), isTrue);
      expect(
        extended.fieldParts.containsAll(Redaction.standard.fieldParts),
        isTrue,
      );
      expect(
        extended.exactFields.containsAll(Redaction.standard.exactFields),
        isTrue,
      );
    });

    test('the rule sets cannot be changed in place', () {
      expect(() => Redaction.standard.headers.clear(), throwsUnsupportedError);
      expect(
        () => Redaction.standard.fieldParts.remove('password'),
        throwsUnsupportedError,
      );
    });

    test('the defaults are as designed', () {
      expect(Redaction.standard.headers, {
        'authorization',
        'cookie',
        'setcookie',
        'proxyauthorization',
      });
      expect(Redaction.standard.fieldParts, {
        'password',
        'passwd',
        'token',
        'secret',
        'otp',
        'pin',
        'apikey',
        'credential',
        'signature',
      });
      expect(Redaction.standard.exactFields, {'code'});
      expect(Redaction.standard.mask, '•••');
      expect(Redaction.standard.maxBodyBytes, 64 * 1024);
    });
  });

  group('masking a stored secret for display', () {
    test('a long secret shows its last four characters and length', () {
      expect(Redaction.maskSecret('${'a' * 408}9f2c'), '•••• 9f2c (412 chars)');
      expect(Redaction.maskSecret('abcdefghijklwxyz'), '•••• wxyz (16 chars)');
    });

    test('a short secret shows only its length', () {
      expect(Redaction.maskSecret('123456'), '•••• (6 chars)');
      expect(Redaction.maskSecret('a' * 15), '•••• (15 chars)');
      expect(Redaction.maskSecret('x'), '•••• (1 char)');
      expect(Redaction.maskSecret(''), '•••• (0 chars)');
    });
  });
}
