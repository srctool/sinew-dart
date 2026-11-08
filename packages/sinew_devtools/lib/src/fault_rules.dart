import 'package:flutter/foundation.dart';
import 'package:sinew_network/sinew_network.dart';

/// A fault the network layer applies, inside the auth layer, to requests that
/// match [method] (any, when `null`) and [pathPattern]. It waits [delay],
/// then drops the connection ([drop]) or answers [status] with [body] without
/// reaching the backend. With only a delay, the request goes out after it.
///
/// [pathPattern] matches the end of the path, at a `/`: `/orders` matches
/// `/v1/orders` but not `/v1/myorders`. A `*` in it matches any run of
/// characters, `/` included: `/orders/*` matches every order.
@immutable
final class FaultRule {
  /// A rule. Throws an [ArgumentError] for a blank pattern, a rule without a
  /// status, a drop or a delay, both a drop and a status, a status outside
  /// 100–599, or a delay that isn't positive.
  FaultRule({
    required this.pathPattern,
    this.method,
    this.status,
    this.delay,
    this.drop = false,
    this.body,
  }) : _regex = RegExp(
         '^(.*/)?${pathPattern.replaceFirst(RegExp('^/+'), '').split('*').map(RegExp.escape).join('.*')}\$',
       ) {
    if (pathPattern.trim().isEmpty) {
      throw ArgumentError.value(pathPattern, 'pathPattern', 'is blank');
    }
    if (status == null && !drop && delay == null) {
      throw ArgumentError('A fault needs a status, a drop or a delay');
    }
    if (drop && status != null) {
      throw ArgumentError(
        'A fault either drops the connection or answers a status, not both',
      );
    }
    if (status != null && (status! < 100 || status! > 599)) {
      throw ArgumentError.value(status, 'status', 'must be an HTTP status');
    }
    if (delay != null && delay! <= Duration.zero) {
      throw ArgumentError.value(delay, 'delay', 'must be positive');
    }
  }

  /// The method it applies to, or `null` for any.
  final String? method;

  /// The path it applies to.
  final String pathPattern;

  /// The status to answer with.
  final int? status;

  /// How long to wait first.
  final Duration? delay;

  /// Whether to drop the connection.
  final bool drop;

  /// The body to answer [status] with.
  final String? body;

  final RegExp _regex;

  /// Whether this rule applies to a request with [method] and [path].
  bool matches(String method, String path) =>
      (this.method == null ||
          this.method!.toUpperCase() == method.toUpperCase()) &&
      _regex.hasMatch(path);

  /// The network layer's decision for this rule.
  FaultDecision decision() =>
      FaultDecision(delay: delay, status: status, body: body, drop: drop);

  @override
  bool operator ==(Object other) =>
      other is FaultRule &&
      other.method == method &&
      other.pathPattern == pathPattern &&
      other.status == status &&
      other.delay == delay &&
      other.drop == drop &&
      other.body == body;

  @override
  int get hashCode =>
      Object.hash(method, pathPattern, status, delay, drop, body);

  @override
  String toString() =>
      'FaultRule(${method ?? '*'} $pathPattern'
      '${status == null ? '' : ' → $status'}'
      '${drop ? ' drop' : ''}'
      '${delay == null ? '' : ' after ${delay!.inMilliseconds} ms'})';
}

/// The active fault rules, in memory only: they're gone after a restart, so a
/// rule forgotten on a test device can't break the next day's session. When
/// several match a request, the most recently added wins.
final class FaultRules {
  final _active = ValueNotifier<List<FaultRule>>(const []);

  /// The rules, oldest first. The ribbon says "faults on" while it isn't
  /// empty.
  ValueListenable<List<FaultRule>> get active => _active;

  /// Adds [rule].
  void add(FaultRule rule) =>
      _active.value = List.unmodifiable([..._active.value, rule]);

  /// Removes [rule].
  void remove(FaultRule rule) =>
      _active.value = List.unmodifiable([..._active.value]..remove(rule));

  /// Removes every rule.
  void clear() => _active.value = const [];

  /// The rule for a request, or `null`: the newest one that matches.
  FaultRule? match(String method, String path) {
    for (final rule in _active.value.reversed) {
      if (rule.matches(method, path)) return rule;
    }
    return null;
  }
}
