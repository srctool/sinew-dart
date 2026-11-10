# sinew_security

[![pub package](https://img.shields.io/pub/v/sinew_security.svg)](https://pub.dev/packages/sinew_security)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**`FieldCipher` and `BiometricVault` on vetted crypto per platform.**

Field encryption and a biometric vault that never invent a cipher: AES-256-GCM from vetted libraries on every platform, keys kept in the platform's key storage, and a fresh nonce for every value.

## Features

- `FieldCipher`: `encrypt` and `decrypt` with a `context` bound as associated data, and `rotateKey` that keeps old values readable
- `BiometricVault`: store a secret behind a biometric match with `store`, release it only by a real match with `unlock`, and report why not as a user outcome, not an error
- One value layout on every platform, so any platform decrypts any other's output

## Getting started

```sh
flutter pub add sinew_security
```

## Usage

```dart
final cipher = await FieldCipher.create();
final sealed = await cipher.encrypt('Alice', context: 'customer:42');
final plain = await cipher.decrypt(sealed, context: 'customer:42');
```

A value decrypted with another `context` fails with `DecryptionFailed`, so a value copied to another field doesn't decrypt.

```dart
final vault = BiometricVault.create();
if (await vault.availability() == BiometricAvailability.available) {
  await vault.store(refreshToken, reason: 'Sign in with biometrics next time');
}
final unlocked = await vault.unlock(reason: 'Sign in');
```

## Requirements

`FieldCipher` uses [`webcrypto`](https://pub.dev/packages/webcrypto): Google's BoringSSL on native platforms, the
browser's Web Crypto on the web. BoringSSL is compiled from source by Dart's native-assets build, so every machine that
builds an app using this package needs **CMake** on its `PATH` (macOS: `brew install cmake`; Ubuntu: `apt install cmake`;
or the CMake that Android Studio's SDK Manager installs, under `<sdk>/cmake/<version>/bin`). The first build per
platform takes a minute or two longer; later builds are cached. GitHub's hosted runners already have CMake.

The keys are kept with [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage); its platform setup
applies (on macOS, the Keychain Sharing entitlement).

## BiometricVault setup

`BiometricVault` is a plugin with native Android and iOS code. Each app needs:

- **Android:** `MainActivity` extends `FlutterFragmentActivity` (`BiometricPrompt` needs a `FragmentActivity`); without
  it, `store` and `unlock` return `BiometricFailed(unavailable)` and log the fix. Exclude the vault's shared preferences
  (`sinew.security.biometric.xml`) from cloud backup and device transfer in `data_extraction_rules.xml`; the key can't
  leave the device anyway.
- **iOS:** `NSFaceIDUsageDescription` in `Info.plist`.
- **macOS:** the Keychain Sharing entitlement, for `FieldCipher`'s keys. The vault is unavailable on desktop and web.

On Android, `store` shows the prompt (the key needs a match to encrypt too); iOS stores without one. A secret is
released only by a real match: no prompt sits in front of a normal read.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_storage`](https://pub.dev/packages/sinew_storage)
- [`sinew_testing`](https://pub.dev/packages/sinew_testing)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_security](https://pub.dev/documentation/sinew_security/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
