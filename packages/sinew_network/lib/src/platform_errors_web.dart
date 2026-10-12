/// No socket errors on the web: the browser reports a failed `fetch` as Dio's
/// connection error.
bool isSocketFailure(Object error) => false;

/// No TLS errors on the web: the browser owns TLS.
bool isTlsFailure(Object error) => false;
