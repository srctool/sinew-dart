import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';
import 'package:sinew_testing/paging.dart';
import 'package:test/test.dart';

/// A page's paging slice and its pager, the way a notifier holds them.
class _Page {
  _Page({Object Function(String item)? itemKey}) {
    pager = Pager<String>.offset(fetch.call, itemKey: itemKey);
  }

  final fetch = ControlledFetch<String>();
  late final Pager<String> pager;
  var state = const PagingState<String>();
  final history = <PagingState<String>>[];

  /// Starts a load, as a notifier's action would, without awaiting it.
  void load(LoadType type, [String query = '']) {
    pager.load(
      type,
      state,
      query: query,
      update: (next) {
        state = next;
        history.add(next);
      },
    );
  }
}

PagingMetaDomain _meta(int page, {required bool hasNext}) =>
    PagingMetaDomain(page: page, hasNextPage: hasNext);

Done<PagingDomain<String>> _done(
  List<String> items,
  int page, {
  required bool hasNext,
}) => Done(
  PagingDomain(
    items: items,
    meta: _meta(page, hasNext: hasNext),
  ),
);

const _offline = NoInternetConnectionException(
  'ORD',
  ExceptionLayer.repository,
  'GO',
);
const _cancelled = CancelException('ORD', ExceptionLayer.repository, 'GO');

