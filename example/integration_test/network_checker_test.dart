import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// ignore: implementation_imports
import 'package:sinew_network/src/network_checker.dart';

/// Set by `tool/network_checker_device_test.sh`, which switches the
/// emulator's Wi-Fi and data when the test prints a marker. A Flutter app
/// can't switch them itself.
const radios = bool.fromEnvironment('SINEW_SWITCH_RADIOS');

/// Waits for [checker] to report [status].
Future<void> until(
  NetworkChecker checker,
  NetworkStatus status,
  Duration timeout,
) async {
  if (checker.status == status) return;
  await checker.changes.firstWhere((s) => s == status).timeout(timeout);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connectivity_plus reports the device online', (_) async {
    final checker = NetworkChecker() as ConnectivityNetworkChecker;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!checker.reported && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(checker.reported, isTrue, reason: 'the platform never answered');
    expect(checker.isOnline, isTrue);
    await checker.dispose();
    await checker.dispose();
  });

  testWidgets(
    'follows Wi-Fi and data going off and on',
    (_) async {
      final checker = NetworkChecker();
      try {
        await until(checker, NetworkStatus.online, const Duration(seconds: 60));
        // ignore: avoid_print
        print('SINEW_RADIOS_OFF');
        await until(
          checker,
          NetworkStatus.offline,
          const Duration(seconds: 30),
        );
        expect(checker.isOnline, isFalse);
        // ignore: avoid_print
        print('SINEW_RADIOS_ON');
        await until(checker, NetworkStatus.online, const Duration(seconds: 60));
        expect(checker.isOnline, isTrue);
      } finally {
        await checker.dispose();
      }
    },
    skip: !radios || !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
