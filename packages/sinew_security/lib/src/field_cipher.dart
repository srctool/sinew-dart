import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';
import 'package:webcrypto/webcrypto.dart';

import 'key_store.dart';

/// Encrypts individual values (a name, a phone number) before they're stored,
/// with AES-256-GCM from `webcrypto`: Google's BoringSSL on native platforms,
/// the browser's Web Crypto on the web.
///
/// Every value gets a fresh 96-bit nonce from a secure random source, and
/// `context` is bound as associated data: a ciphertext copied into another row
/// or column fails to decrypt. The layout is Kotlin's, so a value written by
/// one decrypts on the other: `base64(version 0x01 | key id (4) | nonce (12) |
/// ciphertext | tag (16))`. [rotateKey] adds a key; older values still decrypt
/// with theirs.
///
/// The keys are kept in `flutter_secure_storage`, readable after the first
/// unlock, on this device only. On the web that's `localStorage` wrapped by
/// Web Crypto: it protects against casual reading, not against script on the
/// page.
abstract interface class FieldCipher {
  /// The cipher for [keyAlias], creating its first key if there's none. Calls
  /// with the same alias share one keyring. [keyStorage] replaces the default
  /// `FlutterSecureStorage`.
  static Future<FieldCipher> create({
    String keyAlias = 'sinew.field',
    FlutterSecureStorage? keyStorage,
  }) => openFieldCipher(
    keyStorage == null ? SecureKeyStore.standard : SecureKeyStore(keyStorage),
    keyAlias,
  );

  /// Encrypts [plain], bound to [context] (for example
  /// `'customers.displayName:42'`), with the current key.
  Future<String> encrypt(String plain, {String context = ''});

  /// Decrypts what [encrypt] returned for the same [context], with whichever
  /// key encrypted it. Throws [DecryptionFailed] when the value was changed,
  /// belongs to another context, or its key is gone.
  Future<String> decrypt(String cipher, {String context = ''});

  /// Makes a new key the current one. Older values still decrypt, and move to
  /// the new key when the app next rewrites them.
  Future<void> rotateKey();
}

/// A value couldn't be decrypted: it was changed, belongs to another context,
/// or its key is gone. The storage guard maps it to
/// `LocalStorageCorruptionException`; the caller treats the value as absent.
final class DecryptionFailed implements Exception {
  /// The failure, with what caused it.
  const DecryptionFailed([this.cause]);

  /// What made decryption fail, when there's more to say.
  final Object? cause;

  @override
  String toString() => 'DecryptionFailed: the value could not be decrypted';
}

const _version = 0x01;
const _headerSize = 5;
const _nonceSize = 12;
const _tagSize = 16;
const _keySize = 32;

/// The keyring of one alias: [primary] encrypts, every key in [keys] decrypts.
@visibleForTesting
final class Keyring {
  /// A keyring whose [primary] is among [keys].
  Keyring(this.primary, this.keys) : assert(keys.containsKey(primary));

  /// The id of the key that encrypts.
  final int primary;

  /// Raw 32-byte keys by id.
  final Map<int, Uint8List> keys;

  /// `primary id (4) | (key id (4) | key (32))*`, big-endian ids: the layout of
  /// Kotlin's iOS keyring.
  Uint8List encode() {
    final out = BytesBuilder()..add(_bigEndian(primary));
    for (final MapEntry(:key, :value) in keys.entries) {
      out
        ..add(_bigEndian(key))
        ..add(value);
    }
    return out.toBytes();
  }

  /// The keyring in [bytes], or `null` when they aren't one.
  static Keyring? decode(Uint8List bytes) {
    if (bytes.length < 4 + 4 + _keySize ||
        (bytes.length - 4) % (4 + _keySize) != 0) {
      return null;
    }
    final keys = <int, Uint8List>{
      for (var at = 4; at < bytes.length; at += 4 + _keySize)
        _readBigEndian(bytes, at): Uint8List.sublistView(
          bytes,
          at + 4,
          at + 4 + _keySize,
        ),
    };
    final primary = _readBigEndian(bytes, 0);
    return keys.containsKey(primary) ? Keyring(primary, keys) : null;
  }
}

