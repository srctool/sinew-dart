## 1.1.0

- `appServicesProvider` (override it with the app's services) and `appServiceHostProvider`: reading the host starts the app services, and disposing the container destroys them. The session owner calls `startSession` and `stopSession` on it.

## 1.0.0

- S5: ready providers. `sinewConfigProvider` and `refreshCallProvider`, which the app overrides (a missing override throws a `StateError` naming the provider and how to override it); `secureStoreProvider` (a `FutureProvider`, awaited once at startup), `keyValueStoreProvider`, `refreshTokenStoreProvider` (`SecureRefreshTokenStore`, the refresh token in the secure store under `session.refreshToken`), `tokenSourceProvider` (`SessionTokenSource`), `sinewHttpProvider` (`SinewHttp.dio`) and `networkCheckerProvider` (disposed with the container); `useNetworkChecker(checker)`, rebuilding on connectivity changes. Replaces the S0 placeholder.
- S0: package skeleton.
