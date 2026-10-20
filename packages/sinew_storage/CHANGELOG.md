## 0.1.0-dev.1

- S4: `SecureStore` (`create({namespace})`, `read`, `write`, `delete`, `clearUserData`), as in Kotlin (ADR-26): a `KeyValueStore` (`<namespace>_secure`) whose values `FieldCipher` (`sinew.secure.<namespace>`) encrypts with `<namespace>:<key>` as associated data. An undecryptable value reads as absent and is deleted; writes are serialized; a reinstall starts empty with no marker.
- S4: `KeyValueStore` (`create({name})`, `getString`/`getInt`/`getBool`/`getDouble` and setters, `remove`, `clear`) on `SharedPreferencesAsync`, keys prefixed `<name>.`; a value of another type reads as absent; `clear` removes only the store's own keys. Replaces the S0 placeholder.
- S0: package skeleton.
