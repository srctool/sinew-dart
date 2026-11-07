import 'dart:convert';

/// What devtools hide before anything is stored. Redaction runs **when
/// recording**, so no screen, copy or export can show a secret.
///
/// A name is normalized before matching: lowercased, with `_`, `-` and `.`
/// removed, so `refreshToken`, `refresh_token` and `Refresh-Token` are all
/// `refreshtoken`. A field, query parameter or header is sensitive when its
/// normalized name contains one of [fieldParts] or equals one of
/// [exactFields]. A header is also sensitive when it's one of [headers].
/// Matching runs at every depth of a JSON body.
///
/// Apps extend [standard] with [extend] and can't remove a default, so a
/// custom list never drops `Authorization`.
final class Redaction {
  Redaction._({
    required Set<String> headers,
    required Set<String> fieldParts,
    required Set<String> exactFields,
    required this.mask,
    required this.maxBodyBytes,
  }) : headers = Set.unmodifiable(headers),
       fieldParts = Set.unmodifiable(fieldParts),
       exactFields = Set.unmodifiable(exactFields);

  /// The default body cap: 64 KB.
  static const defaultMaxBodyBytes = 64 * 1024;

  /// The shortest secret whose last 4 characters [maskSecret] shows.
  static const showTailFrom = 16;

  /// Sinew's rules. Extend them with [extend].
  static final Redaction standard = Redaction._(
    headers: {
      'Authorization',
      'Cookie',
      'Set-Cookie',
      'Proxy-Authorization',
    }.map(_normalize).toSet(),
    fieldParts: const {
      'password',
      'passwd',
      'token',
      'secret',
      'otp',
      'pin',
      'apikey',
      'credential',
      'signature',
    },
    exactFields: const {'code'},
    mask: '•••',
    maxBodyBytes: defaultMaxBodyBytes,
  );

  /// Header names, normalized, whose values are masked.
  final Set<String> headers;

  /// Parts of a normalized name that make it sensitive.
  final Set<String> fieldParts;

  /// Normalized names that are sensitive only as a whole: too short to match
  /// as a part.
  final Set<String> exactFields;

  /// What a sensitive value is replaced with.
  final String mask;

  /// A body is cut at this many bytes after redaction, keeping its real size.
  final int maxBodyBytes;

  /// These rules plus the additions. Nothing is removed. [maxBodyBytes]
  /// replaces the cap when given.
  Redaction extend({
    Iterable<String> headers = const [],
    Iterable<String> fieldParts = const [],
    Iterable<String> exactFields = const [],
    int? maxBodyBytes,
  }) {
    final cap = maxBodyBytes ?? this.maxBodyBytes;
    if (cap <= 0) {
      throw ArgumentError.value(cap, 'maxBodyBytes', 'must be positive');
    }
    return Redaction._(
      headers: {...this.headers, ...headers.map(_normalize)},
      fieldParts: {...this.fieldParts, ...fieldParts.map(_normalize)},
      exactFields: {...this.exactFields, ...exactFields.map(_normalize)},
      mask: mask,
      maxBodyBytes: cap,
    );
  }

  /// These rules plus the header [names]: a client's `defaultHeaders`, which
  /// carry API keys and device ids.
  Redaction withHeaders(Iterable<String> names) => extend(headers: names);

  /// Whether a field or query parameter called [name] is masked.
  bool isSensitive(String name) {
    final n = _normalize(name);
    return exactFields.contains(n) || fieldParts.any(n.contains);
  }

  /// Whether the header called [name] is masked.
  bool isSensitiveHeader(String name) =>
      headers.contains(_normalize(name)) || isSensitive(name);

  /// [headers] with every sensitive value masked, keeping the names and how
  /// many values each has.
  Map<String, List<String>> redactHeaders(Map<String, List<String>> headers) =>
      {
        for (final MapEntry(:key, :value) in headers.entries)
          key: isSensitiveHeader(key) ? [for (final _ in value) mask] : value,
      };

