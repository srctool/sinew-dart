import 'package:sinew_models/sinew_models.dart';

/// Which load a paging state belongs to. A new search is an [initial] with the
/// new query.
enum LoadType {
  /// The first open, or a new search query.
  initial,

  /// Pull to refresh.
  refresh,

  /// The end of the list is near.
  more,
}

/// The paging slice of a page's state.
///
/// [loadType] stays set after the load finishes, so the UI can tell a
/// first-page failure from a next-page failure, and retry knows what to
/// repeat. It starts as a loading [LoadType.initial], so a list shows its
/// skeleton from the first frame.
final class PagingState<T> {
  /// Creates a paging state.
  const PagingState({
    this.view = const Loading(),
    this.loadType = LoadType.initial,
  });

  /// What the list renders.
  final ViewState<PagingDomain<T>> view;

  /// The load this state belongs to.
  final LoadType loadType;

  /// Whether a [LoadType.more] may start: the list is loaded and the backend
  /// has a next page.
  bool get canLoadMore => switch (view) {
    Done(:final data) => data.meta.hasNextPage,
    _ => false,
  };

  /// The load to repeat after a failure: the one that failed, or
  /// [LoadType.initial].
  LoadType get retryType => view is Failed ? loadType : LoadType.initial;

  /// A copy with the given fields replaced.
  PagingState<T> copyWith({
    ViewState<PagingDomain<T>>? view,
    LoadType? loadType,
  }) =>
      PagingState(view: view ?? this.view, loadType: loadType ?? this.loadType);

  @override
  bool operator ==(Object other) =>
      other is PagingState && other.view == view && other.loadType == loadType;

  @override
  int get hashCode => Object.hash(view, loadType);

  @override
  String toString() => 'PagingState($view, $loadType)';
}
