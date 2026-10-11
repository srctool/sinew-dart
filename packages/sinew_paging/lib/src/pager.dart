import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

import 'paging_state.dart';
import 'strategies.dart';

/// Loads pages so that only the newest load can write state: a refresh beats a
/// running `more`, a new query beats an old one, and a late response is dropped.
///
/// The pager holds no UI state. It reads the current [PagingState] from the
/// page's state and writes the next one through `update`. It remembers only its
/// strategy, a request counter, and the query of the `initial` load that is
/// running or succeeded, so `initial` runs at most once per query. Dart is
/// single-threaded, so no lock is needed. The notifier owns any `CancelToken`,
/// which keeps this package free of Dio.
final class Pager<T> {
  Pager._(this._strategy, this._itemKey);

  /// Page numbers, where the backend says whether a next page exists. 0-based
  /// APIs pass `firstPage: 0`.
  Pager.offset(
    Future<Result<PagingDomain<T>>> Function(int page, String query) fetch, {
    int firstPage = 1,
    Object Function(T item)? itemKey,
  }) : this._(
         OffsetStrategy(fetch, firstPage: firstPage, byTotal: false),
         itemKey,
       );

  /// Page numbers, where the backend returns only a total page count.
  Pager.offsetByTotal(
    Future<Result<PagingDomain<T>>> Function(int page, String query) fetch, {
    int firstPage = 1,
    Object Function(T item)? itemKey,
  }) : this._(
         OffsetStrategy(fetch, firstPage: firstPage, byTotal: true),
         itemKey,
       );

  /// An opaque cursor in `meta.nextKey`.
  Pager.cursor(
    Future<Result<PagingDomain<T>>> Function(String cursor, String query)
    fetch, {
    Object Function(T item)? itemKey,
  }) : this._(CursorStrategy(fetch), itemKey);

  /// "Items after this ID", with [itemId] reading an item's ID.
  Pager.lastItem(
    Future<Result<PagingDomain<T>>> Function(String? lastId, String query)
    fetch, {
    required String Function(T item) itemId,
    Object Function(T item)? itemKey,
  }) : this._(LastItemStrategy(fetch, itemId: itemId), itemKey);

  final PagingStrategy<T> _strategy;
  final Object Function(T item)? _itemKey;

  int _newestId = 0;
  String?
  _initialQuery; // the query of the last initial that is running or succeeded
  int? _initialRunId; // the id of the initial currently running, if any

  /// Runs one load and completes when it's written (or dropped). `initial` and
  /// `refresh` supersede whatever is running; `more` only starts on a loaded
  /// list with a next page, or to retry a failed `more`.
  Future<void> load(
    LoadType type,
    PagingState<T> current, {
    String query = '',
    required void Function(PagingState<T> state) update,
  }) async {
    if (!_allowed(type, current, query)) return;
    final previous = type == LoadType.more ? current.view.dataOrNull : null;
    final id = ++_newestId;
    if (type == LoadType.initial) {
      _initialQuery = query;
      _initialRunId = id;
    }
    update(PagingState(view: Loading(previous), loadType: type));

    var succeeded = false;
    try {
      final result = previous != null
          ? await _strategy.next(previous, query)
          : await _strategy.first(query);
      if (id != _newestId) {
        return; // stale: a newer load started, or cancel() was called
      }
      result.when(
        success: (page, _) {
          succeeded = true;
          update(
            PagingState(
              view: Done(_strategy.normalize(_merge(previous, page))),
              loadType: type,
            ),
          );
        },
        failure: (error, stackTrace) {
          if (error is CancelException) {
            return; // a superseded request, never shown
          }
          update(
            PagingState(
              view: Failed(error, data: previous, stackTrace: stackTrace),
              loadType: type,
            ),
          );
        },
      );
    } finally {
      if (_initialRunId == id) {
        // this was the initial that set the flag
        _initialRunId = null;
        if (!succeeded) {
          _initialQuery =
              null; // failed, cancelled or stale: the same query may run again
        }
      }
    }
  }

  /// Drops the running load, for example when the page is disposed. A late
  /// result changes nothing.
  void cancel() => _newestId++;

  bool _allowed(LoadType type, PagingState<T> current, String query) =>
      switch (type) {
        LoadType.more =>
          current.canLoadMore ||
              (current.view is Failed && current.loadType == LoadType.more),
        LoadType.initial =>
          query != _initialQuery, // ignored while it runs or after it succeeded
        LoadType.refresh => true,
      };

  PagingDomain<T> _merge(PagingDomain<T>? previous, PagingDomain<T> page) {
    if (previous == null) return page;
    final key = _itemKey;
    final all = [...previous.items, ...page.items];
    if (key == null) return PagingDomain(items: all, meta: page.meta);
    final seen = <Object>{};
    return PagingDomain(
      items: [
        for (final item in all)
          if (seen.add(key(item))) item,
      ],
      meta: page.meta,
    );
  }
}
