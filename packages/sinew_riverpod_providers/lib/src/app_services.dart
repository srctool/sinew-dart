import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:sinew_presentation/sinew_presentation.dart';

/// The app's services, in the order they start. **Override it** in the app's
/// `ProviderScope`:
///
/// ```dart
/// ProviderScope(overrides: [
///   appServicesProvider.overrideWith((ref) => [BillingService(ref.watch(...))]),
/// ], child: const App())
/// ```
final appServicesProvider = Provider<List<AppService>>(
  (ref) => throw StateError(
    'appServicesProvider has no value: override it in your ProviderScope, '
    'for example appServicesProvider.overrideWithValue([...]).',
  ),
  name: 'appServicesProvider',
);

/// The [AppServiceHost] for [appServicesProvider]. **Reading it starts the app
/// services** (`startApp`), so read it once at startup, after the providers the
/// services use are ready. The session owner calls `startSession` after
/// sign-in and `stopSession` after sign-out. Disposing the container destroys
/// every service.
final appServiceHostProvider = Provider<AppServiceHost>((ref) {
  final host = AppServiceHost(ref.watch(appServicesProvider));
  ref.onDispose(() => unawaited(host.stopAll()));
  unawaited(host.startApp());
  return host;
}, name: 'appServiceHostProvider');
