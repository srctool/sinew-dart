// ignore_for_file: avoid_print

import 'package:riverpod/riverpod.dart';
import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:sinew_riverpod_providers/sinew_riverpod_providers.dart';

final class WelcomeService extends AppService {
  WelcomeService() : super(ServiceLifetime.app);

  @override
  void listen() => print('listening');
}

Future<void> main() async {
  // region app-services-provider
  // The app lists its services once; reading the host starts the app services.
  final container = ProviderContainer(
    overrides: [
      appServicesProvider.overrideWithValue([WelcomeService()]),
    ],
  );
  final host = container.read(appServiceHostProvider);

  // The session owner starts the session services after sign-in and stops them at sign-out.
  await host.startSession();
  await host.stopSession();
  // endregion

  container.dispose();
}
