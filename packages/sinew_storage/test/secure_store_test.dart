import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sinew_security/sinew_security.dart';
import 'package:sinew_storage/sinew_storage.dart';
import 'package:sinew_storage/src/secure_store.dart';

import 'secure_store_contract.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('contract', secureStoreContract);

  group('create', () {
    test('a blank namespace or one with a "." is refused', () async {
      for (final namespace in ['', ' ', 'a.b']) {
        await expectLater(
          SecureStore.create(namespace: namespace),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'namespace'),
          ),
          reason: '"$namespace"',
        );
      }
    });

    test('the values are in "<namespace>_secure", the key in '
        '"sinew.secure.<namespace>"', () async {
      final store = await SecureStore.create(namespace: 'session');
      await store.write('token', 'refresh-token');
      expect(
        await KeyValueStore.create(name: 'session_secure').getString('token'),
        isNotNull,
      );
      expect(
        await const FlutterSecureStorage().containsKey(
          key: 'sinew.secure.session',
        ),
        isTrue,
      );
      expect(store, isA<EncryptedSecureStore>());
    });

    test('the default namespace is "sinew"', () async {
      await (await SecureStore.create()).write('token', 'refresh-token');
      expect(
        await KeyValueStore.create(name: 'sinew_secure').getString('token'),
        isNotNull,
      );
    });
  });

  group('with a stand-in cipher', () {
    test('two namespaces sharing a cipher keep their values apart', () async {
      final shared = await FieldCipher.create(keyAlias: 'shared');
      final one = EncryptedSecureStore(
        'one',
        KeyValueStore.create(name: 'one_secure'),
        shared,
      );
      final two = EncryptedSecureStore(
        'two',
        KeyValueStore.create(name: 'two_secure'),
        shared,
      );
      await one.write('token', 'secret');
      await KeyValueStore.create(name: 'two_secure').setString(
        'token',
        (await KeyValueStore.create(name: 'one_secure').getString('token'))!,
      );
      expect(await two.read('token'), isNull);
      expect(await one.read('token'), 'secret');
    });

    test('a failed value replaced while it was decrypting is kept', () async {
      final cipher = GatedCipher();
      final values = KeyValueStore.create(name: 'gated_secure');
      final store = EncryptedSecureStore('gated', values, cipher);
      await values.setString('token', 'tampered');
      final reading = store.read('token'); // waits in decrypt
      await store.write('token', 'new');
      cipher.gate.complete();
      expect(await reading, isNull);
      expect(await store.read('token'), 'new');
    });

    test('the last write wins, whatever each one takes to encrypt', () async {
      final cipher = GatedCipher(slow: {'first'});
      final store = EncryptedSecureStore(
        'ordered',
        KeyValueStore.create(name: 'ordered_secure'),
        cipher,
      );
      final first = store.write('token', 'first');
      final second = store.write('token', 'second');
      await Future<void>.delayed(Duration.zero);
      cipher.gate.complete();
      await Future.wait([first, second]);
      expect(await store.read('token'), 'second');
    });
  });
}

/// A stand-in cipher: `ok:<plain>` decrypts, anything else fails once [gate]
/// completes; encrypting a value in [slow] also waits for [gate].
final class GatedCipher implements FieldCipher {
  GatedCipher({this.slow = const {}});

  final Set<String> slow;
  final gate = Completer<void>();

  @override
  Future<String> encrypt(String plain, {String context = ''}) async {
    if (slow.contains(plain)) await gate.future;
    return 'ok:$plain';
  }

  @override
  Future<String> decrypt(String cipher, {String context = ''}) async {
    if (cipher.startsWith('ok:')) return cipher.substring(3);
    await gate.future;
    throw const DecryptionFailed();
  }

  @override
  Future<void> rotateKey() async {}
}
