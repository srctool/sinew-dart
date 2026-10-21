import 'package:sinew_security/sinew_security.dart';

/// A [FieldCipher] **with no cryptography**: it stores a readable marked
/// form, `enc(Alice)`, or `enc[context](Alice)` with a context, so a test can
/// see which fields were encrypted and with what context. Decrypting checks
/// the mark and the context, as the real cipher does, and throws
/// [DecryptionFailed] otherwise.
///
/// For code that only stores and loads values. Never use it to prove
/// encryption: crypto tests use the real cipher.
final class FakeFieldCipher implements FieldCipher {
  bool _failNext = false;

  /// How many times [rotateKey] was called.
  int rotations = 0;

  /// Makes the next decryption throw [DecryptionFailed], once.
  void failNextDecrypt() => _failNext = true;

  String _prefix(String context) => context.isEmpty ? 'enc(' : 'enc[$context](';

  @override
  Future<String> encrypt(String plain, {String context = ''}) async =>
      '${_prefix(context)}$plain)';

  @override
  Future<String> decrypt(String cipher, {String context = ''}) async {
    if (_failNext) {
      _failNext = false;
      throw const DecryptionFailed();
    }
    final prefix = _prefix(context);
    if (!cipher.startsWith(prefix) || !cipher.endsWith(')')) {
      throw const DecryptionFailed();
    }
    return cipher.substring(prefix.length, cipher.length - 1);
  }

  @override
  Future<void> rotateKey() async => rotations++;
}
