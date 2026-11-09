## Unreleased

- `DevToolsGate`: `flavor`, the `const` `enabled`, and `assertMatchesFlavor()`.

- `DevTools.open()`, `close()` and `isOpen`; settable `redaction` on both recorders; re-exports `InspectableStore`, `KeyValueStore` and `SecureStore`.

- `FaultRule`, `FaultRules`, `HostOverride`, and `DevTools.httpHooks`, `faults`, `hosts`, `canReplay`, `replay` and `expireAccessToken`. `NetworkExchange.requestBodyStreamed`.

- `NetworkRecorder` and `NetworkRecord` (`replayable`, `asText()`, `asCurl()`), `ExceptionRecorder` with de-duplication, `DevToolsCrashReporter`, and `DevTools` (`network`, `exceptions`, `captureUncaughtErrors()`, `clearUserData()`). `Redaction.redactText` for free text.

- `Redaction`: masks secrets in headers, query and fragment parameters, form bodies and JSON bodies at any depth before anything is stored, by normalized name. `Redaction.standard`, `extend` (which can't remove a default), `withHeaders` for a client's `defaultHeaders`, a 64 KB cap, binary bodies as type and size, and `Redaction.maskSecret` for the Secure Store page.

## 0.1.0-dev.1

- S0: package skeleton.
