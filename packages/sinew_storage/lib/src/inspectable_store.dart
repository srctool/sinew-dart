/// A store the devtools can browse: its name, its keys, and each value as
/// text. `KeyValueStore` and `SecureStore` implement it (the devtools mask
/// secure values); an app's DAO can, to appear in the database browser.
/// Nothing in production calls it.
abstract interface class InspectableStore {
  /// The store's name, as the devtools list it.
  String get name;

  /// Every key, sorted.
  Future<List<String>> keys();

  /// [key]'s value as text, whatever its type, or `null` when absent.
  Future<String?> read(String key);
}
