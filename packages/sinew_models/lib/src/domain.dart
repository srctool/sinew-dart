/// A domain model: what the app needs, in business language.
///
/// Equality comes from [props], compared element by element (lists and maps
/// deeply), so models compare by value without an `equatable` dependency.
abstract class Domain {
  /// Creates a domain model.
  const Domain();

  /// The values that make two instances equal.
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          _deepEquals(props, (other as Domain).props);

  @override
  int get hashCode => _deepHash(props);
}

/// What the backend sends, shaped like its JSON. Private to its data module;
/// it exists only to be mapped.
abstract class Remote<D extends Domain> {
  /// Creates a remote model.
  const Remote();

  /// Maps this remote model to its domain model.
  D toDomain();
}

/// What's stored on the device. Private to its data module; it exists only to
/// be mapped.
abstract class Entity<D extends Domain> {
  /// Creates an entity.
  const Entity();

  /// Maps this entity to its domain model.
  D toDomain();
}

// Value equality for Domain.props: lists and maps compare element by element.
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// The hash code matching [_deepEquals].
int _deepHash(Object? value) => switch (value) {
  final List<Object?> list => Object.hashAll(list.map(_deepHash)),
  final Map<Object?, Object?> map => Object.hashAllUnordered(
    map.entries.map((e) => Object.hash(_deepHash(e.key), _deepHash(e.value))),
  ),
  _ => value.hashCode,
};
