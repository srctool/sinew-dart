import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_storage/sinew_storage.dart';

import 'secure_refresh_token_store.dart';

/// The backend's config. **Override it** in the app's `ProviderScope`:
///
/// ```dart
/// ProviderScope(overrides: [
///   sinewConfigProvider.overrideWithValue(SinewConfig(baseUrl: 'https://api.example.com/v1/', locale: () => 'en')),
///   refreshCallProvider.overrideWithValue((token) async => RefreshResult.from(await processApiCall(...))),
/// ], child: const App())
/// ```
final sinewConfigProvider = Provider<SinewConfig>(
  (ref) => throw _missingOverride('sinewConfigProvider'),
  name: 'sinewConfigProvider',
);

/// The app's backend call that trades a refresh token for a new pair, on a
/// `Dio` without the auth interceptor. **Override it** in the app's
/// `ProviderScope`, with [sinewConfigProvider].
final refreshCallProvider = Provider<RefreshCall>(
  (ref) => throw _missingOverride('refreshCallProvider'),
  name: 'refreshCallProvider',
);

/// The app's secrets, opened once. Await `ref.read(secureStoreProvider.future)`
/// at startup, before `runApp`: the providers built on it read it
/// synchronously.
final secureStoreProvider = FutureProvider<SecureStore>(
  (ref) => SecureStore.create(),
  name: 'secureStoreProvider',
);

/// The app's plain preferences.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => KeyValueStore.create(),
  name: 'keyValueStoreProvider',
);

/// The session's refresh token, in the [secureStoreProvider] store.
final refreshTokenStoreProvider = Provider<RefreshTokenStore>(
  (ref) => SecureRefreshTokenStore(
    ref.watch(secureStoreProvider).value ??
        (throw _notAwaited('secureStoreProvider')),
  ),
  name: 'refreshTokenStoreProvider',
);

/// The session: the access token in memory, the refresh token in the secure
/// store, refreshed through [refreshCallProvider]. Sign in with
/// `ref.read(tokenSourceProvider).start(...)`.
final tokenSourceProvider = Provider<SessionTokenSource>(
  (ref) => SessionTokenSource(
    ref.watch(refreshTokenStoreProvider),
    ref.watch(refreshCallProvider),
  ),
  name: 'tokenSourceProvider',
);

/// The Sinew `Dio` for the backend, authenticated by [tokenSourceProvider].
final sinewHttpProvider = Provider<Dio>(
  (ref) => SinewHttp.dio(
    ref.watch(sinewConfigProvider),
    ref.watch(tokenSourceProvider),
  ),
  name: 'sinewHttpProvider',
);

/// The device's connectivity, for the UI, disposed with the container.
final networkCheckerProvider = Provider<NetworkChecker>((ref) {
  final checker = NetworkChecker();
  ref.onDispose(checker.dispose);
  return checker;
}, name: 'networkCheckerProvider');

StateError _missingOverride(String provider) => StateError(
  '$provider has no value: override it in your ProviderScope, '
  'for example $provider.overrideWithValue(...).',
);

StateError _notAwaited(String provider) => StateError(
  '$provider has no value yet: await ref.read($provider.future) once at '
  'startup, before runApp.',
);
