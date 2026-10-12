import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers each request with [handler] and records what it was sent.
final class FakeAdapter implements HttpClientAdapter {
  FakeAdapter([this.handler = _ok]);

  Future<ResponseBody> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  /// What each request carried when it was sent: a replay reuses the same
  /// [RequestOptions], so [requests] alone would show only the last state.
  final sent = <({Uri uri, Map<String, Object?> headers})>[];

  static Future<ResponseBody> _ok(RequestOptions _) async => json('{}');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    sent.add((uri: options.uri, headers: Map.of(options.headers)));
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// A JSON response.
ResponseBody json(
  String body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

/// A plain-text response.
ResponseBody text(String body, {int status = 200}) =>
    ResponseBody.fromBytes(utf8.encode(body), status);

/// A request that never answers.
Future<ResponseBody> never(RequestOptions _) =>
    Completer<ResponseBody>().future;
