import 'error_body.dart';

/// A response with a non-2xx status, raised by the client after it read the
/// error body with its own [ErrorBodyReader]. The guard's handlers classify it
/// by [status].
///
/// Not exported: it only travels from the client to `processApiCall`, which
/// turns it into a `SinewException`. Its `toString` names only the status: the
/// body may hold personal data.
final class HttpStatusError implements Exception {
  /// Creates the error.
  const HttpStatusError(this.status, this.errorBody, this.retryAfter);

  /// The response's status.
  final int status;

  /// What the client's reader made of the body, or `null` when it was
  /// unreadable.
  final ErrorBody? errorBody;

  /// The `Retry-After` header as a wait, for a 429 or a 503.
  final Duration? retryAfter;

  @override
  String toString() => 'HTTP $status';
}

const _months = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

/// IMF-fixdate, the one HTTP date form Sinew reads: `Wed, 21 Oct 2015 07:28:00 GMT`.
final _imfFixdate = RegExp(
  r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) '
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) '
  r'(\d{2}):(\d{2}):(\d{2}) GMT$',
);

// At most 10 digits: on the web, ints are doubles, so a huge value wouldn't overflow to null as on the VM.
final _seconds = RegExp(r'^\d{1,10}$');

/// The wait a `Retry-After` header asks for: delay-seconds (`120`) or an HTTP
/// date (`Wed, 21 Oct 2015 07:28:00 GMT`), counted from [now]. A date in the
/// past is a zero wait. Anything else, including the obsolete RFC 850 and
/// asctime date forms, is `null`, as if the header were absent.
Duration? parseRetryAfter(String? value, {DateTime? now}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (_seconds.hasMatch(text)) {
    final seconds = int.tryParse(text);
    return seconds == null ? null : Duration(seconds: seconds);
  }
  final match = _imfFixdate.firstMatch(text);
  if (match == null) return null;
  final date = DateTime.utc(
    int.parse(match[3]!),
    _months[match[2]]!,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
  final wait = date.difference(now ?? DateTime.now().toUtc());
  return wait.isNegative ? Duration.zero : wait;
}