void main() {
  late _Page page;
  setUp(() {
    page = _Page();
    addTearDown(() => page.fetch.assertAllCompleted());
  });

  group('the load table', () {
    test('initial shows a full skeleton, then page one', () async {
      page.load(LoadType.initial);
      await pumpEventQueue();
      expect(
        page.state,
        const PagingState<String>(view: Loading(), loadType: LoadType.initial),
      );
      page.fetch.succeed(0, ['a', 'b'], meta: _meta(1, hasNext: true));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['a', 'b'], 1, hasNext: true),
          loadType: LoadType.initial,
        ),
      );
    });

    test('an initial failure is a first-page error', () async {
      page.load(LoadType.initial);
      await pumpEventQueue();
      page.fetch.fail(0, _offline);
      await pumpEventQueue();
      expect(
        page.state.view,
        isA<Failed<PagingDomain<String>>>().having(
          (f) => f.data,
          'data',
          isNull,
        ),
      );
      expect(page.state.loadType, LoadType.initial);
    });

    test(
      'refresh shows a full skeleton, then page one, or a first-page error',
      () async {
        page.state = PagingState(view: _done(['a'], 1, hasNext: true));
        page.load(LoadType.refresh);
        await pumpEventQueue();
        expect(
          page.state,
          const PagingState<String>(
            view: Loading(),
            loadType: LoadType.refresh,
          ),
        );
        page.fetch.succeed(0, ['z'], meta: _meta(1, hasNext: false));
        await pumpEventQueue();
        expect(
          page.state,
          PagingState(
            view: _done(['z'], 1, hasNext: false),
            loadType: LoadType.refresh,
          ),
        );
        page.load(LoadType.refresh);
        await pumpEventQueue();
        page.fetch.fail(1, _offline);
        await pumpEventQueue();
        expect(
          (page.state.view as Failed<PagingDomain<String>>).error,
          _offline,
        );
      },
    );

    test('more keeps the items while loading, then merges', () async {
      final first = PagingDomain(
        items: const ['a', 'b'],
        meta: _meta(1, hasNext: true),
      );
      page.state = PagingState(view: Done(first));
      page.load(LoadType.more);
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(view: Loading(first), loadType: LoadType.more),
      );
      expect(page.fetch.calls.single.key, 2);
      page.fetch.succeed(0, ['c'], meta: _meta(2, hasNext: false));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['a', 'b', 'c'], 2, hasNext: false),
          loadType: LoadType.more,
        ),
      );
    });

    test('a more failure keeps the items with a retry row', () async {
      final first = PagingDomain(
        items: const ['a'],
        meta: _meta(1, hasNext: true),
      );
      page.state = PagingState(view: Done(first));
      page.load(LoadType.more);
      await pumpEventQueue();
      page.fetch.fail(0, _offline);
      await pumpEventQueue();
      final failed = page.state.view as Failed<PagingDomain<String>>;
      expect(failed.data, first);
      expect(page.state.retryType, LoadType.more);
    });
  });

  group('guards', () {
    test(
      'more with no next page sends no request and changes nothing',
      () async {
        page.state = PagingState(view: _done(['a'], 1, hasNext: false));
        page.load(LoadType.more);
        await pumpEventQueue();
        expect(page.fetch.calls, isEmpty);
        expect(page.history, isEmpty);
      },
    );

    test('more while a load runs is ignored', () async {
      page.state = PagingState(view: _done(['a'], 1, hasNext: true));
      page.load(LoadType.more);
      page.load(LoadType.more);
      await pumpEventQueue();
      expect(page.fetch.calls, hasLength(1));
      page.fetch.succeed(0, ['b'], meta: _meta(2, hasNext: false));
      await pumpEventQueue();
    });

    test('the first load with the default meta still fetches, and an empty first page is done', () async {
      page.load(LoadType.initial);
      await pumpEventQueue();
      expect(page.fetch.calls, hasLength(1));
      page.fetch.succeed(0, [], meta: _meta(1, hasNext: false));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done([], 1, hasNext: false),
          loadType: LoadType.initial,
        ),
      );
    });
  });

  group('initial runs at most once per query', () {
    test('two initials with the same query start one fetch', () async {
      page.load(LoadType.initial, 'shoe');
      page.load(LoadType.initial, 'shoe');
      await pumpEventQueue();
      expect(page.fetch.calls, hasLength(1));
      page.fetch.succeed(0, ['a'], meta: _meta(1, hasNext: false));
      await pumpEventQueue();
      page.load(LoadType.initial, 'shoe'); // a re-sent opened after success
      await pumpEventQueue();
      expect(page.fetch.calls, hasLength(1));
    });

    test('a failed initial runs again', () async {
      page.load(LoadType.initial);
      await pumpEventQueue();
      page.fetch.fail(0, _offline);
      await pumpEventQueue();
      page.load(LoadType.initial);
      await pumpEventQueue();
      expect(page.fetch.calls, hasLength(2));
      page.fetch.succeed(1, ['a'], meta: _meta(1, hasNext: false));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['a'], 1, hasNext: false),
          loadType: LoadType.initial,
        ),
      );
    });

    test(
      'an initial superseded by a refresh lets the same query run again',
      () async {
        page.load(LoadType.initial, 'q');
        await pumpEventQueue();
        page.load(LoadType.refresh, 'q');
        await pumpEventQueue();
        page.fetch.succeed(1, ['r'], meta: _meta(1, hasNext: false));
        page.fetch.fail(
          0,
          _cancelled,
        ); // the notifier cancelled the superseded request
        await pumpEventQueue();
        page.load(LoadType.initial, 'q');
        await pumpEventQueue();
        expect(page.fetch.calls, hasLength(3));
        page.fetch.succeed(2, ['a'], meta: _meta(1, hasNext: false));
        await pumpEventQueue();
      },
    );

    test('a new query runs', () async {
      page.load(LoadType.initial, 'shoe');
      await pumpEventQueue();
      page.fetch.succeed(0, ['s'], meta: _meta(1, hasNext: false));
      await pumpEventQueue();
      page.load(LoadType.initial, 'hat');
      await pumpEventQueue();
      expect(page.fetch.calls[1].query, 'hat');
      page.fetch.succeed(1, ['h'], meta: _meta(1, hasNext: false));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['h'], 1, hasNext: false),
          loadType: LoadType.initial,
        ),
      );
    });
  });

  group('races', () {
    test('a late more after a refresh is dropped', () async {
      page.state = PagingState(view: _done(['a'], 1, hasNext: true));
      page.load(LoadType.more);
      await pumpEventQueue();
      page.load(LoadType.refresh);
      await pumpEventQueue();
      page.fetch.succeed(1, ['z'], meta: _meta(1, hasNext: false));
      page.fetch.succeed(0, [
        'late',
      ], meta: _meta(2, hasNext: false)); // the more response, late
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['z'], 1, hasNext: false),
          loadType: LoadType.refresh,
        ),
      );
    });

    test('search during more', () async {
      page.state = PagingState(view: _done(['a'], 1, hasNext: true));
      page.load(LoadType.more, 'shoe');
      await pumpEventQueue();
      page.load(LoadType.initial, 'hat');
      await pumpEventQueue();
      expect(page.fetch.calls[1].key, 1);
      expect(page.fetch.calls[1].query, 'hat');
      page.fetch.succeed(1, ['h'], meta: _meta(1, hasNext: false));
      page.fetch.succeed(0, ['late'], meta: _meta(2, hasNext: false));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['h'], 1, hasNext: false),
          loadType: LoadType.initial,
        ),
      );
    });

    test('a stale response never reaches the state', () async {
      page.load(LoadType.initial, 'shoe');
      await pumpEventQueue();
      page.load(LoadType.initial, 'hat');
      await pumpEventQueue();
      page.fetch.succeed(1, ['h'], meta: _meta(1, hasNext: false));
      page.fetch.succeed(0, [
        's',
      ], meta: _meta(1, hasNext: false)); // the old query, late
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['h'], 1, hasNext: false),
          loadType: LoadType.initial,
        ),
      );
      expect(
        page.history.any(
          (s) => s.view.dataOrNull?.items.contains('s') ?? false,
        ),
        isFalse,
      );
    });

    test('retry repeats the failed page', () async {
      page.state = PagingState(
        view: _done(['p1', 'p2'], 2, hasNext: true),
        loadType: LoadType.more,
      );
      page.load(LoadType.more);
      await pumpEventQueue();
      expect(page.fetch.calls[0].key, 3);
      page.fetch.fail(0, _offline);
      await pumpEventQueue();
      page.load(page.state.retryType);
      await pumpEventQueue();
      expect(
        page.fetch.calls[1].key,
        3,
        reason:
            'retry fetched page ${page.fetch.calls[1].key}, not the failed page 3',
      );
      page.fetch.succeed(1, ['p3'], meta: _meta(3, hasNext: false));
      await pumpEventQueue();
      expect(
        page.state,
        PagingState(
          view: _done(['p1', 'p2', 'p3'], 3, hasNext: false),
          loadType: LoadType.more,
        ),
      );
    });

    test('itemKey drops duplicates across pages', () async {
      page = _Page(itemKey: (item) => item);
      addTearDown(() => page.fetch.assertAllCompleted());
      page.state = PagingState(view: _done(['a', 'b'], 1, hasNext: true));
      page.load(LoadType.more);
      await pumpEventQueue();
      page.fetch.succeed(0, ['b', 'c'], meta: _meta(2, hasNext: false));
      await pumpEventQueue();
      expect(page.state.view.dataOrNull?.items, ['a', 'b', 'c']);
    });

    test('a CancelException leaves the state unchanged', () async {
      page.load(LoadType.initial);
      await pumpEventQueue();
      final before = page.history.length;
      page.fetch.fail(0, _cancelled);
      await pumpEventQueue();
      expect(page.history, hasLength(before));
    });
  });

  test('after cancel(), a pending response changes nothing', () async {
    page.load(LoadType.initial);
    await pumpEventQueue();
    final before = page.history.length;
    page.pager.cancel();
    page.fetch.succeed(0, ['a'], meta: _meta(1, hasNext: false));
    await pumpEventQueue();
    expect(page.history, hasLength(before));
  });
}
