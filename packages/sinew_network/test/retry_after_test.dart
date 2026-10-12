import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/src/error_body.dart';
import 'package:sinew_network/src/http_status_error.dart';

void main() {
  final now = DateTime.utc(2015, 10, 21, 7, 26);

  test('parses delay-seconds', () {
    expect(parseRetryAfter('120', now: now), const Duration(seconds: 120));
    expect(parseRetryAfter('0', now: now), Duration.zero);
    expect(parseRetryAfter(' 5 ', now: now), const Duration(seconds: 5));
  });

  test('parses an HTTP date from now', () {
    expect(
      parseRetryAfter('Wed, 21 Oct 2015 07:28:00 GMT', now: now),
      const Duration(minutes: 2),
    );
  });

  test('a date in the past is a zero wait', () {
    expect(
      parseRetryAfter('Wed, 21 Oct 2015 07:20:00 GMT', now: now),
      Duration.zero,
    );
  });

  test('anything else is absent', () {
    for (final value in [
      null,
      '',
      '-5',
      '1.5',
      'soon',
      '99999999999999999999',
      'Wednesday, 21-Oct-15 07:28:00 GMT', // obsolete RFC 850 form
      'Wed Oct 21 07:28:00 2015', // obsolete asctime form
      'Wed, 21 Oct 2015 07:28:00 UTC',
    ]) {
      expect(parseRetryAfter(value, now: now), isNull, reason: '$value');
    }
  });

  test('the error names only its status', () {
    const error = HttpStatusError(
      422,
      ErrorBody(message: 'jane@example.com is taken'),
      null,
    );
    expect(error.toString(), 'HTTP 422');
  });
}
