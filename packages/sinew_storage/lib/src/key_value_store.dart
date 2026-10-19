import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive preferences and flags: onboarding seen, the theme, the last
/// filter. Never tokens or personal data, which go in `SecureStore` or the
/// app's database with `FieldCipher`.
///
/// Wrap it in typed stores with their own keys
/// (`OrderPreferences.lastStatusFilter()`), so string keys stay in one place.
/// A value read as another type than it was written is absent, as is a
/// missing one. Storage failures are thrown as they come; `processStorageCall`
/// turns them into typed exceptions.
///
/// Backed by `SharedPreferencesAsync`, which reads from the platform every
/// time (no in-memory cache), with every key prefixed `<name>.`: DataStore on
/// Android, `NSUserDefaults` on iOS and macOS, a JSON file on Linux and
/// Windows, `localStorage` on the web. On the web a whole-number double also
/// reads as an int, since JavaScript doesn't tell them apart.
abstract interface class KeyValueStore {
  /// The store named [name]. Stores with the same name share their values.
  /// The name prefixes every key, so it must not be blank or contain a `.`.
  static KeyValueStore create({String name = 'sinew_prefs'}) {
    if (name.trim().isEmpty || name.contains('.')) {
      throw ArgumentError.value(name, 'name', 'must be non-blank, without "."');
    }
    return _PrefsKeyValueStore(SharedPreferencesAsync(), name);
  }

  /// The text under [key], or `null`.
  Future<String?> getString(String key);

  /// Stores [value] under [key], replacing any value of any type.
  Future<void> setString(String key, String value);

  /// The integer under [key], or `null`.
  Future<int?> getInt(String key);

  /// Stores [value] under [key], replacing any value of any type.
  Future<void> setInt(String key, int value);

  /// The flag under [key], or `null`.
  Future<bool?> getBool(String key);

  /// Stores [value] under [key], replacing any value of any type.
  Future<void> setBool(String key, bool value);

  /// The decimal under [key], or `null`.
  Future<double?> getDouble(String key);

  /// Stores [value] under [key], replacing any value of any type.
  Future<void> setDouble(String key, double value);

  /// Removes [key], whatever its type.
  Future<void> remove(String key);

  /// Removes every key of this store, and nothing of another store.
  Future<void> clear();
}

/// [KeyValueStore] over [SharedPreferencesAsync]. Each read fetches the one
/// key with `getAll` and checks its type in Dart, so a value of another type
/// reads as absent on every platform instead of throwing on some.
final class _PrefsKeyValueStore implements KeyValueStore {
  /// The store [name] in [prefs].
  _PrefsKeyValueStore(this._prefs, this.name) : _prefix = '$name.';

  final SharedPreferencesAsync _prefs;

  /// The store's name, the prefix of its keys.
  final String name;

  final String _prefix;

  Future<T?> _get<T>(String key) async {
    final full = '$_prefix$key';
    final value = (await _prefs.getAll(allowList: {full}))[full];
    return value is T ? value : null;
  }

  @override
  Future<String?> getString(String key) => _get<String>(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString('$_prefix$key', value);

  @override
  Future<int?> getInt(String key) => _get<int>(key);

  @override
  Future<void> setInt(String key, int value) =>
      _prefs.setInt('$_prefix$key', value);

  @override
  Future<bool?> getBool(String key) => _get<bool>(key);

  @override
  Future<void> setBool(String key, bool value) =>
      _prefs.setBool('$_prefix$key', value);

  @override
  Future<double?> getDouble(String key) => _get<double>(key);

  @override
  Future<void> setDouble(String key, double value) =>
      _prefs.setDouble('$_prefix$key', value);

  @override
  Future<void> remove(String key) => _prefs.remove('$_prefix$key');

  @override
  Future<void> clear() async {
    final own = (await _prefs.getKeys()).where((k) => k.startsWith(_prefix));
    if (own.isNotEmpty) await _prefs.clear(allowList: own.toSet());
  }
}
