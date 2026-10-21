/// Ready Riverpod providers for Sinew's network and storage services, and
/// `useNetworkChecker`.
///
/// The app overrides [sinewConfigProvider] and [refreshCallProvider] once,
/// and awaits [secureStoreProvider] at startup. Security services aren't
/// here (this package reaches `sinew_security` only through storage): an app
/// that needs a `FieldCipher` adds
/// `final fieldCipherProvider = FutureProvider((ref) => FieldCipher.create());`.
library;

import 'src/providers.dart';

export 'src/providers.dart';
export 'src/secure_refresh_token_store.dart';
export 'src/use_network_checker.dart';
