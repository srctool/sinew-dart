import 'package:sinew_models/sinew_models.dart';

/// One page of a local query, for `Pager.offset`: [fetch] is the app's
/// `LIMIT :count OFFSET :offset` query. It asks for one row more than
/// [limit], which tells whether a next page exists without a `COUNT(*)`;
/// `total` and `totalPage` stay 0. A page past the last one is empty, with no
/// next page.
///
/// ```dart
/// Future<PagingEntity<OrderRow>> page(int page, int limit) => pagedQuery(page, limit, (offset, count) =>
///     (db.select(db.orders)..orderBy([(o) => OrderingTerm.desc(o.placedAt)])..limit(count, offset: offset)).get());
/// ```
Future<PagingEntity<T>> pagedQuery<T>(
  int page,
  int limit,
  Future<List<T>> Function(int offset, int count) fetch, {
  int firstPage = 1,
}) async {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'must be positive');
  }
  if (page < firstPage) {
    throw ArgumentError.value(
      page,
      'page',
      'is before the first page, $firstPage',
    );
  }
  // The offset must fit an integer on every platform, the web's included.
  if (page - firstPage > _maxSafeInteger ~/ limit) {
    throw ArgumentError.value(
      page,
      'page',
      'is beyond what an offset can reach',
    );
  }
  final rows = await fetch((page - firstPage) * limit, limit + 1);
  return PagingEntity(
    items: rows.take(limit).toList(),
    meta: PagingMetaEntity(
      page: page,
      limit: limit,
      hasNextPage: rows.length > limit,
      hasPreviousPage: page > firstPage,
    ),
  );
}

/// 2^53 - 1: the largest integer a JavaScript number holds exactly.
const _maxSafeInteger = 9007199254740991;