Uint8List _bigEndian(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

int _readBigEndian(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes, at, at + 4).getUint32(0);

int _randomKeyId() {
  final bytes = Uint8List(4);
  fillRandomBytes(bytes);
  return _readBigEndian(bytes, 0);
}

Uint8List _randomKey() {
  final bytes = Uint8List(_keySize);
  fillRandomBytes(bytes);
  return bytes;
}

/// The ciphers being opened or open, per key store and alias, so two calls for
/// one alias never make two first keys.
final _opening = Expando<Map<String, Future<FieldCipher>>>();

/// The cipher for [alias] in [store]: its keyring, or a new one with a single
/// key, saved before first use. A stored value that isn't a keyring is replaced
/// (its values are lost); a failure to read the store is thrown, so a passing
/// error never replaces a good key.
@visibleForTesting
Future<FieldCipher> openFieldCipher(KeyStore store, String alias) {
  if (alias.trim().isEmpty) {
    throw ArgumentError.value(alias, 'keyAlias', 'must not be blank');
  }
  final perStore = _opening[store] ??= {};
  return perStore[alias] ??= _open(store, alias).catchError((
    Object error,
    StackTrace stack,
  ) {
    perStore.remove(alias); // a failed open can be retried
    Error.throwWithStackTrace(error, stack);
  });
}

Future<FieldCipher> _open(KeyStore store, String alias) async {
  final stored = await store.read(alias);
  Keyring? ring;
  if (stored != null) {
    try {
      ring = Keyring.decode(base64.decode(stored));
    } on FormatException {
      ring = null;
    }
  }
  if (ring == null) {
    final id = _randomKeyId();
    ring = Keyring(id, {id: _randomKey()});
    await store.write(alias, base64.encode(ring.encode()));
  }
  return _RingCipher(store, alias, await _Keys.of(ring));
}

/// A cipher with one known key and nothing stored: the cross-platform fixtures
/// run on it.
@visibleForTesting
Future<FieldCipher> fixedKeyCipher(Uint8List key, int keyId) async =>
    _RingCipher(null, '', await _Keys.of(Keyring(keyId, {keyId: key})));

/// A keyring with its keys imported into `webcrypto`.
final class _Keys {
  _Keys(this.ring, this.imported);

  static Future<_Keys> of(Keyring ring) async => _Keys(ring, {
    for (final MapEntry(:key, :value) in ring.keys.entries)
      key: await AesGcmSecretKey.importRawKey(value),
  });

  final Keyring ring;
  final Map<int, AesGcmSecretKey> imported;
}

final class _RingCipher implements FieldCipher {
  _RingCipher(this._store, this._alias, this._keys);

  final KeyStore? _store;
  final String _alias;
  _Keys _keys;
  Future<void> _rotating = Future.value();

  @override
  Future<String> encrypt(String plain, {String context = ''}) async {
    final keys = _keys;
    final nonce = Uint8List(_nonceSize);
    fillRandomBytes(nonce);
    final sealed = await keys.imported[keys.ring.primary]!.encryptBytes(
      utf8.encode(plain),
      nonce,
      additionalData: utf8.encode(context),
    );
    final out = BytesBuilder()
      ..addByte(_version)
      ..add(_bigEndian(keys.ring.primary))
      ..add(nonce)
      ..add(sealed);
    return base64.encode(out.toBytes());
  }

  @override
  Future<String> decrypt(String cipher, {String context = ''}) async {
    final Uint8List bytes;
    try {
      bytes = base64.decode(cipher);
    } on FormatException catch (e) {
      throw DecryptionFailed(e);
    }
    if (bytes.length < _headerSize + _nonceSize + _tagSize ||
        bytes[0] != _version) {
      throw const DecryptionFailed();
    }
    final key = _keys.imported[_readBigEndian(bytes, 1)];
    if (key == null) throw const DecryptionFailed();
    try {
      final plain = await key.decryptBytes(
        Uint8List.sublistView(bytes, _headerSize + _nonceSize),
        Uint8List.sublistView(bytes, _headerSize, _headerSize + _nonceSize),
        additionalData: utf8.encode(context),
      );
      return utf8.decode(plain);
    } on Object catch (e) {
      throw DecryptionFailed(e);
    }
  }

  /// Rotations run one at a time; a failed one doesn't block the next.
  @override
  Future<void> rotateKey() {
    final rotation = _rotating.then((_) => _rotate());
    _rotating = rotation.then((_) {}, onError: (Object _) {});
    return rotation;
  }

  Future<void> _rotate() async {
    final ring = _keys.ring;
    int id;
    do {
      id = _randomKeyId();
    } while (ring.keys.containsKey(id));
    final next = Keyring(id, {...ring.keys, id: _randomKey()});
    await _store?.write(_alias, base64.encode(next.encode()));
    _keys = await _Keys.of(next);
  }
}
