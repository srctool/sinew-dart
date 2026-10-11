/// A page of items: one shape for every backend, whatever its meta fields are
/// called.
class PagingDomain<T> {
  /// Creates a page.
  const PagingDomain({
    this.items = const [],
    this.meta = const PagingMetaDomain(),
  });

  /// The items of this page (or of every page merged so far).
  final List<T> items;

  /// The page information.
  final PagingMetaDomain meta;

  /// A copy with the given fields replaced.
  PagingDomain<T> copyWith({List<T>? items, PagingMetaDomain? meta}) =>
      PagingDomain(items: items ?? this.items, meta: meta ?? this.meta);

  @override
  bool operator ==(Object other) =>
      other is PagingDomain<T> &&
      other.meta == meta &&
      _listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(Object.hashAll(items), meta);

  @override
  String toString() => 'PagingDomain($items, $meta)';
}

/// Page information. [nextKey] is the cursor for the next page; `''` means none.
class PagingMetaDomain {
  /// Creates page information.
  const PagingMetaDomain({
    this.page = 0,
    this.limit = 0,
    this.total = 0,
    this.totalPage = 0,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.nextKey = '',
  });

  /// The page this response is.
  final int page;

  /// Items per page.
  final int limit;

  /// Items across all pages, when the backend knows.
  final int total;

  /// Pages, when the backend knows.
  final int totalPage;

  /// Whether there's a page after this one.
  final bool hasNextPage;

  /// Whether there's a page before this one.
  final bool hasPreviousPage;

  /// The cursor for the next page; `''` means none.
  final String nextKey;

  /// A copy with the given fields replaced.
  PagingMetaDomain copyWith({
    int? page,
    int? limit,
    int? total,
    int? totalPage,
    bool? hasNextPage,
    bool? hasPreviousPage,
    String? nextKey,
  }) => PagingMetaDomain(
    page: page ?? this.page,
    limit: limit ?? this.limit,
    total: total ?? this.total,
    totalPage: totalPage ?? this.totalPage,
    hasNextPage: hasNextPage ?? this.hasNextPage,
    hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
    nextKey: nextKey ?? this.nextKey,
  );

  @override
  bool operator ==(Object other) =>
      other is PagingMetaDomain &&
      other.page == page &&
      other.limit == limit &&
      other.total == total &&
      other.totalPage == totalPage &&
      other.hasNextPage == hasNextPage &&
      other.hasPreviousPage == hasPreviousPage &&
      other.nextKey == nextKey;

  @override
  int get hashCode => Object.hash(
    page,
    limit,
    total,
    totalPage,
    hasNextPage,
    hasPreviousPage,
    nextKey,
  );

  @override
  String toString() =>
      'PagingMetaDomain(page: $page, limit: $limit, total: $total, totalPage: $totalPage, '
      'hasNextPage: $hasNextPage, hasPreviousPage: $hasPreviousPage, nextKey: $nextKey)';
}

/// A stored page. Its items needn't be entities, so [toDomain] takes the item
/// mapping.
class PagingEntity<T> {
  /// Creates a stored page.
  const PagingEntity({
    this.items = const [],
    this.meta = const PagingMetaEntity(),
  });

  /// The stored items.
  final List<T> items;

  /// The stored page information.
  final PagingMetaEntity meta;

  /// Maps every item with [convert], and the meta field for field.
  PagingDomain<R> toDomain<R>(R Function(T item) convert) => PagingDomain(
    items: [for (final item in items) convert(item)],
    meta: meta.toDomain(),
  );
}

/// Stored page information, mapped field for field to [PagingMetaDomain].
class PagingMetaEntity {
  /// Creates stored page information.
  const PagingMetaEntity({
    this.page = 0,
    this.limit = 0,
    this.total = 0,
    this.totalPage = 0,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.nextKey = '',
  });

  /// See [PagingMetaDomain.page].
  final int page;

  /// See [PagingMetaDomain.limit].
  final int limit;

  /// See [PagingMetaDomain.total].
  final int total;

  /// See [PagingMetaDomain.totalPage].
  final int totalPage;

  /// See [PagingMetaDomain.hasNextPage].
  final bool hasNextPage;

  /// See [PagingMetaDomain.hasPreviousPage].
  final bool hasPreviousPage;

  /// See [PagingMetaDomain.nextKey].
  final String nextKey;

  /// Maps to [PagingMetaDomain].
  PagingMetaDomain toDomain() => PagingMetaDomain(
    page: page,
    limit: limit,
    total: total,
    totalPage: totalPage,
    hasNextPage: hasNextPage,
    hasPreviousPage: hasPreviousPage,
    nextKey: nextKey,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
