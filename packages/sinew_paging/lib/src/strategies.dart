import 'package:sinew_models/sinew_models.dart';

/// How the first and next page are requested, and the has-next rule. Chosen
/// through the `Pager` constructors.
abstract interface class PagingStrategy<T> {
  /// Requests the first page.
  Future<Result<PagingDomain<T>>> first(String query);

  /// Requests the page after [previous].
  Future<Result<PagingDomain<T>>> next(PagingDomain<T> previous, String query);

  /// Rewrites `meta.hasNextPage` with this strategy's rule, so `canLoadMore`
  /// only ever reads one field.
  PagingDomain<T> normalize(PagingDomain<T> page);
}

/// Page numbers. The requested page wins: it's written into `meta.page`, so
/// the next request is always `page + 1`, whatever the backend reported. With
/// `byTotal`, has-next is `page < totalPage`.
final class OffsetStrategy<T> implements PagingStrategy<T> {
  /// Creates the strategy.
  const OffsetStrategy(
    this._fetch, {
    required this.firstPage,
    required this.byTotal,
  });

  final Future<Result<PagingDomain<T>>> Function(int page, String query) _fetch;

  /// The first page number: 1, or 0 for 0-based APIs.
  final int firstPage;

  /// Whether has-next comes from `totalPage` instead of the backend's flag.
  final bool byTotal;

  @override
  Future<Result<PagingDomain<T>>> first(String query) =>
      _request(firstPage, query);

  @override
  Future<Result<PagingDomain<T>>> next(
    PagingDomain<T> previous,
    String query,
  ) => _request(previous.meta.page + 1, query);

  Future<Result<PagingDomain<T>>> _request(int page, String query) async =>
      (await _fetch(
        page,
        query,
      )).transform((p) => p.copyWith(meta: p.meta.copyWith(page: page)));

  @override
  PagingDomain<T> normalize(PagingDomain<T> page) => byTotal
      ? page.copyWith(
          meta: page.meta.copyWith(
            hasNextPage: page.meta.page < page.meta.totalPage,
          ),
        )
      : page;
}

/// An opaque cursor in `meta.nextKey`. An empty cursor means no next page,
/// whatever the flag says.
final class CursorStrategy<T> implements PagingStrategy<T> {
  /// Creates the strategy.
  const CursorStrategy(this._fetch);

  final Future<Result<PagingDomain<T>>> Function(String cursor, String query)
  _fetch;

  @override
  Future<Result<PagingDomain<T>>> first(String query) => _fetch('', query);

  @override
  Future<Result<PagingDomain<T>>> next(
    PagingDomain<T> previous,
    String query,
  ) => _fetch(previous.meta.nextKey, query);

  @override
  PagingDomain<T> normalize(PagingDomain<T> page) => page.copyWith(
    meta: page.meta.copyWith(
      hasNextPage: page.meta.hasNextPage && page.meta.nextKey.isNotEmpty,
    ),
  );
}

/// "Items after this ID". An empty list has no next page.
final class LastItemStrategy<T> implements PagingStrategy<T> {
  /// Creates the strategy.
  const LastItemStrategy(this._fetch, {required this.itemId});

  final Future<Result<PagingDomain<T>>> Function(String? lastId, String query)
  _fetch;

  /// Reads an item's ID.
  final String Function(T item) itemId;

  @override
  Future<Result<PagingDomain<T>>> first(String query) => _fetch(null, query);

  @override
  Future<Result<PagingDomain<T>>> next(
    PagingDomain<T> previous,
    String query,
  ) => _fetch(
    previous.items.isEmpty ? null : itemId(previous.items.last),
    query,
  );

  @override
  PagingDomain<T> normalize(PagingDomain<T> page) => page.copyWith(
    meta: page.meta.copyWith(
      hasNextPage: page.meta.hasNextPage && page.items.isNotEmpty,
    ),
  );
}
