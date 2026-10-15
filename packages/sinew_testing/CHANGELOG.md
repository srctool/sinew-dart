## 0.1.0-dev.1

- S3: `FakeNetworkChecker`, a network checker the test switches with `goOffline()` and `goOnline()`.
- S3: `package:sinew_testing/paging.dart`, `ControlledFetch` alone without Flutter, for packages tested with `dart test` (the network fakes now bring in Flutter through `connectivity_plus`).
- S3: `FakeTokenSource`, a token source the test drives: it counts refreshes and clears, rotates `token-1` → `token-2`, and takes an `onRefresh` to gate a refresh.
- S2: `ControlledFetch`, a paging fetch the test answers call by call.
- S0: package skeleton.
