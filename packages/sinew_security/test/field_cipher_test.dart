import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_security/src/field_cipher.dart';
import 'package:sinew_security/src/key_store.dart';

/// A key store in memory. Two stores over one [values] map are the same storage
/// seen by two processes: each opens its own cipher.
final class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;
  int writes = 0;
  Object? readError;

  @override
  Future<String?> read(String key) async {
    if (readError case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

/// The test key, its id, and what each Kotlin library produced with it.
abstract final class Fixtures {
  static final key = Uint8List.fromList(
    List.generate(32, (i) => (i * 7 + 3) & 0xff),
  );
  static const keyId = 0x2A5F1C07;
  static const context = 'customers.displayName:42';
  static const plain = 'Alice Liddell';
  static const values = {
    'tink': 'ASpfHAcQPsYltGPhvCsrCl3urLaWqtwKoK2RanipnLLdg6sMJs6QTrFZtX2yZA==',
    'tink-android':
        'ASpfHAdbeYXYNPB5CXXihV07wWVBKxgGPd7gubrqt95F2RWGtmUffdm+y7oZOQ==',
    'cryptokit':
        'ASpfHAfET1L4ee0DQgysR9FAJoT22FGCV3ylj+HX3xUy1u/8jUxKlJpNkk7scg==',
    'webcrypto':
        'ASpfHAf3t12g9cCkTkjnMNkQ29RJWgnavJxU1adEh/b/U/V9oJEEXTQpgXswuQ==',
  };
}

Uint8List bytes(String cipher) => base64.decode(cipher);
int keyIdOf(String cipher) =>
    ByteData.sublistView(bytes(cipher), 1, 5).getUint32(0);

void main() {
  late MemoryKeyStore store;

  setUp(() => store = MemoryKeyStore());

  Future<FieldCipher> cipher() => openFieldCipher(store, 'test');

  group('contract', () {
    test('a value round-trips', () async {
      final c = await cipher();
      for (final plain in ['', 'Alice', 'Ä 😀 日本語', 'x' * 10000]) {
        for (final context in ['', 'customers.displayName:42']) {
          expect(
            await c.decrypt(
              await c.encrypt(plain, context: context),
              context: context,
            ),
            plain,
          );
        }
      }
    });

    test('two encryptions differ, with fresh nonces', () async {
      final c = await cipher();
      final values = [for (var i = 0; i < 50; i++) await c.encrypt('Alice')];
      final nonces = {
        for (final v in values) base64.encode(bytes(v).sublist(5, 17)),
      };
      expect(nonces, hasLength(50));
      expect(values.toSet(), hasLength(50));
    });

    test('every flipped byte fails', () async {
      final c = await cipher();
      final sealed = bytes(await c.encrypt('Alice', context: 'ctx'));
      for (var i = 0; i < sealed.length; i++) {
        final changed = Uint8List.fromList(sealed)..[i] ^= 0x01;
        await expectLater(
          c.decrypt(base64.encode(changed), context: 'ctx'),
          throwsA(isA<DecryptionFailed>()),
          reason: 'byte $i',
        );
      }
    });

    test('a wrong context fails', () async {
      final c = await cipher();
      final value = await c.encrypt(
        'Alice',
        context: 'customers.displayName:1',
      );
      await expectLater(
        c.decrypt(value, context: 'customers.displayName:2'),
        throwsA(isA<DecryptionFailed>()),
      );
      await expectLater(c.decrypt(value), throwsA(isA<DecryptionFailed>()));
    });

    test('the header carries the version and key id', () async {
      final c = await cipher();
      final first = await c.encrypt('Alice');
      expect(bytes(first)[0], 0x01);
      expect(bytes(first), hasLength(5 + 12 + 'Alice'.length + 16));
      expect(keyIdOf(first), keyIdOf(await c.encrypt('Bob')));
    });

    test('a value from before a rotation still decrypts', () async {
      final c = await cipher();
      final old = await c.encrypt('Alice');
      await c.rotateKey();
      final rotated = await c.encrypt('Bob');
      expect(keyIdOf(rotated), isNot(keyIdOf(old)));
      expect(await c.decrypt(old), 'Alice');
      expect(await c.decrypt(rotated), 'Bob');
    });

    test('a rotation uses new key material', () async {
      final c = await cipher();
      final old = bytes(await c.encrypt('Alice'));
      await c.rotateKey();
      final newId = keyIdOf(await c.encrypt('Bob'));
      final relabelled = Uint8List.fromList(old)
        ..buffer.asByteData().setUint32(1, newId);
      await expectLater(
        c.decrypt(base64.encode(relabelled)),
        throwsA(isA<DecryptionFailed>()),
      );
    });

    test('keys and rotations persist', () async {
      final c = await cipher();
      final old = await c.encrypt('Alice');
      await c.rotateKey();
      final rotated = await c.encrypt('Bob');
      final restarted = await openFieldCipher(
        MemoryKeyStore(store.values),
        'test',
      );
      expect(await restarted.decrypt(old), 'Alice');
      expect(await restarted.decrypt(rotated), 'Bob');
      expect(keyIdOf(await restarted.encrypt('Carol')), keyIdOf(rotated));
    });

    test('a malformed value fails', () async {
      final c = await cipher();
      final valid = bytes(await c.encrypt('Alice'));
      for (final value in [
        '',
        'not base64!',
        base64.encode(valid.sublist(0, 32)),
        base64.encode(Uint8List.fromList(valid)..[0] = 0),
      ]) {
        await expectLater(
          c.decrypt(value),
          throwsA(isA<DecryptionFailed>()),
          reason: value,
        );
      }
    });

    test("another key's value fails", () async {
      final c = await cipher();
      final foreign = await (await fixedKeyCipher(
        Fixtures.key,
        Fixtures.keyId,
      )).encrypt('Alice');
      await expectLater(c.decrypt(foreign), throwsA(isA<DecryptionFailed>()));
    });
  });

  group('the keyring', () {
    test('concurrent first opens make one key', () async {
      final ciphers = await Future.wait([
        for (var i = 0; i < 10; i++) cipher(),
      ]);
      expect(store.writes, 1);
      final value = await ciphers.first.encrypt('Alice');
      for (final c in ciphers) {
        expect(await c.decrypt(value), 'Alice');
      }
    });

    test('a stored value that is not a keyring is replaced', () async {
      store.values['test'] = 'not a keyring';
      final c = await cipher();
      expect(await c.decrypt(await c.encrypt('Alice')), 'Alice');
      expect(Keyring.decode(base64.decode(store.values['test']!)), isNotNull);
    });

    test('a failure to read the store is thrown, keeps the key, and can be retried', () async {
      store.values['test'] = 'kept';
      store.readError = StateError('keychain locked');
      await expectLater(cipher(), throwsStateError);
      expect(store.values['test'], 'kept');
      store
        ..readError = null
        ..values.remove('test');
      expect(
        await (await cipher()).decrypt(await (await cipher()).encrypt('Alice')),
        'Alice',
      );
    });

    test('a keyring round-trips through its bytes, as Kotlin lays it out', () {
      final ring = Keyring(0xFFFFFFFB, {
        0xFFFFFFFB: Uint8List(32)..fillRange(0, 32, 1),
        0x7FFFFFFF: Uint8List(32)..fillRange(0, 32, 2),
      });
      final encoded = ring.encode();
      expect(encoded.sublist(0, 4), [0xFF, 0xFF, 0xFF, 0xFB]);
      final decoded = Keyring.decode(encoded)!;
      expect(decoded.primary, ring.primary);
      expect(decoded.keys.keys, ring.keys.keys);
      for (final MapEntry(:key, :value) in ring.keys.entries) {
        expect(decoded.keys[key], value);
      }
    });

    test('bytes that are not a keyring decode to null', () {
      final valid = Keyring(1, {1: Uint8List(32)}).encode();
      expect(Keyring.decode(Uint8List(0)), isNull);
      expect(Keyring.decode(valid.sublist(0, valid.length - 1)), isNull);
      expect(Keyring.decode(Uint8List.fromList(valid)..[3] = 2), isNull);
    });

    test('a blank alias is refused', () {
      expect(() => openFieldCipher(store, ' '), throwsArgumentError);
    });
  });

  group('cross-platform fixtures', () {
    test("every Kotlin library's value decrypts", () async {
      final c = await fixedKeyCipher(Fixtures.key, Fixtures.keyId);
      for (final MapEntry(key: producedBy, value: value)
          in Fixtures.values.entries) {
        expect(
          await c.decrypt(value, context: Fixtures.context),
          Fixtures.plain,
          reason: producedBy,
        );
        await expectLater(
          c.decrypt(value, context: '${Fixtures.context}!'),
          throwsA(isA<DecryptionFailed>()),
          reason: producedBy,
        );
      }
    });

    test('a value encrypted here carries the fixture key id', () async {
      final c = await fixedKeyCipher(Fixtures.key, Fixtures.keyId);
      final value = await c.encrypt(Fixtures.plain, context: Fixtures.context);
      expect(keyIdOf(value), Fixtures.keyId);
      expect(await c.decrypt(value, context: Fixtures.context), Fixtures.plain);
    });
  });
}
