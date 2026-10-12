import 'dart:io';

/// A socket-level failure: no connection, DNS failure, refused or reset, or a
/// connection closed mid-response.
bool isSocketFailure(Object error) =>
    error is SocketException || error is HttpException;

/// A TLS or certificate failure, including a pinning mismatch: a security
/// event, never "offline".
bool isTlsFailure(Object error) => error is TlsException;
