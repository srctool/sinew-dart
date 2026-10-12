import 'error_body.dart';

/// What an app configures for one backend. Build one client per backend from
/// it, not one per endpoint.
///
/// [locale] and [defaultHeaders] are read on every request, so a language
/// switch or a new device id applies to the next request without rebuilding
/// the client. Every header name in [defaultHeaders] is redacted by devtools.
final class SinewConfig {
  /// Creates a config. Throws an [ArgumentError] for a blank [baseUrl], a
  /// timeout that isn't positive, or an anonymous path without a leading `/`.
  SinewConfig({
    required this.baseUrl,
    required this.locale,
    this.defaultHeaders,
    this.connectTimeout = const Duration(seconds: 15),
    this.readTimeout = const Duration(seconds: 30),
    this.writeTimeout = const Duration(seconds: 60),
    this.logHttp = false,
    this.anonymousPaths = const {},
    this.errorBodyReader = ErrorBodyReader.standard,
  }) {
    if (baseUrl.trim().isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'is blank');
    }
    for (final (name, value) in [
      ('connectTimeout', connectTimeout),
      ('readTimeout', readTimeout),
      ('writeTimeout', writeTimeout),
    ]) {
      if (value <= Duration.zero) {
        throw ArgumentError.value(value, name, 'must be positive');
      }
    }
    final relative = anonymousPaths.where((p) => !p.startsWith('/')).toList();
    if (relative.isNotEmpty) {
      throw ArgumentError.value(
        relative,
        'anonymousPaths',
        "must start with '/'",
      );
    }
  }

  /// The backend's base URL, from the app's build configuration. Its host is
  /// the only host that receives the user's token.
  final String baseUrl;

  /// The language for `Accept-Language`, read on every request.
  final String Function() locale;

  /// Headers for every request (app version, API key, device id), read on
  /// every request.
  final Map<String, String> Function()? defaultHeaders;

  /// The deadline to open a connection.
  final Duration connectTimeout;

  /// The deadline for reads (`GET`, `HEAD`).
  final Duration readTimeout;

  /// The deadline for writes (`POST`, `PUT`, `PATCH`, `DELETE`), longer
  /// because repeating one is costly.
  final Duration writeTimeout;

  /// Whether to log method, host, path, status and duration. Debug builds
  /// only: never on in release.
  final bool logHttp;

  /// Paths that never get a token and never trigger a refresh (sign-in,
  /// register, OTP, password reset, the refresh call), matched exactly,
  /// relative to [baseUrl]'s path: with `https://api.example.com/v1`,
  /// `/auth/login` matches `/v1/auth/login`.
  final Set<String> anonymousPaths;

  /// How this backend's error bodies read.
  final ErrorBodyReader errorBodyReader;
}
