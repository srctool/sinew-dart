import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';
// ignore: implementation_imports
import 'package:sinew_paging/src/strategies.dart';
import 'package:test/test.dart';

const _error = UnexpectedException('ORD', ExceptionLayer.repository, 'GO');

PagingDomain<String> _page({required bool hasNext}) => PagingDomain(
  items: const ['a'],
  meta: PagingMetaDomain(page: 1, hasNextPage: hasNext),
);

Future<Result<PagingDomain<String>>> _reply(
  PagingMetaDomain meta, [
  List<String> items = const ['x'],
]) async => Result.success(PagingDomain(items: items, meta: meta));

void main() {
  group('PagingState', () {
    test('starts as a loading initial', () {
      expect(
        const PagingState<String>(),
        const PagingState<String>(view: Loading(), loadType: LoadType.initial),
      );
    });

    test('canLoadMore only when done with a next page', () {
      for (final type in LoadType.values) {
        expect(
          PagingState(
            view: Done(_page(hasNext: true)),
            loadType: type,
          ).canLoadMore,
          isTrue,
          reason: '$type',
        );
        expect(
          PagingState(
            view: Done(_page(hasNext: false)),
            loadType: type,
          ).canLoadMore,
          isFalse,
          reason: '$type',
        );
        expect(
          PagingState(
            view: Loading(_page(hasNext: true)),
            loadType: type,
          ).canLoadMore,
          isFalse,
          reason: '$type',
        );
        expect(
          PagingState(
            view: Failed(_error, data: _page(hasNext: true)),
            loadType: type,
          ).canLoadMore,
          isFalse,
          reason: '$type',
        );
      }
    });

    test('retry repeats the load that failed', () {
      for (final type in LoadType.values) {
        expect(
          PagingState<String>(
            view: const Failed(_error),
            loadType: type,
          ).retryType,
          type,
        );
        expect(
          PagingState(
            view: Done(_page(hasNext: true)),
            loadType: type,
          ).retryType,
          LoadType.initial,
        );
        expect(PagingState<String>(loadType: type).retryType, LoadType.initial);
      }
    });
  });

  group('strategies', () {
    late List<Object?> requests;
    setUp(() => requests = []);

    test(
      'offset requests the first page, then page + 1, and trusts the flag',
      () async {
        final strategy = OffsetStrategy<String>(
          (page, _) {
            requests.add(page);
            return _reply(const PagingMetaDomain(hasNextPage: true));
          },
          firstPage: 1,
          byTotal: false,
        );
        final first = (await strategy.first('q')).requireData();
        final second = (await strategy.next(first, 'q')).requireData();
        expect(requests, [1, 2]);
        expect(strategy.normalize(second).meta.hasNextPage, isTrue);
        expect(
          strategy
              .normalize(
                second.copyWith(meta: second.meta.copyWith(hasNextPage: false)),
              )
              .meta
              .hasNextPage,
          isFalse,
        );
      },
    );

    test('offset supports a 0-based first page', () async {
      final strategy = OffsetStrategy<String>(
        (page, _) {
          requests.add(page);
          return _reply(const PagingMetaDomain());
        },
        firstPage: 0,
        byTotal: false,
      );
      await strategy.next((await strategy.first('')).requireData(), '');
      expect(requests, [0, 1]);
    });

    test('the requested page wins over the reported one', () async {
      final strategy = OffsetStrategy<String>(
        (_, _) => _reply(const PagingMetaDomain()),
        firstPage: 1,
        byTotal: false,
      );
      final first = (await strategy.first('')).requireData();
      expect(first.meta.page, 1);
      expect((await strategy.next(first, '')).requireData().meta.page, 2);
    });

    test('offset by total has a next page while page < totalPage', () async {
      final strategy = OffsetStrategy<String>(
        (_, _) => _reply(const PagingMetaDomain(totalPage: 2)),
        firstPage: 1,
        byTotal: true,
      );
      final first = (await strategy.first('')).requireData();
      expect(strategy.normalize(first).meta.hasNextPage, isTrue);
      expect(
        strategy
            .normalize((await strategy.next(first, '')).requireData())
            .meta
            .hasNextPage,
        isFalse,
      );
    });

    test(
      'cursor requests empty, then nextKey, and stops on an empty key',
      () async {
        final strategy = CursorStrategy<String>((cursor, _) {
          requests.add(cursor);
          return _reply(
            const PagingMetaDomain(hasNextPage: true, nextKey: 'c2'),
          );
        });
        final first = (await strategy.first('')).requireData();
        await strategy.next(first, '');
        expect(requests, ['', 'c2']);
        expect(strategy.normalize(first).meta.hasNextPage, isTrue);
        expect(
          strategy
              .normalize(first.copyWith(meta: first.meta.copyWith(nextKey: '')))
              .meta
              .hasNextPage,
          isFalse,
        );
      },
    );

    test(
      'last item requests null, then the last id, and stops on an empty list',
      () async {
        final strategy = LastItemStrategy<String>((lastId, _) {
          requests.add(lastId);
          return _reply(const PagingMetaDomain(hasNextPage: true), const [
            'a',
            'b',
          ]);
        }, itemId: (item) => 'id-$item');
        final first = (await strategy.first('')).requireData();
        await strategy.next(first, '');
        expect(requests, [null, 'id-b']);
        expect(strategy.normalize(first).meta.hasNextPage, isTrue);
        expect(
          strategy.normalize(first.copyWith(items: const [])).meta.hasNextPage,
          isFalse,
        );
      },
    );
  });
}
