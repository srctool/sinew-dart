import 'package:dio/dio.dart';

/// Does nothing in the browser: the browser owns TLS and can't be told to
/// trust only some authorities. See the IO version for what it does on
/// Android, iOS and the desktop.
void pinCertificateAuthorities(Dio dio, Iterable<String> authorities) {
  if (authorities.isEmpty) {
    throw ArgumentError.value(
      authorities,
      'authorities',
      'pins nothing: every request would fail',
    );
  }
}
