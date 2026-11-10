// ignore_for_file: avoid_print

import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';

/// A backend with three pages of two items.
Future<Result<PagingDomain<String>>> fetch(int page, String query) async {
  final items = ['order ${page * 2 - 1}', 'order ${page * 2}'];
  return Result.success(
    PagingDomain(
      items: items,
      meta: PagingMetaDomain(page: page, hasNextPage: page < 3),
    ),
  );
}

Future<void> main() async {
  final pager = Pager<String>.offset(fetch);
  var state = const PagingState<String>();

  // The pager reads the current state and writes the next one through `update`.
  await pager.load(LoadType.initial, state, update: (next) => state = next);
  print('first page: ${state.view.dataOrNull?.items}');

  while (state.canLoadMore) {
    await pager.load(LoadType.more, state, update: (next) => state = next);
  }
  print('all pages: ${state.view.dataOrNull?.items}');
}