  /// Free text, such as an exception message or a stack trace, with the
  /// secrets it can recognize masked: a `Bearer` or `Basic` credential,
  /// `name=value` pairs (query strings, forms, log lines) and JSON
  /// `"name": value` pairs whose names are sensitive. Anything else is kept,
  /// so prefer the structured redactions where there are any.
  String redactText(String text) => text
      .replaceAllMapped(_credential, (m) => '${m[1]} $mask')
      .replaceAllMapped(
        _jsonPair,
        (m) => isSensitive(m[2]!) ? '${m[1]}"$mask"' : m[0]!,
      )
      .replaceAllMapped(
        _keyValue,
        (m) => isSensitive(m[1]!) ? '${m[1]}=$mask' : m[0]!,
      );

  static final _credential = RegExp(
    r'\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]+',
    caseSensitive: false,
  );

  /// `"name": value`: group 1 is everything before the value, group 2 the
  /// name.
  static final _jsonPair = RegExp(
    r'("([^"\\]+)"\s*:\s*)("(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?|true|false)',
  );

  static final _keyValue = RegExp(r'''([A-Za-z0-9_.\-]+)=([^&\s,;"'<>)\]]+)''');

  /// [url] with the value of every sensitive query parameter masked, and of
  /// every sensitive fragment parameter (an OAuth redirect's
  /// `#access_token=…`). The rest is unchanged.
  String redactUrl(String url) {
    final hash = url.indexOf('#');
    final base = hash < 0 ? url : url.substring(0, hash);
    final query = base.indexOf('?');
    final redacted = query < 0
        ? base
        : base.substring(0, query + 1) +
              _redactPairs(base.substring(query + 1));
    return hash < 0
        ? redacted
        : '$redacted#${_redactPairs(url.substring(hash + 1))}';
  }

  /// The body as it's stored. A JSON body (by its type, or text that starts
  /// like JSON) is walked and redacted, and masked whole if it doesn't parse.
  /// A form body is redacted pair by pair. Other text is kept. Images, files
  /// and anything that isn't UTF-8 keep only their type and size. Text is cut
  /// at [maxBodyBytes] after redaction.
  RecordedBody redactBody(List<int>? bytes, String? contentType) {
    if (bytes == null || bytes.isEmpty) return const NoBody();
    final size = bytes.length;
    final raw = contentType?.split(';').first.trim().toLowerCase();
    final type = raw == null || raw.isEmpty ? null : raw;
    final String text;
    if (type == null) {
      final sniffed = _decodeOrNull(bytes);
      if (sniffed == null) return BinaryBody(null, size);
      text = sniffed;
    } else if (_isText(type)) {
      text = utf8.decode(bytes, allowMalformed: true);
    } else {
      return BinaryBody(type, size);
    }
    final trimmed = text.trimLeft();
    final marks = _Marks();
    final String redacted;
    if (type == _form) {
      redacted = _redactPairs(text, marks);
    } else if ((type != null && _isJson(type)) ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      redacted = _redactJson(text, marks);
    } else {
      redacted = text;
    }
    return _cut(redacted, size, masked: marks.masked);
  }

  /// A stored secret as the Secure Store page shows it:
  /// `•••• 9f2c (412 chars)`. The last 4 characters tell two tokens apart. A
  /// secret shorter than [showTailFrom] characters (a PIN, a one-time code)
  /// shows only its length, since 4 of its characters would give most of it
  /// away.
  static String maskSecret(String value) {
    final length = value.length == 1 ? '1 char' : '${value.length} chars';
    return value.length >= showTailFrom
        ? '•••• ${value.substring(value.length - 4)} ($length)'
        : '•••• ($length)';
  }

