import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_security/sinew_security.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  group('FakeFieldCipher', () {
    test('stores a readable marked form', () async {
      final cipher = FakeFieldCipher();
      expect(await cipher.encrypt('Alice'), 'enc(Alice)');
      expect(
        await cipher.encrypt('Alice', context: 'customers.name:1'),
        'enc[customers.name:1](Alice)',
      );
      expect(await cipher.decrypt('enc(Alice)'), 'Alice');
      expect(await cipher.decrypt(await cipher.encrypt('')), '');
      expect(
        await cipher.decrypt(
          await cipher.encrypt('a)b', context: 'ctx'),
          context: 'ctx',
        ),
        'a)b',
      );
    });

    test('refuses another context or an unmarked value', () async {
      final cipher = FakeFieldCipher();
      final sealed = await cipher.encrypt('Alice', context: 'customers.name:1');
      for (final attempt in [
        () => cipher.decrypt(sealed, context: 'customers.name:2'),
        () => cipher.decrypt(sealed),
        () => cipher.decrypt('Alice'),
        () => cipher.decrypt('enc(Alice'),
      ]) {
        await expectLater(attempt(), throwsA(isA<DecryptionFailed>()));
      }
    });

    test('fails the next decrypt once', () async {
      final cipher = FakeFieldCipher();
      final sealed = await cipher.encrypt('Alice');
      cipher.failNextDecrypt();
      await expectLater(
        cipher.decrypt(sealed),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(await cipher.decrypt(sealed), 'Alice');
    });

    test('counts rotations', () async {
      final cipher = FakeFieldCipher();
      await cipher.rotateKey();
      await cipher.rotateKey();
      expect(cipher.rotations, 2);
    });
  });

  group('FakeBiometricVault', () {
    test('stores and unlocks, recording each prompt', () async {
      final vault = FakeBiometricVault();
      expect(await vault.isStored(), isFalse);
      expect(
        await vault.store('refresh-token', reason: 'Turn on'),
        const Stored(),
      );
      expect(await vault.isStored(), isTrue);
      expect(
        await vault.unlock(reason: 'Sign in'),
        const Unlocked('refresh-token'),
      );
      expect(vault.prompts, ['Turn on', 'Sign in']);
      expect(vault.storedSecret, 'refresh-token');
    });

    test(
      'reports the availability set, and fails without biometrics',
      () async {
        final vault = FakeBiometricVault(
          availabilityNow: BiometricAvailability.notEnrolled,
        );
        expect(await vault.availability(), BiometricAvailability.notEnrolled);
        expect(
          await vault.store('t', reason: 'Turn on'),
          const BiometricFailed(BiometricFailure.unavailable),
        );
        vault.availabilityNow = BiometricAvailability.available;
        await vault.store('t', reason: 'Turn on');
        vault.availabilityNow = BiometricAvailability.unavailable;
        expect(
          await vault.unlock(reason: 'Sign in'),
          const BiometricFailed(BiometricFailure.unavailable),
        );
        expect(vault.prompts, ['Turn on']);
      },
    );

    test('fails scripted stores and unlocks in order', () async {
      final vault = FakeBiometricVault()..nextStore(BiometricFailure.cancelled);
      expect(
        await vault.store('t', reason: 'Turn on'),
        const BiometricFailed(BiometricFailure.cancelled),
      );
      expect(await vault.isStored(), isFalse);
      await vault.store('t', reason: 'Turn on');
      vault
        ..nextUnlock(BiometricFailure.cancelled)
        ..nextUnlock(BiometricFailure.lockedOut);
      expect(
        await vault.unlock(reason: 'Sign in'),
        const BiometricFailed(BiometricFailure.cancelled),
      );
      expect(
        await vault.unlock(reason: 'Sign in'),
        const BiometricFailed(BiometricFailure.lockedOut),
      );
      expect(await vault.unlock(reason: 'Sign in'), const Unlocked('t'));
    });

    test('a failed store clears an earlier secret', () async {
      final vault = FakeBiometricVault();
      await vault.store('old', reason: 'Turn on');
      vault.nextStore(BiometricFailure.cancelled);
      await vault.store('new', reason: 'Turn on');
      expect(await vault.isStored(), isFalse);
    });

    test('nothing stored or invalidated unlocks as invalidated', () async {
      final vault = FakeBiometricVault();
      const invalidated = BiometricFailed(BiometricFailure.invalidated);
      expect(await vault.unlock(reason: 'Sign in'), invalidated);
      await vault.store('t', reason: 'Turn on');
      vault.invalidate();
      expect(await vault.unlock(reason: 'Sign in'), invalidated);
      await vault.store('t', reason: 'Turn on');
      await vault.disable();
      expect(await vault.isStored(), isFalse);
      expect(vault.prompts, ['Turn on', 'Turn on']);
    });
  });
}
