# sinew_security

FieldCipher and BiometricVault on vetted crypto per platform.

Part of [Sinew](https://github.com/srctool/sinew). Status: milestone S4.

## Requirements

`FieldCipher` uses [`webcrypto`](https://pub.dev/packages/webcrypto): Google's BoringSSL on native platforms, the
browser's Web Crypto on the web. BoringSSL is compiled from source by Dart's native-assets build, so every machine that
builds an app using this package needs **CMake** on its `PATH` (macOS: `brew install cmake`; Ubuntu: `apt install cmake`;
or the CMake that Android Studio's SDK Manager installs, under `<sdk>/cmake/<version>/bin`). The first build per
platform takes a minute or two longer; later builds are cached. GitHub's hosted runners already have CMake.

The keys are kept with [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage); its platform setup
applies (on macOS, the Keychain Sharing entitlement).
