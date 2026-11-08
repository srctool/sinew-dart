import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sinew_models/sinew_models.dart';

import 'redaction.dart';

/// One request and its response as the network layer saw them, **before**
/// redaction. It's handed to [NetworkRecorder.record], which redacts it and
/// keeps only the result. Content types are read from the headers.
///
/// [clientHeaders] are the names the client adds by itself (its
/// `defaultHeaders`): they're redacted, and a replay gets them again from the
/// client, so masking them doesn't stop a replay.
final class NetworkExchange {
  /// An exchange that started at [startedAt].
  const NetworkExchange({
    required this.method,
    required this.url,
    required this.startedAt,
    this.requestHeaders = const {},
    this.requestBody,
    this.requestBodyStreamed = false,
    this.status,
    this.responseHeaders = const {},
    this.responseBody,
    this.duration,
    this.error,
    this.clientHeaders = const {},
    this.isReplay = false,
  });

  /// The request method.
  final String method;

  /// The full URL, before redaction.
  final String url;

  /// When the request started.
  final DateTime startedAt;

  /// The request headers, before redaction.
  final Map<String, List<String>> requestHeaders;

  /// The request body, before redaction.
  final List<int>? requestBody;

  /// Whether the request body was streamed: it's recorded as binary of
  /// unknown size, and can't be replayed.
  final bool requestBodyStreamed;

  /// The response status, or `null` when the request failed before one.
  final int? status;

  /// The response headers, before redaction.
  final Map<String, List<String>> responseHeaders;

  /// The response body, before redaction.
  final List<int>? responseBody;

  /// How long the exchange took.
  final Duration? duration;

  /// The failure, if the exchange failed.
  final Object? error;

  /// The header names the client adds by itself: its `defaultHeaders`.
  final Set<String> clientHeaders;

  /// Whether the exchange is a replay of an earlier record.
  final bool isReplay;
}

/// A redacted record in the Network Monitor. Nothing in it is a secret:
/// [url], the headers and the bodies went through [Redaction] before the
/// record existed.
@immutable
final class NetworkRecord {
  /// A record. Records are made by [NetworkRecorder].
  const NetworkRecord({
    required this.id,
    required this.startedAt,
    required this.method,
    required this.url,
    required this.requestHeaders,
    required this.requestBody,
    required this.status,
    required this.responseHeaders,
    required this.responseBody,
    required this.duration,
    required this.errorType,
    required this.errorCode,
    required this.cacheSource,
    required this.isReplay,
    required this.replayable,
  });

  /// The record's number, rising with each record.
  final int id;

  /// When the request started.
  final DateTime startedAt;

  /// The request method, upper case.
  final String method;

  /// The redacted URL.
  final String url;

  /// The redacted request headers.
  final Map<String, List<String>> requestHeaders;

  /// The redacted request body.
  final RecordedBody requestBody;

  /// The response status, or `null` when the request failed before a
  /// response.
  final int? status;

  /// The redacted response headers.
  final Map<String, List<String>> responseHeaders;

  /// The redacted response body.
  final RecordedBody responseBody;

  /// How long the exchange took.
  final Duration? duration;

  /// The failure's type, such as `NoInternetConnectionException`.
  final String? errorType;

  /// The failure's Sinew code, when it's a [SinewException].
  final String? errorCode;

  /// Where a cache serve came from (`memory`, `disk`), or `null` for a
  /// request that went out.
  final String? cacheSource;

  /// Whether this record is a replay of an earlier one.
  final bool isReplay;

  /// Whether the request kept everything it needs to be sent again: nothing
  /// in its URL, its own headers or its body was masked, and the body wasn't
  /// cut or binary. `Authorization` and the client's own headers don't count,
  /// since the client adds them again.
  final bool replayable;

  /// Whether this record is a cache serve, not a request that went out.
  bool get fromCache => cacheSource != null;

  /// The record as text, for a bug report. Every secret is still masked.
  String asText() {
    final out = StringBuffer()..writeln('$method $url');
    final summary = [
      status?.toString() ?? 'no response',
      if (duration != null) '${duration!.inMilliseconds} ms',
      if (isReplay) 'replay',
      if (cacheSource != null) 'from cache ($cacheSource)',
    ];
    out.writeln('→ ${summary.join(' · ')}');
    if (errorType != null) {
      out.writeln('Error: $errorType${errorCode == null ? '' : ' $errorCode'}');
    }
    _headers(out, 'Request headers', requestHeaders);
    _body(out, 'Request body', requestBody);
    _headers(out, 'Response headers', responseHeaders);
    _body(out, 'Response body', responseBody);
    return out.toString().trimRight();
  }

