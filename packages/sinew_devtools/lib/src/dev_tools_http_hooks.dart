import 'package:dio/dio.dart';
import 'package:sinew_network/sinew_network.dart';

import 'fault_rules.dart';
import 'host_override.dart';
import 'network_recorder.dart';
import 'redaction.dart';

/// The `extra` key that marks a request devtools sends again, so its record
/// says it's a replay.
const replayMark = 'sinew.devtools.replay';

final class _ReplayTarget {
  const _ReplayTarget(this.dio, this.requestedUrl, this.clientHeaders);

  final Dio dio;
  final String requestedUrl;
  final Set<String> clientHeaders;
}

/// The hooks devtools hands to `SinewHttp.dio(…, hooks: DevTools.httpHooks)`:
/// records every exchange in the recorder, applies the fault rules and the
/// host override, and keeps what a replay needs. A record keeps no client
/// reference itself, and the targets are dropped with the records they belong
/// to.
final class DevToolsHttpHooks extends SinewHttpHooks {
  /// Hooks over [recorder], [faults] and [hosts].
  DevToolsHttpHooks(this._recorder, this._faults, this._hosts);

  final NetworkRecorder _recorder;
  final FaultRules _faults;
  final HostOverride _hosts;
  final _clients = <Dio>[];
  var _targets = <int, _ReplayTarget>{};

  @override
  void attached(Dio dio) => _clients.add(dio);

  @override
  String? hostOverride() => _hosts.current.value;

  @override
  Future<FaultDecision?> fault(String method, Uri uri) async =>
      _faults.match(method, uri.path)?.decision();

  @override
  void record(HttpExchange exchange) {
    final record = _recorder.record(
      NetworkExchange(
        method: exchange.method,
        url: exchange.url,
        startedAt: exchange.startedAt,
        requestHeaders: exchange.requestHeaders,
        requestBody: exchange.requestBody,
        requestBodyStreamed: exchange.requestBodyStreamed,
        status: exchange.status,
        responseHeaders: exchange.responseHeaders,
        responseBody: exchange.responseBody,
        duration: exchange.duration,
        error: exchange.error,
        clientHeaders: exchange.defaultHeaderNames,
        isReplay: exchange.extra[replayMark] == true,
      ),
    );
    final kept = {for (final r in _recorder.records.value) r.id};
    _targets = {
      for (final MapEntry(:key, :value) in _targets.entries)
        if (kept.contains(key)) key: value,
      if (record.replayable)
        record.id: _ReplayTarget(
          exchange.dio,
          exchange.requestedUrl,
          exchange.defaultHeaderNames,
        ),
    };
  }

  /// Whether [record] can be sent again: it kept everything it needs, and
  /// it's still in the recorder with its client.
  bool canReplay(NetworkRecord record) =>
      record.replayable && _target(record) != null;

  /// [record]'s target, while the recorder still holds the record.
  _ReplayTarget? _target(NetworkRecord record) =>
      _recorder.records.value.any((r) => r.id == record.id)
      ? _targets[record.id]
      : null;

  /// Sends [record]'s request again through the client that sent it. The auth
  /// interceptor adds a fresh token and the client its own headers, so nothing
  /// secret comes from the record. Faults and the host override apply as for
  /// any request, and the result is recorded as a new record marked as a
  /// replay. A failure is in that record; it isn't thrown.
  ///
  /// Throws an [ArgumentError] for a record that isn't replayable and a
  /// [StateError] for one whose target is gone.
  Future<void> replay(NetworkRecord record) async {
    if (!record.replayable) {
      throw ArgumentError.value(
        record.id,
        'record',
        "can't be replayed: a secret in it was hidden",
      );
    }
    final target = _target(record);
    if (target == null) {
      throw StateError(
        "Record ${record.id} can't be replayed: it was dropped or cleared",
      );
    }
    final readded = {
      for (final name in target.clientHeaders) name.toLowerCase(),
      'authorization',
      'content-type',
      'content-length',
    };
    String? contentType;
    final headers = <String, dynamic>{};
    for (final MapEntry(:key, :value) in record.requestHeaders.entries) {
      if (key.toLowerCase() == 'content-type') contentType = value.firstOrNull;
      if (!readded.contains(key.toLowerCase())) {
        headers[key] = value.length == 1 ? value.single : value;
      }
    }
    final body = record.requestBody;
    try {
      await target.dio.request<dynamic>(
        target.requestedUrl,
        data: body is TextBody ? body.text : null,
        options: Options(
          method: record.method,
          headers: headers,
          contentType: contentType,
          extra: {replayMark: true},
        ),
      );
    } on DioException {
      // The failure is in the replay's own record.
    }
  }

  /// Devtools' "Expire access token": every client's next request with a
  /// token sends an invalid one.
  void expireAccessToken() => _clients.forEach(SinewHttp.debugExpireToken);
}
