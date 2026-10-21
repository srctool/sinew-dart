import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_security/sinew_security.dart';
import 'package:sinew_storage/sinew_storage.dart';
import 'package:sinew_storage/src/secure_store.dart';

/// The key options `FieldCipher` writes with: a delete must match them.
const _iOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);
const _mOptions = MacOsOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

/// The suite every platform's [SecureStore] passes: the unit tests run it over
/// in-memory plugins, and the example app's integration test on each device.
/// The test namespaces are emptied before each test.
void secureStoreContract() {
  KeyValueStore values(String namespace) =>
      KeyValueStore.create(name: '${namespace}_secure');

  setUp(() async {
    for (final namespace in ['contract', 'contract_other']) {
      await values(namespace).clear();
    }
  });

  test('a secret round-trips', () async {
    final store = await SecureStore.create(namespace: 'contract');
    for (final secret in ['', 'refresh-token', 'Ä 😀 日本語', 'x' * 4000]) {
      await store.write('session.refreshToken', secret);
      expect(await store.read('session.refreshToken'), secret);
    }
  });

  test('a missing key is absent', () async {
    final store = await SecureStore.create(namespace: 'contract');
    expect(await store.read('missing'), isNull);
  });

  test('delete removes one secret', () async {
    final store = await SecureStore.create(namespace: 'contract');
    await store.write('a', '1');
    await store.write('b', '2');
    await store.delete('a');
    await store.delete('never-written');
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), '2');
  });

  test('clearUserData empties this namespace only', () async {
    final store = await SecureStore.create(namespace: 'contract');
    final other = await SecureStore.create(namespace: 'contract_other');
    await store.write('a', '1');
    await store.write('b', '2');
    await other.write('a', 'kept');
    await store.clearUserData();
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), isNull);
    expect(await other.read('a'), 'kept');
  });

  test('secrets persist for the same namespace', () async {
    await (await SecureStore.create(namespace: 'contract'))
        .write('token', 'refresh-token');
    expect(
      await (await SecureStore.create(namespace: 'contract')).read('token'),
      'refresh-token',
    );
  });

  test('the stored value is not the plain secret', () async {
    await (await SecureStore.create(namespace: 'contract'))
        .write('token', 'refresh-token');
    final stored = await values('contract').getString('token');
    expect(stored, isNotNull);
    expect(stored, isNot(contains('refresh-token')));
  });

  test('a value that can\'t be decrypted is absent, and deleted', () async {
    final store = await SecureStore.create(namespace: 'contract');
    await values('contract').setString('token', 'not a ciphertext');
    expect(await store.read('token'), isNull);
    expect(await values('contract').getString('token'), isNull);
  });

  test('a value copied to another key doesn\'t decrypt', () async {
    final store = await SecureStore.create(namespace: 'contract');
    await store.write('a', 'secret');
    await values('contract')
        .setString('b', (await values('contract').getString('a'))!);
    expect(await store.read('b'), isNull);
    expect(await store.read('a'), 'secret');
  });

  test('a lost key makes the secret absent, and deletes it', () async {
    // A fresh plugin instance for each open: FieldCipher keeps one keyring
    // per key storage, and a restore onto a new device starts with none.
    Future<SecureStore> open() async => EncryptedSecureStore(
      'contract',
      values('contract'),
      await FieldCipher.create(
        keyAlias: 'sinew.secure.contract',
        keyStorage: const FlutterSecureStorage(),
      ),
    );
    await (await open()).write('token', 'refresh-token');
    await const FlutterSecureStorage().delete(
      key: 'sinew.secure.contract',
      iOptions: _iOptions,
      mOptions: _mOptions,
    );
    expect(await (await open()).read('token'), isNull);
    expect(await values('contract').getString('token'), isNull);
  });

  test('concurrent writes all land', () async {
    final store = await SecureStore.create(namespace: 'contract');
    await Future.wait([
      for (var i = 0; i < 30; i++) store.write('key$i', 'value $i'),
    ]);
    for (var i = 0; i < 30; i++) {
      expect(await store.read('key$i'), 'value $i');
    }
  });

  test('it can be inspected', () async {
    final store = await SecureStore.create(namespace: 'contract');
    await store.write('b', '2');
    await store.write('a', '1');
    expect(store.name, 'contract');
    expect(await store.keys(), ['a', 'b']);
    expect(await store.read('a'), '1');
    expect(
      await (await SecureStore.create(namespace: 'contract_other')).keys(),
      isEmpty,
    );
  });
}