  String _redactJson(String text, _Marks marks) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      marks.masked = true;
      return mask; // can't be walked, so nothing in it can be kept
    }
    return jsonEncode(_walk(decoded, marks));
  }

  Object? _walk(Object? value, _Marks marks) => switch (value) {
    final Map<String, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        key: isSensitive(key) ? marks.hide(mask) : _walk(value, marks),
    },
    final List<Object?> list => [for (final item in list) _walk(item, marks)],
    _ => value,
  };

  String _redactPairs(String pairs, [_Marks? marks]) => pairs
      .split('&')
      .map((pair) {
        final eq = pair.indexOf('=');
        if (eq < 0 || !isSensitive(_decodeName(pair.substring(0, eq)))) {
          return pair;
        }
        marks?.masked = true;
        return '${pair.substring(0, eq + 1)}$mask';
      })
      .join('&');

  TextBody _cut(String text, int size, {required bool masked}) {
    final encoded = utf8.encode(text);
    if (encoded.length <= maxBodyBytes) {
      return TextBody(text, size: size, truncated: false, masked: masked);
    }
    var end = maxBodyBytes;
    // Back to the start of a character.
    while (end > 0 && (encoded[end] & 0xC0) == 0x80) {
      end--;
    }
    return TextBody(
      utf8.decode(encoded.sublist(0, end)),
      size: size,
      truncated: true,
      masked: masked,
    );
  }

  static const _form = 'application/x-www-form-urlencoded';

  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp('[_.-]'), '');

  static bool _isJson(String type) =>
      type == 'application/json' || type.endsWith('+json');

  static bool _isText(String type) =>
      type.startsWith('text/') ||
      _isJson(type) ||
      type == _form ||
      type.endsWith('+xml') ||
      const {
        'application/xml',
        'application/javascript',
        'application/graphql',
        'application/x-ndjson',
      }.contains(type);

  static String? _decodeOrNull(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.contains('\u0000') ? null : text;
    } on FormatException {
      return null;
    }
  }

  /// A query or form name, percent-decoded, so `new%5Fpassword` matches like
  /// `new_password`.
  static String _decodeName(String raw) {
    try {
      return Uri.decodeQueryComponent(raw);
    } on ArgumentError {
      return raw;
    } on FormatException {
      return raw;
    }
  }
}

/// A request or response body as devtools store it, after
/// [Redaction.redactBody].
sealed class RecordedBody {
  const RecordedBody();
}

/// No body.
final class NoBody extends RecordedBody {
  /// No body.
  const NoBody();

  @override
  bool operator ==(Object other) => other is NoBody;

  @override
  int get hashCode => (NoBody).hashCode;

  @override
  String toString() => 'NoBody()';
}

/// Whether redacting has hidden anything yet: a body with a hidden secret
/// can't be replayed.
final class _Marks {
  bool masked = false;

  String hide(String mask) {
    masked = true;
    return mask;
  }
}

/// Redacted text, cut at the cap when [truncated]. [size] is the body's real
/// size in bytes. [masked] says whether anything in it was hidden, so a
/// request whose body lost a secret is never replayed.
final class TextBody extends RecordedBody {
  /// Redacted text, cut at the cap when [truncated].
  const TextBody(
    this.text, {
    required this.size,
    required this.truncated,
    this.masked = false,
  });

  /// The redacted text.
  final String text;

  /// The body's real size in bytes.
  final int size;

  /// Whether [text] was cut at the cap.
  final bool truncated;

  /// Whether anything in the body was hidden.
  final bool masked;

  @override
  bool operator ==(Object other) =>
      other is TextBody &&
      other.text == text &&
      other.size == size &&
      other.truncated == truncated &&
      other.masked == masked;

  @override
  int get hashCode => Object.hash(text, size, truncated, masked);

  @override
  String toString() =>
      'TextBody(${text.length} chars, size: $size, truncated: $truncated, '
      'masked: $masked)';
}

/// A binary body: only its type and its size in bytes are kept.
final class BinaryBody extends RecordedBody {
  /// A binary body of [contentType] and [size] bytes.
  const BinaryBody(this.contentType, this.size);

  /// The body's content type, without parameters, if it had one.
  final String? contentType;

  /// The body's size in bytes.
  final int size;

  @override
  bool operator ==(Object other) =>
      other is BinaryBody &&
      other.contentType == contentType &&
      other.size == size;

  @override
  int get hashCode => Object.hash(contentType, size);

  @override
  String toString() => 'BinaryBody($contentType, $size)';
}
