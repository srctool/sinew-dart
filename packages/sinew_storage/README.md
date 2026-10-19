# sinew_storage

SecureStore, KeyValueStore, processStorageCall and pagedQuery.

Part of [Sinew](https://github.com/srctool/sinew). Status: milestone S4.

## KeyValueStore

Plain preferences (the theme, onboarding seen), never tokens or personal data:

```dart
final prefs = KeyValueStore.create(); // or create(name: 'orders')
await prefs.setString('theme', 'dark');
final theme = await prefs.getString('theme'); // null when missing or of another type
```

It's `SharedPreferencesAsync` (no in-memory cache) with every key prefixed `<name>.`, so `clear()` removes only this
store's keys. In unit tests, set `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()`
(from `shared_preferences_platform_interface`).
