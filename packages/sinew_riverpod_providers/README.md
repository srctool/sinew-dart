# sinew_riverpod_providers

[![pub package](https://img.shields.io/pub/v/sinew_riverpod_providers.svg)](https://pub.dev/packages/sinew_riverpod_providers)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**Ready Riverpod providers for Sinew's network and storage services, and `useNetworkChecker`.**

The wiring every Riverpod app writes by hand: the configured `Dio`, the token source, the stores and the connectivity checker, as providers you override only where your app differs.

## Features

- `sinewHttpProvider`, `tokenSourceProvider`, `refreshTokenStoreProvider` and `refreshCallProvider`
- `keyValueStoreProvider` and `secureStoreProvider`, and `SecureRefreshTokenStore` to keep the refresh token in the secure store
- `networkCheckerProvider` and `useNetworkChecker` to show connectivity in a widget

## Getting started

```sh
flutter pub add sinew_riverpod_providers
```

## Setup

Override the two app-specific providers once, and open the secure store before `runApp`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(overrides: [
    sinewConfigProvider.overrideWithValue(SinewConfig(baseUrl: 'https://api.example.com/v1/', locale: () => 'en')),
    refreshCallProvider.overrideWithValue((token) async => RefreshResult.from(await processApiCall(...))),
  ]);
  await container.read(secureStoreProvider.future);
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
```

Then API classes take `ref.watch(sinewHttpProvider)`, sign-in calls `ref.read(tokenSourceProvider).start(...)`, and a widget shows connectivity with `useNetworkChecker(ref.watch(networkCheckerProvider))`.

Security services aren't provided here (this package reaches `sinew_security` only through `sinew_storage`); add `FutureProvider((ref) => FieldCipher.create())` or `Provider((ref) => BiometricVault.create())` in the app.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_riverpod`](https://pub.dev/packages/sinew_riverpod)
- [`sinew_network`](https://pub.dev/packages/sinew_network)
- [`sinew_storage`](https://pub.dev/packages/sinew_storage)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_riverpod_providers](https://pub.dev/documentation/sinew_riverpod_providers/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
