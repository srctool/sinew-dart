# sinew_testing

[![pub package](https://img.shields.io/pub/v/sinew_testing.svg)](https://pub.dev/packages/sinew_testing)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**Fakes and test helpers for apps built on Sinew. A dev dependency only.**

A fake for every Sinew interface, so a test of your repository or notifier runs without a device, a network or a platform plugin, and fails the way the real thing fails.

## Features

- `mockHttp`: a real `Dio` on a mock adapter, with routes and recorded requests
- `ControlledFetch`: answer a pager's calls by hand, to test loading, retry and refresh in order
- `FakeKeyValueStore`, `FakeSecureStore`, `FakeFieldCipher`, `FakeBiometricVault`, `FakeTokenSource`, `FakeRefreshTokenStore`, `FakeNetworkChecker` and `FakeLocalizer`
- `RecordingCrashReporter` and `installRecordingReporter`, to assert what was reported
- `fixture` to load a JSON fixture, and `diskFullError` and `platformStorageError` for storage failures

## Getting started

```sh
flutter pub add --dev sinew_testing
```

## Usage

Test a repository against a mock backend:

```dart
test('orders load', () async {
  final http = mockHttp((routes) => routes
      .on('GET', '/v1/orders').respond(200, body: fixture('orders_page.json')));
  final result = await OrderRepository(OrderApi(http.dio)).page(1);
  expect(http.requests.single.uri.path, '/v1/orders');
});
```

Hold a pager's calls open to test every state of a list:

```dart
final fetch = controlledFetch<Order>();
final pager = Pager<Order>.offset(fetch.call);
```

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_paging`](https://pub.dev/packages/sinew_paging)
- [`sinew_network`](https://pub.dev/packages/sinew_network)
- [`sinew_storage`](https://pub.dev/packages/sinew_storage)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_testing](https://pub.dev/documentation/sinew_testing/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
