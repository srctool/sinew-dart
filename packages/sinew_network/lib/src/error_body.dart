import 'dart:convert';

/// What a backend's error body says: a message to show, and per-field
/// validation messages.
final class ErrorBody {
  /// Creates an error body.
  const ErrorBody({this.message, this.fieldErrors});

  /// The backend's text for the user, never blank.
  final String? message;

  /// Validation messages by field name, never empty.
  final Map<String, List<String>>? fieldErrors;

  @override
  bool operator ==(Object other) =>
      other is ErrorBody &&
      other.message == message &&
      _sameFields(other.fieldErrors, fieldErrors);

  @override
  int get hashCode => Object.hash(
    message,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in (fieldErrors ?? const {}).entries)
        Object.hash(key, Object.hashAll(value)),
    ]),
  );

  @override
  String toString() => 'ErrorBody($message, $fieldErrors)';
}

bool _sameFields(Map<String, List<String>>? a, Map<String, List<String>>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    final other = b[key];
    if (other == null || other.length != value.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (other[i] != value[i]) return false;
    }
  }
  return true;
}

/// Reads a backend's error body. Each client runs its own reader on every
/// failed response, and the guard turns a readable [ErrorBody.message] into a
/// server message, and [ErrorBody.fieldErrors] into a `ValidationException`.
///
/// A backend with another error shape supplies its own reader in
/// `SinewConfig`.
abstract interface class ErrorBodyReader {
  /// The error body of a [status] response, or `null` when there's nothing
  /// readable. [body] is what Dio decoded: usually a `Map`, sometimes a
  /// `String`.
  ErrorBody? read(int status, Object? body);

  /// Reads a JSON object's `message` (a string) and `errors`
  /// (`{"field": ["message", …]}`, or a single string per field). Returns
  /// `null` for an empty, HTML or non-JSON body, or an object with neither. A
  /// blank message, an empty list or a non-string entry is ignored, so it
  /// never reaches the user.
  static const ErrorBodyReader standard = _StandardErrorBodyReader();

  /// A reader from a function: `ErrorBodyReader.from((status, body) => …)`.
  const factory ErrorBodyReader.from(
    ErrorBody? Function(int status, Object? body) read,
  ) = _FunctionErrorBodyReader;
}

final class _FunctionErrorBodyReader implements ErrorBodyReader {
  const _FunctionErrorBodyReader(this._read);

  final ErrorBody? Function(int status, Object? body) _read;

  @override
  ErrorBody? read(int status, Object? body) => _read(status, body);
}

final class _StandardErrorBodyReader implements ErrorBodyReader {
  const _StandardErrorBodyReader();

  @override
  ErrorBody? read(int status, Object? body) {
    final root = _object(body);
    if (root == null) return null;
    final message = _text(root['message']);
    final errors = root['errors'];
    Map<String, List<String>>? fieldErrors;
    if (errors is Map) {
      fieldErrors = {
        for (final MapEntry(:key, :value) in errors.entries)
          if (key is String && _messages(value).isNotEmpty)
            key: _messages(value),
      };
      if (fieldErrors.isEmpty) fieldErrors = null;
    }
    if (message == null && fieldErrors == null) return null;
    return ErrorBody(message: message, fieldErrors: fieldErrors);
  }

  static Map<Object?, Object?>? _object(Object? body) {
    if (body is Map) return body;
    if (body is! String || body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static List<String> _messages(Object? value) => switch (value) {
    final List<Object?> list => [for (final item in list) ?_text(item)],
    _ => [?_text(value)],
  };
}
