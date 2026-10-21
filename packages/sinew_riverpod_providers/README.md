# sinew_riverpod_providers

Ready Riverpod providers for Sinew's network and storage services.

Part of [Sinew](https://github.com/srctool/sinew). Status: milestone S5.

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
