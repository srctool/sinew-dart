import 'package:camouflage_core/camouflage_core.dart';
import 'package:flutter/widgets.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_l10n/sinew_l10n.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';

/// A [PagingState] as `CamoPagedList` shows it.
extension PagingStateToCamo<T> on PagingState<T> {
  /// This state for a `CamoPagedList`.
  ///
  /// Only a next-page load or failure keeps the items: a refresh drops them,
  /// so the list shows its skeleton. An error's text is rendered now with
  /// [localizer], so call this while building the UI and the text follows the
  /// current language. Without a localizer, a local message falls back to
  /// English.
  CamoPagedListState<T> toCamo(Localizer? localizer) => switch (view) {
    Loading(:final data) => CamoPagedListState(
      items: loadType == LoadType.more ? data?.items ?? const [] : const [],
      loading: switch (loadType) {
        LoadType.initial => PagedLoad.initial,
        LoadType.refresh => PagedLoad.refresh,
        LoadType.more => PagedLoad.more,
      },
    ),
    Done(:final data) => CamoPagedListState(
      items: data.items,
      endReached: !canLoadMore,
    ),
    Failed(:final data, :final error) => CamoPagedListState(
      items: loadType == LoadType.more ? data?.items ?? const [] : const [],
      error: PagedError(
        message: error.displayMessage(localizer),
        scope: loadType == LoadType.more
            ? PagedErrorScope.nextPage
            : PagedErrorScope.firstPage,
      ),
    ),
  };

  /// [toCamo] with Sinew's localizer for [context]'s locale. Requires
  /// `SinewLocalizations.delegate` in the app's `localizationsDelegates`.
  CamoPagedListState<T> toCamoOf(BuildContext context) =>
      toCamo(SinewLocalizer.of(context));
}
