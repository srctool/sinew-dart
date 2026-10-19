import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinew_security/sinew_security.dart';
// ignore: implementation_imports
import 'package:sinew_security/src/biometric_vault.dart'
    show debugRemoveInstallMarker, debugVaultState;

/// Set by `tool/biometric_vault_device_test.sh`, which answers the prompts the
/// tests ask for: without it, a prompt would wait forever.
const biometrics = bool.fromEnvironment('SINEW_BIOMETRICS');

/// Also set by the script with `--enroll`: an Android test enrolls another
/// finger in Settings.
const enroll = bool.fromEnvironment('SINEW_ENROLL');

const alias = 'sinew.test.biometric';

/// Asks the script to act on the next prompt: on Android `TOUCH <finger>` (1
/// is enrolled, 2 isn't), `BACK` or `ENROLL`; on iOS `FACE match`.
void ask(String action) {
  // ignore: avoid_print
  print('SINEW_BIOMETRIC $action');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final skip = biometrics ? null : 'run by tool/biometric_vault_device_test.sh';

  group('Android', skip: Platform.isAndroid ? skip : 'Android only', () {
    final vault = BiometricVault.create(keyAlias: alias);

    setUp(vault.disable);
    tearDown(vault.disable);

    testWidgets('an enrolled finger makes it available', (_) async {
      expect(await vault.availability(), BiometricAvailability.available);
    });

    testWidgets('a stored secret unlocks with the enrolled finger', (_) async {
      expect(await vault.isStored(), isFalse);
      ask('TOUCH 1');
      expect(
        await vault.store(
          'refresh-token',
          reason: 'Turn on fingerprint sign-in',
        ),
        const Stored(),
      );
      expect(await vault.isStored(), isTrue);
      ask('TOUCH 1');
      expect(
        await vault.unlock(reason: 'Sign in'),
        const Unlocked('refresh-token'),
      );
    });

    testWidgets('another finger releases nothing, and Back cancels', (_) async {
      ask('TOUCH 1');
      expect(
        await vault.store(
          'refresh-token',
          reason: 'Turn on fingerprint sign-in',
        ),
        const Stored(),
      );
      ask('TOUCH 2'); // not enrolled: the prompt stays up
      ask('BACK');
      expect(
        await vault.unlock(reason: 'Sign in'),
        const BiometricFailed(BiometricFailure.cancelled),
      );
      expect(await vault.isStored(), isTrue);
    });

    testWidgets('cancelling the store leaves nothing stored', (_) async {
      ask('BACK');
      expect(
        await vault.store(
          'refresh-token',
          reason: 'Turn on fingerprint sign-in',
        ),
        const BiometricFailed(BiometricFailure.cancelled),
      );
      expect(await vault.isStored(), isFalse);
      expect(await debugVaultState(alias), {'key': 'missing'});
    });

    testWidgets('disable deletes the secret and its key', (_) async {
      ask('TOUCH 1');
      expect(
        await vault.store(
          'refresh-token',
          reason: 'Turn on fingerprint sign-in',
        ),
        const Stored(),
      );
      expect(await debugVaultState(alias), {'key': 'usable'});
      await vault.disable();
      expect(await vault.isStored(), isFalse);
      expect(await debugVaultState(alias), {'key': 'missing'});
      expect(
        await vault.unlock(reason: 'Sign in'),
        const BiometricFailed(BiometricFailure.invalidated),
      );
    });

    testWidgets(
      'enrolling another finger invalidates the secret',
      skip: !enroll,
      (_) async {
        ask('TOUCH 1');
        expect(
          await vault.store(
            'refresh-token',
            reason: 'Turn on fingerprint sign-in',
          ),
          const Stored(),
        );
        ask('ENROLL');
        var waited = 0;
        while ((await debugVaultState(alias))['key'] == 'usable' &&
            waited++ < 300) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(await debugVaultState(alias), {'key': 'invalidated'});
        // No prompt: the invalidated key fails before one would show.
        expect(
          await vault.unlock(reason: 'Sign in'),
          const BiometricFailed(BiometricFailure.invalidated),
        );
        expect(await vault.isStored(), isFalse);
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });

  // The simulator stores the item with its biometric access control but
  // doesn't enforce it (no Secure Enclave): a read succeeds without a match. So
  // these tests check the item's protection; that no match releases nothing,
  // and that a new enrollment invalidates it, can only be shown on a device.
  group('iOS', skip: Platform.isIOS ? skip : 'iOS only', () {
    BiometricVault vault({bool clearOnReinstall = true}) =>
        BiometricVault.create(
          keyAlias: alias,
          clearOnReinstall: clearOnReinstall,
        );

    setUp(() => vault().disable());
    tearDown(() => vault().disable());

    testWidgets('Face ID is available', (_) async {
      expect(await vault().availability(), BiometricAvailability.available);
    });

    testWidgets('a stored secret unlocks after a match', (_) async {
      final v = vault();
      expect(await v.isStored(), isFalse);
      // No prompt on iOS.
      expect(
        await v.store('refresh-token', reason: 'Turn on Face ID'),
        const Stored(),
      );
      expect(await v.isStored(), isTrue);
      ask('FACE match');
      expect(
        await v.unlock(reason: 'Sign in'),
        const Unlocked('refresh-token'),
      );
    });

    testWidgets('storing again replaces the secret', (_) async {
      final v = vault();
      await v.store('first-token', reason: 'Turn on Face ID');
      await v.store('second-token', reason: 'Turn on Face ID');
      ask('FACE match');
      expect(await v.unlock(reason: 'Sign in'), const Unlocked('second-token'));
    });

    testWidgets(
      'the item is protected by the current biometrics, on this device only',
      (_) async {
        await vault().store('refresh-token', reason: 'Turn on Face ID');
        final state = await debugVaultState(alias);
        // kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        expect(state['pdmn'], 'akpu');
        // biometryCurrentSet
        expect(state['accc'], contains('cbio'));
      },
    );

    testWidgets('disable deletes the secret', (_) async {
      final v = vault();
      await v.store('refresh-token', reason: 'Turn on Face ID');
      await v.disable();
      expect(await v.isStored(), isFalse);
      expect(await debugVaultState(alias), isEmpty);
      expect(
        await v.unlock(reason: 'Sign in'),
        const BiometricFailed(BiometricFailure.invalidated),
      );
    });

    testWidgets('a reinstall leaves no vault item', (_) async {
      await vault().store('refresh-token', reason: 'Turn on Face ID');
      await debugRemoveInstallMarker(alias); // what an uninstall does
      expect(await vault().isStored(), isFalse);
      expect(await debugVaultState(alias), isEmpty);
    });

    testWidgets('without clearOnReinstall the secret survives', (_) async {
      await vault().store('refresh-token', reason: 'Turn on Face ID');
      await debugRemoveInstallMarker(alias);
      expect(await vault(clearOnReinstall: false).isStored(), isTrue);
    });
  });
}
