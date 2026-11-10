# sinew_security example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

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
