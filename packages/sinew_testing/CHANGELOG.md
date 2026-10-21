## 0.1.0-dev.1

- S5: a fake for every Sinew interface: `FakeKeyValueStore` (a wrong type reads as absent; `failNextRead`, `failNextWrite`, `failNextWriteWithDiskFull`), `FakeSecureStore` (`failNextRead`, `failNextWrite`, `loseKey`), `FakeFieldCipher` (no cryptography: a readable `enc(…)` / `enc[context](…)` form; `failNextDecrypt`, `rotations`), `FakeBiometricVault` (settable `availabilityNow`, `nextStore` / `nextUnlock` failures, `invalidate`, `prompts`), `FakeRefreshTokenStore`, `RecordingCrashReporter` (`reports`, `codes`, `clear`) and `FakeLocalizer` (a map with `{name}` arguments; the key itself or `null` when missing; `requested`), beside `FakeTokenSource` and `FakeNetworkChecker`. `platformStorageError()` and `diskFullError()` are the `PlatformException`s a storage plugin throws, so an app's `processStorageCall` classifies a fake's failure as a real one's.
- S3: `FakeNetworkChecker`, a network checker the test switches with `goOffline()` and `goOnline()`.
- S3: `package:sinew_testing/paging.dart`, `ControlledFetch` alone without Flutter, for packages tested with `dart test` (the network fakes now bring in Flutter through `connectivity_plus`).
- S3: `FakeTokenSource`, a token source the test drives: it counts refreshes and clears, rotates `token-1` → `token-2`, and takes an `onRefresh` to gate a refresh.
- S2: `ControlledFetch`, a paging fetch the test answers call by call.
- S0: package skeleton.
