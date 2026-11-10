# sinew_network

[![pub package](https://img.shields.io/pub/v/sinew_network.svg)](https://pub.dev/packages/sinew_network)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**`SinewHttp` (Dio): the auth layer, `processApiCall`, retry, polling and `NetworkChecker`.**

An HTTP client that handles what every app rewrites: attaching the token only to your backend, refreshing it once for any number of concurrent 401s, mapping responses to typed failures, and retrying and polling with backoff. Use the preset, or add only the interceptors you need to your own `Dio`.

## Features

- `SinewHttp.dio`: a `Dio` with timeouts, headers, auth, error bodies and logging from one `SinewConfig`
- `SinewAuthInterceptor`: the token goes only to `baseUrl`'s host, outside the anonymous paths, with a single-flight refresh through `TokenSource` and `SessionTokenSource`
- `processApiCall` and `processOptionalApiCall`: map an `Envelope` to a `Result` and every status to a typed `SinewException`
- `retryWithBackoff` and `poll`, `NetworkChecker`, `pinCertificateAuthorities`, and `SinewHttpHooks` for the devtools

## Getting started

```sh
flutter pub add sinew_network
```

## Usage

```dart
final config = SinewConfig(
  baseUrl: 'https://api.example.com/v1',
  locale: () => 'en',
  anonymousPaths: {'/auth/login'},
);
final dio = SinewHttp.dio(config, tokenSource);

// In a repository: any failure becomes a typed SinewException.
Future<Result<Order>> cancel(String id) =>
    processApiCall('ORD', 'CANCEL', () => api.cancel(id));
```

API classes use paths relative to `baseUrl` (`get('orders')`), since a leading `/` would replace its own path. On sign-out, call `SinewHttp.resetAuth(dio)` and `tokenSource.clear()`.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_exception`](https://pub.dev/packages/sinew_exception)
- [`sinew_models`](https://pub.dev/packages/sinew_models)
- [`sinew_riverpod_providers`](https://pub.dev/packages/sinew_riverpod_providers)
- [`sinew_devtools`](https://pub.dev/packages/sinew_devtools)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_network](https://pub.dev/documentation/sinew_network/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
