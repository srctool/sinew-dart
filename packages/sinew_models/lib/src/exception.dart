/// The layer a failure was translated in. Its [code] is part of every
/// [SinewException.code].
enum ExceptionLayer {
  /// A view model or notifier.
  viewModel('VM'),

  /// A use case.
  useCase('UC'),

  /// A repository: the source guards.
  repository('R'),

  /// A utility outside the layers.
  utility('UT');

  const ExceptionLayer(this.code);

  /// The short code used in [SinewException.code].
  final String code;
}

/// Who provides a failure's user-facing text.
sealed class ErrorMessage {
  const ErrorMessage();

  /// The text shown when nothing translates it: the server's text, or the
  /// English fallback with its arguments filled in. Logs and crash reports use it.
  String get text;
}

/// The backend's text, already localized from the request's `Accept-Language`.
/// Shown as is.
final class ServerMessage extends ErrorMessage {
  /// Creates a server message.
  const ServerMessage(this.text);

  @override
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ServerMessage && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ServerMessage($text)';
}

/// A message key with named arguments, resolved by the app's localizer at
/// render time.
final class LocalMessage extends ErrorMessage {
  /// Creates a local message.
  const LocalMessage(this.key, {this.args = const {}, required this.fallback});

  /// The message key, such as `sinew.error.noInternet`.
  final String key;

  /// Named arguments, such as `{'seconds': 30}`.
  final Map<String, Object> args;

  /// The English text, with `{name}` placeholders for [args].
  final String fallback;

  @override
  String get text => args.entries.fold(
    fallback,
    (text, arg) => text.replaceAll('{${arg.key}}', '${arg.value}'),
  );

  @override
  bool operator ==(Object other) =>
      other is LocalMessage &&
      other.key == key &&
      other.fallback == fallback &&
      _mapEquals(other.args, args);

  @override
  int get hashCode => Object.hash(
    key,
    fallback,
    Object.hashAllUnordered(
      args.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'LocalMessage($key, $args)';
}

bool _mapEquals(Map<String, Object> a, Map<String, Object> b) =>
    a.length == b.length &&
    a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

/// A failure translated once, where it happened.
///
/// [code] reads `module-layer-function-type`, so a support report points at
/// the exact call. The user-facing text is [message], rendered at display time.
abstract class SinewException implements Exception {
  /// Creates an exception for the guard's [module], [layer] and [function].
  const SinewException(this.module, this.layer, this.function, {this.cause});

  /// The feature module, such as `ORD`.
  final String module;

  /// The layer the failure was translated in.
  final ExceptionLayer layer;

  /// The function, such as `PO` for "place order".
  final String function;

  /// The original error, for crash reports. Never shown to users.
  final Object? cause;

  /// The short type code, such as `NIC`.
  String get typeCode;

  /// Who provides the user-facing text.
  ErrorMessage get message;

  /// Whether retrying the same call may succeed.
  bool get retryable => false;

  /// `module-layer-function-type`, such as `ORD-R-PO-NIC`.
  String get code => '$module-${layer.code}-$function-$typeCode';

  @override
  String toString() => '$runtimeType($code): ${message.text}';
}

/// Thrown by an object envelope whose payload is absent.
///
/// A plain error, not a [SinewException]: the envelope doesn't know the
/// guard's module or function, so the guard's handler turns it into a
/// `ParseException`.
class EnvelopeDataMissing implements Exception {
  /// Creates the error.
  const EnvelopeDataMissing();

  @override
  String toString() => 'EnvelopeDataMissing: the envelope has no data';
}
