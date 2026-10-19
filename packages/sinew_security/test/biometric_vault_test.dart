import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_security/sinew_security.dart';
import 'package:sinew_security/src/biometric_vault.dart'
    show
        ChannelBiometricVault,
        UnavailableBiometricVault,
        biometricVaultChannel,
        debugRemoveInstallMarker,
        debugVaultState;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? Function(MethodCall) answer;

  setUp(() {
    calls = [];
    answer = (_) => null;
    messenger.setMockMethodCallHandler(biometricVaultChannel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(biometricVaultChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('create', skip: kIsWeb ? 'native platforms' : null, () {
    test('Android and iOS get the native vault, with the options', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final vault = BiometricVault.create(
          keyAlias: 'app.bio',
          clearOnReinstall: false,
        );
        expect(
          vault,
          isA<ChannelBiometricVault>()
              .having((v) => v.alias, 'alias', 'app.bio')
              .having((v) => v.clearOnReinstall, 'clearOnReinstall', false),
          reason: '$platform',
        );
      }
    });

    test('the defaults', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        BiometricVault.create(),
        isA<ChannelBiometricVault>()
            .having((v) => v.alias, 'alias', 'sinew.biometric')
            .having((v) => v.clearOnReinstall, 'clearOnReinstall', true),
      );
    });

    test('desktops get the unavailable vault', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          BiometricVault.create(),
          isA<UnavailableBiometricVault>(),
          reason: '$platform',
        );
      }
    });

    test('a blank alias is refused', () {
      expect(() => BiometricVault.create(keyAlias: ' '), throwsArgumentError);
    });
  });

  test('the web gets the unavailable vault', skip: !kIsWeb, () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(BiometricVault.create(), isA<UnavailableBiometricVault>());
  });

  group('the unavailable vault', () {
    const vault = UnavailableBiometricVault();

    test('offers nothing and fails every call', () async {
      expect(await vault.availability(), BiometricAvailability.unavailable);
      expect(await vault.isStored(), isFalse);
      expect(
        await vault.store('token', reason: 'r'),
        const BiometricFailed(BiometricFailure.unavailable),
      );
      expect(
        await vault.unlock(reason: 'r'),
        const BiometricFailed(BiometricFailure.unavailable),
      );
      await vault.disable();
      expect(calls, isEmpty);
    });
  });

  group('the native vault', () {
    final vault = ChannelBiometricVault('app.bio', clearOnReinstall: false);
    const options = {'alias': 'app.bio', 'clearOnReinstall': false};

    test('availability', () async {
      for (final value in BiometricAvailability.values) {
        answer = (_) => value.name;
        expect(await vault.availability(), value);
      }
      expect(calls.first.method, 'availability');
    });

    test('isStored sends the alias and options', () async {
      answer = (_) => true;
      expect(await vault.isStored(), isTrue);
      answer = (_) => false;
      expect(await vault.isStored(), isFalse);
      expect(calls.first.method, 'isStored');
      expect(calls.first.arguments, options);
    });

    test('store sends the secret and reason', () async {
      expect(await vault.store('token', reason: 'Turn on'), const Stored());
      expect(calls.single.method, 'store');
      expect(calls.single.arguments, {
        ...options,
        'secret': 'token',
        'reason': 'Turn on',
      });
    });

    test('a store failure carries its reason', () async {
      for (final reason in BiometricFailure.values) {
        answer = (_) => reason.name;
        expect(
          await vault.store('token', reason: 'Turn on'),
          BiometricFailed(reason),
        );
      }
    });

    test('unlock returns the secret', () async {
      answer = (_) => {'secret': 'token'};
      expect(await vault.unlock(reason: 'Sign in'), const Unlocked('token'));
      expect(calls.single.method, 'unlock');
      expect(calls.single.arguments, {...options, 'reason': 'Sign in'});
    });

    test('an unlock failure carries its reason', () async {
      for (final reason in BiometricFailure.values) {
        answer = (_) => {'failure': reason.name};
        expect(await vault.unlock(reason: 'Sign in'), BiometricFailed(reason));
      }
    });

    test('an unknown answer is an error', () async {
      answer = (_) => {'other': 'x'};
      await expectLater(vault.unlock(reason: 'r'), throwsStateError);
      answer = (_) => 'unknown';
      await expectLater(vault.store('t', reason: 'r'), throwsArgumentError);
      await expectLater(vault.availability(), throwsArgumentError);
    });

    test('a native error reaches the caller', () async {
      answer = (_) => throw PlatformException(code: 'sinew.biometric');
      await expectLater(
        vault.unlock(reason: 'r'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('disable sends the alias and options', () async {
      await vault.disable();
      expect(calls.single.method, 'disable');
      expect(calls.single.arguments, options);
    });
  });

  group('outcomes', () {
    test('compare by value', () {
      expect(const Unlocked('a'), const Unlocked('a'));
      expect(const Unlocked('a'), isNot(const Unlocked('b')));
      expect(const Unlocked('a').hashCode, const Unlocked('a').hashCode);
      expect(
        const BiometricFailed(BiometricFailure.cancelled),
        isNot(const BiometricFailed(BiometricFailure.lockedOut)),
      );
      expect(
        const BiometricFailed(BiometricFailure.cancelled).hashCode,
        const BiometricFailed(BiometricFailure.cancelled).hashCode,
      );
      expect(const Stored(), const Stored());
      expect(const Stored().hashCode, const Stored().hashCode);
    });

    test('an unlocked outcome never prints its secret', () {
      expect(
        const Unlocked('refresh-token').toString(),
        isNot(contains('refresh')),
      );
      expect(
        const BiometricFailed(BiometricFailure.lockedOut).toString(),
        'BiometricFailed(lockedOut)',
      );
    });

    test('a failure is both a store and an unlock outcome', () {
      String describe(BiometricUnlock outcome) => switch (outcome) {
        Unlocked(:final secret) => 'unlocked $secret',
        BiometricFailed(:final reason) => 'failed ${reason.name}',
      };
      String describeStore(BiometricStore outcome) => switch (outcome) {
        Stored() => 'stored',
        BiometricFailed(:final reason) => 'failed ${reason.name}',
      };
      const failed = BiometricFailed(BiometricFailure.invalidated);
      expect(describe(failed), 'failed invalidated');
      expect(describeStore(failed), 'failed invalidated');
      expect(describeStore(const Stored()), 'stored');
    });
  });

  group('device-test hooks', () {
    test(
      'debugVaultState and debugRemoveInstallMarker send the alias',
      () async {
        answer = (call) =>
            call.method == 'debugState' ? {'key': 'usable'} : null;
        expect(await debugVaultState('app.bio'), {'key': 'usable'});
        await debugRemoveInstallMarker('app.bio');
        expect(
          [for (final c in calls) c.method],
          ['debugState', 'debugRemoveInstallMarker'],
        );
        expect(
          [for (final c in calls) c.arguments],
          [
            {'alias': 'app.bio'},
            {'alias': 'app.bio'},
          ],
        );
      },
    );
  });
}