  /// A `curl` command for the request. Every secret is still masked, so a
  /// request that needs a token won't run as copied: it's for a bug report.
  String asCurl() {
    // After the command: a comment inside a continued line ends it.
    final notes = <String>[];
    final parts = [
      method == 'GET'
          ? 'curl ${_quote(url)}'
          : 'curl -X $method ${_quote(url)}',
      for (final MapEntry(:key, :value) in requestHeaders.entries)
        for (final v in value) '-H ${_quote('$key: $v')}',
    ];
    switch (requestBody) {
      case NoBody():
        break;
      case TextBody(:final text, :final size, :final truncated):
        parts.add('--data-raw ${_quote(text)}');
        if (truncated) {
          notes.add(
            'body cut at ${formatSize(utf8.encode(text).length)} '
            'of ${formatSize(size)}',
          );
        }
      case BinaryBody(:final contentType, :final size):
        notes.add(
          'body not included: ${contentType ?? 'binary'}, ${formatSize(size)}',
        );
    }
    return parts.join(' \\\n  ') + notes.map((n) => '\n# $n').join();
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static void _headers(
    StringBuffer out,
    String title,
    Map<String, List<String>> headers,
  ) {
    if (headers.isEmpty) return;
    out
      ..writeln()
      ..writeln(title);
    for (final MapEntry(:key, :value) in headers.entries) {
      for (final v in value) {
        out.writeln('$key: $v');
      }
    }
  }

  static void _body(StringBuffer out, String title, RecordedBody body) {
    switch (body) {
      case NoBody():
        return;
      case TextBody(:final text, :final size, :final truncated):
        out
          ..writeln()
          ..writeln(title)
          ..writeln(text);
        if (truncated) {
          out.writeln(
            '(cut at ${formatSize(utf8.encode(text).length)} '
            'of ${formatSize(size)})',
          );
        }
      case BinaryBody(:final contentType, :final size):
        out
          ..writeln()
          ..writeln(title)
          ..writeln(
            '${contentType ?? 'binary'}, ${formatSize(size)} (not recorded)',
          );
    }
  }

  @override
  String toString() =>
      'NetworkRecord(#$id $method $url → $status, '
      'replayable: $replayable)';
}

/// The Network Monitor's records, in memory only, newest first. Each exchange
/// is redacted before it's stored, so no record holds a secret. Holds at most
/// [capacity] records and drops the oldest.
final class NetworkRecorder {
  /// A recorder that keeps [capacity] records, redacted with [redaction].
  NetworkRecorder({this.capacity = defaultCapacity, Redaction? redaction})
    : redaction = redaction ?? Redaction.standard {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  /// The default number of records kept.
  static const defaultCapacity = 200;

  /// How many records are kept.
  final int capacity;

  /// What's hidden before a record is stored. `SinewDevTools(redaction:)`
  /// sets the app's rules.
  Redaction redaction;

  final _records = ValueNotifier<List<NetworkRecord>>(const []);
  var _ids = 0;

  /// The records, newest first.
  ValueListenable<List<NetworkRecord>> get records => _records;

  /// Redacts [exchange] and stores the result.
  NetworkRecord record(NetworkExchange exchange) {
    final rules = redaction.withHeaders(exchange.clientHeaders);
    final type = _contentType(exchange.requestHeaders);
    final requestBody = exchange.requestBodyStreamed
        ? BinaryBody(type?.split(';').first.trim(), unknownSize)
        : rules.redactBody(exchange.requestBody, type);
    final url = rules.redactUrl(exchange.url);
    final readded = {
      for (final name in exchange.clientHeaders) name.toLowerCase(),
      'authorization',
    };
    final headersKept = !exchange.requestHeaders.keys.any(
      (name) =>
          !readded.contains(name.toLowerCase()) &&
          rules.isSensitiveHeader(name),
    );
    final bodyKept = switch (requestBody) {
      NoBody() => true,
      TextBody(:final truncated, :final masked) => !truncated && !masked,
      BinaryBody() => false,
    };
    final error = exchange.error;
    return _add(
      NetworkRecord(
        id: ++_ids,
        startedAt: exchange.startedAt,
        method: exchange.method.toUpperCase(),
        url: url,
        requestHeaders: rules.redactHeaders(exchange.requestHeaders),
        requestBody: requestBody,
        status: exchange.status,
        responseHeaders: rules.redactHeaders(exchange.responseHeaders),
        responseBody: rules.redactBody(
          exchange.responseBody,
          _contentType(exchange.responseHeaders),
        ),
        duration: exchange.duration,
        errorType: error?.runtimeType.toString(),
        errorCode: error is SinewException ? error.code : null,
        cacheSource: null,
        isReplay: exchange.isReplay,
        replayable: url == exchange.url && headersKept && bodyKept,
      ),
    );
  }

  /// Records that the app served [key] from its cache ([source]: `memory`,
  /// `disk`) instead of the network. The body goes through the same
  /// redaction: a cached response is still a response. A cache serve is never
  /// replayable.
  NetworkRecord recordCacheServe(
    String key,
    String source, {
    List<int>? body,
    String? contentType,
    DateTime? at,
  }) => _add(
    NetworkRecord(
      id: ++_ids,
      startedAt: at ?? DateTime.now(),
      method: 'CACHE',
      url: redaction.redactUrl(key),
      requestHeaders: const {},
      requestBody: const NoBody(),
      status: null,
      responseHeaders: const {},
      responseBody: redaction.redactBody(body, contentType),
      duration: null,
      errorType: null,
      errorCode: null,
      cacheSource: source,
      isReplay: false,
      replayable: false,
    ),
  );

  /// Forgets every record: on "Clear", and on sign-out through
  /// `DevTools.clearUserData()`.
  void clear() => _records.value = const [];

  NetworkRecord _add(NetworkRecord record) {
    _records.value = List.unmodifiable(
      [record, ..._records.value].take(capacity),
    );
    return record;
  }

  static String? _contentType(Map<String, List<String>> headers) {
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() == 'content-type' && value.isNotEmpty) {
        return value.first;
      }
    }
    return null;
  }
}

/// The size of a streamed body, which isn't read.
const unknownSize = -1;

/// A size as the pages show it: `512 B`, `12 KB`, `1.2 MB`, or
/// `unknown size` for a streamed body.
String formatSize(int bytes) {
  if (bytes < 0) return 'unknown size';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes + 512) ~/ 1024} KB';
  final tenths = (bytes * 10 + 512 * 1024) ~/ (1024 * 1024);
  return tenths % 10 == 0
      ? '${tenths ~/ 10} MB'
      : '${tenths ~/ 10}.${tenths % 10} MB';
}
