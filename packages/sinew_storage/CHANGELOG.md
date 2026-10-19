## 0.1.0-dev.1

- S4: `KeyValueStore` (`create({name})`, `getString`/`getInt`/`getBool`/`getDouble` and setters, `remove`, `clear`) on `SharedPreferencesAsync`, keys prefixed `<name>.`; a value of another type reads as absent; `clear` removes only the store's own keys. Replaces the S0 placeholder.
- S0: package skeleton.
