## 0.1.0-dev.1

- S4: `FieldCipher` (`create`, `encrypt`, `decrypt`, `rotateKey`) and `DecryptionFailed`: AES-256-GCM through `webcrypto` (BoringSSL on native, Web Crypto on web) with `context` as associated data and a fresh `fillRandomBytes` nonce per value, in Kotlin's layout (`version | key id | nonce | ciphertext | tag`); the Kotlin fixtures (Tink, CryptoKit, Web Crypto) decrypt. The keyring (Kotlin's byte layout) is one `flutter_secure_storage` entry, first-unlock this-device-only; concurrent opens of one alias share it. Builds need CMake (see the README). Replaces the S0 placeholder.
- S0: package skeleton.
