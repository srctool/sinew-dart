import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Pins [dio] to the certificate authorities in [authorities] (PEM): it
/// trusts only those, and no system root. A server whose chain doesn't lead
/// to one of them fails **during the TLS handshake**, before any header,
/// token or body is sent. Dio's `validateCertificate` runs only after the
/// response, which is too late for a token.
///
/// It pins authorities, not a leaf key: `dart:io` can't check a leaf key
/// before sending. Pin the authority that issues your certificates, plus a
/// backup, so a renewal doesn't lock users out.
///
/// The failed handshake reaches `processApiCall` as a TLS failure: a reported
/// `UnexpectedException`, never "offline". In the browser, this does nothing:
/// the browser owns TLS.
///
/// ```dart
/// pinCertificateAuthorities(dio, [await rootBundle.loadString('assets/ca.pem')]);
/// ```
void pinCertificateAuthorities(Dio dio, Iterable<String> authorities) {
  final pems = authorities.toList();
  if (pems.isEmpty) {
    throw ArgumentError.value(
      pems,
      'authorities',
      'pins nothing: every request would fail',
    );
  }
  final context = SecurityContext(withTrustedRoots: false);
  for (final pem in pems) {
    context.setTrustedCertificatesBytes(utf8.encode(pem));
  }
  HttpClient create() => HttpClient(context: context);
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = create;
  } else {
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: create);
  }
}
